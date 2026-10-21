#!/usr/bin/env bash
# core's rules load in every session through one index; every other rule carries a paths: block
# and loads only once a session touches a matching file; and each tier stays inside its budget.
set -euo pipefail

cd tests/fixture
npm install --silent --no-audit --no-fund

kit='node_modules/charter'

grep -qx "@$kit/core/rules.md" CLAUDE.md ||
  { echo "  ✗ the fixture's CLAUDE.md does not import core/rules.md"; exit 1; }

# core's index imports exactly core/rules/: nothing left out, nothing from elsewhere.
imported="$( { grep -o '^@[^ ]*\.md' "$kit/core/rules.md" || true; } | sed 's/^@//' | sort)"
shipped="$(cd "$kit/core" && find rules -type f -name '*.md' | sort)"
[ "$imported" = "$shipped" ] || {
  echo "  ✗ core/rules.md does not import exactly core/rules/ (< index, > files):"
  diff <(echo "$imported") <(echo "$shipped") || true
  exit 1
}

# No module has an index: an @ import of one would load its rules in every session.
stray="$(find "$kit/domains" "$kit/stacks" -name rules.md 2>/dev/null || true)"
[ -z "$stray" ] || { echo "  ✗ a module has an index, so its rules would always load:"; echo "$stray"; exit 1; }

# A rule's body: the file without its paths: block, which Claude Code strips before loading.
body_lines() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm { n++ } END { print n + 0 }' "$1"
}

# The block sync reads without a YAML parser: ---, paths:, one   - "<pattern>" line or more, ---.
has_paths_block() {
  awk 'NR == 1 { ok = ($0 == "---"); next }
       NR == 2 { ok = ok && ($0 == "paths:"); next }
       ok && /^  - "[^"]+"$/ { n++; next }
       { print ((ok && n > 0 && $0 == "---") ? "yes" : "no"); done = 1; exit }
       END { if (!done) print "no" }' "$1"
}

total() { local sum=0 f; for f in "$@"; do sum=$((sum + $(body_lines "$f"))); done; echo "$sum"; }

checked=0
for f in "$kit"/core/rules/*.md "$kit"/domains/*/rules/*.md "$kit"/stacks/*/rules/*.md; do
  [ -e "$f" ] || continue
  lines="$(body_lines "$f")"
  [ "$lines" -le 60 ] || { echo "  ✗ ${f#"$kit"/} is $lines lines; the limit is 60"; exit 1; }
  case "$f" in
    "$kit"/core/*) ;;
    *) [ "$(has_paths_block "$f")" = yes ] ||
      { echo "  ✗ ${f#"$kit"/} does not open with a paths: block"; exit 1; } ;;
  esac
  checked=$((checked + 1))
done

# A skill loads only when its task calls for it, so it keeps a budget of its own, and a
# description, which is all a session sees of it until then. sync mirrors core's alone.
[ -f "$kit/core/skills/release/SKILL.md" ] || { echo "  ✗ core ships no release skill"; exit 1; }
skills=0
for f in "$kit"/core/skills/*/SKILL.md; do
  lines="$(wc -l < "$f" | tr -d ' ')"
  [ "$lines" -le 100 ] || { echo "  ✗ ${f#"$kit"/} is $lines lines; the limit is 100"; exit 1; }
  awk 'NR == 1 { fm = ($0 == "---"); next } fm && $0 == "---" { exit } fm && /^description: ./ { found = 1 } END { exit !found }' "$f" ||
    { echo "  ✗ ${f#"$kit"/} has no description in its frontmatter"; exit 1; }
  skills=$((skills + 1))
done
[ -z "$(find "$kit/domains" "$kit/stacks" -type d -name skills 2>/dev/null)" ] ||
  { echo "  ✗ a module ships skills, which sync does not mirror"; exit 1; }

# Module names are unique: charter.json names a module, not its directory.
dupes="$(cd "$kit" && ls -d domains/*/ stacks/*/ | awk -F/ '{ print $2 }' | sort | uniq -d)"
[ -z "$dupes" ] || { echo "  ✗ module names used twice: $dupes"; exit 1; }

