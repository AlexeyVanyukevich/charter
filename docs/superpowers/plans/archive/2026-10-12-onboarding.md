# Project onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `npx dev-kit init <section…> [--workspace <dir>]` turns on a project's Claude Code plugins and imports its rules, and `need_plugins` installs those plugins on every clone.

**Architecture:** One zero-dependency Node file, `bin/dev-kit.mjs`, reads each section's `plugins.json` and merges into the root `.claude/settings.json` and the target `CLAUDE.md`, then calls `need_plugins` from `common/lib.sh`. `need_plugins` is Bash, parses JSON with `node`, and talks to the `claude` CLI. Both are proved by `./check`, against a stub `claude` that records its arguments.

**Tech Stack:** Node 24 (ESM, `node:util` `parseArgs`), Bash, the `claude plugin` CLI.

**Spec:** `docs/superpowers/specs/2026-10-12-onboarding-design.md`

## Global Constraints

- Node `>=24.0.0`; the package declares no `dependencies`, no `peerDependencies`, and no `prepare`/`install`/`postinstall` script (`checks/10-package.sh` fails otherwise).
- Code style follows `common/prettier.json`: `semi: false`, `singleQuote: true`, `printWidth: 100`.
- `common/lib.sh` stays inert when sourced: no shell options set, no directory changed, nothing run.
- `./run` never fails because Claude Code is absent: `need_plugins` returns 0 with a `note`.
- Commit messages are one Conventional Commits subject line, lowercase, imperative, ≤72 characters, no body, no `Co-Authored-By` trailer (`common/rules/commits.md`).
- Work stays on branch `feat/onboarding`. The `chore: release 2.3.0` commit and `v2.3.0` tag happen on `main` after the merge, not in this plan.
- `./check` is the only verification command; there is no test framework.

## Review Focus

- `enabledPlugins` present but not an object (an array, `null`): `init` stops with a message naming the file, not a stack trace — Task 2.
- A `CLAUDE.md` with no final newline: appended imports start on their own line after one blank line — Task 2.
- `--workspace` pointing outside the repository (`..`): refused, because the computed prefix would be meaningless — Task 2.
- The same section named twice (`init common common`): one import line, one plugin entry — Task 2.
- `.claude/settings.json` that is not valid JSON when `need_plugins` runs: `die` with an instruction, not a Node stack trace — Task 1.

---

## File map

| File | Change | Responsibility |
| ---- | ------ | -------------- |
| `common/lib.sh` | modify | add `need_plugins` after `need_deps` |
| `checks/50-lib.sh` | modify | prove `need_plugins` against a stub `claude` |
| `common/plugins.json` | create | `common`'s plugins |
| `ui/plugins.json` | create | `ui`'s plugins |
| `bin/dev-kit.mjs` | create | the `init` command |
| `package.json` | modify | `bin` field; `bin` in `files` |
| `checks/10-package.sh` | modify | allow and require `bin/dev-kit.mjs` in the tarball |
| `checks/70-init.sh` | create | prove `init` |
| `README.md` | modify | "Onboarding a project"; `need_plugins` in the `./run` section |

`need_plugins`'s behaviour is tested in `checks/50-lib.sh`, beside every other `lib.sh` function and its fakes, rather than in `70-init.sh` as spec §6 places it. `70-init.sh` still proves that `init` calls it.

---

### Task 1: `need_plugins`

**Files:**
- Modify: `common/lib.sh` (insert after `need_deps`, before `need_env`)
- Test: `checks/50-lib.sh` (function list on line 15; new block before the final `echo`)

**Interfaces:**
- Consumes: `step`, `ok`, `note`, `die` from `common/lib.sh`.
- Produces: `need_plugins` — no arguments, run with the repository root as the working directory. Returns 0 when there is nothing to do, Claude Code is absent, or every install succeeded; exits 1 through `die` otherwise. Called by Task 2 as `bash -c 'source "$1" && need_plugins' need_plugins <kit>/common/lib.sh`.

