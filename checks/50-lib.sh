#!/usr/bin/env bash
# The library defines what it promises, and load_env_file keeps the documented precedence.
set -euo pipefail

lib="$PWD/core/lib.sh"
[ -f "$lib" ] || { echo "  ✗ core/lib.sh does not exist"; exit 1; }

# Sourcing must be inert: no shell options changed, no directory changed, nothing executed.
# A library that runs on load cannot be sourced near the top of someone else's script.
before="$(set +o)"
# shellcheck disable=SC1090
source "$lib"
[ "$(set +o)" = "$before" ] || { echo "  ✗ sourcing lib.sh changed shell options"; exit 1; }

for fn in step ok note die load_env_file need_docker need_node need_deps need_plugins need_hooks need_env with_github_token; do
  declare -F "$fn" >/dev/null || { echo "  ✗ lib.sh does not define $fn"; exit 1; }
done

for var in BOLD DIM RED GREEN YELLOW OFF; do
  [ -n "${!var+set}" ] || { echo "  ✗ lib.sh does not define $var"; exit 1; }
done

# die exits 1 and writes to stderr, so a failure is a failure even when stdout is piped.
( source "$lib"; die "nope" "do this instead" ) >/dev/null 2>&1 &&
  { echo "  ✗ die did not exit non-zero"; exit 1; }

# The precedence rule, which is the reason this is a line-by-line reader rather than `. ./.env`:
# command line beats the file. Sourcing the file would silently invert it.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'FROM_FILE=file\nOVERRIDDEN=file\n# a comment\n\nWITH_EQUALS=a=b\n' > "$tmp/.env"

result="$(
  cd "$tmp"
  source "$lib"
  OVERRIDDEN=shell
  export OVERRIDDEN
  load_env_file
  echo "$FROM_FILE|$OVERRIDDEN|$WITH_EQUALS"
)"
[ "$result" = "file|shell|a=b" ] || {
  echo "  ✗ load_env_file precedence is wrong: got '$result', wanted 'file|shell|a=b'"
  exit 1
}

# A missing .env is normal on a first run and must not be fatal.
( cd "$tmp" && rm -f .env && source "$lib" && load_env_file ) ||
  { echo "  ✗ load_env_file failed when .env was absent"; exit 1; }

# need_env reports a created .env by returning non-zero, which the README tells a caller under
# `set -e` to catch. The contract is both halves: non-zero when it copied, zero when it did not.
( cd "$tmp" && rm -f .env && echo 'A=1' > .env.example && source "$lib" && need_env ) >/dev/null &&
  { echo "  ✗ need_env returned zero after creating .env"; exit 1; }
[ -f "$tmp/.env" ] || { echo "  ✗ need_env did not create .env"; exit 1; }
( cd "$tmp" && source "$lib" && need_env ) >/dev/null ||
  { echo "  ✗ need_env returned non-zero when .env already existed"; exit 1; }

# with_github_token hands a token to one command and to nothing after it: GITHUB_TOKEN when the
# environment has one, as CI does, otherwise the GitHub CLI's own login. Fakes stand in for gh
# and npm, so nothing here reaches the network or a real credential.
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/gh" <<'FAKE'
#!/usr/bin/env bash
[ "${FAKE_GH:-}" = consulted ] && { echo "gh was consulted" >&2; exit 3; }
[ "${FAKE_GH:-}" = signed-in ] && [ "$*" = "auth token" ] && { echo gh-token; exit 0; }
exit 1
FAKE
cat > "$bin/npm" <<'FAKE'
#!/usr/bin/env bash
echo "npm $* token=${GITHUB_TOKEN:-none}"
FAKE
chmod +x "$bin/gh" "$bin/npm"
real_path="$PATH"

result="$(source "$lib"; PATH="$bin:$real_path" FAKE_GH=consulted GITHUB_TOKEN=ci-token with_github_token printenv GITHUB_TOKEN)"
[ "$result" = ci-token ] || { echo "  ✗ with_github_token did not pass GITHUB_TOKEN through: got '$result'"; exit 1; }