# Budgets — spec 2026-10-13-foundation-design §5. The always tier is what every session reads;
# a workspace's worst case is core plus every path rule of its modules, as if every glob matched.
# Over a limit, move a rule to the module that needs it; raising the limit only spends the
# budget that keeps the rules followed.
always="$(total "$kit"/core/rules/*.md)"
[ "$always" -le 150 ] || {
  echo "  ✗ core's rules are $always lines; the always tier's limit is 150. Move a rule to the module that needs it rather than raising the limit."
  exit 1
}
worst() {
  local m f
  local files=("$kit"/core/rules/*.md)
  for m in "$@"; do
    # A module with no rules, as vitest, adds nothing; a name that is no module is a typo.
    [ -d "$kit/domains/$m" ] || [ -d "$kit/stacks/$m" ] ||
      { echo "  ✗ a budget names $m, which is not a module" >&2; exit 1; }
    for f in "$kit"/domains/"$m"/rules/*.md "$kit"/stacks/"$m"/rules/*.md; do
      [ -e "$f" ] && files+=("$f")
    done
  done
  total "${files[@]}"
}
backend_worst="$(worst backend typescript node vitest)"
ui_worst="$(worst frontend typescript react vitest playwright)"
[ "$backend_worst" -le 225 ] || {
  echo "  ✗ core + backend, typescript, node, vitest is $backend_worst lines if every glob matched; the limit is 225. Move a rule to the module that needs it rather than raising the limit."
  exit 1
}
[ "$ui_worst" -le 225 ] || {
  echo "  ✗ core + frontend, typescript, react, vitest, playwright is $ui_worst lines if every glob matched; the limit is 225. Move a rule to the module that needs it rather than raising the limit."
  exit 1
}

# The live session asks for two facts no session could guess, one in core, one in a path rule.
# Each fact must live in exactly one rule, or the session's answer stops proving which file
# loaded. These guards keep that true, and run even when the session is skipped.
core_fact='2026-09-29'
path_fact='forbidden_origin'
holders() {
  { grep -rlF "$1" "$kit"/core/rules "$kit"/domains/*/rules "$kit"/stacks/*/rules || true; } | sed "s|^$kit/||"
}
[ "$(holders "$core_fact")" = core/rules/backlog.md ] ||
  { echo "  ✗ $core_fact must live in core/rules/backlog.md alone; found: $(holders "$core_fact")"; exit 1; }
[ "$(holders "$path_fact")" = domains/backend/rules/http.md ] ||
  { echo "  ✗ $path_fact must live in domains/backend/rules/http.md alone; found: $(holders "$path_fact")"; exit 1; }

# Skipped where the CLI is absent: the assertions above hold on their own.
#
# The session runs in a scratch consumer holding the unpacked `npm pack` tarball, set up by a real
# `charter init`, so the hook, the manifest and sync are proven together. The mirror is deleted
# before each session, so only the hook can have written it.
#
# It does not run in the fixture: the fixture's `file:` install is a symlink out of the project,
# and Claude Code does not follow an import whose real path lies outside the project. The fixture
# would fail where every registry or git consumer, who gets a real directory, succeeds.
if [ -z "${CHARTER_SKIP_SESSION_CHECK:-}" ] && command -v claude >/dev/null 2>&1; then
  # Its physical path, as the session sees it: on macOS mktemp's /var is a link to /private/var.
  consumer="$(cd "$(mktemp -d)" && pwd -P)"
  trap 'rm -rf "$consumer"' EXIT
  # The root and a server workspace both hold a routes file and a script, so the same questions are
  # asked of a session started at the root and of one started in the workspace, which reads core
  # from its own hook's output, not from the root CLAUDE.md's import.
  for dir in . server; do mkdir -p "$consumer/$dir/src/modules/issues" "$consumer/$dir/scripts"; done
  mkdir -p "$consumer/node_modules/charter"
  tarball="$(cd ../.. && npm pack --silent --pack-destination "$consumer")"
  tar -xzf "$consumer/$tarball" -C "$consumer/node_modules/charter" --strip-components 1
  for dir in . server; do
    echo 'export const routes = []' > "$consumer/$dir/src/modules/issues/issue.routes.ts"
    echo 'export const seed = 1' > "$consumer/$dir/scripts/seed.ts"
  done
  git -C "$consumer" init -q
  ( cd "$consumer" && node node_modules/charter/bin/charter.mjs init backend typescript node vitest &&
    node node_modules/charter/bin/charter.mjs init backend typescript node vitest --workspace server ) >/dev/null ||
    { echo "  ✗ charter init failed in the scratch consumer"; exit 1; }

  # session <directory the session starts in> <file in it to read>: sets $answer, and $seen to
  # what the session's transcript shows — `read <file>` for each Read, `rule <file>` for each path
  # rule it loaded — and fails unless the session read the file asked for.
  #
  # The file is given absolute. Given a relative one, a workspace session often resolved it from
  # the repository root and was refused the read: the git status in its context lists this
  # uncommitted consumer's root directories by name, and the workspace only as `./`. An answer
  # alone cannot tell a refused read from a rule that failed to load; the transcript can.
  session() {
    local id file transcript
    file="$consumer/$1/$2"
    [ "$1" = . ] && file="$consumer/$2"
    id="$(node -e 'console.log(crypto.randomUUID())')"
    rm -rf "$consumer/.claude/rules/charter"
    answer="$( (cd "$consumer/$1" && claude -p "First use Read on $file and nothing else. Then answer from your loaded instructions only, never by searching files. Line 1: the date the backlog rule's example entry was found, or NONE. Line 2: the error code for a write whose Origin is not the app's own, or NONE. Nothing else." \
      --session-id "$id" --disallowedTools Bash Grep Glob Edit Write Agent WebFetch WebSearch < /dev/null 2>&1 || true) | tr -d '`')"
    transcript="$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" -name "$id.jsonl" 2>/dev/null | head -n 1 || true)"
    [ -n "$transcript" ] || { echo "  ✗ run $run, started $at: no transcript for session $id, so what it loaded is unknown"; exit 1; }
    seen="$(node -e '
      const [transcript, consumer] = process.argv.slice(1)
      const within = (path, dir) => (path.replaceAll("\\", "/").startsWith(dir + "/") ? path.replaceAll("\\", "/").slice(dir.length + 1) : null)
      for (const line of require("fs").readFileSync(transcript, "utf8").split("\n")) {
        let entry
        try { entry = JSON.parse(line) } catch { continue }
        for (const part of entry?.type === "assistant" ? entry.message?.content ?? [] : [])
          if (part?.type === "tool_use" && part.name === "Read") console.log(`read ${within(part.input?.file_path ?? "", consumer) ?? part.input?.file_path}`)
        const rule = entry?.type === "attachment" && entry.attachment?.type === "nested_memory" ? within(entry.attachment.path ?? "", `${consumer}/.claude/rules/charter`) : null
        if (rule) console.log(`rule ${rule}`)
      }' "$transcript" "$consumer")"
    grep -qxF "read ${file#"$consumer"/}" <<< "$seen" ||
      { echo "  ✗ run $run, started $at: asked to read ${file#"$consumer"/}, the session did not. Saw: $(tr '\n' ' ' <<< "$seen")"; exit 1; }
  }
  for run in 1 2 3; do
    for dir in . server; do
      at="$([ "$dir" = . ] && echo 'at the root' || echo "in $dir/")"
      session "$dir" scripts/seed.ts
      ! grep -q '^rule .*/backend/http\.md$' <<< "$seen" ||
        { echo "  ✗ run $run, started $at: http.md loaded outside its globs. Saw: $(tr '\n' ' ' <<< "$seen")"; exit 1; }
      grep -qF "$core_fact" <<< "$answer" && grep -qx 'NONE' <<< "$answer" && ! grep -qF "$path_fact" <<< "$answer" ||
        { echo "  ✗ run $run, started $at: outside http.md's globs, wanted $core_fact and NONE. Got: $answer"; exit 1; }
      session "$dir" src/modules/issues/issue.routes.ts
      grep -q '^rule .*/backend/http\.md$' <<< "$seen" ||
        { echo "  ✗ run $run, started $at: http.md did not load in a routes file. Saw: $(tr '\n' ' ' <<< "$seen")"; exit 1; }
      grep -qF "$core_fact" <<< "$answer" && grep -qx "$path_fact" <<< "$answer" ||
        { echo "  ✗ run $run, started $at: http.md loaded in a routes file, but the answer lacked $core_fact or $path_fact. Got: $answer"; exit 1; }
    done
  done

  # init's sync wrote the skill; a fresh clone's first session gets it only because the hook,
  # having written it again, asks for the skills to be rescanned.
  [ -f "$consumer/.claude/skills/charter-release/SKILL.md" ] || { echo "  ✗ init did not mirror the release skill"; exit 1; }
  rm -rf "$consumer/.claude/skills"
  answer="$( (cd "$consumer" && claude -p "List the name of every skill available to you whose name contains 'release', one per line, or NONE. Nothing else." \
    --disallowedTools Bash Grep Glob Read Edit Write Agent WebFetch WebSearch < /dev/null 2>&1 || true) | tr -d '`')"
  grep -qx 'charter-release' <<< "$answer" ||
    { echo "  ✗ a session whose hook wrote the release skill did not list it. Got: $answer"; exit 1; }
  echo "  ✓ three times over, a real session started at the root and one started in a workspace each"
  echo "    read core at once and http.md only in a matching file, as answered and as each transcript shows;"
  echo "    and a fresh session lists the release skill its hook wrote"
else
  echo "  · session check skipped (no claude CLI, or CHARTER_SKIP_SESSION_CHECK set)"
fi

echo "  ✓ $checked rules: core loads always ($always lines), the rest by path; a backend"
echo "    workspace reads at most $backend_worst, a UI one $ui_worst; $skills skill by task"
