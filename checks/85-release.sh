#!/usr/bin/env bash
# charter release: the gates, the commits since the last tag and the version they propose; the
# notes' skeleton; and the cut — the bump, the commit and the tag, never a push.
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
    printf '{\n  "name": "app",\n  "version": "1.2.3"\n}\n' > package.json
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

# ── the notes' skeleton: stdout is the notes, stderr the title and what was left out ──

fresh
commit 'docs: say how' 'feat(lib): add need_tools' 'feat!: drop the old path'
before="$(cd "$r" && git rev-parse HEAD && git tag && git status --porcelain)"
release notes > "$tmp/notes" 2> "$tmp/err" || fail "charter release notes failed: $(cat "$tmp/err")"
cat > "$tmp/expected" <<'NOTES'
## What's new

- feat!: drop the old path
- feat(lib): add need_tools

## Fixes

- fix: keep the session

## Known gaps

<What a consumer can hit that this release does not fix. Delete this section if there is nothing.>

## Upgrading

Move the dependency to `^2.0.0` and run `npm install`. <What else a consumer has to change, or: Nothing else changes.>
NOTES
diff "$tmp/expected" "$tmp/notes" >/dev/null || { echo "  ✗ the notes' skeleton is not the expected one:"; diff "$tmp/expected" "$tmp/notes"; exit 1; }
grep -qxF 'Title: v2.0.0 — <what a consumer would notice>' "$tmp/err" || fail "the notes did not suggest a title on stderr: $(cat "$tmp/err")"
grep -qxF 'Left out: docs: say how' "$tmp/err" || fail "the notes did not list what they left out on stderr: $(cat "$tmp/err")"
[ "$(cd "$r" && git rev-parse HEAD && git tag && git status --porcelain)" = "$before" ] || fail "charter release notes changed the repository"

# A version given decides the number; a release with no feat has no "What's new".
fresh
release notes 1.2.9 > "$tmp/notes" 2>/dev/null || fail "charter release notes 1.2.9 failed"
grep -q "What's new" "$tmp/notes" && fail "a release with no feat got a What's new section"
grep -qF 'Move the dependency to `^1.2.9`' "$tmp/notes" || fail "the version given did not reach Upgrading"
release notes minor > "$tmp/notes" 2>/dev/null || fail "charter release notes minor failed"
grep -qF 'Move the dependency to `^1.3.0`' "$tmp/notes" || fail "a level given did not bump the last tag's version"
err="$(release notes banana 2>&1 >/dev/null)" && fail "charter release notes accepted 'banana'"
grep -qF 'banana' <<< "$err" || fail "refusing a version, charter release notes did not name it: $err"

# ── the cut: every copy of the version, one commit through the commit rule, a tag, no push ──

# A project as the kit leaves one: a lockfile, the README's install range listed in release.files,
# the commit-msg hook need_hooks installs, and a document that only mentions the version.
cut_project() {
  fresh
  (
    cd "$r"
    npm install --package-lock-only --ignore-scripts --offline --silent
    printf 'Install: "app": "^1.2.3"\n' > README.md
    printf 'Since 1.2.3 the session is kept.\n' > history.md
    # Dated records: they mention versions as history, and are never copies of one.
    mkdir -p docs/superpowers/specs docs/superpowers/plans/archive
    printf '1.2.3 showed the gap.\n' > docs/superpowers/specs/2026-01-01-x-design.md
    printf 'Before 1.2.3.\n' > docs/superpowers/plans/archive/2026-01-01-x.md
    printf '{ "workspaces": {}, "release": { "files": ["README.md"] } }\n' > charter.json
    git add -A && git commit -qm 'chore: list the release files' && git push -q origin main
    mkdir -p "../hooks"
    printf '#!/usr/bin/env bash\nexec bash "%s/core/hooks/commit-msg" "$1"\n' "${charter%/bin/charter.mjs}" > ../hooks/commit-msg
    chmod +x ../hooks/commit-msg
    git config core.hooksPath "$PWD/../hooks"
  )
}
state() { (cd "$r" && git rev-parse HEAD && git tag && git status --porcelain && git ls-remote origin); }

cut_project
commit 'feat(lib): add need_tools'
remote="$(cd "$r" && git ls-remote origin)"
out="$(release 1.3.0 2>&1)" || { echo "  ✗ charter release 1.3.0 failed:"; echo "$out"; exit 1; }
[ "$(cd "$r" && git log -1 --format=%s)" = 'chore: release 1.3.0' ] || fail "the release commit's subject is not 'chore: release 1.3.0'"
[ "$(cd "$r" && git show --name-only --format= HEAD | sort | tr '\n' ' ')" = 'README.md package-lock.json package.json ' ] ||
  fail "the release commit holds $(cd "$r" && git show --name-only --format= HEAD | tr '\n' ' '), not the version's copies alone"
