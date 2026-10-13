#!/usr/bin/env bash
# charter sync mirrors each workspace's path-scoped rules into .claude/rules/charter/, prefixed
# with the workspace's path; deletes what the kit stopped shipping; prints nothing on success;
# and writes nothing at all when it refuses.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
fail() { echo "  ✗ $*"; exit 1; }

# A project holding a small kit of its own: the real bin/, and modules made up for this check,
# so the check does not move whenever a real rule's globs do.
p="$tmp/project"
kit="$p/node_modules/charter"
mkdir -p "$kit/domains/alpha/rules" "$kit/stacks/beta/rules" "$kit/stacks/gamma" \
  "$p/server/api" "$p/apps/web"
cp -R bin "$kit/bin"
printf -- '---\npaths:\n  - "src/*"\n  - "src/modules/**"\n---\n# Alpha\n\nAlpha body.\n' \
  > "$kit/domains/alpha/rules/a.md"
printf -- '---\npaths:\n  - "**/*.ts"\n---\n# Beta\n' > "$kit/stacks/beta/rules/b.md"
# CRLF, as a kit checked out on Windows has it, parses the same.
printf -- '---\r\npaths:\r\n  - "tests/**"\r\n---\r\n# Beta two\r\n\r\nBeta two body.\r\n' > "$kit/stacks/beta/rules/c.md"
echo '{}' > "$kit/stacks/gamma/oxlint.json"
out="$p/.claude/rules/charter"

run() { (cd "$p" && node node_modules/charter/bin/charter.mjs sync); }
manifest() { printf '%s\n' "$1" > "$p/charter.json"; }

# ── the root workspace ────────────────────────────────────────────────────────

manifest '{ "workspaces": { ".": ["alpha", "gamma"] } }'
start="$(node -p 'Date.now()')"
stdout="$(run)" || fail "sync failed on a valid manifest"
took=$(( $(node -p 'Date.now()') - start ))
# A SessionStart hook's stdout goes into the session's context, so success must say nothing.
[ -z "$stdout" ] || fail "sync printed '$stdout' on success"
expected=$'---\npaths:\n  - "src/*"\n  - "src/modules/**"\n---\n# Alpha\n\nAlpha body.'
[ "$(cat "$out/@root/alpha/a.md")" = "$expected" ] ||
  { echo "  ✗ the root workspace's rule is not the kit's:"; cat "$out/@root/alpha/a.md"; exit 1; }
[ ! -e "$out/@root/gamma" ] || fail "a module with no rules got a directory"

# ── workspaces: prefixed, nested ones too, and the root's mirror gone ──────────

manifest '{ "workspaces": { "./server/": ["alpha"], "server/api": ["beta"], "apps/web": ["beta"] } }'
run >/dev/null || fail "sync failed on three workspaces"
grep -qx '  - "server/src/modules/\*\*"' "$out/server/alpha/a.md" ||
  fail "a workspace's patterns were not prefixed with its path"
grep -qx '  - "server/api/\*\*/\*\.ts"' "$out/server/api/beta/b.md" ||
  fail "a nested workspace's patterns were not prefixed with its own path"
grep -qx '  - "apps/web/tests/\*\*"' "$out/apps/web/beta/c.md" || fail "a CRLF rule was not read"
# The body is copied byte for byte: its CRLF line endings survive; only the header is rewritten.
printf -- '---\npaths:\n  - "apps/web/tests/**"\n---\n# Beta two\r\n\r\nBeta two body.\r\n' > "$tmp/c-expected.md"
cmp -s "$tmp/c-expected.md" "$out/apps/web/beta/c.md" || { echo "  ✗ a CRLF rule's body was not copied unchanged:"; cat -v "$out/apps/web/beta/c.md"; exit 1; }
[ ! -e "$out/@root" ] || fail "the root's mirror survived the root's removal from charter.json"

# ── a second run writes nothing ───────────────────────────────────────────────

# Read-only files and directories: any write or delete fails the run.
chmod -R a-w "$out"
run >/dev/null || fail "a second run tried to write files that had not changed"
chmod -R u+w "$out"

# ── what the kit or the manifest dropped is deleted ───────────────────────────