result="$(source "$lib"; unset GITHUB_TOKEN; PATH="$bin:$real_path" FAKE_GH=signed-in with_github_token printenv GITHUB_TOKEN)"
[ "$result" = gh-token ] || { echo "  ✗ with_github_token did not take the GitHub CLI's token: got '$result'"; exit 1; }

result="$(source "$lib"; unset GITHUB_TOKEN; PATH="$bin:$real_path" FAKE_GH=signed-in with_github_token true; echo "${GITHUB_TOKEN:-unset}")"
[ "$result" = unset ] || { echo "  ✗ with_github_token left the token in the caller's environment"; exit 1; }

# No token anywhere is a stop with the command that fixes it, not a 401 from whatever ran next.
mkdir -p "$tmp/empty"
for case in "no gh:$tmp/empty" "gh signed out:$bin"; do
  name="${case%%:*}"
  dir="${case#*:}"
  err="$( (source "$lib"; unset GITHUB_TOKEN; PATH="$dir" FAKE_GH='' with_github_token true) 2>&1 >/dev/null )" &&
    { echo "  ✗ with_github_token succeeded with $name"; exit 1; }
  grep -q 'gh auth login' <<< "$err" || { echo "  ✗ with $name, the failure does not say to run gh auth login"; exit 1; }
done

# need_deps asks for a token only when the project's .npmrc does; a project without private
# packages never needs the GitHub CLI.
mkdir -p "$tmp/private" "$tmp/public"
printf '//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}\n' > "$tmp/private/.npmrc"
result="$(cd "$tmp/private" && source "$lib" && unset GITHUB_TOKEN && PATH="$bin:$real_path" FAKE_GH=signed-in need_deps)"
grep -q 'npm install token=gh-token' <<< "$result" ||
  { echo "  ✗ need_deps did not install with the token its .npmrc asks for: got '$result'"; exit 1; }
result="$(cd "$tmp/public" && source "$lib" && unset GITHUB_TOKEN && PATH="$bin:$real_path" FAKE_GH=consulted need_deps)"
grep -q 'npm install token=none' <<< "$result" ||
  { echo "  ✗ need_deps involved a token for a project that asks for none: got '$result'"; exit 1; }

# need_plugins installs, at project scope, the enabled plugins this machine lacks for this
# repository. A stub claude answers from FAKE_INSTALLED and FAKE_MARKETPLACES and records every
# call, so nothing here touches this machine's real plugins.
cat > "$bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
case "$*" in
  'plugin list --json') printf '%s' "${FAKE_INSTALLED:-[]}" ;;
  'plugin marketplace list --json') printf '%s' "${FAKE_MARKETPLACES:-[]}" ;;
  'plugin install '*) if [ -n "${FAKE_READS_STDIN:-}" ]; then cat >/dev/null; fi ;;
esac
FAKE
chmod +x "$bin/claude"
export CLAUDE_LOG="$tmp/claude.log"

project="$tmp/plugins"
mkdir -p "$project/.claude"
printf '%s\n' '{ "enabledPlugins": {
  "a@claude-plugins-official": true,
  "b@claude-plugins-official": true,
  "off@claude-plugins-official": false
} }' > "$project/.claude/settings.json"
# The directory as Node resolves it, already a JSON string. On Windows that is C:\…; pwd would
# give Git Bash's /tmp/…, which Node cannot resolve, so need_plugins would see nothing installed.
here="$(cd "$project" && node -p 'JSON.stringify(require("fs").realpathSync("."))')"

