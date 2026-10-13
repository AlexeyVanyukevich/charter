#!/usr/bin/env bash
# Every path the README promises a consumer actually exists.
set -euo pipefail

[ -f README.md ] || { echo "  ✗ README.md does not exist"; exit 1; }

# The migration section names 1.x paths on purpose, so it is the one part not checked. It is
# the README's last section: everything from its heading down is dropped.
promised="$(sed '/^## Migrating from 1\.x/,$d' README.md)"

# A 1.x path anywhere else is a dead line handed to whoever copies the example. The loops below
# only see 2.0 shapes, so without this an old specifier would pass unexamined.
stale="$(grep -nE '(dev-kit|charter)/(tsconfig|prettier|rules|sh|ignore)([^a-z]|$)' <<< "$promised" || true)"
[ -z "$stale" ] || { echo "  ✗ the README still shows 1.x paths:"; echo "$stale"; exit 1; }

# The install line moves with every release. A range left behind still installs within its
# major, so nothing else fails until a major release, when it installs the previous one.
version="$(node -p "require('./package.json').version")"
range="$(grep -o '"charter": "\^[0-9][^"]*"' <<< "$promised" | sed 's/.*"\^//; s/"$//')"
[ -n "$range" ] || { echo "  ✗ the README has no ^X.Y.Z install range"; exit 1; }
[ "$range" = "$version" ] ||
  { echo "  ✗ the README installs ^$range; package.json is at $version"; exit 1; }

checked=0

# Filesystem paths — rule imports, the shell library, the ignore files. Each never touches npm's
# resolver, so the only promise is that the file is there: strip node_modules/charter/ and look.
while read -r path; do
  rel="${path#node_modules/charter/}"
  [ -f "$rel" ] || { echo "  ✗ README promises $path; $rel does not exist"; exit 1; }
  checked=$((checked + 1))
done < <(grep -o 'node_modules/charter/[^ )`"]*' <<< "$promised" | sort -u)

# Specifiers that go through module resolution must be in the exports map.
specifier='charter/stacks/\(typescript\|node\|react\)/\(tsconfig\|prettier\)[^ )`"]*'
while read -r spec; do
  sub="./${spec#charter/}"
  node -e "
    const map = require('./package.json').exports
    if (!map['$sub']) { console.error('  ✗ README promises $spec, absent from exports'); process.exit(1) }
    const target = map['$sub'].replace(/^\.\//, '')
    if (!require('fs').existsSync(target)) {
      console.error('  ✗ exports maps $sub to ' + target + ', which does not exist')
      process.exit(1)
    }
  "
  checked=$((checked + 1))
done < <(grep -o "$specifier" <<< "$promised" | sort -u)

[ "$checked" -ge 8 ] || { echo "  ✗ only $checked paths checked; the README looks incomplete"; exit 1; }

echo "  ✓ the install range matches $version; $checked promised paths all resolve"
