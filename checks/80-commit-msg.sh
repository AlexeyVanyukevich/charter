#!/usr/bin/env bash
# The commit-msg hook refuses exactly the messages core/rules/commits.md forbids, and says
# which part of the rule each one broke.
set -euo pipefail

hook="$PWD/core/hooks/commit-msg"
[ -f "$hook" ] || { echo "  ✗ core/hooks/commit-msg does not exist"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "  ✗ $*"; exit 1; }

# One row per message: the expected result, the words a refusal must contain (empty for a pass),
# and the message, with \n for a newline. A refusal that names no reason leaves its author
# guessing which part of the rule they broke.
#
# Read with `read`, not `$(cat <<…)`: bash 3.2, macOS's, misparses the quotes in a heredoc
# inside a command substitution and then exits 0 without running the rest of the script.
IFS= read -r -d '' cases <<'ROWS' || true
pass||fix: add x
pass||feat(lib): install the kit's commit-msg hook
pass||feat!: divide the rules into four sections
pass||fix(rules)!: rename a rule
pass||fix(plugins-2): say what a scope may hold
pass||revert: undo the release commit
pass||fix: `need_env` returns non-zero once
pass||fix: add x\n# Please enter the commit message for your changes.\n#\n# On branch main
pass||fix: add x\n\n\n
pass||fix: add x\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x\n+Body. Long.
pass||fixup! fix: Anything at all.
pass||squash! fix: add x\n\nA body, folded away later.
pass||amend! fix: add x\n\nfix: add y
refuse|one line|fix: add x\n\nWith a body.
refuse|one line|fix: add x\n\nCo-Authored-By: Someone <someone@example.com>
refuse|unknown type|feature: add x
refuse|unknown type|Fix: add x
refuse|type(scope): subject|add x
refuse|type(scope): subject|fix:add x
refuse|type(scope): subject|fix:
refuse|type(scope): subject|Merge branch 'main' into fix/x
refuse|type(scope): subject|Revert "fix: add x"
refuse|scope|fix(API): add x
refuse|scope|fix(): add x
refuse|capital|fix: Add x
refuse|period|fix: add x.
refuse|empty|# Only a comment\n
ROWS
cases="${cases%$'\n'}"

# Lengths are counted in characters. An em dash is three bytes; a byte count would refuse a
# 72-character subject that holds one.
pad() { printf 'a%.0s' $(seq "$1"); }
cases+=$'\n'"pass||fix: $(pad 67)"
cases+=$'\n'"refuse|72|fix: $(pad 68)"
cases+=$'\n'"pass||fix: x — $(pad 63)"

checked=0
while IFS='|' read -r expect reason message; do
  printf '%b' "$message" > "$tmp/COMMIT_EDITMSG"
  shown="$(printf '%q' "$message")"
  if out="$(bash "$hook" "$tmp/COMMIT_EDITMSG" 2>&1)"; then
    [ "$expect" = pass ] || fail "the hook accepted $shown; it should refuse it ($reason)"
  else
    [ "$expect" = refuse ] || { echo "  ✗ the hook refused $shown:"; echo "$out"; exit 1; }
    grep -qF -- "$reason" <<< "$out" ||
      { echo "  ✗ refusing $shown, the hook did not say '$reason':"; echo "$out"; exit 1; }
  fi
  checked=$((checked + 1))
done <<< "$cases"

# ── need_hooks ────────────────────────────────────────────────────────────────

# This machine's own git config must not decide where hooks land or who commits.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=check GIT_AUTHOR_EMAIL=check@example.com
export GIT_COMMITTER_NAME=check GIT_COMMITTER_EMAIL=check@example.com
lib="$PWD/core/lib.sh"

repo="$tmp/repo"
git init -q "$repo"
( cd "$repo" && source "$lib" && need_hooks ) >/dev/null || fail "need_hooks failed in a fresh repository"
installed="$repo/.git/hooks/commit-msg"
[ -x "$installed" ] || fail "need_hooks did not write an executable .git/hooks/commit-msg"
grep -qx '# charter commit-msg' "$installed" || fail "the installed hook carries no charter marker"