- [ ] **Step 1: Write the failing test**

In `checks/50-lib.sh`, add `need_plugins` to the function list on line 15:

```bash
for fn in step ok note die load_env_file need_docker need_node need_deps need_plugins need_env with_github_token; do
```

Then insert this block immediately before the final `echo "  ✓ lib.sh sources inertly, …"` line, and extend that line as shown:

```bash
# need_plugins installs, at project scope, the enabled plugins this machine lacks for this
# repository. A stub claude answers from FAKE_INSTALLED and FAKE_MARKETPLACES and records every
# call, so nothing here touches this machine's real plugins.
cat > "$bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
case "$*" in
  'plugin list --json') printf '%s' "${FAKE_INSTALLED:-[]}" ;;
  'plugin marketplace list --json') printf '%s' "${FAKE_MARKETPLACES:-[]}" ;;
esac
FAKE
chmod +x "$bin/claude"
export CLAUDE_LOG="$tmp/claude.log"

project="$tmp/plugins"
mkdir -p "$project/.claude"
printf '%s\n' '{ "enabledPlugins": {
  "a@claude-plugins-official": true,
  "b@claude-plugins-official": true,
  "off@claude-plugins-official": false
} }' > "$project/.claude/settings.json"
here="$(cd "$project" && pwd -P)"

# a is installed here, b only in another repository, so b alone is missing; the official
# marketplace is not registered, so it is added first.
: > "$CLAUDE_LOG"
( cd "$project" && source "$lib" && PATH="$bin:$real_path" \
  FAKE_INSTALLED="[{\"id\":\"a@claude-plugins-official\",\"scope\":\"project\",\"projectPath\":\"$here\"},
                   {\"id\":\"b@claude-plugins-official\",\"scope\":\"project\",\"projectPath\":\"/elsewhere\"}]" \
  need_plugins ) >/dev/null || { echo "  ✗ need_plugins failed installing a missing plugin"; exit 1; }
grep -qx 'plugin install b@claude-plugins-official --scope project' "$CLAUDE_LOG" ||
  { echo "  ✗ need_plugins did not install the missing plugin"; cat "$CLAUDE_LOG"; exit 1; }
grep -qE 'install (a|off)@' "$CLAUDE_LOG" &&
  { echo "  ✗ need_plugins installed a plugin that was present or turned off"; exit 1; }
grep -qx 'plugin marketplace add anthropics/claude-plugins-official' "$CLAUDE_LOG" ||
  { echo "  ✗ need_plugins did not register the missing official marketplace"; exit 1; }

# A registered marketplace is not added again.
: > "$CLAUDE_LOG"
( cd "$project" && source "$lib" && PATH="$bin:$real_path" \
  FAKE_MARKETPLACES='[{"name":"claude-plugins-official"}]' need_plugins ) >/dev/null ||
  { echo "  ✗ need_plugins failed with the marketplace registered"; exit 1; }
grep -q 'marketplace add' "$CLAUDE_LOG" &&
  { echo "  ✗ need_plugins added a marketplace that was already registered"; exit 1; }

# Nothing missing: nothing installed, nothing printed.
: > "$CLAUDE_LOG"
result="$(cd "$project" && source "$lib" && PATH="$bin:$real_path" \
  FAKE_INSTALLED="[{\"id\":\"a@claude-plugins-official\",\"scope\":\"project\",\"projectPath\":\"$here\"},
                   {\"id\":\"b@claude-plugins-official\",\"scope\":\"project\",\"projectPath\":\"$here\"}]" \
  need_plugins)"
[ -z "$result" ] || { echo "  ✗ need_plugins printed '$result' with nothing to install"; exit 1; }
grep -q 'install' "$CLAUDE_LOG" && { echo "  ✗ need_plugins installed with nothing missing"; exit 1; }

# No Claude Code — CI — is a note and a zero, never a failure. Node stays on PATH; claude does not.
mkdir -p "$tmp/nodeonly"
ln -sf "$(command -v node)" "$tmp/nodeonly/node"
result="$(cd "$project" && source "$lib" && PATH="$tmp/nodeonly" need_plugins)" ||
  { echo "  ✗ need_plugins failed without Claude Code installed"; exit 1; }
grep -q 'Claude Code' <<< "$result" ||
  { echo "  ✗ need_plugins said nothing when skipping without Claude Code: got '$result'"; exit 1; }

# No settings file: nothing to do, and claude is never asked.
: > "$CLAUDE_LOG"
( cd "$tmp/public" && source "$lib" && PATH="$bin:$real_path" need_plugins ) ||
  { echo "  ✗ need_plugins failed in a project with no settings file"; exit 1; }
[ -s "$CLAUDE_LOG" ] && { echo "  ✗ need_plugins called claude with no settings file"; exit 1; }

# Broken JSON is a stop that names the file, not a Node stack trace.
mkdir -p "$tmp/broken/.claude"
echo '{' > "$tmp/broken/.claude/settings.json"
err="$( (cd "$tmp/broken" && source "$lib" && PATH="$bin:$real_path" need_plugins) 2>&1 >/dev/null )" &&
  { echo "  ✗ need_plugins accepted a settings file that is not JSON"; exit 1; }
grep -q 'settings.json' <<< "$err" ||
  { echo "  ✗ need_plugins failed on broken JSON without naming the file: got '$err'"; exit 1; }

echo "  ✓ lib.sh sources inertly, defines its surface, keeps env precedence, reports a new .env, hands a GitHub token only where one is asked for, and installs only missing plugins"
```

