#!/usr/bin/env bash
# The commit-msg hook refuses exactly the messages common/rules/commits.md forbids, and says
# which part of the rule each one broke.
set -euo pipefail

hook="$PWD/common/hooks/commit-msg"
[ -f "$hook" ] || { echo "  ✗ common/hooks/commit-msg does not exist"; exit 1; }

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

echo "  ✓ the commit-msg hook judges $checked messages as the commit rule does"
