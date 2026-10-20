#!/usr/bin/env bash
# The html stack checks hand-written markup element by element, with two tools: its html-validate
# config, extended by the fixture's .htmlvalidate.json as the README tells a project to, and
# `charter scan`, which runs axe-core over static files with the tools the project installed.
set -euo pipefail

cd tests/fixture
npm install --silent --no-audit --no-fund

kit="$PWD/node_modules/charter"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "  ✗ $*"; exit 1; }

# The rule ids each tool reported, sorted and space-separated; '-' for none.
validated() {
  local out
  out="$(node_modules/.bin/html-validate --formatter json "$@" 2>&1 || true)"
  node -e '
    let results
    try { results = JSON.parse(process.argv[1]) } catch { console.error(process.argv[1]); process.exit(1) }
    const ids = [...new Set(results.flatMap((r) => r.messages.map((m) => m.ruleId)))].sort()
    console.log(ids.join(" ") || "-")
  ' "$out"
}
scanned() {
  local out ids
  out="$(node_modules/.bin/charter scan "$@" 2>&1)" && { echo -; return; }
  ids="$(sed -nE 's/^[^ ]+: ([a-z0-9-]+) — .*/\1/p' <<< "$out" | sort -u | tr '\n' ' ' | sed 's/ $//')"
  [ -n "$ids" ] || { echo "charter scan failed without a finding: $out" >&2; return 1; }
  echo "$ids"
}

# One row per file under tests/fixture/html: exactly what html-validate reports, then exactly
# what charter scan reports. Exactly, not at least: a page-level rule firing on a fragment is as
# much a failure as an invalid ARIA value that passes.
IFS= read -r -d '' cases <<'ROWS' || true
tabs.html|-|aria-valid-attr-value
labels.html|input-missing-label wcag/h37|image-alt label
aria.html|-|aria-roles aria-valid-attr
button.html|no-implicit-button-type text-content|button-name
fragment.html|-|-
page.html|-|-
untitled.html|element-required-attributes element-required-content|document-title html-has-lang
click-static.html|charter/clickable-control|-
click-role.html|charter/clickable-control|-
click-keys.html|charter/clickable-control|-
click-controls.html|-|-
ROWS
cases="${cases%$'\n'}"

checked=0
while IFS='|' read -r file validate scan; do
  got="$(validated "html/$file")" || fail "html-validate could not read html/$file"
  [ "$got" = "$validate" ] || fail "html-validate on $file reported '$got'; expected '$validate'"
  got="$(scanned "html/$file")" || fail "charter scan could not read html/$file"
  [ "$got" = "$scan" ] || fail "charter scan on $file reported '$got'; expected '$scan'"
  checked=$((checked + 1))
done <<< "$cases"

# Given a directory, scan walks it for .html files, past node_modules and dot-directories.
cp -R html "$tmp/site"
mkdir -p "$tmp/site/node_modules/pkg" "$tmp/site/.cache" "$tmp/site/nested"
cp html/tabs.html "$tmp/site/node_modules/pkg/"
cp html/tabs.html "$tmp/site/.cache/"
cp html/button.html "$tmp/site/nested/"
echo '<p>not markup</p>' > "$tmp/site/notes.txt"
# On Windows scan names each file natively, C:\…\site\aria.html, so the prefix is cut at site/.
files="$( { node_modules/.bin/charter scan "$tmp/site" 2>&1 || true; } | sed -nE 's/^([^ ]+): .*/\1/p' |
  tr '\\' / | sed 's|^.*/site/||' | sort -u | tr '\n' ' ' | sed 's/ $//')"
[ "$files" = 'aria.html button.html labels.html nested/button.html tabs.html untitled.html' ] ||
  fail "scanning a directory reported '$files'"

# Without axe-core and jsdom in the project, scan refuses and says what to install.
mkdir "$tmp/bare"
echo '{ "name": "bare", "private": true }' > "$tmp/bare/package.json"
cp html/tabs.html "$tmp/bare/"
err="$(cd "$tmp/bare" && node "$kit/bin/charter.mjs" scan tabs.html 2>&1)" &&
  fail "scan passed in a project without axe-core and jsdom"
grep -qF 'npm install -D axe-core jsdom' <<< "$err" ||
  fail "without axe-core and jsdom, scan did not say what to install: got '$err'"

# With nothing to scan, it says how it is used; a path that is not there is an error, not a pass.
err="$(node_modules/.bin/charter scan 2>&1)" && fail "scan with no paths succeeded"
grep -q 'charter scan <file or directory' <<< "$err" || fail "scan with no paths did not print its usage: got '$err'"
err="$(node_modules/.bin/charter scan html/missing.html 2>&1)" && fail "scan of a missing file succeeded"
grep -q 'html/missing.html' <<< "$err" || fail "scan of a missing file did not name it: got '$err'"

echo "  ✓ $checked files report exactly what html-validate and charter scan promise; scan walks a"
echo "    directory, and refuses without axe-core and jsdom"