(Delete the old final `echo` line; the one above replaces it.)

- [ ] **Step 2: Run the check to verify it fails**

Run: `./check 50`
Expected: FAIL with `✗ lib.sh does not define need_plugins`

- [ ] **Step 3: Implement `need_plugins`**

In `common/lib.sh`, insert between the end of `need_deps` and the comment above `need_env`:

```bash
# Plugins are turned on in the repository's .claude/settings.json and downloaded per machine, so
# a fresh clone has the first and not the second. This installs, at project scope, each enabled
# plugin this machine lacks for this repository. A machine without Claude Code — CI among them —
# has nothing to install into, and ./run must not fail over that.
need_plugins() {
  [ -f .claude/settings.json ] || return 0
  local wanted
  wanted="$(node -e '
    const settings = JSON.parse(require("fs").readFileSync(".claude/settings.json", "utf8"))
    for (const [id, on] of Object.entries(settings.enabledPlugins ?? {})) if (on === true) console.log(id)
  ' 2>/dev/null)" || die ".claude/settings.json is not valid JSON." "Fix it, then run this again."
  [ -n "$wanted" ] || return 0

  if ! command -v claude >/dev/null 2>&1; then
    note "Claude Code is not installed; skipping its plugins"
    return 0
  fi

  # Installed for this repository means a project-scope entry whose projectPath is this directory.
  # Both sides go through realpath, because a temp or symlinked path is recorded resolved.
  local missing
  # shellcheck disable=SC2086
  missing="$(claude plugin list --json | node -e '
    const fs = require("fs")
    const real = (p) => { try { return fs.realpathSync(p) } catch { return p } }
    const here = real(".")
    const have = new Set(JSON.parse(fs.readFileSync(0, "utf8"))
      .filter((p) => p.scope === "project" && real(p.projectPath) === here)
      .map((p) => p.id))
    for (const id of process.argv.slice(1)) if (!have.has(id)) console.log(id)
  ' $wanted)" || die "Could not list Claude Code's installed plugins." "Run: claude plugin list"
  [ -n "$missing" ] || return 0

  step "Installing Claude Code plugins"
  # A machine where Claude Code never ran interactively has not registered the official marketplace.
  if grep -q '@claude-plugins-official$' <<< "$missing" &&
    ! claude plugin marketplace list --json | node -e '
      const list = JSON.parse(require("fs").readFileSync(0, "utf8"))
      process.exit(list.some((m) => m.name === "claude-plugins-official") ? 0 : 1)
    ' 2>/dev/null; then
    claude plugin marketplace add anthropics/claude-plugins-official >/dev/null ||
      die "Could not add Claude Code's official plugin marketplace." \
        "Run: claude plugin marketplace add anthropics/claude-plugins-official"
  fi
  local id
  while read -r id; do
    claude plugin install "$id" --scope project >/dev/null ||
      die "Could not install the Claude Code plugin $id." "Run: claude plugin install $id --scope project"
    ok "$id"
  done <<< "$missing"
}
```