rm "$kit/stacks/beta/rules/c.md"
run >/dev/null || fail "sync failed after a rule left the kit"
[ ! -e "$out/apps/web/beta/c.md" ] || fail "a rule the kit no longer ships survived"
[ -e "$out/apps/web/beta/b.md" ] || fail "removing one rule took another with it"
manifest '{ "workspaces": { "server": ["alpha"] } }'
run >/dev/null || fail "sync failed after workspaces were dropped"
[ ! -e "$out/apps" ] || fail "a dropped workspace left its directories behind"

# ── nothing outside the mirror is touched ─────────────────────────────────────

echo '# Own' > "$p/.claude/rules/own.md"
run >/dev/null || fail "sync failed beside a project's own rule"
[ -f "$p/.claude/rules/own.md" ] || fail "sync deleted a rule outside .claude/rules/charter/"

# A symlink to a directory inside the mirror is removed as a link; the directory it names is left alone.
mkdir "$p/outside-dir"
echo keep > "$p/outside-dir/k.md"
ln -s "$p/outside-dir" "$out/server/linkdir"
run >/dev/null || fail "sync failed beside a symlink in the mirror"
[ ! -L "$out/server/linkdir" ] || fail "a symlink in the mirror survived"
[ -f "$p/outside-dir/k.md" ] || fail "sync followed a symlink out of the mirror and deleted through it"

# ── sync roots at CLAUDE_PROJECT_DIR, not at the directory it runs in ─────────

rm -rf "$out"
( cd "$p/server" && CLAUDE_PROJECT_DIR="$p" node ../node_modules/charter/bin/charter.mjs sync ) ||
  fail "sync failed when run from a subdirectory"
[ -f "$out/server/alpha/a.md" ] || fail "sync did not write at CLAUDE_PROJECT_DIR"
[ ! -e "$p/server/.claude" ] || fail "sync wrote into the directory it was run from"

# ── refusals: exit 1, the cause on stderr, nothing written ────────────────────

snapshot() { (cd "$p/.claude" && find . | sort && find . -type f -exec cat {} +) | shasum; }
refuses() {
  local name="$1" expect="$2" before err
  before="$(snapshot)"
  err="$(run 2>&1 >/dev/null)" && fail "sync accepted $name"
  grep -qF -- "$expect" <<< "$err" || fail "refusing $name, sync did not say '$expect': got '$err'"
  [ "$(snapshot)" = "$before" ] || fail "sync wrote files while refusing $name"
}

# Every refusal below starts from a mirror that a run would change: a premature write adds
# server/alpha/a.md, a premature prune deletes the stale file. Nothing may move.
rm -rf "$out"
mkdir -p "$out/server/stale"
echo stale > "$out/server/stale/x.md"

manifest '{ "workspaces": '
refuses 'broken JSON' 'charter.json'
manifest '{ "workspaces": [] }'
refuses 'workspaces as a list' 'workspaces'
manifest '{ "workspaces": { "server": ["alpha", "delta"] } }'
refuses 'an unknown module' 'delta'
manifest '{ "workspaces": { "nope": ["alpha"] } }'
refuses 'a missing workspace' 'not a directory'
manifest '{ "workspaces": { "../elsewhere": ["alpha"] } }'
refuses 'a workspace outside' 'outside'
manifest '{ "workspaces": { "/": ["alpha"] } }'
refuses 'an absolute workspace' 'outside'
manifest '{ "workspaces": { "@root": ["alpha"] } }'
refuses 'a workspace named @root' '@root'
rm "$p/charter.json"
refuses 'no manifest' 'charter.json'
manifest '{ "workspaces": { "server": ["alpha"] } }'
printf '# No paths block\n' > "$kit/domains/alpha/rules/d.md"
refuses 'a rule with no paths block' 'd.md'
rm "$kit/domains/alpha/rules/d.md"
mkdir "$kit/domains/beta"
refuses 'a module name used twice' 'beta'
rmdir "$kit/domains/beta"
err="$( (cd "$p" && node node_modules/charter/bin/charter.mjs sync extra) 2>&1 >/dev/null )" &&
  fail "sync accepted an argument"
grep -q 'no arguments' <<< "$err" || fail "sync with an argument did not say it takes none: got '$err'"

echo "  ✓ sync mirrors and prefixes each workspace's rules, deletes what was dropped, prints"
echo "    nothing, and writes nothing when refusing; one run took ${took} ms"
