#!/usr/bin/env bash
# charter release: the gates, the commits since the last tag and the version they propose.
# Every case runs in a repository of its own, in a temporary directory, with a bare repository
# as its origin, so nothing here reaches a network or this repository's own tags.
set -euo pipefail

charter="$PWD/bin/charter.mjs"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "  ✗ $*"; exit 1; }

# A released project: package.json at 1.2.3, tagged v1.2.3, pushed, and one fix since, pushed.
# Leaves $r as the clone; $tmp/<n>/origin.git as its origin.
n=0
fresh() {
  n=$((n + 1))
  r="$tmp/$n/repo"
  git init -q --bare -b main "$tmp/$n/origin.git"
  git init -q -b main "$r"
  (
    cd "$r"
    git config user.email check@example.com
    git config user.name check
    git remote add origin "$tmp/$n/origin.git"
    printf '{ "name": "app", "version": "1.2.3" }\n' > package.json
    git add package.json && git commit -qm 'chore: release 1.2.3'
    git tag v1.2.3
    git commit -q --allow-empty -m 'fix: keep the session'
    git push -q origin main v1.2.3
  )
}
commit() { (cd "$r" && for subject in "$@"; do git commit -q --allow-empty -m "$subject"; done && git push -q origin main); }
release() { (cd "$r" && node "$charter" release "$@"); }

# ── the proposal: one row per set of subjects since the last tag ──────────────
# name | subjects since v1.2.3, after the fix fresh() adds, separated by ; | proposed

while IFS='|' read -r name subjects expected; do
  [ -n "$name" ] || continue
  fresh
  IFS=';' read -ra list <<< "$subjects"
  [ -z "$subjects" ] || commit "${list[@]}"
  out="$(release 2>&1)" || fail "$name: charter release failed: $out"
  grep -qx "Proposed: $expected" <<< "$out" || { echo "  ✗ $name: expected Proposed: $expected, got:"; echo "$out"; exit 1; }
done <<'ROWS'
a fix alone||1.2.4
docs and tests|docs: say how;test: cover it|1.2.4
a subject that is not conventional|Merge branch 'topic'|1.2.4
a feat among fixes|fix: a;feat(lib): b;docs: c|1.3.0
a breaking feat|feat!: drop the old path;fix: b|2.0.0
a breaking change with a scope|refactor(api)!: rename the route|2.0.0
ROWS

# With no tag yet, the base is package.json's version and every commit counts.
n=$((n + 1))
r="$tmp/$n/repo"
git init -q -b main "$r"
(cd "$r" && git config user.email check@example.com && git config user.name check &&
  printf '{ "name": "app", "version": "0.1.0" }\n' > package.json && git add package.json &&
  git commit -qm 'feat: start')
out="$(release 2>&1)" || fail "an untagged project: charter release failed: $out"
grep -qx 'Proposed: 0.2.0' <<< "$out" || { echo "  ✗ an untagged project did not propose 0.2.0:"; echo "$out"; exit 1; }
grep -q 'no origin remote' <<< "$out" || fail "a project with no origin did not say it skipped that gate"

# ── what it shows ─────────────────────────────────────────────────────────────

fresh
commit 'feat(lib): add need_tools' 'docs: say how'
printf '{ "workspaces": {}, "release": { "verify": "echo verify-ran >&2" } }\n' > "$r/charter.json"
(cd "$r" && git add charter.json && git commit -qm 'chore: verify releases' && git push -q origin main)
before="$(cd "$r" && git rev-parse HEAD && git tag && git status --porcelain && cat package.json)"
out="$(release 2>"$tmp/err")" || fail "charter release failed on a releasable project: $out $(cat "$tmp/err")"
for line in 'Since v1.2.3, 4 commits:' '  feat(lib): add need_tools' '  fix: keep the session' \
  '  ✓ on main' '  ✓ the working tree is clean' '  ✓ level with origin/main' \
  '  ✓ no plan outside docs/superpowers/plans/archive/' '  ✓ release.verify passed' 'Proposed: 1.3.0'; do
  grep -qxF -- "$line" <<< "$out" || { echo "  ✗ charter release did not show '$line':"; echo "$out"; exit 1; }
done
grep -qx 'verify-ran' "$tmp/err" || fail "release.verify's output did not reach stderr"
[ "$(cd "$r" && git rev-parse HEAD && git tag && git status --porcelain && cat package.json)" = "$before" ] ||
  fail "charter release with no version changed the repository"
fresh
out="$(release 2>&1)" || fail "charter release failed with no charter.json"
grep -qF 'no release.verify in charter.json' <<< "$out" || fail "with no release.verify, charter release did not say the checks were not run"

# ── the gates: one row per state, each refused with its cause ─────────────────
# name | what turns the fresh project into that state | what the refusal says

while IFS='|' read -r name setup expect; do
  [ -n "$name" ] || continue
  fresh
  (cd "$r" && eval "$setup")
  out="$(release 2>&1)" && { echo "  ✗ charter release accepted $name:"; echo "$out"; exit 1; }
  grep -qF -- "$expect" <<< "$out" || { echo "  ✗ refusing $name, charter release did not say '$expect':"; echo "$out"; exit 1; }
done <<'ROWS'
another branch|git switch -q -c topic|✗ on main
a dirty tree|echo x > dirty.txt|✗ the working tree is clean
main behind origin|git clone -q "$PWD/../origin.git" ../other && (cd ../other && git -c user.email=o@example.com -c user.name=o commit -q --allow-empty -m 'fix: elsewhere' && git push -q origin main)|✗ level with origin/main
main ahead of origin|git commit -q --allow-empty -m 'fix: unpushed'|✗ level with origin/main
a plan outside the archive|mkdir -p docs/superpowers/plans/archive && echo plan > docs/superpowers/plans/x.md && git add -A && git commit -qm 'docs: plan x' && git push -q origin main|✗ no plan outside docs/superpowers/plans/archive/
a failing release.verify|printf '{ "release": { "verify": "exit 3" } }\n' > charter.json && git add -A && git commit -qm 'chore: verify' && git push -q origin main|✗ release.verify failed
nothing since the last tag|git reset -q --hard v1.2.3 && git push -q -f origin main|✗ something to release
release that is not an object|printf '{ "release": [] }\n' > charter.json && git add -A && git commit -qm 'chore: x' && git push -q origin main|"release" in charter.json
a verify that is not a string|printf '{ "release": { "verify": 1 } }\n' > charter.json && git add -A && git commit -qm 'chore: x' && git push -q origin main|release.verify
files that are not a list of strings|printf '{ "release": { "files": "README.md" } }\n' > charter.json && git add -A && git commit -qm 'chore: x' && git push -q origin main|release.files
ROWS

# A plan in the archive is spent, not in progress.
fresh
(cd "$r" && mkdir -p docs/superpowers/plans/archive && echo plan > docs/superpowers/plans/archive/x.md &&
  git add -A && git commit -qm 'docs: archive x' && git push -q origin main)
release >/dev/null 2>&1 || fail "an archived plan stopped the release"

echo "  ✓ charter release proposes the version from the commits since the last tag, shows them and"
echo "    every gate, refuses each failed gate with its cause, and changes nothing"