- [ ] **Step 4: Run the check to verify it passes**

Run: `./check 50`
Expected: PASS, ending `✓ … and installs only missing plugins`

- [ ] **Step 5: Commit**

```bash
git add common/lib.sh checks/50-lib.sh
git commit -m "feat(lib): install a project's missing claude code plugins"
```

---

### Task 2: `dev-kit init`

**Files:**
- Create: `common/plugins.json`, `ui/plugins.json`, `bin/dev-kit.mjs`, `checks/70-init.sh`
- Modify: `package.json` (`files`, new `bin`), `checks/10-package.sh` (the `outside` filter and one `expect_packed`)

**Interfaces:**
- Consumes: `need_plugins` from Task 1, run through `bash -c 'source "$1" && need_plugins' need_plugins <kit>/common/lib.sh` with the repository root as the working directory.
- Produces: the `dev-kit` executable. `dev-kit init <section…> [--workspace <dir>]` exits 0 on success, 1 on any refusal, and writes nothing when it refuses. A usage error prints `Usage: dev-kit init <section…> [--workspace <dir>]` to stderr. Task 3 documents this interface.

- [ ] **Step 1: Write the failing check**

Create `checks/70-init.sh`:

```bash
#!/usr/bin/env bash
# dev-kit init turns on the plugins a project's sections need and imports their rules, merges
# into what is already there, refuses what it cannot do cleanly, and reaches a consumer as
# `dev-kit`.
set -euo pipefail

cli="$PWD/bin/dev-kit.mjs"
[ -f "$cli" ] || { echo "  ✗ bin/dev-kit.mjs does not exist"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A stub claude records each call and reports nothing installed, so init's last step — running
# need_plugins — is observed without touching this machine's plugins.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$CLAUDE_LOG"
case "$*" in
  'plugin list --json') echo '[]' ;;
  'plugin marketplace list --json') echo '[{"name":"claude-plugins-official"}]' ;;
esac
FAKE
chmod +x "$tmp/bin/claude"
export CLAUDE_LOG="$tmp/claude.log"
export PATH="$tmp/bin:$PATH"

# A new, empty project directory.
project() { rm -rf "$tmp/$1"; mkdir -p "$tmp/$1"; echo "$tmp/$1"; }
fail() { echo "  ✗ $*"; exit 1; }

# ── a first run ───────────────────────────────────────────────────────────────

p="$(project fresh)"
: > "$CLAUDE_LOG"
( cd "$p" && node "$cli" init common ui ) >/dev/null || fail "init common ui failed"

expected='{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "frontend-design@claude-plugins-official": true,
    "playwright@claude-plugins-official": true
  }
}'
[ "$(cat "$p/.claude/settings.json")" = "$expected" ] ||
  { echo "  ✗ settings.json is not what common + ui enable:"; cat "$p/.claude/settings.json"; exit 1; }

expected='@node_modules/dev-kit/common/rules.md
@node_modules/dev-kit/ui/rules.md'
[ "$(cat "$p/CLAUDE.md")" = "$expected" ] ||
  { echo "  ✗ CLAUDE.md is not the two imports:"; cat "$p/CLAUDE.md"; exit 1; }

grep -qx 'plugin install superpowers@claude-plugins-official --scope project' "$CLAUDE_LOG" ||
  fail "init did not run need_plugins"

# ── a second run changes nothing ───────────────────────────────────────────────

cp "$p/.claude/settings.json" "$tmp/settings.before"
cp "$p/CLAUDE.md" "$tmp/claude.before"
( cd "$p" && node "$cli" init common ui ) >/dev/null || fail "a second init failed"
cmp -s "$p/.claude/settings.json" "$tmp/settings.before" || fail "a second run changed settings.json"
cmp -s "$p/CLAUDE.md" "$tmp/claude.before" || fail "a second run changed CLAUDE.md"

# ── merging into what is there ────────────────────────────────────────────────

# An opt-out survives, and so does every key init does not own.
p="$(project merge)"
mkdir -p "$p/.claude"
echo '{ "model": "opus", "enabledPlugins": { "superpowers@claude-plugins-official": false } }' \
  > "$p/.claude/settings.json"
( cd "$p" && node "$cli" init common ) >/dev/null || fail "init into existing settings failed"
node -e '
  const s = require(process.argv[1])
  if (s.model !== "opus") throw new Error("model was dropped")
  if (s.enabledPlugins["superpowers@claude-plugins-official"] !== false) throw new Error("opt-out was overwritten")
' "$p/.claude/settings.json" 2>/dev/null || fail "init changed a value already set in settings.json"

# An existing CLAUDE.md with no final newline gets its imports on their own lines.
printf '# Project' > "$p/CLAUDE.md"
( cd "$p" && node "$cli" init testing ) >/dev/null || fail "init into an existing CLAUDE.md failed"
[ "$(cat "$p/CLAUDE.md")" = $'# Project\n\n@node_modules/dev-kit/testing/rules.md' ] ||
  { echo "  ✗ imports were not appended after one blank line:"; cat "$p/CLAUDE.md"; exit 1; }

# A section named twice is written once.
p="$(project twice)"
( cd "$p" && node "$cli" init common common ) >/dev/null || fail "init common common failed"
[ "$(grep -c 'common/rules.md' "$p/CLAUDE.md")" = 1 ] || fail "a repeated section was imported twice"

# ── workspaces ────────────────────────────────────────────────────────────────

p="$(project split)"
mkdir -p "$p/server" "$p/apps/web"
( cd "$p" && node "$cli" init backend --workspace server ) >/dev/null || fail "init --workspace server failed"
( cd "$p" && node "$cli" init ui --workspace apps/web ) >/dev/null || fail "init --workspace apps/web failed"
[ "$(cat "$p/server/CLAUDE.md")" = '@../node_modules/dev-kit/backend/rules.md' ] ||
  fail "a workspace one level down does not import through ../"
[ "$(cat "$p/apps/web/CLAUDE.md")" = '@../../node_modules/dev-kit/ui/rules.md' ] ||
  fail "a workspace two levels down does not import through ../../"
grep -q 'playwright@claude-plugins-official' "$p/.claude/settings.json" ||
  fail "a workspace's plugins did not land in the root settings.json"
[ ! -e "$p/apps/web/.claude" ] || fail "a workspace got its own .claude directory"

# ── refusals: non-zero, and nothing written ───────────────────────────────────

refuses() {
  local name="$1" expect="$2"
  shift 2
  local p
  p="$(project "refuse-$name")"
  [ -n "${SETUP:-}" ] && (cd "$p" && eval "$SETUP")
  local before err
  before="$(cd "$p" && find . | sort)"
  err="$( (cd "$p" && node "$cli" "$@") 2>&1 >/dev/null )" && fail "init accepted $name"
  grep -q -- "$expect" <<< "$err" || fail "refusing $name, init did not say '$expect': got '$err'"
  [ "$(cd "$p" && find . | sort)" = "$before" ] || fail "init wrote files while refusing $name"
}

refuses 'no command' 'Usage: dev-kit init'
refuses 'another command' 'Usage: dev-kit init' build common
refuses 'no sections' 'Usage: dev-kit init' init
refuses 'an unknown section' 'backend, common, testing, ui' init frontend
refuses 'backend with ui' '--workspace' init backend ui
refuses 'a missing workspace' 'not a directory' init ui --workspace nope
refuses 'a workspace outside' 'outside this repository' init ui --workspace ..
SETUP='mkdir .claude && echo "{" > .claude/settings.json' \
  refuses 'broken settings JSON' 'settings.json' init common
SETUP='mkdir .claude && echo "{ \"enabledPlugins\": [] }" > .claude/settings.json' \
  refuses 'enabledPlugins as an array' 'enabledPlugins' init common

# ── reachable from a consumer ─────────────────────────────────────────────────

( cd tests/fixture && npm install --silent --no-audit --no-fund )
[ -x tests/fixture/node_modules/.bin/dev-kit ] || fail "a consumer gets no dev-kit executable"
err="$(tests/fixture/node_modules/.bin/dev-kit 2>&1 >/dev/null)" && fail "dev-kit with no arguments succeeded"
grep -q 'Usage: dev-kit init' <<< "$err" || fail "a consumer's dev-kit does not print its usage"

echo "  ✓ init enables plugins and imports rules, merges without overwriting, places workspace imports, refuses cleanly, and reaches a consumer"
```

