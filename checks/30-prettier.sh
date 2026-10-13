#!/usr/bin/env bash
# The config is discovered from the package.json key, and it enforces the house style.
set -euo pipefail

cd tests/fixture
npm install --silent --no-audit --no-fund

# 1. Prettier finds the shared config through the "prettier" key. If it silently fell back to
#    its own defaults this would still "work", so the assertions below are what give it meaning.
npx prettier --check src/unformatted.ts >/dev/null 2>&1 &&
  { echo "  ✗ unformatted.ts passed --check; the config is not being applied"; exit 1; }

formatted="$(npx prettier src/unformatted.ts)"

grep -q "'double quotes'" <<< "$formatted" ||
  { echo "  ✗ singleQuote is not in effect"; exit 1; }
grep -q "^export const greeting = 'double quotes'$" <<< "$formatted" ||
  { echo "  ✗ semi: false is not in effect"; exit 1; }
# printWidth 100 keeps that array on one line; the default 80 would break it across lines.
[ "$(grep -c 'columns' <<< "$formatted")" = 1 ] ||
  { echo "  ✗ printWidth is not 100"; exit 1; }

cd ../..

# 2. The ignore files ship and carry the entries every project needs. They are copied rather
#    than referenced, so this proves availability, not application.
for entry in 'node_modules/' 'dist/' '.env' '.DS_Store'; do
  grep -qx -- "$entry" core/ignore/gitignore ||
    { echo "  ✗ core/ignore/gitignore is missing $entry"; exit 1; }
done
for entry in 'node_modules' 'dist' 'test-results' 'playwright-report'; do
  grep -qx -- "$entry" core/ignore/prettierignore ||
    { echo "  ✗ core/ignore/prettierignore is missing $entry"; exit 1; }
done

echo "  ✓ prettier config resolves and applies; ignore files ship with core"
