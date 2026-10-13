#!/usr/bin/env bash
# charter init records a workspace's modules in charter.json, imports core into the root
# CLAUDE.md, wires the sync hook, the .gitignore line and the modules' plugins, then syncs —
# merging into what is there, refusing what it cannot do cleanly, and reaching a consumer as
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
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

project() { rm -rf "$tmp/$1"; mkdir -p "$tmp/$1/node_modules/charter"; echo "$tmp/$1"; }
fail() { echo "  ✗ $*"; exit 1; }
hook='node "$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs" sync'

# ── a first run ───────────────────────────────────────────────────────────────

p="$(project fresh)"
( cd "$p" && node "$cli" init backend typescript node vitest ) >/dev/null ||
  fail "init backend typescript node vitest failed"
[ "$(node -p 'JSON.stringify(require(process.argv[1]))' "$p/charter.json")" = \
  '{"workspaces":{".":["backend","typescript","node","vitest"]}}' ] ||
  { echo "  ✗ charter.json is not the four modules:"; cat "$p/charter.json"; exit 1; }
[ "$(cat "$p/CLAUDE.md")" = '@node_modules/charter/core/rules.md' ] ||
  { echo "  ✗ CLAUDE.md is not the core import:"; cat "$p/CLAUDE.md"; exit 1; }
node -e '
  const s = require(process.argv[1])
  const entries = s.hooks.SessionStart
  if (entries.length !== 1 || entries[0].hooks.length !== 1) throw new Error("not one hook")
  if (entries[0].hooks[0].type !== "command" || entries[0].hooks[0].command !== process.argv[2]) throw new Error("not sync")
  if (s.enabledPlugins !== undefined) throw new Error("plugins for modules that bring none")
' "$p/.claude/settings.json" "$hook" 2>/dev/null ||
  { echo "  ✗ settings.json does not hold exactly the sync hook:"; cat "$p/.claude/settings.json"; exit 1; }
[ "$(cat "$p/.gitignore")" = '.claude/rules/charter/' ] || fail ".gitignore does not ignore the synced rules"
grep -qx '  - "src/modules/\*\*"' "$p/.claude/rules/charter/@root/backend/http.md" ||
  fail "init did not sync the backend rules"

# ── a second run changes nothing ───────────────────────────────────────────────

for f in charter.json CLAUDE.md .gitignore .claude/settings.json; do cp "$p/$f" "$tmp/before.${f//\//_}"; done
( cd "$p" && node "$cli" init backend typescript node vitest ) >/dev/null || fail "a second init failed"
for f in charter.json CLAUDE.md .gitignore .claude/settings.json; do
  cmp -s "$p/$f" "$tmp/before.${f//\//_}" || fail "a second run changed $f"
done

# Nothing to add means a file is not rewritten, so a project's own formatting survives.
p="$(project formatted)"
mkdir -p "$p/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":%s}]}]}}\n' \
  "$(node -p 'JSON.stringify(process.argv[1])' "$hook")" > "$p/.claude/settings.json"
cp "$p/.claude/settings.json" "$tmp/settings.before"
( cd "$p" && node "$cli" init typescript ) >/dev/null || fail "init with its hook already set failed"
cmp -s "$p/.claude/settings.json" "$tmp/settings.before" || fail "init rewrote settings.json with nothing to add"

# ── no modules: core alone ────────────────────────────────────────────────────

p="$(project bare)"
( cd "$p" && node "$cli" init ) >/dev/null || fail "init with no modules failed"
[ "$(node -p 'JSON.stringify(require(process.argv[1]).workspaces)' "$p/charter.json")" = '{".":[]}' ] ||
  fail "init with no modules did not record an empty root workspace"
grep -qx '@node_modules/charter/core/rules.md' "$p/CLAUDE.md" || fail "init with no modules did not import core"

# ── merging into what is there ────────────────────────────────────────────────

p="$(project merge)"
mkdir -p "$p/.claude"
echo '{ "model": "opus", "enabledPlugins": { "playwright@claude-plugins-official": false },
  "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo own" } ] } ] } }' \
  > "$p/.claude/settings.json"
printf '# Project' > "$p/CLAUDE.md"
printf 'dist/' > "$p/.gitignore"
echo '{ "workspaces": { ".": ["typescript"] }, "note": "kept" }' > "$p/charter.json"
: > "$CLAUDE_LOG"
( cd "$p" && node "$cli" init react vitest ) >/dev/null || fail "init into an existing project failed"
node -e '
  const s = require(process.argv[1])
  if (s.model !== "opus") throw new Error("model was dropped")
  if (s.enabledPlugins["playwright@claude-plugins-official"] !== false) throw new Error("opt-out overwritten")
  if (s.enabledPlugins["frontend-design@claude-plugins-official"] !== true) throw new Error("plugin not enabled")
  const commands = s.hooks.SessionStart.flatMap((e) => e.hooks.map((h) => h.command))
  if (commands.length !== 2 || commands[0] !== "echo own") throw new Error("own hook not kept first")