It runs under `bash`, like the other checks, so it needs no executable bit.

- [ ] **Step 2: Run the check to verify it fails**

Run: `./check 70`
Expected: FAIL with `✗ bin/dev-kit.mjs does not exist`

- [ ] **Step 3: Add the section data**

Create `common/plugins.json`:

```json
["superpowers@claude-plugins-official"]
```

Create `ui/plugins.json`:

```json
["frontend-design@claude-plugins-official", "playwright@claude-plugins-official"]
```

- [ ] **Step 4: Write `bin/dev-kit.mjs`**

```js
#!/usr/bin/env node
// Onboards a project: turns on the Claude Code plugins its sections need, in the root
// .claude/settings.json, and imports their rules into CLAUDE.md. Adds what is missing and
// changes nothing that is set. Spec: docs/superpowers/specs/2026-10-12-onboarding-design.md.

import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'

const kit = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const usage = 'Usage: dev-kit init <section…> [--workspace <dir>]'
const settingsFile = join('.claude', 'settings.json')

function fail(message, hint) {
  console.error(`✗ ${message}`)
  if (hint) console.error(`  ${hint}`)
  process.exit(1)
}

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)

function parse(argv) {
  let parsed
  try {
    parsed = parseArgs({
      args: argv,
      allowPositionals: true,
      options: { workspace: { type: 'string' } },
    })
  } catch (error) {
    fail(error.message, usage)
  }
  const [command, ...sections] = parsed.positionals
  if (command !== 'init') fail(command ? `Unknown command: ${command}.` : 'No command given.', usage)
  if (sections.length === 0) fail('Name at least one section.', usage)
  return { sections: [...new Set(sections)], workspace: parsed.values.workspace ?? '.' }
}

// Every refusal happens here, before anything is written.
function check({ sections, workspace }) {
  const valid = readdirSync(kit)
    .filter((name) => existsSync(join(kit, name, 'rules.md')))
    .sort()
  const unknown = sections.filter((section) => !valid.includes(section))
  if (unknown.length > 0) {
    fail(`Unknown section: ${unknown.join(', ')}.`, `The sections are ${valid.join(', ')}.`)
  }
  if (sections.includes('backend') && sections.includes('ui')) {
    fail(
      'backend and ui cannot load in the same directory.',
      'Give each its own workspace: dev-kit init backend --workspace <dir>, and the same for ui.',
    )
  }
  const dir = resolve(workspace)
  const fromRoot = relative(process.cwd(), dir)
  if (fromRoot === '..' || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot)) {
    fail(`${workspace} is outside this repository.`, 'Run dev-kit init at the repository root.')
  }
  if (!existsSync(dir) || !statSync(dir).isDirectory()) {
    fail(`${workspace} is not a directory.`, 'Create the workspace first, then run this again.')
  }
  return dir
}

function readSettings() {
  if (!existsSync(settingsFile)) return {}
  let settings
  try {
    settings = JSON.parse(readFileSync(settingsFile, 'utf8'))
  } catch {
    fail(`${settingsFile} is not valid JSON.`, 'Fix it, then run this again.')
  }
  if (!isObject(settings)) {
    fail(`${settingsFile} does not hold a JSON object.`, 'Fix it, then run this again.')
  }
  if (settings.enabledPlugins !== undefined && !isObject(settings.enabledPlugins)) {
    fail(`enabledPlugins in ${settingsFile} is not an object.`, 'Fix it, then run this again.')
  }
  return settings
}

function pluginsOf(section) {
  const file = join(kit, section, 'plugins.json')
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : []
}

const options = parse(process.argv.slice(2))
const dir = check(options)
const settings = readSettings()

const enabled = settings.enabledPlugins ?? {}
const plugins = [...new Set(options.sections.flatMap(pluginsOf))]
const newPlugins = plugins.filter((id) => !Object.hasOwn(enabled, id))

// The import climbs from the workspace back to the root, where node_modules is hoisted.
const up = relative(dir, process.cwd()).split(sep).join('/')
const imports = options.sections.map(
  (section) => `@${up ? `${up}/` : ''}node_modules/dev-kit/${section}/rules.md`,
)
const claudeFile = join(dir, 'CLAUDE.md')
const claude = existsSync(claudeFile) ? readFileSync(claudeFile, 'utf8') : ''
const present = new Set(claude.split('\n').map((line) => line.trimEnd()))
const newImports = imports.filter((line) => !present.has(line))

if (newPlugins.length > 0) {
  settings.enabledPlugins = {
    ...enabled,
    ...Object.fromEntries(newPlugins.map((id) => [id, true])),
  }
  mkdirSync('.claude', { recursive: true })
  writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`)
}
if (newImports.length > 0) {
  const block = `${newImports.join('\n')}\n`
  const head = claude.trim() === '' ? '' : `${claude}${claude.endsWith('\n') ? '' : '\n'}\n`
  writeFileSync(claudeFile, head + block)
}

