#!/usr/bin/env bash
# The bases are extendable by specifier, and the strictness they promise actually bites.
set -euo pipefail

cd tests/fixture
npm install --silent --no-audit --no-fund

# 1. The clean sources compile under the node stack, and under the typescript stack alone for a
#    workspace that is neither node nor react. This is what proves `extends` resolved at all:
#    an unresolved extends is a hard tsc error, not a silent fallback to defaults.
npx tsc --noEmit -p tsconfig.json ||
  { echo "  ✗ clean.ts did not compile under stacks/node/tsconfig"; exit 1; }
npx tsc --noEmit -p tsconfig.common.json ||
  { echo "  ✗ clean.ts did not compile under stacks/typescript/tsconfig"; exit 1; }

# 2. The violations do not. Asserting on codes rather than on prose keeps this working when
#    the compiler rewords a message.
probe="$(npx tsc --noEmit -p tsconfig.probe.json 2>&1 || true)"

for code in TS2322 TS2375; do
  grep -q "$code" <<< "$probe" || {
    echo "  ✗ expected $code from violations.ts; strictness is not being inherited"
    echo "$probe"
    exit 1
  }
done

# 3. The react stack carries the DOM lib. Without it this file must NOT compile, which is what
#    stops a Node project silently believing it has a `document`.
npx tsc --noEmit -p tsconfig.web.json ||
  { echo "  ✗ dom.ts did not compile under stacks/react/tsconfig"; exit 1; }

npx tsc --noEmit --strict --types node --lib ES2023 src/dom.ts >/dev/null 2>&1 &&
  { echo "  ✗ dom.ts compiled without the DOM lib; the react base is not what makes it work"; exit 1; }

echo "  ✓ typescript, node and react resolve by specifier; strictness and the DOM lib are real"
