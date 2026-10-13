#!/usr/bin/env bash
# charter init turns on the plugins a project's modules need and imports their rules, merges
# into what is already there, refuses what it cannot do cleanly, and reaches a consumer as
# `charter`.
set -euo pipefail

cli="$PWD/bin/charter.mjs"
[ -f "$cli" ] || { echo "  ✗ bin/charter.mjs does not exist"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A stub claude records each call and reports nothing installed, so init's last step — running
# need_plugins — is observed without touching this machine's plugins.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
case "$*" in
  'plugin list --json') echo '[]' ;;
  'plugin marketplace list --json') echo '[{"name":"claude-plugins-official"}]' ;;
esac
FAKE
chmod +x "$tmp/bin/claude"
export CLAUDE_LOG="$tmp/claude.log"
export PATH="$tmp/bin:$PATH"

# A new project directory with the kit installed at its root, as init expects.
project() { rm -rf "$tmp/$1"; mkdir -p "$tmp/$1/node_modules/charter"; echo "$tmp/$1"; }
fail() { echo "  ✗ $*"; exit 1; }

# ── a first run ───────────────────────────────────────────────────────────────

p="$(project fresh)"
: > "$CLAUDE_LOG"
( cd "$p" && node "$cli" init typescript react ) >/dev/null || fail "init typescript react failed"

expected='{
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true,
    "playwright@claude-plugins-official": true
  }
}'
[ "$(cat "$p/.claude/settings.json")" = "$expected" ] ||
  { echo "  ✗ settings.json is not what typescript + react enable:"; cat "$p/.claude/settings.json"; exit 1; }

expected='@node_modules/charter/core/rules.md
@node_modules/charter/stacks/typescript/rules.md
@node_modules/charter/stacks/react/rules.md'
[ "$(cat "$p/CLAUDE.md")" = "$expected" ] ||
  { echo "  ✗ CLAUDE.md is not core and the two stacks:"; cat "$p/CLAUDE.md"; exit 1; }

grep -qx 'plugin install playwright@claude-plugins-official --scope project' "$CLAUDE_LOG" ||
  fail "init did not run need_plugins"

# ── a second run changes nothing ───────────────────────────────────────────────

cp "$p/.claude/settings.json" "$tmp/settings.before"
cp "$p/CLAUDE.md" "$tmp/claude.before"
( cd "$p" && node "$cli" init typescript react ) >/dev/null || fail "a second init failed"
cmp -s "$p/.claude/settings.json" "$tmp/settings.before" || fail "a second run changed settings.json"
cmp -s "$p/CLAUDE.md" "$tmp/claude.before" || fail "a second run changed CLAUDE.md"

# Nothing to add means the file is not rewritten, so a project's own formatting survives.
p="$(project formatted)"
mkdir -p "$p/.claude"
echo '{"enabledPlugins":{"frontend-design@claude-plugins-official":true,"playwright@claude-plugins-official":true}}' \
  > "$p/.claude/settings.json"
cp "$p/.claude/settings.json" "$tmp/settings.before"
( cd "$p" && node "$cli" init react ) >/dev/null || fail "init with its plugins already set failed"
cmp -s "$p/.claude/settings.json" "$tmp/settings.before" ||
  fail "init rewrote settings.json with nothing to add"

# ── merging into what is there ────────────────────────────────────────────────

# An opt-out survives, and so does every key init does not own.
p="$(project merge)"
mkdir -p "$p/.claude"
echo '{ "model": "opus", "enabledPlugins": { "playwright@claude-plugins-official": false } }' \
  > "$p/.claude/settings.json"
( cd "$p" && node "$cli" init react ) >/dev/null || fail "init into existing settings failed"
node -e '
  const s = require(process.argv[1])
  if (s.model !== "opus") throw new Error("model was dropped")
  if (s.enabledPlugins["playwright@claude-plugins-official"] !== false) throw new Error("opt-out was overwritten")
' "$p/.claude/settings.json" 2>/dev/null || fail "init changed a value already set in settings.json"

# An existing CLAUDE.md with no final newline gets its imports on their own lines.
printf '# Project' > "$p/CLAUDE.md"
( cd "$p" && node "$cli" init vitest ) >/dev/null || fail "init into an existing CLAUDE.md failed"
[ "$(cat "$p/CLAUDE.md")" = $'# Project\n\n@node_modules/charter/core/rules.md' ] ||
  { echo "  ✗ imports were not appended after one blank line:"; cat "$p/CLAUDE.md"; exit 1; }