const shown = relative(process.cwd(), claudeFile)
for (const id of plugins) {
  console.log(newPlugins.includes(id) ? `✓ enabled ${id}` : `  ${id} already set`)
}
for (const line of imports) {
  console.log(newImports.includes(line) ? `✓ ${shown}: ${line}` : `  ${shown} already has ${line}`)
}

const lib = join(kit, 'common', 'lib.sh')
const run = spawnSync('bash', ['-c', 'source "$1" && need_plugins', 'need_plugins', lib], {
  stdio: 'inherit',
})
process.exit(run.status ?? 1)
```

Make it executable: `chmod +x bin/dev-kit.mjs`.

- [ ] **Step 5: Ship the executable**

In `package.json`, add `"bin"` to `files` and a `bin` field after `files`:

```json
  "files": [
    "bin",
    "common",
    "backend",
    "ui",
    "testing"
  ],
  "bin": {
    "dev-kit": "bin/dev-kit.mjs"
  },
```

In `checks/10-package.sh`, require the executable after `expect_packed 'package.json'`:

```bash
expect_packed 'bin/dev-kit.mjs'
```

and let `bin/` through the `outside` filter, updating its comment:

```bash
# Only the four sections and the onboarding executable ship, plus what npm always adds. A 1.x
# directory left in `files` would ship a second, stale copy of a rule.
outside="$(grep -vE '^(bin|common|backend|ui|testing)/|^package\.json$|^README\.md$' \
  <<< "$packed" || true)"
