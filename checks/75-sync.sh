#!/usr/bin/env bash
# charter sync mirrors each workspace's path-scoped rules into .claude/rules/charter/, prefixed
# with the workspace's path, and core's skills into .claude/skills/charter-<name>/; deletes what
# the kit stopped shipping; prints nothing on success, unless a hook's run wrote a skill; and
# writes nothing at all when it refuses.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
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
# core's index names its rules out of alphabetical order, so printing them in its order shows.
mkdir -p "$kit/core/rules"
printf '# Core\n\n@rules/zeta.md\n@rules/eta.md\n' > "$kit/core/rules.md"
printf '# Zeta\n\nZeta body.\n' > "$kit/core/rules/zeta.md"
printf '# Eta\n\nEta body.\n' > "$kit/core/rules/eta.md"
# A skill with CRLF endings, copied byte for byte, and a supporting file one directory down.
mkdir -p "$kit/core/skills/probe/notes"
printf -- '---\r\ndescription: Probe\r\n---\r\n\r\nProbe body.\r\n' > "$kit/core/skills/probe/SKILL.md"
printf 'More.\n' > "$kit/core/skills/probe/notes/more.md"
out="$p/.claude/rules/charter"
skills="$p/.claude/skills"
(cd "$p" && git init -q)

# By hand, as a person runs it: with no CLAUDE_PROJECT_DIR, even when this check runs in a session.
run() { (cd "$p" && env -u CLAUDE_PROJECT_DIR node node_modules/charter/bin/charter.mjs sync); }
# As a hook runs it, the session having started in $1.
hook() { (cd "$p" && CLAUDE_PROJECT_DIR="$1" node node_modules/charter/bin/charter.mjs sync); }
# What a hook printed, as JSON asking for a reload: its additionalContext, or nothing.
reloads() { node -e '
  const out = JSON.parse(require("fs").readFileSync(0, "utf8")).hookSpecificOutput
  if (out?.hookEventName !== "SessionStart" || out.reloadSkills !== true) process.exit(1)
  process.stdout.write(out.additionalContext ?? "")'; }
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

# ── core's skills: under a charter- prefix, each directory ignoring itself ────

cmp -s "$kit/core/skills/probe/SKILL.md" "$skills/charter-probe/SKILL.md" ||
  { echo "  ✗ core's skill was not mirrored byte for byte:"; cat -v "$skills/charter-probe/SKILL.md"; exit 1; }
cmp -s "$kit/core/skills/probe/notes/more.md" "$skills/charter-probe/notes/more.md" ||
  fail "a skill's supporting file was not mirrored"
[ "$(cat "$skills/charter-probe/.gitignore")" = '*' ] || fail "a mirrored skill does not ignore itself"
(cd "$p" && git check-ignore -q .claude/skills/charter-probe/SKILL.md &&
  git check-ignore -q .claude/skills/charter-probe/.gitignore) ||
  fail "git does not ignore the mirrored skill"

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

# Everything in the mirror is dated 2000, so a write, a delete or a re-created file dates
# something later. Making the mirror read-only instead would prove nothing as root, which
# ignores the mode, as a container CI runs.
find "$out" "$skills" -exec touch -h -t 200001010000 {} +
touch -t 200001020000 "$tmp/dated"
listed="$(cd "$p/.claude" && find . | sort)"
run >/dev/null || fail "a second run failed"
[ "$(cd "$p/.claude" && find . | sort)" = "$listed" ] || fail "a second run changed which files the mirror holds"
[ -z "$(find "$out" "$skills" -newer "$tmp/dated")" ] || fail "a second run wrote files that had not changed"

# ── what the kit or the manifest dropped is deleted ───────────────────────────

rm "$kit/stacks/beta/rules/c.md"
run >/dev/null || fail "sync failed after a rule left the kit"
[ ! -e "$out/apps/web/beta/c.md" ] || fail "a rule the kit no longer ships survived"
[ -e "$out/apps/web/beta/b.md" ] || fail "removing one rule took another with it"
manifest '{ "workspaces": { "server": ["alpha"] } }'
run >/dev/null || fail "sync failed after workspaces were dropped"
[ ! -e "$out/apps" ] || fail "a dropped workspace left its directories behind"
# server/api lies inside server, which stays: only its own directory goes.
[ ! -e "$out/server/api" ] || fail "a dropped nested workspace left its mirror behind"
[ -f "$out/server/alpha/a.md" ] || fail "dropping a nested workspace took its parent's rules with it"

# A charter- skill the kit does not ship goes, and so does a file the kit dropped from one it does.
# Every other skill is the project's own.
mkdir -p "$skills/release" "$skills/charter-gone"
echo own > "$skills/release/SKILL.md"
echo old > "$skills/charter-gone/SKILL.md"
mv "$kit/core/skills/probe/notes" "$tmp/notes"
run >/dev/null || fail "sync failed after a skill left the kit"
[ ! -e "$skills/charter-gone" ] || fail "a charter- skill the kit does not ship survived"
[ ! -e "$skills/charter-probe/notes" ] || fail "a skill file the kit no longer ships survived"
[ -f "$skills/charter-probe/SKILL.md" ] || fail "removing a skill's file took the skill with it"
[ "$(cat "$skills/release/SKILL.md")" = own ] || fail "sync touched a project's own skill"
mv "$tmp/notes" "$kit/core/skills/probe/notes"

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

# A symlink where the mirror wants a file, or a directory, or as the mirror itself, is replaced
# by the real thing; what it points at is never written or pruned through.
echo own > "$p/outside-file.md"
rm "$out/server/alpha/a.md"
ln -s "$p/outside-file.md" "$out/server/alpha/a.md"
run >/dev/null || fail "sync failed over a symlinked rule"
[ "$(cat "$p/outside-file.md")" = own ] || fail "sync wrote through a symlink at a rule's path"
[ ! -L "$out/server/alpha/a.md" ] && grep -q 'Alpha body' "$out/server/alpha/a.md" ||
  fail "a symlink at a rule's path was not replaced by the rule"

mkdir "$p/outside-alpha"
rm -rf "$out/server/alpha"
ln -s "$p/outside-alpha" "$out/server/alpha"
run >/dev/null || fail "sync failed over a symlinked module directory"
[ -z "$(ls -A "$p/outside-alpha")" ] || fail "sync wrote through a symlinked directory in the mirror"
[ ! -L "$out/server/alpha" ] && [ -f "$out/server/alpha/a.md" ] ||
  fail "a symlinked directory in the mirror was not replaced by a real one"

mkdir -p "$p/outside-root/stale"
echo own > "$p/outside-root/stale/x.md"
rm -rf "$out"
ln -s "$p/outside-root" "$out"
run >/dev/null || fail "sync failed over a symlinked mirror"
[ -f "$p/outside-root/stale/x.md" ] || fail "sync pruned through a symlinked mirror"
[ ! -e "$p/outside-root/server" ] || fail "sync wrote through a symlinked mirror"
[ ! -L "$out" ] && [ -f "$out/server/alpha/a.md" ] || fail "a symlinked mirror was not replaced by a real one"

# The same for a skill: a symlink as a mirrored skill's directory or file is replaced, and one
# named charter- that the kit does not ship is removed as a link; neither is written through.
mkdir "$p/outside-skill"
echo own > "$p/outside-skill/SKILL.md"
rm -rf "$skills/charter-probe"
ln -s "$p/outside-skill" "$skills/charter-probe"
run >/dev/null || fail "sync failed over a symlinked skill directory"
[ "$(ls -A "$p/outside-skill")" = SKILL.md ] && [ "$(cat "$p/outside-skill/SKILL.md")" = own ] ||
  fail "sync wrote through a symlinked skill directory"
[ ! -L "$skills/charter-probe" ] && cmp -s "$kit/core/skills/probe/SKILL.md" "$skills/charter-probe/SKILL.md" ||
  fail "a symlinked skill directory was not replaced by the skill"
rm "$skills/charter-probe/SKILL.md"
ln -s "$p/outside-skill/SKILL.md" "$skills/charter-probe/SKILL.md"
run >/dev/null || fail "sync failed over a symlinked skill file"
[ "$(cat "$p/outside-skill/SKILL.md")" = own ] || fail "sync wrote through a symlink at a skill's path"
[ ! -L "$skills/charter-probe/SKILL.md" ] || fail "a symlink at a skill's path was not replaced"
mkdir "$p/outside-stale"
echo keep > "$p/outside-stale/SKILL.md"
ln -s "$p/outside-stale" "$skills/charter-stale"
run >/dev/null || fail "sync failed beside a symlinked charter- skill"
[ ! -e "$skills/charter-stale" ] && [ ! -L "$skills/charter-stale" ] || fail "a symlinked charter- skill survived"
[ -f "$p/outside-stale/SKILL.md" ] || fail "sync deleted through a symlinked charter- skill"

# ── sync roots at CLAUDE_PROJECT_DIR, not at the directory it runs in ─────────

rm -rf "$out"
printed="$( cd "$p/server" && CLAUDE_PROJECT_DIR="$p" node ../node_modules/charter/bin/charter.mjs sync )" ||
  fail "sync failed when run from a subdirectory"
[ -f "$out/server/alpha/a.md" ] || fail "sync did not write at CLAUDE_PROJECT_DIR"
[ ! -e "$p/server/.claude" ] || fail "sync wrote into the directory it was run from"
[ -z "$printed" ] || fail "a hook's sync at the root printed '$printed'"

# A skills directory a hook creates is not scanned by the session it starts, so a hook's run that
# wrote a skill asks for a rescan; one that wrote none, and a run by hand, print nothing.
rm -rf "$skills"
printed="$(hook "$p")" || fail "a hook's sync failed writing a skill"
context="$(reloads <<< "$printed")" || fail "a hook's sync that wrote a skill did not ask for a reload: got '$printed'"
[ -z "$context" ] || fail "a hook's sync at the root added context: '$context'"
printed="$(hook "$p")" || fail "a second hook's sync failed"
[ -z "$printed" ] || fail "a hook's sync that wrote no skill printed '$printed'"
rm -rf "$skills"
printed="$(run)" || fail "sync by hand failed writing a skill"
[ -z "$printed" ] && [ -f "$skills/charter-probe/SKILL.md" ] || fail "sync by hand that wrote a skill printed '$printed'"

# ── from a workspace: the root found by walking up, and core printed ──────────

# A session started in a workspace runs the workspace's hook, with CLAUDE_PROJECT_DIR set to the
# workspace. sync walks up to the nearest charter.json and syncs the root's mirror, then prints
# core, which the root CLAUDE.md's import does not reach from there.
rm -rf "$out"
printed="$( cd "$p" && CLAUDE_PROJECT_DIR="$p/server/api" node node_modules/charter/bin/charter.mjs sync )" ||
  fail "sync failed with CLAUDE_PROJECT_DIR in a workspace"
[ -f "$out/server/alpha/a.md" ] || fail "sync from a workspace did not write the root's mirror"
[ ! -e "$p/server/api/.claude" ] && [ ! -e "$p/server/.claude" ] || fail "sync from a workspace wrote into it"
expected="charter: this session started in server/api/, below the repository root, where CLAUDE.md's import of core does not reach. core's rules follow."
expected+=$'\n\n# Zeta\n\nZeta body.\n\n# Eta\n\nEta body.'
[ "$printed" = "$expected" ] || { echo "  ✗ sync from a workspace did not print core in its index's order:"; echo "$printed"; exit 1; }

# The same run writing a skill carries core in the reload request's context, which the session reads.
rm -rf "$skills"
printed="$(hook "$p/server/api")" || fail "a workspace hook's sync failed writing a skill"
context="$(reloads <<< "$printed")" || fail "a workspace hook's sync that wrote a skill did not ask for a reload"
[ "$context" = "$expected" ] || { echo "  ✗ the reload request did not carry core:"; echo "$context"; exit 1; }

# By hand there is no session to read core, so a run from a workspace syncs the root, silently.
rm -rf "$out"
printed="$( cd "$p/server" && env -u CLAUDE_PROJECT_DIR node ../node_modules/charter/bin/charter.mjs sync )" ||
  fail "sync by hand from a workspace failed"
[ -f "$out/server/alpha/a.md" ] || fail "sync by hand from a workspace did not write the root's mirror"
[ -z "$printed" ] || fail "sync by hand from a workspace printed '$printed'"

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
rm -rf "$out" "$skills/charter-probe"
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

echo "  ✓ sync mirrors and prefixes each workspace's rules and core's skills, deletes what was"
echo "    dropped, finds the root from a workspace and prints core there, asks a session to reload"
echo "    a skill it wrote, and writes nothing when refusing; one run took ${took} ms"
