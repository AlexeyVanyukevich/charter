#!/usr/bin/env bash
# Each section's rules load through its own index, stay inside the section, and stay small
# enough to be followed.
set -euo pipefail

cd tests/fixture
npm install --silent --no-audit --no-fund

kit='node_modules/charter'

# The fixture imports every index, which proves each is reachable at the path the README
# promises. It is a harness: a real project imports only the sections it needs.
for section in common backend ui testing; do
  grep -qx "@$kit/$section/rules.md" CLAUDE.md ||
    { echo "  ✗ the fixture's CLAUDE.md does not import $section/rules.md"; exit 1; }
done

# Prints a section's rule line count, after proving its index imports exactly the files in its
# own rules/. None left out, so nothing shipped is unreachable; nothing from elsewhere, so
# loading one section never loads another.
section_lines() {
  local section="$1"
  local dir="$kit/$1"
  [ -f "$dir/rules.md" ] || { echo "  ✗ $section/rules.md does not exist" >&2; return 1; }

  local imported shipped
  imported="$( { grep -o '^@[^ ]*\.md' "$dir/rules.md" || true; } | sed 's/^@//' | sort)"
  shipped="$(cd "$dir" && find rules -type f -name '*.md' | sort)"
  [ -n "$shipped" ] || { echo "  ✗ $section/rules/ holds no rules" >&2; return 1; }
  [ "$imported" = "$shipped" ] || {
    echo "  ✗ $section/rules.md does not import exactly $section/rules/ (< index, > files):" >&2
    diff <(echo "$imported") <(echo "$shipped") >&2 || true
    return 1
  }

  local total=0 file lines
  while read -r file; do
    lines="$(wc -l < "$dir/$file")"
    # Per-file budget. A rule nobody finishes reading is a rule nobody follows.
    [ "$lines" -le 60 ] ||
      { echo "  ✗ $section/$file is $lines lines; the limit is 60" >&2; return 1; }
    total=$((total + lines))
  done <<< "$shipped"
  echo "$total"
}

common="$(section_lines common)"
backend="$(section_lines backend)"
ui="$(section_lines ui)"
testing="$(section_lines testing)"

# The budget is what one session reads, not what the kit ships — spec 2026-10-01 §6. Past
# roughly 225 lines adherence suffers. A project loads common, testing and one of backend or
# ui; a repository with both loads them in separate workspaces, so no session reads all four.
# Crossing it means a rule is in a section that does not need it, not that the limit is wrong.
within_budget() {
  local load=$((common + testing + $2))
  # To stderr: this runs inside $(…), where stdout is the captured result, not the terminal.
  [ "$load" -le 225 ] || {
    echo "  ✗ common + testing + $1 is $load lines; the limit is 225. Move a rule to the" >&2
    echo "    section that needs it rather than raising the limit — see spec 2026-10-01 §6." >&2
    exit 1
  }
  echo "$load"
}
backend_load="$(within_budget backend "$backend")"
ui_load="$(within_budget ui "$ui")"

# The end-to-end proof: a real session reads a rule back. It asks for a fact that lives in one
# rule file only, two imports deep in backend, and that no session could guess — so the answer
# proves that file loaded, not merely that some nested import did. Kept true by the guard below,
# which runs even when the session is skipped.
fact='forbidden_origin'
holders="$( { grep -rlF "$fact" "$kit"/*/rules || true; } | wc -l | tr -d ' ')"
[ "$holders" = 1 ] || {
  echo "  ✗ the session check's fact, $fact, must live in exactly one rule; found $holders."
  echo "    Pick a fact that does, or the check stops proving which file loaded."
  exit 1
}

# Skipped where the CLI is absent, because a check that cannot run everywhere must not be the
# only thing standing behind a claim — the path assertions above hold on their own.
#
# The session runs in a scratch consumer holding the unpacked `npm pack` tarball, not in the
# fixture. The fixture's `file:` install is a symlink out of the project, and Claude Code does
# not follow a nested import whose real path lies outside the project — so the fixture would
# fail where every registry or git consumer, who gets a real directory, succeeds.
if [ -z "${CHARTER_SKIP_SESSION_CHECK:-}" ] && command -v claude >/dev/null 2>&1; then
  consumer="$(mktemp -d)"
  trap 'rm -rf "$consumer"' EXIT
  mkdir -p "$consumer/node_modules/charter"
  tarball="$(cd ../.. && npm pack --silent --pack-destination "$consumer")"
  tar -xzf "$consumer/$tarball" -C "$consumer/node_modules/charter" --strip-components 1
  cp CLAUDE.md "$consumer/CLAUDE.md"
  git -C "$consumer" init -q
  answer="$(cd "$consumer" && claude -p 'Per the HTTP rule in your instructions, which error code answers a write whose Origin is not the app'"'"'s own? Answer with the code and nothing else.' 2>&1 || true)"
  # The code alone, backticks allowed: a session that talks around it has not read it.
  tr -d '`' <<< "$answer" | grep -qx "$fact" || {
    echo "  ✗ a session did not read the imported rule back. Got: $answer"
    exit 1
  }
  echo "  ✓ a real session read a nested rule back"
else
  echo "  · session check skipped (no claude CLI, or CHARTER_SKIP_SESSION_CHECK set)"
fi

echo "  ✓ 4 sections load through their own index; a backend session reads $backend_load lines,"
echo "    a ui session $ui_load"
