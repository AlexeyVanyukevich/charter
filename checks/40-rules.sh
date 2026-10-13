#!/usr/bin/env bash
# Each module's rules load through its own index, stay inside the module, and stay small enough
# to be followed. (Interim: Task 5 moves every module but core to the path tier.)
set -euo pipefail

cd tests/fixture
npm install --silent --no-audit --no-fund

kit='node_modules/charter'
indexed='core domains/backend stacks/typescript stacks/node stacks/react'

for module in $indexed; do
  grep -qx "@$kit/$module/rules.md" CLAUDE.md ||
    { echo "  ✗ the fixture's CLAUDE.md does not import $module/rules.md"; exit 1; }
done

# Prints a module's rule line count, after proving its index imports exactly its rules/.
module_lines() {
  local module="$1" dir="$kit/$1" imported shipped total=0 file lines
  [ -f "$dir/rules.md" ] || { echo "  ✗ $module/rules.md does not exist" >&2; return 1; }
  imported="$( { grep -o '^@[^ ]*\.md' "$dir/rules.md" || true; } | sed 's/^@//' | sort)"
  shipped="$(cd "$dir" && find rules -type f -name '*.md' | sort)"
  [ -n "$shipped" ] || { echo "  ✗ $module/rules/ holds no rules" >&2; return 1; }
  [ "$imported" = "$shipped" ] || {
    echo "  ✗ $module/rules.md does not import exactly $module/rules/ (< index, > files):" >&2
    diff <(echo "$imported") <(echo "$shipped") >&2 || true
    return 1
  }
  while read -r file; do
    lines="$(wc -l < "$dir/$file")"
    [ "$lines" -le 60 ] || { echo "  ✗ $module/$file is $lines lines; the limit is 60" >&2; return 1; }
    total=$((total + lines))
  done <<< "$shipped"
  echo "$total"
}

core="$(module_lines core)"
backend="$(module_lines domains/backend)"
typescript="$(module_lines stacks/typescript)"
node_rules="$(module_lines stacks/node)"
react="$(module_lines stacks/react)"

within_budget() {
  local load=$((core + typescript + $2))
  [ "$load" -le 225 ] || {
    echo "  ✗ core + typescript + $1 is $load lines; the limit is 225." >&2
    exit 1
  }
  echo "$load"
}
backend_load="$(within_budget 'node + backend' $((node_rules + backend)))"
react_load="$(within_budget react "$react")"

fact='forbidden_origin'
holders="$( { grep -rlF "$fact" "$kit"/core/rules "$kit"/domains/*/rules "$kit"/stacks/*/rules || true; } |
  wc -l | tr -d ' ')"
[ "$holders" = 1 ] || {
  echo "  ✗ the session check's fact, $fact, must live in exactly one rule; found $holders."
  exit 1
}

if [ -z "${CHARTER_SKIP_SESSION_CHECK:-}" ] && command -v claude >/dev/null 2>&1; then
  consumer="$(mktemp -d)"
  trap 'rm -rf "$consumer"' EXIT
  mkdir -p "$consumer/node_modules/charter"
  tarball="$(cd ../.. && npm pack --silent --pack-destination "$consumer")"
  tar -xzf "$consumer/$tarball" -C "$consumer/node_modules/charter" --strip-components 1
  cp CLAUDE.md "$consumer/CLAUDE.md"
  git -C "$consumer" init -q
  answer="$(cd "$consumer" && claude -p 'Per the HTTP rule in your instructions, which error code answers a write whose Origin is not the app'"'"'s own? Answer with the code and nothing else.' 2>&1 || true)"
  tr -d '`' <<< "$answer" | grep -qx "$fact" || {
    echo "  ✗ a session did not read the imported rule back. Got: $answer"
    exit 1
  }
  echo "  ✓ a real session read a nested rule back"
else
  echo "  · session check skipped (no claude CLI, or CHARTER_SKIP_SESSION_CHECK set)"
fi

echo "  ✓ 5 modules load through their own index; a backend session reads $backend_load lines,"
echo "    a react session $react_load"
