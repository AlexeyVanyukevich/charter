#!/usr/bin/env bash
# dev-kit init turns on the plugins a project's sections need and imports their rules, merges
# into what is already there, refuses what it cannot do cleanly, and reaches a consumer as
# `dev-kit`.
set -euo pipefail

cli="$PWD/bin/dev-kit.mjs"
[ -f "$cli" ] || { echo "  ✗ bin/dev-kit.mjs does not exist"; exit 1; }

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
project() { rm -rf "$tmp/$1"; mkdir -p "$tmp/$1/node_modules/dev-kit"; echo "$tmp/$1"; }
fail() { echo "  ✗ $*"; exit 1; }

# ── a first run ───────────────────────────────────────────────────────────────

p="$(project fresh)"
: > "$CLAUDE_LOG"
( cd "$p" && node "$cli" init common ui ) >/dev/null || fail "init common ui failed"

expected='{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "frontend-design@claude-plugins-official": true,
    "playwright@claude-plugins-official": true
  }
}'
[ "$(cat "$p/.claude/settings.json")" = "$expected" ] ||
  { echo "  ✗ settings.json is not what common + ui enable:"; cat "$p/.claude/settings.json"; exit 1; }

expected='@node_modules/dev-kit/common/rules.md
@node_modules/dev-kit/ui/rules.md'
[ "$(cat "$p/CLAUDE.md")" = "$expected" ] ||
  { echo "  ✗ CLAUDE.md is not the two imports:"; cat "$p/CLAUDE.md"; exit 1; }

grep -qx 'plugin install superpowers@claude-plugins-official --scope project' "$CLAUDE_LOG" ||
  fail "init did not run need_plugins"

# ── a second run changes nothing ───────────────────────────────────────────────

cp "$p/.claude/settings.json" "$tmp/settings.before"
cp "$p/CLAUDE.md" "$tmp/claude.before"
( cd "$p" && node "$cli" init common ui ) >/dev/null || fail "a second init failed"
cmp -s "$p/.claude/settings.json" "$tmp/settings.before" || fail "a second run changed settings.json"
cmp -s "$p/CLAUDE.md" "$tmp/claude.before" || fail "a second run changed CLAUDE.md"

# Nothing to add means the file is not rewritten, so a project's own formatting survives.
p="$(project formatted)"
mkdir -p "$p/.claude"
echo '{"enabledPlugins":{"superpowers@claude-plugins-official":true}}' > "$p/.claude/settings.json"
cp "$p/.claude/settings.json" "$tmp/settings.before"
( cd "$p" && node "$cli" init common ) >/dev/null || fail "init with its plugin already set failed"
cmp -s "$p/.claude/settings.json" "$tmp/settings.before" ||
  fail "init rewrote settings.json with nothing to add"

# ── merging into what is there ────────────────────────────────────────────────

# An opt-out survives, and so does every key init does not own.
p="$(project merge)"
mkdir -p "$p/.claude"
echo '{ "model": "opus", "enabledPlugins": { "superpowers@claude-plugins-official": false } }' \
  > "$p/.claude/settings.json"
( cd "$p" && node "$cli" init common ) >/dev/null || fail "init into existing settings failed"
node -e '
  const s = require(process.argv[1])
  if (s.model !== "opus") throw new Error("model was dropped")
  if (s.enabledPlugins["superpowers@claude-plugins-official"] !== false) throw new Error("opt-out was overwritten")
' "$p/.claude/settings.json" 2>/dev/null || fail "init changed a value already set in settings.json"

# An existing CLAUDE.md with no final newline gets its imports on their own lines.
printf '# Project' > "$p/CLAUDE.md"
( cd "$p" && node "$cli" init testing ) >/dev/null || fail "init into an existing CLAUDE.md failed"
[ "$(cat "$p/CLAUDE.md")" = $'# Project\n\n@node_modules/dev-kit/testing/rules.md' ] ||
  { echo "  ✗ imports were not appended after one blank line:"; cat "$p/CLAUDE.md"; exit 1; }

# A section named twice is written once.
p="$(project twice)"
( cd "$p" && node "$cli" init common common ) >/dev/null || fail "init common common failed"
[ "$(grep -c 'common/rules.md' "$p/CLAUDE.md")" = 1 ] || fail "a repeated section was imported twice"

# ── workspaces ────────────────────────────────────────────────────────────────

p="$(project split)"
mkdir -p "$p/server" "$p/apps/web"
( cd "$p" && node "$cli" init backend --workspace server ) >/dev/null || fail "init --workspace server failed"
( cd "$p" && node "$cli" init ui --workspace apps/web ) >/dev/null || fail "init --workspace apps/web failed"
[ "$(cat "$p/server/CLAUDE.md")" = '@../node_modules/dev-kit/backend/rules.md' ] ||
  fail "a workspace one level down does not import through ../"
[ "$(cat "$p/apps/web/CLAUDE.md")" = '@../../node_modules/dev-kit/ui/rules.md' ] ||
  fail "a workspace two levels down does not import through ../../"
grep -q 'playwright@claude-plugins-official' "$p/.claude/settings.json" ||
  fail "a workspace's plugins did not land in the root settings.json"
[ ! -e "$p/apps/web/.claude" ] || fail "a workspace got its own .claude directory"

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

refuses 'no command' 'Usage: dev-kit init'
refuses 'another command' 'Usage: dev-kit init' build common
refuses 'no sections' 'Usage: dev-kit init' init
refuses 'an unknown section' 'backend, common, testing, ui' init frontend
refuses 'backend with ui' '--workspace' init backend ui
refuses 'a missing workspace' 'not a directory' init ui --workspace nope
refuses 'a workspace outside' 'outside this repository' init ui --workspace ..
SETUP='mkdir .claude && echo "{" > .claude/settings.json' \
  refuses 'broken settings JSON' 'settings.json' init common
SETUP='mkdir .claude && echo "{ \"enabledPlugins\": [] }" > .claude/settings.json' \
  refuses 'enabledPlugins as an array' 'enabledPlugins' init common

# Run from a workspace instead of the root, init would write a .claude/ no session reads and an
# import that loads nothing. Without the kit in node_modules here, it is not the root.
p="$(project subdir)"
mkdir -p "$p/server"
before="$(cd "$p" && find . | sort)"
err="$( (cd "$p/server" && node "$cli" init backend) 2>&1 >/dev/null )" && fail "init accepted a run from a subdirectory"
grep -q 'repository root' <<< "$err" || fail "refusing a subdirectory, init did not point to the root: got '$err'"
[ "$(cd "$p" && find . | sort)" = "$before" ] || fail "init wrote files while refusing a subdirectory"

# ── reachable from a consumer ─────────────────────────────────────────────────

( cd tests/fixture && npm install --silent --no-audit --no-fund )
[ -x tests/fixture/node_modules/.bin/dev-kit ] || fail "a consumer gets no dev-kit executable"
err="$(tests/fixture/node_modules/.bin/dev-kit 2>&1 >/dev/null)" && fail "dev-kit with no arguments succeeded"
grep -q 'Usage: dev-kit init' <<< "$err" || fail "a consumer's dev-kit does not print its usage"

echo "  ✓ init enables plugins and imports rules, merges without overwriting, places workspace imports, refuses cleanly, and reaches a consumer"