# a is installed here, b only in another repository, so b alone is missing; the official
# marketplace is not registered, so it is added first.
: > "$CLAUDE_LOG"
( cd "$project" && source "$lib" && PATH="$bin:$real_path" \
  FAKE_INSTALLED="[{\"id\":\"a@claude-plugins-official\",\"scope\":\"project\",\"projectPath\":$here},
                   {\"id\":\"b@claude-plugins-official\",\"scope\":\"project\",\"projectPath\":\"/elsewhere\"}]" \
  need_plugins ) >/dev/null || { echo "  ✗ need_plugins failed installing a missing plugin"; exit 1; }
grep -qx 'plugin install b@claude-plugins-official --scope project' "$CLAUDE_LOG" ||
  { echo "  ✗ need_plugins did not install the missing plugin"; cat "$CLAUDE_LOG"; exit 1; }
grep -qE 'install (a|off)@' "$CLAUDE_LOG" &&
  { echo "  ✗ need_plugins installed a plugin that was present or turned off"; exit 1; }
grep -qx 'plugin marketplace add anthropics/claude-plugins-official' "$CLAUDE_LOG" ||
  { echo "  ✗ need_plugins did not register the missing official marketplace"; exit 1; }

# A registered marketplace is not added again.
: > "$CLAUDE_LOG"
( cd "$project" && source "$lib" && PATH="$bin:$real_path" \
  FAKE_MARKETPLACES='[{"name":"claude-plugins-official"}]' need_plugins ) >/dev/null ||
  { echo "  ✗ need_plugins failed with the marketplace registered"; exit 1; }
grep -q 'marketplace add' "$CLAUDE_LOG" &&
  { echo "  ✗ need_plugins added a marketplace that was already registered"; exit 1; }

# Nothing missing: nothing installed, nothing printed.
: > "$CLAUDE_LOG"
result="$(cd "$project" && source "$lib" && PATH="$bin:$real_path" \
  FAKE_INSTALLED="[{\"id\":\"a@claude-plugins-official\",\"scope\":\"project\",\"projectPath\":$here},
                   {\"id\":\"b@claude-plugins-official\",\"scope\":\"project\",\"projectPath\":$here}]" \
  need_plugins)"
[ -z "$result" ] || { echo "  ✗ need_plugins printed '$result' with nothing to install"; exit 1; }
grep -q 'install' "$CLAUDE_LOG" && { echo "  ✗ need_plugins installed with nothing missing"; exit 1; }

# Each install runs with no stdin: a claude that reads it — a confirmation prompt — would
# otherwise consume the ids still waiting in the loop, and those plugins would silently not install.
: > "$CLAUDE_LOG"
( cd "$project" && source "$lib" && PATH="$bin:$real_path" FAKE_READS_STDIN=1 \
  FAKE_MARKETPLACES='[{"name":"claude-plugins-official"}]' need_plugins ) >/dev/null ||
  { echo "  ✗ need_plugins failed with a claude that reads stdin"; exit 1; }
[ "$(grep -c '^plugin install' "$CLAUDE_LOG")" = 2 ] ||
  { echo "  ✗ an install that read stdin swallowed the remaining plugins"; cat "$CLAUDE_LOG"; exit 1; }

# No Claude Code — CI — is a note and a zero, never a failure. Node stays on PATH; claude does not.
mkdir -p "$tmp/nodeonly"
ln -sf "$(command -v node)" "$tmp/nodeonly/node"
result="$(cd "$project" && source "$lib" && PATH="$tmp/nodeonly" need_plugins)" ||
  { echo "  ✗ need_plugins failed without Claude Code installed"; exit 1; }
grep -q 'Claude Code' <<< "$result" ||
  { echo "  ✗ need_plugins said nothing when skipping without Claude Code: got '$result'"; exit 1; }

# No settings file: nothing to do, and claude is never asked.
: > "$CLAUDE_LOG"
( cd "$tmp/public" && source "$lib" && PATH="$bin:$real_path" need_plugins ) ||
  { echo "  ✗ need_plugins failed in a project with no settings file"; exit 1; }
[ -s "$CLAUDE_LOG" ] && { echo "  ✗ need_plugins called claude with no settings file"; exit 1; }

# Broken JSON is a stop that names the file, not a Node stack trace.
mkdir -p "$tmp/broken/.claude"
echo '{' > "$tmp/broken/.claude/settings.json"
err="$( (cd "$tmp/broken" && source "$lib" && PATH="$bin:$real_path" need_plugins) 2>&1 >/dev/null )" &&
  { echo "  ✗ need_plugins accepted a settings file that is not JSON"; exit 1; }
grep -q 'settings.json' <<< "$err" ||
  { echo "  ✗ need_plugins failed on broken JSON without naming the file: got '$err'"; exit 1; }

echo "  ✓ lib.sh sources inertly, defines its surface, keeps env precedence, reports a new .env, hands a GitHub token only where one is asked for, and installs only missing plugins"