# A second run is silent and changes nothing.
cp "$installed" "$tmp/hook.before"
out="$(cd "$repo" && source "$lib" && need_hooks)" || fail "a second need_hooks failed"
[ -z "$out" ] || fail "a second need_hooks printed '$out'"
cmp -s "$installed" "$tmp/hook.before" || fail "a second need_hooks rewrote the hook"

# A project's own hook is never replaced; the developer is told the kit's is not installed.
repo="$tmp/foreign"
git init -q "$repo"
printf '#!/bin/sh\nexit 0\n' > "$repo/.git/hooks/commit-msg"
cp "$repo/.git/hooks/commit-msg" "$tmp/hook.before"
out="$(cd "$repo" && source "$lib" && need_hooks)" || fail "need_hooks failed beside a foreign hook"
cmp -s "$repo/.git/hooks/commit-msg" "$tmp/hook.before" || fail "need_hooks replaced a foreign hook"
grep -q 'commit-msg' <<< "$out" || fail "need_hooks said nothing about the foreign hook: got '$out'"

# core.hooksPath moves the hooks directory, and the hook goes where git will look for it.
repo="$tmp/hookspath"
git init -q "$repo"
git -C "$repo" config core.hooksPath .githooks
( cd "$repo" && source "$lib" && need_hooks ) >/dev/null || fail "need_hooks failed with core.hooksPath"
[ -f "$repo/.githooks/commit-msg" ] || fail "need_hooks ignored core.hooksPath"

# A wrapper an older kit wrote — dev-kit's included — is brought up to date, not taken for the
# project's own hook.
repo="$tmp/outdated"
git init -q "$repo"
printf '#!/bin/sh\n# dev-kit commit-msg\nf=node_modules/dev-kit/common/hooks/commit-msg\n[ -f "$f" ] || exit 0\nexec bash "$f" "$@"\n' \
  > "$repo/.git/hooks/commit-msg"
( cd "$repo" && source "$lib" && need_hooks ) >/dev/null || fail "need_hooks failed beside an outdated wrapper"
grep -qx '# charter commit-msg' "$repo/.git/hooks/commit-msg" ||
  fail "need_hooks took a dev-kit wrapper for the project's own hook, or left it as it was"

# Outside a repository there is nothing to install into, and ./run must not fail over that.
mkdir -p "$tmp/plain"
( cd "$tmp/plain" && source "$lib" && need_hooks ) >/dev/null || fail "need_hooks failed outside a repository"
[ -z "$(ls -A "$tmp/plain")" ] || fail "need_hooks wrote files outside a repository"

# ── end to end ────────────────────────────────────────────────────────────────

# A consumer holding the unpacked tarball, as a registry or git install gives it: proves the
# wrapper reaches the script and that git refuses, not just that the script exits 1.
consumer="$tmp/consumer"
mkdir -p "$consumer/node_modules/charter"
tarball="$(npm pack --silent --pack-destination "$tmp")"
tar -xzf "$tmp/$tarball" -C "$consumer/node_modules/charter" --strip-components 1
git init -q "$consumer"
echo 'node_modules/' > "$consumer/.gitignore"
git -C "$consumer" add .gitignore
( cd "$consumer" && source node_modules/charter/core/lib.sh && need_hooks ) >/dev/null ||
  fail "need_hooks failed in a consumer"
git -C "$consumer" commit -q -m 'Fix: x' 2>/dev/null && fail "git accepted 'Fix: x' with the hook installed"
git -C "$consumer" commit -q -m 'fix: x' 2>/dev/null || fail "git refused 'fix: x' with the hook installed"

# Before the kit is installed — a fresh clone — the wrapper lets every commit through, and says
# that nothing was checked rather than passing in silence.
rm -rf "$consumer/node_modules"
err="$(git -C "$consumer" commit -q --allow-empty -m 'Fix: y' 2>&1 >/dev/null)" ||
  fail "with the kit not installed, the wrapper still refused a commit"
grep -q 'was not checked' <<< "$err" ||
  fail "with the kit not installed, the wrapper let the commit through without saying so: got '$err'"

echo "  ✓ the commit-msg hook judges $checked messages as the commit rule does; need_hooks installs it"
echo "    once, beside nothing foreign, where core.hooksPath points, and git enforces it"