' "$p/.claude/settings.json" 2>/dev/null || fail "init changed or dropped something set in settings.json"
[ "$(cat "$p/CLAUDE.md")" = $'# Project\n\n@node_modules/charter/core/rules.md' ] ||
  { echo "  ✗ the core import was not appended after one blank line:"; cat "$p/CLAUDE.md"; exit 1; }
[ "$(cat "$p/.gitignore")" = $'dist/\n\n.claude/rules/charter/' ] ||
  { echo "  ✗ the .gitignore line was not appended after one blank line:"; cat "$p/.gitignore"; exit 1; }
node -e '
  const m = require(process.argv[1])
  if (m.note !== "kept" || m.workspaces["."].join() !== "typescript,react,vitest") throw new Error()
' "$p/charter.json" 2>/dev/null || fail "init did not append to the workspace's modules, keeping the rest"
grep -qx 'plugin install frontend-design@claude-plugins-official --scope project' "$CLAUDE_LOG" ||
  fail "init did not run need_plugins"

# A .gitignore already ignoring the directory, without the slash, is left alone.
p="$(project ignored)"
printf '.claude/rules/charter\n' > "$p/.gitignore"
( cd "$p" && node "$cli" init ) >/dev/null || fail "init beside an existing ignore line failed"
[ "$(cat "$p/.gitignore")" = '.claude/rules/charter' ] || fail "init added a second ignore line"

# A module named twice is recorded once.
p="$(project twice)"
( cd "$p" && node "$cli" init node node ) >/dev/null || fail "init node node failed"
[ "$(node -p 'require(process.argv[1]).workspaces["."].join()' "$p/charter.json")" = node ] ||
  fail "a repeated module was recorded twice"

# ── workspaces ────────────────────────────────────────────────────────────────

p="$(project split)"
mkdir -p "$p/server" "$p/apps/web"
( cd "$p" && node "$cli" init backend typescript node --workspace server ) >/dev/null ||
  fail "init --workspace server failed"
( cd "$p" && node "$cli" init typescript react --workspace apps/web/ ) >/dev/null ||
  fail "init --workspace apps/web/ failed"
node -e '
  const w = require(process.argv[1]).workspaces
  if (w.server.join() !== "backend,typescript,node" || w["apps/web"].join() !== "typescript,react") throw new Error()
' "$p/charter.json" 2>/dev/null || fail "workspaces are not recorded by their path from the root"
grep -qx '  - "server/src/modules/\*\*"' "$p/.claude/rules/charter/server/backend/http.md" ||
  fail "a workspace's rules were not synced with its prefix"
[ -f "$p/.claude/rules/charter/apps/web/react/typescript.md" ] || fail "a nested workspace's rules were not synced"
[ "$(cat "$p/CLAUDE.md")" = '@node_modules/charter/core/rules.md' ] || fail "core was not imported at the root, once"
[ ! -e "$p/server/CLAUDE.md" ] && [ ! -e "$p/apps/web/.claude" ] || fail "init wrote into a workspace"
grep -q 'playwright@claude-plugins-official' "$p/.claude/settings.json" ||
  fail "a workspace's plugins did not land in the root settings.json"

# ── the commit-msg hook ───────────────────────────────────────────────────────

# core carries the commit rule and every project loads core, so every init installs the hook.
p="$(project hooked)"
git -C "$p" init -q
( cd "$p" && node "$cli" init ) >/dev/null || fail "init in a repository failed"
[ -f "$p/.git/hooks/commit-msg" ] || fail "init did not install the commit-msg hook"

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
refuses 'sync with arguments' 'no arguments' sync backend
refuses 'an unknown module' 'backend, node, react, typescript, vitest' init frontend
refuses 'node with react' 'cannot share a workspace' init node react
SETUP='echo "{ \"workspaces\": { \".\": [\"node\"] } }" > charter.json' \
  refuses 'react beside a recorded node' 'cannot share a workspace' init react
refuses 'a missing workspace' 'not a directory' init react --workspace nope
refuses 'a workspace outside' 'outside this repository' init react --workspace ..
SETUP='mkdir @root' refuses 'a workspace named @root' '@root' init react --workspace @root
SETUP='mkdir .claude && echo "{" > .claude/settings.json' \
  refuses 'broken settings JSON' 'settings.json' init typescript
SETUP='mkdir .claude && echo "{ \"enabledPlugins\": [] }" > .claude/settings.json' \
  refuses 'enabledPlugins as an array' 'enabledPlugins' init typescript
SETUP='mkdir .claude && echo "{ \"hooks\": [] }" > .claude/settings.json' \
  refuses 'hooks as an array' 'hooks' init typescript
SETUP='echo "{" > charter.json' refuses 'broken charter.json' 'charter.json' init typescript

# Run from a workspace instead of the root, init would write where no session reads. Without the
# kit in node_modules here, it is not the root.
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

echo "  ✓ init records modules, imports core, wires the sync hook and the ignore line, merges"
echo "    without overwriting, syncs each workspace, refuses cleanly, and reaches a consumer"