```

- [ ] **Step 6: Run the checks to verify they pass**

Run: `./check 70 && ./check 10`
Expected: both PASS; `70-init` ends `✓ init enables plugins and imports rules, …`

- [ ] **Step 7: Commit**

```bash
git add bin/dev-kit.mjs common/plugins.json ui/plugins.json package.json checks/10-package.sh checks/70-init.sh
git commit -m "feat: add dev-kit init to turn on plugins and import rules"
```

Confirm git recorded the executable bit: `git ls-files -s bin/dev-kit.mjs` shows mode `100755`. A consumer's `node_modules/.bin/dev-kit` runs only if it does.

---

### Task 3: README

**Files:**
- Modify: `README.md` — the Sections table (lines 72–77), a new `## Onboarding a project` section between `### A repository with both a backend and a UI` and `## The modules`, and the `./run` section (lines 168–198)

**Interfaces:**
- Consumes: the `dev-kit init` interface from Task 2 and `need_plugins` from Task 1.
- Produces: nothing code depends on. `checks/60-readme.sh` must still pass: every `node_modules/dev-kit/…` path the README names must exist.

- [ ] **Step 1: Update the Sections table**

Replace the `common` and `ui` rows:

```markdown
| `common` | every project | six rules, the TypeScript base, Prettier, the `./run` skeleton, ignore files, the `superpowers` plugin |
| `ui` | bundled browser applications | one rule, the browser tsconfig, the `frontend-design` and `playwright` plugins |
```

