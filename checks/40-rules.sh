#!/usr/bin/env bash
# core's rules load in every session through one index; every other rule carries a paths: block
# and loads only once a session touches a matching file; and each tier stays inside its budget.
set -euo pipefail

cd tests/fixture
npm install --silent --no-audit --no-fund

kit='node_modules/charter'

grep -qx "@$kit/core/rules.md" CLAUDE.md ||
  { echo "  ✗ the fixture's CLAUDE.md does not import core/rules.md"; exit 1; }

# core's index imports exactly core/rules/: nothing left out, nothing from elsewhere.
imported="$( { grep -o '^@[^ ]*\.md' "$kit/core/rules.md" || true; } | sed 's/^@//' | sort)"
shipped="$(cd "$kit/core" && find rules -type f -name '*.md' | sort)"
[ "$imported" = "$shipped" ] || {
  echo "  ✗ core/rules.md does not import exactly core/rules/ (< index, > files):"
  diff <(echo "$imported") <(echo "$shipped") || true
  exit 1
}

# No module has an index: an @ import of one would load its rules in every session.
stray="$(find "$kit/domains" "$kit/stacks" -name rules.md 2>/dev/null || true)"
[ -z "$stray" ] || { echo "  ✗ a module has an index, so its rules would always load:"; echo "$stray"; exit 1; }

# A rule's body: the file without its paths: block, which Claude Code strips before loading.
body_lines() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm { n++ } END { print n + 0 }' "$1"
}

# The block sync reads without a YAML parser: ---, paths:, one   - "<pattern>" line or more, ---.
has_paths_block() {
  awk 'NR == 1 { ok = ($0 == "---"); next }
       NR == 2 { ok = ok && ($0 == "paths:"); next }
       ok && /^  - "[^"]+"$/ { n++; next }
       { print ((ok && n > 0 && $0 == "---") ? "yes" : "no"); done = 1; exit }
       END { if (!done) print "no" }' "$1"
}

total() { local sum=0 f; for f in "$@"; do sum=$((sum + $(body_lines "$f"))); done; echo "$sum"; }

