#!/usr/bin/env bash
# Each stack's lint config fires the rules it promises, holds the exceptions it makes, and
# merges with the others the way the README tells a project to combine them.
set -euo pipefail

cd tests/fixture
npm install --silent --no-audit --no-fund

oxlint="$PWD/node_modules/.bin/oxlint"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "  ✗ $*"; exit 1; }

# A project's .oxlintrc.json, extending the named stacks in the order given. Node writes the
# paths: in Git Bash on Windows, $PWD is /c/Users/…, which oxlint reads as C:/c/Users/….
config() {
  node -e '
    const { resolve } = require("path")
    const stacks = process.argv.slice(1).map((stack) => resolve("node_modules/charter/stacks", stack, "oxlint.json"))
    console.log(JSON.stringify({ extends: stacks }))
  ' "$@" > "$tmp/oxlintrc.json"
}

# The rules that fired, as plugin(rule), sorted and space-separated; '-' for none.
fired() {
  local out
  out="$(cd lint && "$oxlint" -c "$tmp/oxlintrc.json" --format unix "$@" 2>&1 || true)"
  if grep -q 'Failed\|error:' <<< "$out" && ! grep -q '\[Error/' <<< "$out"; then
    echo "oxlint did not run: $out" >&2
    return 1
  fi
  local rules
  rules="$(grep -oE '\[(Error|Warning)/[a-z0-9_-]+\([a-z0-9-]+\)\]' <<< "$out" |
    sed -E 's/^\[[A-Za-z]+\/(.*)\]$/\1/' | sort -u | tr '\n' ' ' | sed 's/ $//')"
  echo "${rules:--}"
}

# One row per case: the stacks extended, the files under tests/fixture/lint, and exactly the
# rules expected to fire. Exactly, not at least: a rule the kit turned off that fires anyway is
# as much a failure as a promised rule that does not.
IFS= read -r -d '' cases <<'ROWS' || true
typescript|any.ts|typescript(no-explicit-any)
typescript|floating.ts|typescript(no-floating-promises)
typescript|switch.ts|typescript(switch-exhaustiveness-check)
typescript|misused.ts|typescript(no-misused-promises)
typescript|onclick.tsx|typescript(no-misused-promises)
typescript|cast.ts|-
typescript|sort.ts|-
typescript|migrations/0001.ts|typescript(no-explicit-any)
node|migrations/0001.ts|-
node|any.ts|typescript(no-explicit-any)
react|onclick.tsx|-
react|key.tsx|react(jsx-key)
react|a11y.tsx|jsx-a11y(click-events-have-key-events) jsx-a11y(no-static-element-interactions)
typescript|a11y.tsx|-
typescript vitest|focused.test.ts|vitest(no-focused-tests)
typescript vitest|message.test.ts|-
node vitest|any.ts focused.test.ts|typescript(no-explicit-any) vitest(no-focused-tests)
vitest node|any.ts focused.test.ts|typescript(no-explicit-any) vitest(no-focused-tests)
ROWS
cases="${cases%$'\n'}"

checked=0
while IFS='|' read -r stacks files expected; do
  # shellcheck disable=SC2086
  config $stacks
  # shellcheck disable=SC2086
  got="$(fired $files)" || fail "oxlint could not lint $files under $stacks"
  [ "$got" = "$expected" ] ||
    fail "under $stacks, $files fired '$got'; expected '$expected'"
  checked=$((checked + 1))
done <<< "$cases"

# The type-aware rules are real only if the config asks for them: without oxlint-tsgolint the
# run must fail and name the package, not quietly lint without types.
mkdir -p "$tmp/bare"
cp lint/floating.ts "$tmp/bare/"
echo '{ "include": ["*.ts"] }' > "$tmp/bare/tsconfig.json"
config typescript
out="$(cd "$tmp/bare" && env -u OXLINT_TSGOLINT_PATH "$oxlint" -c "$tmp/oxlintrc.json" floating.ts 2>&1)" &&
  fail "oxlint passed without oxlint-tsgolint; the config does not turn on type-aware rules"
grep -q 'oxlint-tsgolint' <<< "$out" ||
  { echo "  ✗ without oxlint-tsgolint, oxlint failed without naming it:"; echo "$out"; exit 1; }

echo "  ✓ $checked lint cases fire exactly what each stack promises, and type-aware rules"
echo "    need oxlint-tsgolint"