- [ ] **Step 2: Add "Onboarding a project"**

Insert immediately before `## The modules`:

````markdown
## Onboarding a project

Once the kit is installed, one command turns on the Claude Code plugins a project's sections
need and imports their rules:

```bash
npx dev-kit init common testing
```

| Section | Turns on |
| ------- | -------- |
| `common` | `superpowers` |
| `ui` | `frontend-design`, `playwright` |

The plugins go in the root `.claude/settings.json`, at project scope: they load in this
repository's sessions and in no other. Commit the file. The imports go in `CLAUDE.md`. A
section's plugins are listed in its `plugins.json`, and a section without one brings none.

A repository with a server and a web workspace runs it once per directory. The imports land in
each workspace's `CLAUDE.md`, climbing back to the root's `node_modules`; the plugins always
land in the root's settings, because Claude Code enables a plugin per repository:

```bash
npx dev-kit init common testing
npx dev-kit init backend --workspace server
npx dev-kit init ui --workspace web
```

Running it again adds only what is missing. A plugin set to `false` stays off. `backend` and
`ui` in one directory is refused, for the reason given above.

**A committed plugin is turned on, not downloaded.** Each clone installs it once:
`need_plugins`, in the `./run` frame below, does that, and `init` runs it before it finishes.
````

- [ ] **Step 3: Update the `./run` section**

In the sentence beginning `Defines \`step\`, …`, add `need_plugins` after `need_deps`:

```markdown
Defines `step`, `ok`, `note`, `die`, `load_env_file`, `need_docker`, `need_node`, `need_deps`,
`need_plugins`, `need_env` and `with_github_token`, plus the colour variables. Sourcing is
inert: no shell options set, no directory changed, nothing run.
```

Then insert after the paragraph ending `` call it as `need_env || note "…"`. ``:

````markdown
`need_plugins` comes after `need_deps`, because it reads the settings with `node`:

```bash
need_node
need_deps
need_plugins
```

It installs, at project scope, each plugin `.claude/settings.json` turns on and this machine
lacks for the repository, registering the official marketplace first on a machine where Claude
Code has never run. With nothing missing it prints nothing. Without Claude Code — CI — it notes
the skip and returns zero.
````

- [ ] **Step 4: Run every check**

Run: `./check`
Expected: PASS, `✓ 7 checks passed`

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: say how to onboard a project with dev-kit init"
```

---

## After the branch

Merge by rebase onto `main`. Then, on `main`, the release the README describes: `chore: release
2.3.0` changing `"version"` in `package.json` and the `^2.3.0` and `#v2.3.0` pins under Install,
and the `v2.3.0` tag on it. Consuming projects then run `npx dev-kit init` for their sections and
add `need_plugins` to their `./run`.