[ "$(cd "$r" && git show HEAD -- package.json | grep '^[-+] ')" = $'-  "version": "1.2.3"\n+  "version": "1.3.0"' ] ||
  { echo "  ✗ package.json changed beyond its version:"; (cd "$r" && git show HEAD -- package.json); exit 1; }
grep -qF '"version": "1.3.0"' "$r/package-lock.json" && ! grep -qF '"version": "1.2.3"' "$r/package-lock.json" ||
  fail "the lockfile's version was not bumped"
[ "$(cat "$r/README.md")" = 'Install: "app": "^1.3.0"' ] || fail "a listed file's version was not bumped: $(cat "$r/README.md")"
grep -qF 'history.md' <<< "$out" || fail "an unlisted file still holding 1.2.3 was not reported: $out"
grep -qF 'docs/' <<< "$out" && fail "a dated record under docs/ was reported as a copy of the version: $out"
[ "$(cat "$r/history.md")" = 'Since 1.2.3 the session is kept.' ] || fail "an unlisted file was changed"
[ "$(cd "$r" && git cat-file -t v1.3.0)" = commit ] || fail "the tag is not a lightweight tag"
[ "$(cd "$r" && git rev-parse v1.3.0)" = "$(cd "$r" && git rev-parse HEAD)" ] || fail "the tag is not on the release commit"
[ "$(cd "$r" && git ls-remote origin)" = "$remote" ] || fail "charter release pushed"
grep -qF 'git push origin main v1.3.0' <<< "$out" || fail "charter release did not say how to push: $out"
# A level bumps the last tag's version.
commit 'fix: after'
out="$(release patch 2>&1)" || { echo "  ✗ charter release patch failed:"; echo "$out"; exit 1; }
[ "$(cd "$r" && git describe --tags)" = v1.3.1 ] || fail "charter release patch did not tag v1.3.1"

# With npm workspaces, the root's version and its entries in the lockfile move; a workspace's do not.
fresh
(
  cd "$r"
  printf '{\n  "name": "root",\n  "version": "1.2.3",\n  "workspaces": ["packages/a"]\n}\n' > package.json
  mkdir -p packages/a && printf '{\n  "name": "a",\n  "version": "0.0.1"\n}\n' > packages/a/package.json
  npm install --package-lock-only --ignore-scripts --offline --silent
  git add -A && git commit -qm 'build: split into workspaces' && git push -q origin main
)
release minor >/dev/null 2>&1 || fail "charter release minor failed in an npm workspaces project"
(cd "$r" && node -e '
  const lock = require("./package-lock.json"), a = require("./packages/a/package.json")
  const ok = lock.version === "1.3.0" && lock.packages[""].version === "1.3.0" &&
    lock.packages["packages/a"].version === "0.0.1" && a.version === "0.0.1"
  process.exit(ok ? 0 : 1)') || fail "in an npm workspaces project the lockfile's versions are wrong"

# Each refusal writes nothing: no file, no commit, no tag, no push.
# name | what turns a fresh cut_project into that state | version | what the refusal says
while IFS='|' read -r name setup version expect; do
  [ -n "$name" ] || continue
  cut_project
  (cd "$r" && eval "$setup")
  before="$(state)"
  out="$(release "$version" 2>&1)" && { echo "  ✗ charter release $version accepted $name:"; echo "$out"; exit 1; }
  grep -qF -- "$expect" <<< "$out" || { echo "  ✗ refusing $name, charter release did not say '$expect':"; echo "$out"; exit 1; }
  [ "$(state)" = "$before" ] || fail "charter release wrote something while refusing $name"
done <<'ROWS'
a failed gate|echo x > dirty.txt|1.3.0|✗ the working tree is clean
the last tag's version|:|1.2.3|1.2.3 is not above
a lower version|:|1.0.0|1.0.0 is not above
a tag that exists off main|git switch -q -c side && git commit -q --allow-empty -m 'fix: side' && git tag v1.3.0 && git switch -q main && git branch -q -D side|1.3.0|v1.3.0 already exists
a listed file without the version|printf 'Install: "app": "^1.2.2"\n' > README.md && git commit -qam 'docs: old range' && git push -q origin main|1.3.0|README.md does not hold 1.2.3
a listed file that is missing|git rm -q README.md && git commit -qm 'docs: drop the readme' && git push -q origin main|1.3.0|README.md does not hold 1.2.3
package.json ahead of the tag|sed -i.bak 's/1.2.3/1.2.4/' package.json && rm package.json.bak && git commit -qam 'chore: bump by hand' && git push -q origin main|1.3.0|package.json says 1.2.4
not a version|:|banana|banana
ROWS

echo "  ✓ charter release proposes the version from the commits since the last tag, shows them and"
echo "    every gate, refuses each failed gate with its cause, and changes nothing; its notes"
echo "    skeleton sorts the commits into sections and suggests a title; and the cut bumps every"
echo "    listed copy, commits through the commit rule, tags, reports stray copies, and never pushes"