checked=0
for f in "$kit"/core/rules/*.md "$kit"/domains/*/rules/*.md "$kit"/stacks/*/rules/*.md; do
  [ -e "$f" ] || continue
  lines="$(body_lines "$f")"
  [ "$lines" -le 60 ] || { echo "  ✗ ${f#"$kit"/} is $lines lines; the limit is 60"; exit 1; }
  case "$f" in
    "$kit"/core/*) ;;
    *) [ "$(has_paths_block "$f")" = yes ] ||
      { echo "  ✗ ${f#"$kit"/} does not open with a paths: block"; exit 1; } ;;
  esac
  checked=$((checked + 1))
done

# Module names are unique: charter.json names a module, not its directory.
dupes="$(cd "$kit" && ls -d domains/*/ stacks/*/ | awk -F/ '{ print $2 }' | sort | uniq -d)"
[ -z "$dupes" ] || { echo "  ✗ module names used twice: $dupes"; exit 1; }

# Budgets — spec 2026-10-13-foundation-design §5. The always tier is what every session reads;
# a workspace's worst case is core plus every path rule of its modules, as if every glob matched.
# Over a limit, move a rule to the module that needs it; raising the limit only spends the
# budget that keeps the rules followed.
always="$(total "$kit"/core/rules/*.md)"
[ "$always" -le 150 ] || {
  echo "  ✗ core's rules are $always lines; the always tier's limit is 150. Move a rule to the module that needs it rather than raising the limit."
  exit 1
}
worst() {
  local m f
  local files=("$kit"/core/rules/*.md)
  for m in "$@"; do
    for f in "$kit"/domains/"$m"/rules/*.md "$kit"/stacks/"$m"/rules/*.md; do
      [ -e "$f" ] && files+=("$f")
    done
  done
  total "${files[@]}"
}
backend_worst="$(worst backend typescript node vitest)"
react_worst="$(worst typescript react vitest)"
[ "$backend_worst" -le 225 ] || {
  echo "  ✗ core + backend, typescript, node, vitest is $backend_worst lines if every glob matched; the limit is 225. Move a rule to the module that needs it rather than raising the limit."
  exit 1
}
[ "$react_worst" -le 225 ] || {
  echo "  ✗ core + typescript, react, vitest is $react_worst lines if every glob matched; the limit is 225. Move a rule to the module that needs it rather than raising the limit."
  exit 1
}

# The live session asks for two facts no session could guess, one in core, one in a path rule.
# Each fact must live in exactly one rule, or the session's answer stops proving which file
# loaded. These guards keep that true, and run even when the session is skipped.
core_fact='2026-09-29'
path_fact='forbidden_origin'
holders() {
  { grep -rlF "$1" "$kit"/core/rules "$kit"/domains/*/rules "$kit"/stacks/*/rules || true; } | sed "s|^$kit/||"
}
[ "$(holders "$core_fact")" = core/rules/backlog.md ] ||
  { echo "  ✗ $core_fact must live in core/rules/backlog.md alone; found: $(holders "$core_fact")"; exit 1; }
[ "$(holders "$path_fact")" = domains/backend/rules/http.md ] ||
  { echo "  ✗ $path_fact must live in domains/backend/rules/http.md alone; found: $(holders "$path_fact")"; exit 1; }

# Skipped where the CLI is absent: the assertions above hold on their own.
#
# The session runs in a scratch consumer holding the unpacked `npm pack` tarball, set up by a real
# `charter init`, so the hook, the manifest and sync are proven together. The mirror is deleted
# before each session, so only the hook can have written it.
#
# It does not run in the fixture: the fixture's `file:` install is a symlink out of the project,
# and Claude Code does not follow an import whose real path lies outside the project. The fixture
# would fail where every registry or git consumer, who gets a real directory, succeeds.
if [ -z "${CHARTER_SKIP_SESSION_CHECK:-}" ] && command -v claude >/dev/null 2>&1; then
  consumer="$(mktemp -d)"
  trap 'rm -rf "$consumer"' EXIT
  mkdir -p "$consumer/node_modules/charter" "$consumer/src/modules/issues" "$consumer/scripts"
  tarball="$(cd ../.. && npm pack --silent --pack-destination "$consumer")"
  tar -xzf "$consumer/$tarball" -C "$consumer/node_modules/charter" --strip-components 1
  echo 'export const routes = []' > "$consumer/src/modules/issues/issue.routes.ts"
  echo 'export const seed = 1' > "$consumer/scripts/seed.ts"
  git -C "$consumer" init -q
  ( cd "$consumer" && node node_modules/charter/bin/charter.mjs init backend typescript node vitest ) >/dev/null ||
    { echo "  ✗ charter init failed in the scratch consumer"; exit 1; }

  ask() {
    rm -rf "$consumer/.claude/rules/charter"
    ( cd "$consumer" && claude -p "First use Read on $1 and nothing else. Then answer from your loaded instructions only, never by searching files. Line 1: the date the backlog rule's example entry was found, or NONE. Line 2: the error code for a write whose Origin is not the app's own, or NONE. Nothing else." \
      --disallowedTools Bash Grep Glob Edit Write Agent WebFetch WebSearch 2>&1 || true ) | tr -d '`'
  }
  for run in 1 2 3; do
    answer="$(ask scripts/seed.ts)"
    grep -qF "$core_fact" <<< "$answer" && grep -qx 'NONE' <<< "$answer" && ! grep -qF "$path_fact" <<< "$answer" ||
      { echo "  ✗ run $run: outside http.md's globs, wanted $core_fact and NONE. Got: $answer"; exit 1; }
    answer="$(ask src/modules/issues/issue.routes.ts)"
    grep -qF "$core_fact" <<< "$answer" && grep -qx "$path_fact" <<< "$answer" ||
      { echo "  ✗ run $run: in a routes file, wanted $core_fact and $path_fact. Got: $answer"; exit 1; }
  done
  echo "  ✓ three times over, a real session read core at once and http.md only in a matching file"
else
  echo "  · session check skipped (no claude CLI, or CHARTER_SKIP_SESSION_CHECK set)"
fi

echo "  ✓ $checked rules: core loads always ($always lines), the rest by path; a backend"
echo "    workspace reads at most $backend_worst, a react one $react_worst"