# A module named twice is written once.
p="$(project twice)"
( cd "$p" && node "$cli" init node node ) >/dev/null || fail "init node node failed"
[ "$(grep -c 'stacks/node/rules.md' "$p/CLAUDE.md")" = 1 ] || fail "a repeated module was imported twice"

# ── workspaces ────────────────────────────────────────────────────────────────

p="$(project split)"
mkdir -p "$p/server" "$p/apps/web"
( cd "$p" && node "$cli" init backend --workspace server ) >/dev/null || fail "init --workspace server failed"
( cd "$p" && node "$cli" init react --workspace apps/web ) >/dev/null || fail "init --workspace apps/web failed"
[ "$(cat "$p/server/CLAUDE.md")" = '@../node_modules/charter/domains/backend/rules.md' ] ||
  fail "a workspace one level down does not import through ../"
[ "$(cat "$p/apps/web/CLAUDE.md")" = '@../../node_modules/charter/stacks/react/rules.md' ] ||
  fail "a workspace two levels down does not import through ../../"
grep -q 'playwright@claude-plugins-official' "$p/.claude/settings.json" ||
  fail "a workspace's plugins did not land in the root settings.json"
[ ! -e "$p/apps/web/.claude" ] || fail "a workspace got its own .claude directory"

# ── the commit-msg hook ───────────────────────────────────────────────────────

# core carries the commit rule and every project loads it, so every init installs the hook.
# This machine's own git config must not decide where the hook lands.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
p="$(project hooked)"
git -C "$p" init -q
( cd "$p" && node "$cli" init react ) >/dev/null || fail "init react in a repository failed"
[ -f "$p/.git/hooks/commit-msg" ] || fail "every init installs the commit-msg hook"

# ── refusals: non-zero, and nothing written ───────────────────────────────────

refuses() {
  local name="$1" expect="$2"
  shift 2
  local p
  p="$(project "refuse-$name")"
  [ -n "${SETUP:-}" ] && (cd "$p" && eval "$SETUP")
  local before err
  before="$(cd "$p" && find . | sort)"
  err="$( (cd "$p" && node "$cli" "$@") 2>&1 >/dev/null )" && fail "init accepted $name"
  grep -q -- "$expect" <<< "$err" || fail "refusing $name, init did not say '$expect': got '$err'"
  [ "$(cd "$p" && find . | sort)" = "$before" ] || fail "init wrote files while refusing $name"
}

refuses 'no command' 'Usage: charter init'
refuses 'another command' 'Usage: charter init' build typescript
refuses 'no modules' 'Usage: charter init' init
refuses 'an unknown module' 'backend, node, react, typescript, vitest' init frontend
refuses 'node with react' '--workspace' init node react
refuses 'a missing workspace' 'not a directory' init react --workspace nope
refuses 'a workspace outside' 'outside this repository' init react --workspace ..
SETUP='mkdir .claude && echo "{" > .claude/settings.json' \
  refuses 'broken settings JSON' 'settings.json' init typescript
SETUP='mkdir .claude && echo "{ \"enabledPlugins\": [] }" > .claude/settings.json' \
  refuses 'enabledPlugins as an array' 'enabledPlugins' init typescript

# Run from a workspace instead of the root, init would write a .claude/ no session reads and an
# import that loads nothing. Without the kit in node_modules here, it is not the root.
p="$(project subdir)"
mkdir -p "$p/server"
before="$(cd "$p" && find . | sort)"
err="$( (cd "$p/server" && node "$cli" init node) 2>&1 >/dev/null )" && fail "init accepted a run from a subdirectory"
grep -q 'repository root' <<< "$err" || fail "refusing a subdirectory, init did not point to the root: got '$err'"
[ "$(cd "$p" && find . | sort)" = "$before" ] || fail "init wrote files while refusing a subdirectory"

# ── reachable from a consumer ─────────────────────────────────────────────────

( cd tests/fixture && npm install --silent --no-audit --no-fund )
[ -x tests/fixture/node_modules/.bin/charter ] || fail "a consumer gets no charter executable"
err="$(tests/fixture/node_modules/.bin/charter 2>&1 >/dev/null)" && fail "charter with no arguments succeeded"
grep -q 'Usage: charter init' <<< "$err" || fail "a consumer's charter does not print its usage"

echo "  ✓ init enables plugins and imports rules, merges without overwriting, places workspace imports, refuses cleanly, and reaches a consumer"
