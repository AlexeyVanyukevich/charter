# charter 3.0 — load tiers, domains and stacks: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the kit to `charter`, lay it out as `core` / `domains` / `stacks`, and deliver every rule outside `core` through `charter sync`, so a rule loads only when a session touches a matching file.

**Architecture:** `core/rules.md` stays the one `@` import. Rules under `domains/*/rules/` and `stacks/*/rules/` carry a fixed `paths:` block; `charter sync` (run by a `SessionStart` hook that `charter init` writes) mirrors them into the project's git-ignored `.claude/rules/charter/`, prefixing each pattern with its workspace's path from `charter.json`. Configs keep being reached by `extends` or path.

**Tech Stack:** Node ≥ 24 ESM with no dependencies (`bin/*.mjs`), bash 3.2-compatible shell (`core/lib.sh`, `checks/*.sh`), npm pack, TypeScript, Prettier, oxlint, the `claude` CLI for the live session check.

**Spec:** `docs/superpowers/specs/2026-10-13-foundation-design.md`, within `docs/superpowers/specs/2026-10-13-roadmap-design.md`.

## Global Constraints

- `./check` passes after every task; it is the only verification command.
- Every commit is one line, `type(scope)!: subject`, no body, no trailer, ≤ 72 characters (`core/rules/commits.md`; the commit-msg hook refuses anything else).
- Branch: `feat/charter-3`, cut from `main` once `docs/roadmap` (the specs and this plan) is merged. Merge back by rebase and `git merge --ff-only`.
- The package declares no `dependencies`, no `peerDependencies`, no `prepare`/`install`/`postinstall` scripts (`checks/10-package.sh`).
- Node `>=24.0.0`. Shell code runs on macOS's bash 3.2: no `${var,,}`, no `mapfile`, no heredoc inside `$(…)` (read heredocs with `IFS= read -r -d '' var <<'X' || true`).
- The package name is `charter`; `package.json`'s `version` stays `2.4.0` until Task 7.
- Rule budgets, counted on a rule's body (frontmatter excluded): one file ≤ 60 lines; `core/rules/` ≤ 150; a workspace's worst case ≤ 225.
- `charter sync` prints nothing to stdout on success.
- Writing rule: refer to projects and people by role; name only what must be installed, opened, run or called.

## Review Focus

Inputs the spec implies but does not spell out, most likely to bite first. Each has a test in the task named.

1. **A workspace written as `./server/` or `apps/web/`** — by hand in `charter.json`, or on the command line — means `server` and `apps/web`, not a second workspace. Tests: Task 3 (`75-sync`, `"./server/"`), Task 5 (`70-init`, `--workspace apps/web/`).
2. **A rule file with CRLF line endings**, as a kit checked out on Windows has it, parses like an LF one. Test: Task 3 (`75-sync`, `c.md`).
3. **A project's own `SessionStart` hooks and other settings keys** survive `init`, with the project's hook kept first. Test: Task 5 (`70-init`, merge case).
4. **A `.gitignore` without a final newline, or already ignoring `.claude/rules/charter` without the slash,** gets one clean line or none. Test: Task 5 (`70-init`).
5. **Nested workspaces** (`server` and `server/api`) get separate mirrors and separate prefixes. Test: Task 3 (`75-sync`).

## Decisions this plan takes that the spec does not state

Each is flagged for the reader of the plan:

- **`node` and `react` are refused in one workspace.** The spec drops 2.x's "backend and ui in one directory" refusal. Its reason survives per workspace: `stacks/node/rules/typescript.md` (`.js` on every relative import) and `stacks/react/rules/typescript.md` (no extension) contradict each other, and both match `*.ts`. `init` refuses the pair within one workspace, counting modules already recorded there.
- **`DEVKIT_NODE_MIN` / `DEVKIT_NODE_HINT` become `CHARTER_NODE_MIN` / `CHARTER_NODE_HINT`**, and the README's example secret `DEV_KIT_TOKEN` becomes `CHARTER_TOKEN`. The migration section lists the variables.
- **`sync` uses the kit it runs from** — the package holding `bin/charter.mjs` — and takes the project root from `CLAUDE_PROJECT_DIR`, else the working directory. In a consuming project the kit it runs from is `node_modules/charter`; a session started in a subdirectory still syncs at the root.
- **The live session's always-on fact is the backlog rule's example date, `2026-09-29`.** It is in `core/rules/backlog.md` only and no session could guess it.
- **Task 4 leaves an interim state:** each module keeps a temporary `rules.md` index, imported as in 2.x, until Task 5 moves the rules to the path tier.
- **This repository's own `CLAUDE.md` imports `@core/rules.md`** instead of `@common/rules.md`.

---

### Task 1: The commit-msg wrapper repairs itself and stops failing silently

The wrapper a 2.x project holds lets every commit through, silently, once the script it calls is gone — which 3.0's moves guarantee. Fix that first, under the current name, so every later move is repaired automatically.

**Files:**
- Modify: `common/lib.sh:153-177` (`need_hooks`)
- Test: `checks/80-commit-msg.sh`

**Interfaces:**
- Produces: `need_hooks` writes the wrapper when it is missing **or** when the file carries the kit's marker but differs from the current wrapper. The wrapper prints `… was not checked …` to stderr and exits 0 when the script is missing.

- [ ] **Step 1: Write the failing tests**

In `checks/80-commit-msg.sh`, after the `core.hooksPath` block (before `# Outside a repository there is nothing to install into`), add:

```bash
# A wrapper an older kit wrote is brought up to date, not taken for the project's own hook.
repo="$tmp/outdated"
git init -q "$repo"
printf '#!/bin/sh\n# dev-kit commit-msg\nf=node_modules/dev-kit/common/hooks/commit-msg\n[ -f "$f" ] || exit 0\nexec bash "$f" "$@"\n' \
  > "$repo/.git/hooks/commit-msg"
( cd "$repo" && source "$lib" && need_hooks ) >/dev/null || fail "need_hooks failed beside an outdated wrapper"
grep -q 'was not checked' "$repo/.git/hooks/commit-msg" || fail "need_hooks left an outdated wrapper as it was"
```

Replace the last block of the end-to-end section:

```bash
# Before the kit is installed — a fresh clone — the wrapper lets every commit through.
rm -rf "$consumer/node_modules"
git -C "$consumer" commit -q --allow-empty -m 'Fix: y' 2>/dev/null ||
  fail "with the kit not installed, the wrapper still refused a commit"
```

with:

```bash
# Before the kit is installed — a fresh clone — the wrapper lets every commit through, and says
# that nothing was checked rather than passing in silence.
rm -rf "$consumer/node_modules"
err="$(git -C "$consumer" commit -q --allow-empty -m 'Fix: y' 2>&1 >/dev/null)" ||
  fail "with the kit not installed, the wrapper still refused a commit"
grep -q 'was not checked' <<< "$err" ||
  fail "with the kit not installed, the wrapper let the commit through without saying so: got '$err'"
```

- [ ] **Step 2: Run the check to verify it fails**

Run: `./check 80`
Expected: FAIL with `✗ need_hooks left an outdated wrapper as it was`

- [ ] **Step 3: Rewrite `need_hooks`**

Replace `common/lib.sh` lines 153–177 (the comment above `need_hooks` and the function) with:

```bash
# The commit rule is enforced by the kit's commit-msg hook, and hooks are not cloned, so each
# clone installs it. The hooks directory gets a wrapper rather than a copy or a symlink: it
# follows the kit through upgrades and needs no executable bit from the tarball. Until the kit
# is installed it lets a commit through and says nothing was checked. A wrapper an older kit
# wrote is rewritten; a project's own commit-msg hook is never replaced.
need_hooks() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local hooks wrapper
  hooks="$(git rev-parse --git-path hooks)"
  # Read with `read`, not `$(cat <<…)`: bash 3.2 misparses the quotes in a heredoc inside a
  # command substitution.
  IFS= read -r -d '' wrapper <<'HOOK' || true
#!/bin/sh
# dev-kit commit-msg
f=node_modules/dev-kit/common/hooks/commit-msg
if [ ! -f "$f" ]; then
  echo "dev-kit: $f is missing, so this message was not checked. Run npm install." >&2
  exit 0
fi
exec bash "$f" "$@"
HOOK
  if [ -e "$hooks/commit-msg" ] || [ -L "$hooks/commit-msg" ]; then
    if ! grep -qx '# dev-kit commit-msg' "$hooks/commit-msg" 2>/dev/null; then
      note "$hooks/commit-msg is this project's own, so dev-kit's is not installed."
      note "To enforce the commit rule, call node_modules/dev-kit/common/hooks/commit-msg \"\$1\" from it."
      return 0
    fi
    [ "$(cat "$hooks/commit-msg")" = "${wrapper%$'\n'}" ] && return 0
  fi
  mkdir -p "$hooks"
  printf '%s' "$wrapper" > "$hooks/commit-msg"
  chmod +x "$hooks/commit-msg"
  ok "commit-msg hook"
}
```

- [ ] **Step 4: Run the checks**

Run: `./check 80 && ./check 50 && ./check 70`
Expected: each ends `✓ 1 checks passed`. (`50` proves sourcing is still inert; `70` runs `need_hooks` through `init`.)

- [ ] **Step 5: Run the whole suite and commit**

Run: `./check` — expected `✓ 9 checks passed`.

```bash
git add common/lib.sh checks/80-commit-msg.sh
git commit -m "fix(lib): rewrite an outdated commit-msg wrapper and warn when unchecked"
```

---

### Task 2: Rename the package to `charter`

**Files:**
- Rename: `bin/dev-kit.mjs` → `bin/charter.mjs`
- Modify: `package.json`, `common/lib.sh`, `CLAUDE.md`, `README.md`, every `checks/*.sh` that names the kit, `tests/fixture/package.json`, `tests/fixture/CLAUDE.md`, `tests/fixture/tsconfig*.json`, `tests/fixture/lint/tsconfig.json`
- Leave alone: `docs/` (dated records), the README's `## Migrating from 1.x` section (it describes 1.x and 2.0, which were `dev-kit`)

**Interfaces:**
- Produces: package `charter`, executable `charter`, paths `node_modules/charter/…`, specifiers `charter/<section>/…`, wrapper marker `# charter commit-msg`, env vars `CHARTER_NODE_MIN`, `CHARTER_NODE_HINT`, `CHARTER_SKIP_SESSION_CHECK`.

- [ ] **Step 1: Rename mechanically**

```bash
git mv bin/dev-kit.mjs bin/charter.mjs
perl -pi -e 's/dev-kit/charter/g; s/DEVKIT_/CHARTER_/g' \
  package.json common/lib.sh CLAUDE.md bin/charter.mjs \
  checks/10-package.sh checks/40-rules.sh checks/60-readme.sh checks/70-init.sh \
  checks/80-commit-msg.sh checks/90-lint.sh \
  tests/fixture/package.json tests/fixture/CLAUDE.md tests/fixture/tsconfig.json \
  tests/fixture/tsconfig.common.json tests/fixture/tsconfig.probe.json \
  tests/fixture/tsconfig.web.json tests/fixture/lint/tsconfig.json
perl -pi -e '$m = 1 if /^## Migrating from 1\.x/; unless ($m) { s/dev-kit/charter/g; s/DEVKIT_/CHARTER_/g; s/DEV_KIT_TOKEN/CHARTER_TOKEN/g }' README.md
```

- [ ] **Step 2: Write the failing test for a 2.x wrapper**

The substitution turned the outdated-wrapper fixture in `checks/80-commit-msg.sh` into a charter wrapper. It must stay a **2.x** wrapper, and the block must assert that it ends up rewritten under the new name. Replace the whole block (from `# A wrapper an older kit wrote` to its `fail` line) with:

```bash
# A wrapper an older kit wrote — dev-kit's included — is brought up to date, not taken for the
# project's own hook.
repo="$tmp/outdated"
git init -q "$repo"
printf '#!/bin/sh\n# dev-kit commit-msg\nf=node_modules/dev-kit/common/hooks/commit-msg\n[ -f "$f" ] || exit 0\nexec bash "$f" "$@"\n' \
  > "$repo/.git/hooks/commit-msg"
( cd "$repo" && source "$lib" && need_hooks ) >/dev/null || fail "need_hooks failed beside an outdated wrapper"
grep -qx '# charter commit-msg' "$repo/.git/hooks/commit-msg" ||
  fail "need_hooks took a dev-kit wrapper for the project's own hook, or left it as it was"
```

Run: `./check 80`
Expected: FAIL with `✗ need_hooks took a dev-kit wrapper for the project's own hook, or left it as it was`

- [ ] **Step 3: Recognise both markers**

In `common/lib.sh`, in `need_hooks`, replace

```bash
    if ! grep -qx '# charter commit-msg' "$hooks/commit-msg" 2>/dev/null; then
```

with

```bash
    # dev-kit is the kit's name before 3.0; a wrapper it wrote is ours to rewrite too.
    if ! grep -qxE '# (charter|dev-kit) commit-msg' "$hooks/commit-msg" 2>/dev/null; then
```

- [ ] **Step 4: Point the 1.x stale-path searches at both names**

A 1.x path is stale under either name. In `checks/10-package.sh` and `checks/60-readme.sh`, the regex `charter/(tsconfig|prettier|rules|sh|ignore)([^a-z]|$)` becomes `(dev-kit|charter)/(tsconfig|prettier|rules|sh|ignore)([^a-z]|$)`.

- [ ] **Step 5: Check what is left**

Run: `git grep -n -e 'dev-kit' -e 'DEVKIT' -- ':!docs' ':!README.md'`
Expected: only `common/lib.sh` (the marker regex and its comment), `checks/80-commit-msg.sh` (the 2.x fixture), and the two stale-path regexes.

Run: `grep -n 'dev-kit' README.md`
Expected: only lines inside `## Migrating from 1.x`, plus the sentence near the top that now reads "A package called `charter` on the public registry is an unrelated project" — confirm it says `charter`.

- [ ] **Step 6: Run the whole suite**

Run: `./check`
Expected: `✓ 9 checks passed`. `10` resolves `charter/package.json` from the fixture; `70` finds `node_modules/.bin/charter`; `80` rewrites the 2.x wrapper.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor!: rename the package to charter"
```

---

### Task 3: `charter sync` mirrors path-scoped rules into a project

Built and tested against a kit made up inside the check, so it lands before the real layout exists.

**Files:**
- Create: `bin/modules.mjs`, `bin/sync.mjs`, `checks/75-sync.sh`
- Modify: `bin/charter.mjs` (`usage`, `parse`, dispatch), `checks/10-package.sh` (expect the new files)

**Interfaces:**
- Produces, in `bin/modules.mjs`:
  - `class KitError extends Error` — `new KitError(message, hint)`; `.hint: string | undefined`.
  - `findModules(kit: string): Map<string, string>` — module name → directory relative to the kit (`'backend' → 'domains/backend'`), from every directory under `kit/domains/` and `kit/stacks/`, domains first, each sorted. Throws `KitError` when a name appears twice.
- Produces, in `bin/sync.mjs`:
  - `manifestFile = 'charter.json'`, `rulesDir = join('.claude', 'rules', 'charter')`.
  - `normalizeWorkspace(key: string): string` — forward slashes, no `./`, no trailing `/`; `''` and `'.'` give `'.'`.
  - `readManifest(root: string): { workspaces: Record<string, string[]> }` — throws `KitError`.
  - `plan(root: string, kit: string): Map<string, string>` — mirror path relative to `root` → file content. Throws `KitError`.
  - `sync(root: string, kit: string): void` — writes the plan, prunes the rest of `rulesDir`.
- Produces, in `bin/charter.mjs`: `charter sync` (no arguments) runs `sync(process.env.CLAUDE_PROJECT_DIR || process.cwd(), kit)`, where `kit` is the package holding `bin/`.

- [ ] **Step 1: Write the failing check**

Create `checks/75-sync.sh`:

```bash
#!/usr/bin/env bash
# charter sync mirrors each workspace's path-scoped rules into .claude/rules/charter/, prefixed
# with the workspace's path; deletes what the kit stopped shipping; prints nothing on success;
# and writes nothing at all when it refuses.
set -euo pipefail

tmp="$(mktemp -d)"
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
fail() { echo "  ✗ $*"; exit 1; }

# A project holding a small kit of its own: the real bin/, and modules made up for this check,
# so the check does not move whenever a real rule's globs do.
p="$tmp/project"
kit="$p/node_modules/charter"
mkdir -p "$kit/domains/alpha/rules" "$kit/stacks/beta/rules" "$kit/stacks/gamma" \
  "$p/server/api" "$p/apps/web"
cp -R bin "$kit/bin"
printf -- '---\npaths:\n  - "src/*"\n  - "src/modules/**"\n---\n# Alpha\n\nAlpha body.\n' \
  > "$kit/domains/alpha/rules/a.md"
printf -- '---\npaths:\n  - "**/*.ts"\n---\n# Beta\n' > "$kit/stacks/beta/rules/b.md"
# CRLF, as a kit checked out on Windows has it, parses the same.
printf -- '---\r\npaths:\r\n  - "tests/**"\r\n---\r\n# Beta two\r\n' > "$kit/stacks/beta/rules/c.md"
echo '{}' > "$kit/stacks/gamma/oxlint.json"
out="$p/.claude/rules/charter"

run() { (cd "$p" && node node_modules/charter/bin/charter.mjs sync); }
manifest() { printf '%s\n' "$1" > "$p/charter.json"; }

# ── the root workspace ────────────────────────────────────────────────────────

manifest '{ "workspaces": { ".": ["alpha", "gamma"] } }'
start="$(node -p 'Date.now()')"
stdout="$(run)" || fail "sync failed on a valid manifest"
took=$(( $(node -p 'Date.now()') - start ))
# A SessionStart hook's stdout goes into the session's context, so success must say nothing.
[ -z "$stdout" ] || fail "sync printed '$stdout' on success"
expected=$'---\npaths:\n  - "src/*"\n  - "src/modules/**"\n---\n# Alpha\n\nAlpha body.'
[ "$(cat "$out/@root/alpha/a.md")" = "$expected" ] ||
  { echo "  ✗ the root workspace's rule is not the kit's:"; cat "$out/@root/alpha/a.md"; exit 1; }
[ ! -e "$out/@root/gamma" ] || fail "a module with no rules got a directory"

# ── workspaces: prefixed, nested ones too, and the root's mirror gone ──────────

manifest '{ "workspaces": { "./server/": ["alpha"], "server/api": ["beta"], "apps/web": ["beta"] } }'
run >/dev/null || fail "sync failed on three workspaces"
grep -qx '  - "server/src/modules/\*\*"' "$out/server/alpha/a.md" ||
  fail "a workspace's patterns were not prefixed with its path"
grep -qx '  - "server/api/\*\*/\*\.ts"' "$out/server/api/beta/b.md" ||
  fail "a nested workspace's patterns were not prefixed with its own path"
grep -qx '  - "apps/web/tests/\*\*"' "$out/apps/web/beta/c.md" || fail "a CRLF rule was not read"
[ ! -e "$out/@root" ] || fail "the root's mirror survived the root's removal from charter.json"

# ── a second run writes nothing ───────────────────────────────────────────────

# Read-only files and directories: any write or delete fails the run.
chmod -R a-w "$out"
run >/dev/null || fail "a second run tried to write files that had not changed"
chmod -R u+w "$out"

# ── what the kit or the manifest dropped is deleted ───────────────────────────

rm "$kit/stacks/beta/rules/c.md"
run >/dev/null || fail "sync failed after a rule left the kit"
[ ! -e "$out/apps/web/beta/c.md" ] || fail "a rule the kit no longer ships survived"
[ -e "$out/apps/web/beta/b.md" ] || fail "removing one rule took another with it"
manifest '{ "workspaces": { "server": ["alpha"] } }'
run >/dev/null || fail "sync failed after workspaces were dropped"
[ ! -e "$out/apps" ] || fail "a dropped workspace left its directories behind"

# ── nothing outside the mirror is touched ─────────────────────────────────────

echo '# Own' > "$p/.claude/rules/own.md"
run >/dev/null || fail "sync failed beside a project's own rule"
[ -f "$p/.claude/rules/own.md" ] || fail "sync deleted a rule outside .claude/rules/charter/"

# ── run from a subdirectory, the hook's CLAUDE_PROJECT_DIR is the root ────────

rm -rf "$out"
( cd "$p/server" && CLAUDE_PROJECT_DIR="$p" node ../node_modules/charter/bin/charter.mjs sync ) ||
  fail "sync failed when run from a subdirectory"
[ -f "$out/server/alpha/a.md" ] || fail "sync did not write at CLAUDE_PROJECT_DIR"
[ ! -e "$p/server/.claude" ] || fail "sync wrote into the directory it was run from"

# ── refusals: exit 1, the cause on stderr, nothing written ────────────────────

snapshot() { (cd "$p/.claude" && find . | sort && find . -type f -exec cat {} +) | shasum; }
refuses() {
  local name="$1" expect="$2" before err
  before="$(snapshot)"
  err="$(run 2>&1 >/dev/null)" && fail "sync accepted $name"
  grep -qF -- "$expect" <<< "$err" || fail "refusing $name, sync did not say '$expect': got '$err'"
  [ "$(snapshot)" = "$before" ] || fail "sync wrote files while refusing $name"
}

manifest '{ "workspaces": '
refuses 'broken JSON' 'charter.json'
manifest '{ "workspaces": [] }'
refuses 'workspaces as a list' 'workspaces'
manifest '{ "workspaces": { "server": ["alpha", "delta"] } }'
refuses 'an unknown module' 'delta'
manifest '{ "workspaces": { "nope": ["alpha"] } }'
refuses 'a missing workspace' 'not a directory'
manifest '{ "workspaces": { "../elsewhere": ["alpha"] } }'
refuses 'a workspace outside' 'outside'
manifest '{ "workspaces": { "@root": ["alpha"] } }'
refuses 'a workspace named @root' '@root'
rm "$p/charter.json"
refuses 'no manifest' 'charter.json'
manifest '{ "workspaces": { "server": ["alpha"] } }'
printf '# No paths block\n' > "$kit/domains/alpha/rules/d.md"
refuses 'a rule with no paths block' 'd.md'
rm "$kit/domains/alpha/rules/d.md"
mkdir "$kit/domains/beta"
refuses 'a module name used twice' 'beta'
rmdir "$kit/domains/beta"
err="$( (cd "$p" && node node_modules/charter/bin/charter.mjs sync extra) 2>&1 >/dev/null )" &&
  fail "sync accepted an argument"
grep -q 'no arguments' <<< "$err" || fail "sync with an argument did not say it takes none: got '$err'"

echo "  ✓ sync mirrors and prefixes each workspace's rules, deletes what was dropped, prints"
echo "    nothing, and writes nothing when refusing; one run took ${took} ms"
```

Run: `./check 75`
Expected: FAIL — `✗ sync failed on a valid manifest` (the command does not exist yet).

- [ ] **Step 2: Create `bin/modules.mjs`**

```js
// The modules a project's charter.json can name: every directory under domains/ and stacks/.
// core/ is not one — it loads in every project through the CLAUDE.md import.

import { existsSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

// A refusal the person can act on: the message says what is wrong, the hint what to do.
export class KitError extends Error {
  constructor(message, hint) {
    super(message)
    this.hint = hint
  }
}

export function findModules(kit) {
  const modules = new Map()
  for (const group of ['domains', 'stacks']) {
    const dir = join(kit, group)
    if (!existsSync(dir)) continue
    for (const name of readdirSync(dir).sort()) {
      if (!statSync(join(dir, name)).isDirectory()) continue
      if (modules.has(name)) {
        throw new KitError(
          `The module ${name} appears in both ${modules.get(name)} and ${group}/${name}.`,
          'Module names must be unique: charter.json names a module, not its directory.',
        )
      }
      modules.set(name, `${group}/${name}`)
    }
  }
  return modules
}
```

- [ ] **Step 3: Create `bin/sync.mjs`**

```js
// Mirrors each workspace's path-scoped rules into .claude/rules/charter/, writing the workspace's
// path in front of every pattern. Computes everything before writing anything, and prints
// nothing: a SessionStart hook's stdout goes into the session's context. Spec §3.

import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  rmdirSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { dirname, isAbsolute, join, posix, relative } from 'node:path'
import { KitError, findModules } from './modules.mjs'

export const manifestFile = 'charter.json'
export const rulesDir = join('.claude', 'rules', 'charter')
const rootName = '@root'

export function normalizeWorkspace(key) {
  const cleaned = posix.normalize(key.replaceAll('\\', '/')).replace(/\/+$/, '')
  return cleaned === '' ? '.' : cleaned
}

export function readManifest(root) {
  const file = join(root, manifestFile)
  if (!existsSync(file)) {
    throw new KitError(`There is no ${manifestFile} at ${root}.`, 'Run npx charter init at the repository root.')
  }
  let manifest
  try {
    manifest = JSON.parse(readFileSync(file, 'utf8'))
  } catch {
    throw new KitError(`${manifestFile} is not valid JSON.`, 'Fix it, then run this again.')
  }
  const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)
  if (!isObject(manifest) || !isObject(manifest.workspaces)) {
    throw new KitError(
      `${manifestFile} has no "workspaces" object.`,
      'It reads { "workspaces": { ".": ["<module>", …] } }.',
    )
  }
  for (const [key, names] of Object.entries(manifest.workspaces)) {
    if (!Array.isArray(names) || names.some((name) => typeof name !== 'string')) {
      throw new KitError(`In ${manifestFile}, workspace "${key}" is not a list of module names.`)
    }
  }
  return manifest
}

// The block's form is fixed so that no YAML parser is needed: ---, paths:, one   - "<pattern>"
// line or more, then ---. ./check holds every rule outside core/ to it.
function parseRule(text, name) {
  const lines = text.split(/\r?\n/)
  const patterns = []
  let i = 2
  while (i < lines.length && /^ {2}- "[^"]+"$/.test(lines[i])) {
    patterns.push(lines[i].slice(5, -1))
    i++
  }
  if (lines[0] !== '---' || lines[1] !== 'paths:' || patterns.length === 0 || lines[i] !== '---') {
    throw new KitError(
      `${name} does not open with a paths: block.`,
      'A rule outside core/ starts with ---, paths:, one   - "<pattern>" line per pattern, then ---.',
    )
  }
  return { patterns, body: lines.slice(i + 1).join('\n') }
}

export function plan(root, kit) {
  const manifest = readManifest(root)
  const modules = findModules(kit)
  const wanted = new Map()
  for (const [key, names] of Object.entries(manifest.workspaces)) {
    const workspace = normalizeWorkspace(key)
    if (workspace === rootName) {
      throw new KitError(`A workspace cannot be named ${rootName}.`, 'charter uses that name for the root.')
    }
    if (workspace === '..' || workspace.startsWith('../') || isAbsolute(workspace)) {
      throw new KitError(`Workspace "${key}" is outside the repository.`, 'Name it by its path from the root.')
    }
    const dir = join(root, workspace)
    if (!existsSync(dir) || !statSync(dir).isDirectory()) {
      throw new KitError(`Workspace "${key}" is not a directory.`, `Create it, or remove it from ${manifestFile}.`)
    }
    const out = workspace === '.' ? rootName : workspace
    for (const name of names) {
      const home = modules.get(name)
      if (!home) {
        throw new KitError(
          `Unknown module "${name}" in ${manifestFile}.`,
          `The modules are ${[...modules.keys()].join(', ')}.`,
        )
      }
      const rules = join(kit, home, 'rules')
      if (!existsSync(rules)) continue
      for (const file of readdirSync(rules).filter((f) => f.endsWith('.md')).sort()) {
        const { patterns, body } = parseRule(readFileSync(join(rules, file), 'utf8'), `${home}/rules/${file}`)
        const prefixed = patterns.map((pattern) => (workspace === '.' ? pattern : `${workspace}/${pattern}`))
        const content = `---\npaths:\n${prefixed.map((p) => `  - "${p}"`).join('\n')}\n---\n${body}`
        wanted.set(join(rulesDir, ...out.split('/'), name, file), content)
      }
    }
  }
  return wanted
}

export function sync(root, kit) {
  const wanted = plan(root, kit)
  for (const [path, content] of wanted) {
    const file = join(root, path)
    if (existsSync(file) && readFileSync(file, 'utf8') === content) continue
    mkdirSync(dirname(file), { recursive: true })
    writeFileSync(file, content)
  }
  prune(join(root, rulesDir), root, wanted)
}

// Deletes every file under dir the mirror no longer holds, then each directory that leaves empty.
function prune(dir, root, wanted) {
  if (!existsSync(dir)) return
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) {
      prune(path, root, wanted)
      if (readdirSync(path).length === 0) rmdirSync(path)
    } else if (!wanted.has(relative(root, path))) {
      rmSync(path)
    }
  }
}
```

- [ ] **Step 4: Dispatch `sync` from `bin/charter.mjs`**

1. Add after the existing imports:

```js
import { KitError } from './modules.mjs'
import { sync } from './sync.mjs'
```

2. Replace the `usage` line with:

```js
const usage = 'Usage: charter init <section…> [--workspace <dir>]  |  charter sync'
```

3. In `parse`, replace

```js
  const [command, ...sections] = parsed.positionals
  if (command !== 'init') fail(command ? `Unknown command: ${command}.` : 'No command given.', usage)
```

with

```js
  const [command, ...sections] = parsed.positionals
  if (command === 'sync') {
    if (sections.length > 0 || parsed.values.workspace !== undefined) fail('sync takes no arguments.', usage)
    return { command }
  }
  if (command !== 'init') fail(command ? `Unknown command: ${command}.` : 'No command given.', usage)
```

and make its final `return` read `return { command, sections: [...new Set(sections)], workspace: parsed.values.workspace ?? '.' }`.

4. Replace `const options = parse(process.argv.slice(2))` with:

```js
const options = parse(process.argv.slice(2))
if (options.command === 'sync') {
  // The hook runs with the project root in CLAUDE_PROJECT_DIR, whatever directory the session
  // started in; by hand, sync runs at the root.
  try {
    sync(process.env.CLAUDE_PROJECT_DIR || process.cwd(), kit)
  } catch (error) {
    if (error instanceof KitError) fail(error.message, error.hint)
    throw error
  }
  process.exit(0)
}
```

- [ ] **Step 5: Expect the new files in the package**

In `checks/10-package.sh`, after `expect_packed 'bin/charter.mjs'`, add:

```bash
expect_packed 'bin/modules.mjs'
expect_packed 'bin/sync.mjs'
```

- [ ] **Step 6: Run the checks**

Run: `./check 75 && ./check 10 && ./check 70`
Expected: each `✓ 1 checks passed`; `75` prints its run time.

- [ ] **Step 7: Run the whole suite and commit**

Run: `./check` — expected `✓ 10 checks passed`.

```bash
git add bin checks/75-sync.sh checks/10-package.sh
git commit -m "feat: mirror path-scoped rules into a project with charter sync"
```

---

### Task 4: Lay the kit out as `core`, `domains` and `stacks`

Every file moves; rules still load through `@` imports, through a temporary index in each module. `init` learns module names.

**Files:**
- Move: see Step 1
- Create: `core/rules.md`, `domains/backend/rules.md`, `stacks/typescript/rules.md`, `stacks/node/rules.md`, `stacks/react/rules.md`
- Delete: `common/rules.md`, `backend/rules.md`, `ui/rules.md`, `testing/rules.md`, the empty `common/`, `backend/`, `ui/`, `testing/`
- Modify: `package.json`, `bin/charter.mjs`, `core/lib.sh`, `core/hooks/commit-msg` (comment), `stacks/*/tsconfig.json`, `stacks/*/oxlint.json`, `domains/backend/rules/http.md`, `stacks/node/rules/typescript.md`, `stacks/typescript/rules/typescript.md`, `CLAUDE.md`, `README.md`, `tests/fixture/*`, `checks/10,20,30,40,50,60,70,80,90`

**Interfaces:**
- Consumes: `findModules` (Task 3).
- Produces: the 3.0 tree; specifiers `charter/stacks/{typescript,node,react}/tsconfig`, `charter/stacks/typescript/prettier`; `core/lib.sh`; `core/hooks/commit-msg`; module names `backend`, `node`, `react`, `typescript`, `vitest`.

- [ ] **Step 1: Move the files**

```bash
mkdir -p core/rules domains/backend/rules stacks/typescript/rules stacks/node/rules stacks/react/rules stacks/vitest
git mv common/rules/commits.md common/rules/documentation.md common/rules/writing.md \
  common/rules/review.md common/rules/backlog.md core/rules/
git mv testing/rules/testing.md core/rules/
git mv common/hooks core/hooks
git mv common/lib.sh core/lib.sh
git mv common/ignore core/ignore
git mv common/tsconfig.json common/prettier.json common/oxlint.json stacks/typescript/
git mv common/rules/typescript.md stacks/typescript/rules/
git mv backend/tsconfig.json backend/oxlint.json stacks/node/
git mv backend/rules/typescript.md stacks/node/rules/
git mv backend/rules/http.md backend/rules/layout.md backend/rules/database-tests.md domains/backend/rules/
git mv ui/tsconfig.json ui/oxlint.json ui/plugins.json stacks/react/
git mv ui/rules/typescript.md stacks/react/rules/
git mv testing/oxlint.json stacks/vitest/
git rm -q common/rules.md backend/rules.md ui/rules.md testing/rules.md
```

Run: `ls common backend ui testing 2>&1`
Expected: four `No such file or directory` lines. Remove any directory left behind.

- [ ] **Step 2: Write the indexes**

`core/rules.md`:

```markdown
# Core

@rules/commits.md
@rules/documentation.md
@rules/writing.md
@rules/review.md
@rules/backlog.md
@rules/testing.md
```

`domains/backend/rules.md` — temporary, deleted in Task 5:

```markdown
# Backend

@rules/http.md
@rules/layout.md
@rules/database-tests.md
```

`stacks/typescript/rules.md`, `stacks/node/rules.md`, `stacks/react/rules.md` — temporary — each a heading (`# TypeScript`, `# Node`, `# React`), a blank line and `@rules/typescript.md`.

- [ ] **Step 3: Fix the relative `extends`**

- `stacks/node/tsconfig.json` and `stacks/react/tsconfig.json`: `"extends": "../common/tsconfig.json"` → `"extends": "../typescript/tsconfig.json"`.
- `stacks/node/oxlint.json` and `stacks/react/oxlint.json`: `"extends": ["../common/oxlint.json"]` → `"extends": ["../typescript/oxlint.json"]`.

- [ ] **Step 4: Take the library out of the backend domain's rule**

In `domains/backend/rules/http.md`, replace

```markdown
**Every request body is a TypeBox schema with `additionalProperties: false`.** Unknown fields
are rejected, never ignored: a field the server silently drops is a feature the client believes
it has.
```

with

```markdown
**Every request body is validated against a schema that rejects unknown fields.** A field the
server silently drops is a feature the client believes it has.
```

In `stacks/node/rules/typescript.md`, replace

```markdown
**The TypeBox package is `typebox`, not `@sinclair/typebox`,** paired with
`@fastify/type-provider-typebox`. The two publish similar APIs under different names, and
installing the wrong one produces type errors that read as though the schema is at fault.
```

with

```markdown
**Request schemas are TypeBox, with `additionalProperties: false`. The package is `typebox`,
not `@sinclair/typebox`,** paired with `@fastify/type-provider-typebox`. The two publish
similar APIs under different names, and installing the wrong one produces type errors that
read as though the schema is at fault.
```

In `stacks/typescript/rules/typescript.md`: `Extend a section's tsconfig` → `Extend a stack's tsconfig`.

- [ ] **Step 5: `package.json`**

```json
  "files": [
    "bin",
    "core",
    "domains",
    "stacks"
  ],
```

```json
  "exports": {
    "./package.json": "./package.json",
    "./stacks/typescript/tsconfig": "./stacks/typescript/tsconfig.json",
    "./stacks/typescript/prettier": "./stacks/typescript/prettier.json",
    "./stacks/node/tsconfig": "./stacks/node/tsconfig.json",
    "./stacks/react/tsconfig": "./stacks/react/tsconfig.json"
  }
```

- [ ] **Step 6: Paths inside the kit**

- `core/lib.sh`: every `node_modules/charter/common/` → `node_modules/charter/core/` (the header comment, the `need_hooks` note and the wrapper's `f=` line). The changed wrapper content is what makes `need_hooks` rewrite every installed wrapper on upgrade.
- `core/hooks/commit-msg`: the comment `common/rules/commits.md` → `core/rules/commits.md`.
- `CLAUDE.md` (this repository's): `The kit follows its own \`common\` rules.` → `The kit follows its own \`core\` rules.`, and `@common/rules.md` → `@core/rules.md`.

- [ ] **Step 7: `init` learns modules**

In `bin/charter.mjs`:

1. Change the import from Task 3 to `import { KitError, findModules } from './modules.mjs'`.
2. Replace `usage` with `'Usage: charter init <module…> [--workspace <dir>]  |  charter sync'`, and `'Name at least one section.'` with `'Name at least one module.'`.
3. Before `const options = parse(…)`, add `const modules = findModules(kit)`.
4. In `check`, replace everything from `const valid = readdirSync(kit)` through the `backend`/`ui` refusal with:

```js
  const unknown = sections.filter((name) => !modules.has(name))
  if (unknown.length > 0) {
    fail(`Unknown module: ${unknown.join(', ')}.`, `The modules are ${[...modules.keys()].join(', ')}.`)
  }
  if (sections.includes('node') && sections.includes('react')) {
    fail(
      'node and react cannot load in the same directory.',
      'Give each its own workspace: charter init node --workspace <dir>, and the same for react.',
    )
  }
```

5. Replace `pluginsOf`'s first line with `const file = join(kit, modules.get(section), 'plugins.json')`.
6. Replace the `imports` computation with:

```js
// core loads from the root's CLAUDE.md; each module's index from its workspace's.
const indexOf = (name) => (name === 'core' ? 'core' : modules.get(name))
const atRoot = dir === process.cwd()
const imports = [...(atRoot ? ['core'] : []), ...options.sections]
  .filter((name) => existsSync(join(kit, indexOf(name), 'rules.md')))
  .map((name) => `@${up ? `${up}/` : ''}node_modules/charter/${indexOf(name)}/rules.md`)
```

7. Replace the hook lines at the end with:

```js
// core carries the commit rule, and every project loads core, so every init installs the hook.
const lib = join(kit, 'core', 'lib.sh')
const run = spawnSync('bash', ['-c', 'source "$1" && need_plugins && need_hooks', 'charter', lib], {
  stdio: 'inherit',
})
process.exit(run.status ?? 1)
```

8. Remove `readdirSync` from the `node:fs` import if nothing else uses it.

- [ ] **Step 8: The fixture**

- `tests/fixture/package.json`: `"prettier": "charter/stacks/typescript/prettier"`.
- `tests/fixture/tsconfig.json`, `tsconfig.probe.json`: `"extends": "charter/stacks/node/tsconfig"`. `tsconfig.common.json`, `lint/tsconfig.json`: `"extends": "charter/stacks/typescript/tsconfig"`. `tsconfig.web.json`: `"extends": "charter/stacks/react/tsconfig"`.
- `tests/fixture/CLAUDE.md`: replace the four imports with

```markdown
@node_modules/charter/core/rules.md
@node_modules/charter/domains/backend/rules.md
@node_modules/charter/stacks/typescript/rules.md
@node_modules/charter/stacks/node/rules.md
@node_modules/charter/stacks/react/rules.md
```

  and make its prose say "every module index" instead of "every section".

- [ ] **Step 9: The checks**

Make these exact changes:

- `checks/10-package.sh`: `find common backend ui testing -type f` → `find core domains stacks -type f`; the stale-path `grep -rnE … common backend ui testing` → `… core domains stacks`; the outside regex → `'^(bin|core|domains|stacks)/|^package\.json$|^README\.md$'`; its comment "Only the four sections" → "Only core, domains, stacks". Add after the stale 1.x search:

```bash
# A 2.x path in a shipped file sends a consumer to a directory 3.0 removed.
stale2="$(grep -rnE '(dev-kit|charter)/(common|backend|ui|testing)/' core domains stacks 2>/dev/null || true)"
[ -z "$stale2" ] || { echo "  ✗ shipped files still name 2.x paths:"; echo "$stale2"; exit 1; }
```

- `checks/20-tsconfig.sh`: messages `backend/tsconfig` → `stacks/node/tsconfig`, `common/tsconfig` → `stacks/typescript/tsconfig`, `ui/tsconfig` → `stacks/react/tsconfig`, "the ui base" → "the react base"; the final line → `"  ✓ typescript, node and react resolve by specifier; strictness and the DOM lib are real"`.
- `checks/30-prettier.sh`: `common/ignore/` → `core/ignore/` (four places); final line "with the common core" → "with core".
- `checks/50-lib.sh`: `common/lib.sh` → `core/lib.sh` (two places).
- `checks/80-commit-msg.sh`: `hook="$PWD/core/hooks/commit-msg"` and its message; `lib="$PWD/core/lib.sh"`; `source node_modules/charter/core/lib.sh`; header comment `core/rules/commits.md`. The outdated-wrapper fixture stays the 2.x text.
- `checks/90-lint.sh`: in `config()`, `"$kit/$section/oxlint.json"` → `"$kit/stacks/$section/oxlint.json"`; in the rows, `common` → `typescript`, `backend` → `node`, `ui` → `react`, `testing` → `vitest` (the module names only, never the file names); the comment "the named sections" → "the named stacks".
- `checks/60-readme.sh`: the specifier line becomes exactly:

  ```bash
  specifier='charter/stacks/\(typescript\|node\|react\)/\(tsconfig\|prettier\)[^ )`"]*'
  ```
- `checks/70-init.sh`: apply these replacements, in order:
  - `init common ui` → `init typescript react` (both runs); expected `CLAUDE.md` →
    ```
    @node_modules/charter/core/rules.md
    @node_modules/charter/stacks/typescript/rules.md
    @node_modules/charter/stacks/react/rules.md
    ```
    and its message "is not the two imports" → "is not core and the two stacks".
  - `init ui` → `init react` (formatted and merge cases); `init testing` → `init vitest`, expected `$'# Project\n\n@node_modules/charter/core/rules.md'`.
  - `init common common` → `init node node`; grep `'stacks/node/rules.md'`; message "a repeated module".
  - workspaces: `init backend --workspace server` → expected `'@../node_modules/charter/domains/backend/rules.md'`; `init ui --workspace apps/web` → `init react --workspace apps/web`, expected `'@../../node_modules/charter/stacks/react/rules.md'`.
  - hook block: replace both `hooked`/`unhooked` cases with one — `init react` in a fresh repository installs `.git/hooks/commit-msg` (message "every init installs the commit-msg hook"), and drop the "common carries the commit rule" comment for "core carries the commit rule and every project loads it".
  - refusals: `'backend, common, testing, ui'` → `'backend, node, react, typescript, vitest'` with `init frontend`; the `backend with ui` case → `refuses 'node with react' '--workspace' init node react`; the remaining `init common` / `init ui` arguments → `init typescript` / `init react`; `init backend` (subdir case) → `init node`.
  - header comment: "sections" → "modules".

- `checks/40-rules.sh`: replace the whole file with:

```bash
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
```

- [ ] **Step 10: The README's paths**

Paths only; the prose is rewritten in Task 6. Outside `## Migrating from 1.x`:

```bash
perl -pi -e '
  $m = 1 if /^## Migrating from 1\.x/;
  next if $m;
  s{charter/common/tsconfig}{charter/stacks/typescript/tsconfig}g;
  s{charter/backend/tsconfig}{charter/stacks/node/tsconfig}g;
  s{charter/ui/tsconfig}{charter/stacks/react/tsconfig}g;
  s{charter/common/prettier}{charter/stacks/typescript/prettier}g;
  s{charter/common/(lib\.sh|ignore|hooks)}{charter/core/$1}g;
  s{charter/common/rules\.md}{charter/core/rules.md}g;
  s{charter/backend/rules\.md}{charter/domains/backend/rules.md}g;
  s{charter/ui/rules\.md}{charter/stacks/react/rules.md}g;
  s{charter/backend/oxlint\.json}{charter/stacks/node/oxlint.json}g;
  s{charter/testing/oxlint\.json}{charter/stacks/vitest/oxlint.json}g;
  $_ = "" if m{^\@node_modules/charter/testing/rules\.md$};
' README.md
```

Run: `grep -nE 'charter/(common|backend|ui|testing)/' README.md`
Expected: no output.

- [ ] **Step 11: Run the whole suite**

Run: `./check`
Expected: `✓ 10 checks passed`; `40` reports a backend session of 216 lines and a react session of 149.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "refactor!: lay the kit out as core, domains and stacks"
```

---

### Task 5: Domain and stack rules load only for matching paths

`init` writes the manifest, the hook and the `.gitignore` line and syncs; the module indexes go; rules carry `paths:`.

**Files:**
- Modify: the six rule files under `domains/` and `stacks/` (frontmatter)
- Delete: `domains/backend/rules.md`, `stacks/typescript/rules.md`, `stacks/node/rules.md`, `stacks/react/rules.md`
- Replace: `bin/charter.mjs`, `checks/40-rules.sh`, `checks/70-init.sh`
- Modify: `tests/fixture/CLAUDE.md`, `README.md` (the import lines `60` checks), `docs/backlog.md`

**Interfaces:**
- Consumes: `KitError`, `findModules` (Task 3); `manifestFile`, `normalizeWorkspace`, `readManifest`, `sync` (Task 3).
- Produces: `charter init [<module…>] [--workspace <dir>]` as spec §4; the hook command `node "$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs" sync`.

- [ ] **Step 1: Write the failing checks**

Replace `checks/70-init.sh` with:

```bash
#!/usr/bin/env bash
# charter init records a workspace's modules in charter.json, imports core into the root
# CLAUDE.md, wires the sync hook, the .gitignore line and the modules' plugins, then syncs —
# merging into what is there, refusing what it cannot do cleanly, and reaching a consumer as
# `charter`.
set -euo pipefail

cli="$PWD/bin/charter.mjs"
[ -f "$cli" ] || { echo "  ✗ bin/charter.mjs does not exist"; exit 1; }

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
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

project() { rm -rf "$tmp/$1"; mkdir -p "$tmp/$1/node_modules/charter"; echo "$tmp/$1"; }
fail() { echo "  ✗ $*"; exit 1; }
hook='node "$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs" sync'

# ── a first run ───────────────────────────────────────────────────────────────

p="$(project fresh)"
( cd "$p" && node "$cli" init backend typescript node vitest ) >/dev/null ||
  fail "init backend typescript node vitest failed"
[ "$(node -p 'JSON.stringify(require(process.argv[1]))' "$p/charter.json")" = \
  '{"workspaces":{".":["backend","typescript","node","vitest"]}}' ] ||
  { echo "  ✗ charter.json is not the four modules:"; cat "$p/charter.json"; exit 1; }
[ "$(cat "$p/CLAUDE.md")" = '@node_modules/charter/core/rules.md' ] ||
  { echo "  ✗ CLAUDE.md is not the core import:"; cat "$p/CLAUDE.md"; exit 1; }
node -e '
  const s = require(process.argv[1])
  const entries = s.hooks.SessionStart
  if (entries.length !== 1 || entries[0].hooks.length !== 1) throw new Error("not one hook")
  if (entries[0].hooks[0].type !== "command" || entries[0].hooks[0].command !== process.argv[2]) throw new Error("not sync")
  if (s.enabledPlugins !== undefined) throw new Error("plugins for modules that bring none")
' "$p/.claude/settings.json" "$hook" 2>/dev/null ||
  { echo "  ✗ settings.json does not hold exactly the sync hook:"; cat "$p/.claude/settings.json"; exit 1; }
[ "$(cat "$p/.gitignore")" = '.claude/rules/charter/' ] || fail ".gitignore does not ignore the synced rules"
grep -qx '  - "src/modules/\*\*"' "$p/.claude/rules/charter/@root/backend/http.md" ||
  fail "init did not sync the backend rules"

# ── a second run changes nothing ───────────────────────────────────────────────

for f in charter.json CLAUDE.md .gitignore .claude/settings.json; do cp "$p/$f" "$tmp/before.${f//\//_}"; done
( cd "$p" && node "$cli" init backend typescript node vitest ) >/dev/null || fail "a second init failed"
for f in charter.json CLAUDE.md .gitignore .claude/settings.json; do
  cmp -s "$p/$f" "$tmp/before.${f//\//_}" || fail "a second run changed $f"
done

# Nothing to add means a file is not rewritten, so a project's own formatting survives.
p="$(project formatted)"
mkdir -p "$p/.claude"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":%s}]}]}}\n' \
  "$(node -p 'JSON.stringify(process.argv[1])' "$hook")" > "$p/.claude/settings.json"
cp "$p/.claude/settings.json" "$tmp/settings.before"
( cd "$p" && node "$cli" init typescript ) >/dev/null || fail "init with its hook already set failed"
cmp -s "$p/.claude/settings.json" "$tmp/settings.before" || fail "init rewrote settings.json with nothing to add"

# ── no modules: core alone ────────────────────────────────────────────────────

p="$(project bare)"
( cd "$p" && node "$cli" init ) >/dev/null || fail "init with no modules failed"
[ "$(node -p 'JSON.stringify(require(process.argv[1]).workspaces)' "$p/charter.json")" = '{".":[]}' ] ||
  fail "init with no modules did not record an empty root workspace"
grep -qx '@node_modules/charter/core/rules.md' "$p/CLAUDE.md" || fail "init with no modules did not import core"

# ── merging into what is there ────────────────────────────────────────────────

p="$(project merge)"
mkdir -p "$p/.claude"
echo '{ "model": "opus", "enabledPlugins": { "playwright@claude-plugins-official": false },
  "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo own" } ] } ] } }' \
  > "$p/.claude/settings.json"
printf '# Project' > "$p/CLAUDE.md"
printf 'dist/' > "$p/.gitignore"
echo '{ "workspaces": { ".": ["typescript"] }, "note": "kept" }' > "$p/charter.json"
: > "$CLAUDE_LOG"
( cd "$p" && node "$cli" init react vitest ) >/dev/null || fail "init into an existing project failed"
node -e '
  const s = require(process.argv[1])
  if (s.model !== "opus") throw new Error("model was dropped")
  if (s.enabledPlugins["playwright@claude-plugins-official"] !== false) throw new Error("opt-out overwritten")
  if (s.enabledPlugins["frontend-design@claude-plugins-official"] !== true) throw new Error("plugin not enabled")
  const commands = s.hooks.SessionStart.flatMap((e) => e.hooks.map((h) => h.command))
  if (commands.length !== 2 || commands[0] !== "echo own") throw new Error("own hook not kept first")
' "$p/.claude/settings.json" 2>/dev/null || fail "init changed or dropped something set in settings.json"
[ "$(cat "$p/CLAUDE.md")" = $'# Project\n\n@node_modules/charter/core/rules.md' ] ||
  { echo "  ✗ the core import was not appended after one blank line:"; cat "$p/CLAUDE.md"; exit 1; }
[ "$(cat "$p/.gitignore")" = $'dist/\n\n.claude/rules/charter/' ] ||
  { echo "  ✗ the .gitignore line was not appended after one blank line:"; cat "$p/.gitignore"; exit 1; }
node -e '
  const m = require(process.argv[1])
  if (m.note !== "kept" || m.workspaces["."].join() !== "typescript,react,vitest") throw new Error()
' "$p/charter.json" 2>/dev/null || fail "init did not append to the workspace's modules, keeping the rest"
grep -qx 'plugin install frontend-design@claude-plugins-official --scope project' "$CLAUDE_LOG" ||
  fail "init did not run need_plugins"

# A .gitignore already ignoring the directory, without the slash, is left alone.
p="$(project ignored)"
printf '.claude/rules/charter\n' > "$p/.gitignore"
( cd "$p" && node "$cli" init ) >/dev/null || fail "init beside an existing ignore line failed"
[ "$(cat "$p/.gitignore")" = '.claude/rules/charter' ] || fail "init added a second ignore line"

# A module named twice is recorded once.
p="$(project twice)"
( cd "$p" && node "$cli" init node node ) >/dev/null || fail "init node node failed"
[ "$(node -p 'require(process.argv[1]).workspaces["."].join()' "$p/charter.json")" = node ] ||
  fail "a repeated module was recorded twice"

# ── workspaces ────────────────────────────────────────────────────────────────

p="$(project split)"
mkdir -p "$p/server" "$p/apps/web"
( cd "$p" && node "$cli" init backend typescript node --workspace server ) >/dev/null ||
  fail "init --workspace server failed"
( cd "$p" && node "$cli" init typescript react --workspace apps/web/ ) >/dev/null ||
  fail "init --workspace apps/web/ failed"
node -e '
  const w = require(process.argv[1]).workspaces
  if (w.server.join() !== "backend,typescript,node" || w["apps/web"].join() !== "typescript,react") throw new Error()
' "$p/charter.json" 2>/dev/null || fail "workspaces are not recorded by their path from the root"
grep -qx '  - "server/src/modules/\*\*"' "$p/.claude/rules/charter/server/backend/http.md" ||
  fail "a workspace's rules were not synced with its prefix"
[ -f "$p/.claude/rules/charter/apps/web/react/typescript.md" ] || fail "a nested workspace's rules were not synced"
[ "$(cat "$p/CLAUDE.md")" = '@node_modules/charter/core/rules.md' ] || fail "core was not imported at the root, once"
[ ! -e "$p/server/CLAUDE.md" ] && [ ! -e "$p/apps/web/.claude" ] || fail "init wrote into a workspace"
grep -q 'playwright@claude-plugins-official' "$p/.claude/settings.json" ||
  fail "a workspace's plugins did not land in the root settings.json"

# ── the commit-msg hook ───────────────────────────────────────────────────────

# core carries the commit rule and every project loads core, so every init installs the hook.
p="$(project hooked)"
git -C "$p" init -q
( cd "$p" && node "$cli" init ) >/dev/null || fail "init in a repository failed"
[ -f "$p/.git/hooks/commit-msg" ] || fail "init did not install the commit-msg hook"

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

refuses 'no command' 'Usage: charter init'
refuses 'another command' 'Usage: charter init' build typescript
refuses 'sync with arguments' 'no arguments' sync backend
refuses 'an unknown module' 'backend, node, react, typescript, vitest' init frontend
refuses 'node with react' 'cannot share a workspace' init node react
SETUP='echo "{ \"workspaces\": { \".\": [\"node\"] } }" > charter.json' \
  refuses 'react beside a recorded node' 'cannot share a workspace' init react
refuses 'a missing workspace' 'not a directory' init react --workspace nope
refuses 'a workspace outside' 'outside this repository' init react --workspace ..
SETUP='mkdir @root' refuses 'a workspace named @root' '@root' init react --workspace @root
SETUP='mkdir .claude && echo "{" > .claude/settings.json' \
  refuses 'broken settings JSON' 'settings.json' init typescript
SETUP='mkdir .claude && echo "{ \"enabledPlugins\": [] }" > .claude/settings.json' \
  refuses 'enabledPlugins as an array' 'enabledPlugins' init typescript
SETUP='mkdir .claude && echo "{ \"hooks\": [] }" > .claude/settings.json' \
  refuses 'hooks as an array' 'hooks' init typescript
SETUP='echo "{" > charter.json' refuses 'broken charter.json' 'charter.json' init typescript

# Run from a workspace instead of the root, init would write where no session reads. Without the
# kit in node_modules here, it is not the root.
p="$(project subdir)"
mkdir -p "$p/server"
before="$(cd "$p" && find . | sort)"
err="$( (cd "$p/server" && node "$cli" init node) 2>&1 >/dev/null )" && fail "init accepted a run from a subdirectory"
grep -q 'repository root' <<< "$err" || fail "refusing a subdirectory, init did not point to the root: got '$err'"
[ "$(cd "$p" && find . | sort)" = "$before" ] || fail "init wrote files while refusing a subdirectory"

# ── reachable from a consumer ─────────────────────────────────────────────────

( cd tests/fixture && npm install --silent --no-audit --no-fund )
[ -x tests/fixture/node_modules/.bin/charter ] || fail "a consumer gets no charter executable"
err="$(tests/fixture/node_modules/.bin/charter 2>&1 >/dev/null)" && fail "charter with no arguments succeeded"
grep -q 'Usage: charter init' <<< "$err" || fail "a consumer's charter does not print its usage"

echo "  ✓ init records modules, imports core, wires the sync hook and the ignore line, merges"
echo "    without overwriting, syncs each workspace, refuses cleanly, and reaches a consumer"
```

Replace `checks/40-rules.sh` with:

```bash
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

# Module names are unique: charter.json names a module, not its directory.
dupes="$(cd "$kit" && ls -d domains/*/ stacks/*/ | awk -F/ '{ print $2 }' | sort | uniq -d)"
[ -z "$dupes" ] || { echo "  ✗ module names used twice: $dupes"; exit 1; }

# Budgets — spec 2026-10-13-foundation-design §5. The always tier is what every session reads;
# a workspace's worst case is core plus every path rule of its modules, as if every glob matched.
always="$(total "$kit"/core/rules/*.md)"
[ "$always" -le 150 ] || { echo "  ✗ core's rules are $always lines; the always tier's limit is 150"; exit 1; }
worst() {
  local m f
  local files=("$kit"/core/rules/*.md)
  for m in "$@"; do
    for f in "$kit"/domains/"$m"/rules/*.md "$kit"/stacks/"$m"/rules/*.md; do
      [ -e "$f" ] && files+=("$f")
    done
  done
  total "${files[@]}"
}
backend_worst="$(worst backend typescript node vitest)"
react_worst="$(worst typescript react vitest)"
[ "$backend_worst" -le 225 ] ||
  { echo "  ✗ core + backend, typescript, node, vitest is $backend_worst lines if every glob matched; the limit is 225"; exit 1; }
[ "$react_worst" -le 225 ] ||
  { echo "  ✗ core + typescript, react, vitest is $react_worst lines if every glob matched; the limit is 225"; exit 1; }

# The live session asks for two facts no session could guess, each in exactly one rule: one in
# core, one in a path rule. These guards keep that true, and run even when the session is skipped.
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
if [ -z "${CHARTER_SKIP_SESSION_CHECK:-}" ] && command -v claude >/dev/null 2>&1; then
  consumer="$(mktemp -d)"
  trap 'rm -rf "$consumer"' EXIT
  mkdir -p "$consumer/node_modules/charter" "$consumer/src/modules/issues" "$consumer/scripts"
  tarball="$(cd ../.. && npm pack --silent --pack-destination "$consumer")"
  tar -xzf "$consumer/$tarball" -C "$consumer/node_modules/charter" --strip-components 1
  echo 'export const routes = []' > "$consumer/src/modules/issues/issue.routes.ts"
  echo 'export const seed = 1' > "$consumer/scripts/seed.ts"
  git -C "$consumer" init -q
  ( cd "$consumer" && node node_modules/charter/bin/charter.mjs init backend typescript node vitest ) >/dev/null ||
    { echo "  ✗ charter init failed in the scratch consumer"; exit 1; }

  ask() {
    rm -rf "$consumer/.claude/rules/charter"
    ( cd "$consumer" && claude -p "First use Read on $1 and nothing else. Then answer from your loaded instructions only, never by searching files. Line 1: the date the backlog rule's example entry was found, or NONE. Line 2: the error code for a write whose Origin is not the app's own, or NONE. Nothing else." \
      --disallowedTools Bash Grep Glob Edit Write Agent WebFetch WebSearch 2>&1 || true ) | tr -d '`'
  }
  for run in 1 2 3; do
    answer="$(ask scripts/seed.ts)"
    grep -qF "$core_fact" <<< "$answer" && grep -qx 'NONE' <<< "$answer" && ! grep -qF "$path_fact" <<< "$answer" ||
      { echo "  ✗ run $run: outside http.md's globs, wanted $core_fact and NONE. Got: $answer"; exit 1; }
    answer="$(ask src/modules/issues/issue.routes.ts)"
    grep -qF "$core_fact" <<< "$answer" && grep -qx "$path_fact" <<< "$answer" ||
      { echo "  ✗ run $run: in a routes file, wanted $core_fact and $path_fact. Got: $answer"; exit 1; }
  done
  echo "  ✓ three times over, a real session read core at once and http.md only in a matching file"
else
  echo "  · session check skipped (no claude CLI, or CHARTER_SKIP_SESSION_CHECK set)"
fi

echo "  ✓ $checked rules: core loads always ($always lines), the rest by path; a backend"
echo "    workspace reads at most $backend_worst, a react one $react_worst"
```

Run: `CHARTER_SKIP_SESSION_CHECK=1 ./check 40; ./check 70`
Expected: `40` FAILS with `✗ a module has an index, so its rules would always load:`; `70` FAILS with `✗ charter.json is not the four modules:` (no such file).

- [ ] **Step 2: Give each module rule its `paths:` block**

Prepend exactly these blocks (each file then continues with its existing `# …` heading):

`domains/backend/rules/http.md`:

```markdown
---
paths:
  - "src/*"
  - "src/modules/**"
  - "src/shared/**"
---
```

`domains/backend/rules/layout.md`:

```markdown
---
paths:
  - "src/**"
---
```

`domains/backend/rules/database-tests.md`:

```markdown
---
paths:
  - "tests/integration/**"
---
```

`stacks/typescript/rules/typescript.md`:

```markdown
---
paths:
  - "**/*.{ts,tsx,mts,cts}"
  - "**/tsconfig*.json"
---
```

`stacks/node/rules/typescript.md`:

```markdown
---
paths:
  - "**/*.{ts,mts,cts}"
  - "**/tsconfig*.json"
---
```

`stacks/react/rules/typescript.md`:

```markdown
---
paths:
  - "**/*.{ts,tsx}"
---
```

- [ ] **Step 3: Remove the module indexes and the fixture's imports of them**

```bash
git rm -q domains/backend/rules.md stacks/typescript/rules.md stacks/node/rules.md stacks/react/rules.md
```

`tests/fixture/CLAUDE.md`:

```markdown
# charter fixture

Imports core, the one index a project writes. Every other rule reaches a project through
`charter sync`, which ./check 40 and 75 prove.

@node_modules/charter/core/rules.md
```

- [ ] **Step 4: Replace `bin/charter.mjs`**

```js
#!/usr/bin/env node
// Onboards a project and keeps its path-scoped rules current:
//
//   charter init [<module…>] [--workspace <dir>]   records the modules in charter.json, imports
//                                                  core, wires the sync hook, then syncs
//   charter sync                                   mirrors the modules' rules into the project
//
// init adds what is missing and changes nothing that is set. Spec:
// docs/superpowers/specs/2026-10-13-foundation-design.md.

import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'
import { KitError, findModules } from './modules.mjs'
import { manifestFile, normalizeWorkspace, readManifest, sync } from './sync.mjs'

const kit = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const usage = 'Usage: charter init [<module…>] [--workspace <dir>]  |  charter sync'
const settingsFile = join('.claude', 'settings.json')
const coreImport = '@node_modules/charter/core/rules.md'
const ignored = '.claude/rules/charter/'
const hookCommand = 'node "$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs" sync'
// Their TypeScript rules contradict each other on relative imports, so no workspace takes both.
const exclusive = ['node', 'react']

function fail(message, hint) {
  console.error(`✗ ${message}`)
  if (hint) console.error(`  ${hint}`)
  process.exit(1)
}

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)

function guard(action) {
  try {
    return action()
  } catch (error) {
    if (error instanceof KitError) fail(error.message, error.hint)
    throw error
  }
}

function parse(argv) {
  let parsed
  try {
    parsed = parseArgs({ args: argv, allowPositionals: true, options: { workspace: { type: 'string' } } })
  } catch (error) {
    fail(error.message, usage)
  }
  const [command, ...names] = parsed.positionals
  if (command === 'sync') {
    if (names.length > 0 || parsed.values.workspace !== undefined) fail('sync takes no arguments.', usage)
    return { command }
  }
  if (command !== 'init') fail(command ? `Unknown command: ${command}.` : 'No command given.', usage)
  return { command, names: [...new Set(names)], workspace: parsed.values.workspace ?? '.' }
}

// Returns the workspace's key in charter.json. Refuses before anything is written.
function check(names, workspace, modules) {
  // Run anywhere else, the settings would land where no session reads them. The root is where
  // the kit is installed.
  if (!existsSync(join('node_modules', 'charter'))) {
    fail(
      'This is not the repository root: there is no node_modules/charter here.',
      'Run charter init at the repository root, where the kit is installed.',
    )
  }
  const unknown = names.filter((name) => !modules.has(name))
  if (unknown.length > 0) {
    fail(`Unknown module: ${unknown.join(', ')}.`, `The modules are ${[...modules.keys()].join(', ')}.`)
  }
  const dir = resolve(workspace)
  const fromRoot = relative(process.cwd(), dir)
  if (fromRoot === '..' || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot)) {
    fail(`${workspace} is outside this repository.`, 'Run charter init at the repository root.')
  }
  if (!existsSync(dir) || !statSync(dir).isDirectory()) {
    fail(`${workspace} is not a directory.`, 'Create the workspace first, then run this again.')
  }
  const key = normalizeWorkspace(fromRoot.split(sep).join('/'))
  if (key === '@root') fail('A workspace cannot be named @root.', 'charter uses that name for the root.')
  return key
}

function readSettings() {
  if (!existsSync(settingsFile)) return {}
  let settings
  try {
    settings = JSON.parse(readFileSync(settingsFile, 'utf8'))
  } catch {
    fail(`${settingsFile} is not valid JSON.`, 'Fix it, then run this again.')
  }
  if (!isObject(settings)) fail(`${settingsFile} does not hold a JSON object.`, 'Fix it, then run this again.')
  if (settings.enabledPlugins !== undefined && !isObject(settings.enabledPlugins)) {
    fail(`enabledPlugins in ${settingsFile} is not an object.`, 'Fix it, then run this again.')
  }
  if (settings.hooks !== undefined && !isObject(settings.hooks)) {
    fail(`hooks in ${settingsFile} is not an object.`, 'Fix it, then run this again.')
  }
  if (settings.hooks?.SessionStart !== undefined && !Array.isArray(settings.hooks.SessionStart)) {
    fail(`hooks.SessionStart in ${settingsFile} is not a list.`, 'Fix it, then run this again.')
  }
  return settings
}

function pluginsOf(name, modules) {
  const file = join(kit, modules.get(name), 'plugins.json')
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : []
}

// Appends `line` after one blank line, unless a line already reads one of `same`.
function appendLine(file, line, same = [line]) {
  const text = existsSync(file) ? readFileSync(file, 'utf8') : ''
  if (text.split(/\r?\n/).some((existing) => same.includes(existing.trim()))) return false
  const head = text.trim() === '' ? '' : `${text}${text.endsWith('\n') ? '' : '\n'}\n`
  writeFileSync(file, `${head}${line}\n`)
  return true
}

function init({ names, workspace }) {
  const modules = guard(() => findModules(kit))
  const key = check(names, workspace, modules)
  const settings = readSettings()
  const manifest = existsSync(manifestFile) ? guard(() => readManifest(process.cwd())) : { workspaces: {} }
  const recorded = Object.keys(manifest.workspaces).find((k) => normalizeWorkspace(k) === key) ?? key
  const current = manifest.workspaces[recorded] ?? []
  const merged = [...current, ...names.filter((name) => !current.includes(name))]
  const clash = exclusive.filter((name) => merged.includes(name))
  if (clash.length > 1) {
    fail(
      `${clash.join(' and ')} cannot share a workspace.`,
      'Their TypeScript rules contradict each other. Give each its own: charter init <module…> --workspace <dir>.',
    )
  }

  // Nothing has been written up to here.
  if (!(recorded in manifest.workspaces) || merged.length > current.length) {
    manifest.workspaces[recorded] = merged
    writeFileSync(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`)
    console.log(`✓ ${manifestFile}: ${recorded} — ${merged.length > 0 ? merged.join(', ') : 'core only'}`)
  } else {
    console.log(`  ${manifestFile} already has ${recorded} with these modules`)
  }

  const enabled = settings.enabledPlugins ?? {}
  const plugins = [...new Set(merged.flatMap((name) => pluginsOf(name, modules)))]
  const newPlugins = plugins.filter((id) => !Object.hasOwn(enabled, id))
  const sessionStart = settings.hooks?.SessionStart ?? []
  const hooked = sessionStart.some(
    (entry) => Array.isArray(entry?.hooks) && entry.hooks.some((hook) => hook?.command === hookCommand),
  )
  if (newPlugins.length > 0) {
    settings.enabledPlugins = { ...enabled, ...Object.fromEntries(newPlugins.map((id) => [id, true])) }
  }
  if (!hooked) {
    settings.hooks = {
      ...settings.hooks,
      SessionStart: [...sessionStart, { hooks: [{ type: 'command', command: hookCommand }] }],
    }
  }
  if (newPlugins.length > 0 || !hooked) {
    mkdirSync('.claude', { recursive: true })
    writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`)
  }
  for (const id of plugins) console.log(newPlugins.includes(id) ? `✓ enabled ${id}` : `  ${id} already set`)
  console.log(hooked ? '  the sync hook is already set' : `✓ ${settingsFile}: SessionStart runs charter sync`)

  console.log(appendLine('CLAUDE.md', coreImport) ? `✓ CLAUDE.md: ${coreImport}` : `  CLAUDE.md already has ${coreImport}`)
  const ignoredNow = appendLine('.gitignore', ignored, [ignored, ignored.slice(0, -1)])
  console.log(ignoredNow ? `✓ .gitignore: ${ignored}` : `  .gitignore already has ${ignored}`)

  guard(() => sync(process.cwd(), kit))
  console.log('✓ synced the path-scoped rules')

  // core carries the commit rule, and every project loads core, so every init installs the hook.
  const lib = join(kit, 'core', 'lib.sh')
  const run = spawnSync('bash', ['-c', 'source "$1" && need_plugins && need_hooks', 'charter', lib], {
    stdio: 'inherit',
  })
  process.exit(run.status ?? 1)
}

const options = parse(process.argv.slice(2))
if (options.command === 'sync') {
  // The hook runs with the project root in CLAUDE_PROJECT_DIR, whatever directory the session
  // started in; by hand, sync runs at the root.
  guard(() => sync(process.env.CLAUDE_PROJECT_DIR || process.cwd(), kit))
  process.exit(0)
}
init(options)
```

- [ ] **Step 5: The README's import lines**

`60` checks every promised path; the module indexes are gone. Delete the lines that import them:

```bash
perl -ni -e 'print unless m{^\@(\.\./)*node_modules/charter/(domains|stacks)/[a-z]+/rules\.md$}' README.md
```

Run: `grep -n 'rules\.md' README.md | grep -v Migrating`
Expected: only `core/rules.md` lines and prose mentions. Task 6 rewrites the sections around them.

- [ ] **Step 6: Delete the backlog entry this fixes**

In `docs/backlog.md`, delete the whole entry `## Rules for particular tasks and files load in every session`, from its heading to the line before `## Two \`superpowers\` skills give opposite review ranges`.

- [ ] **Step 7: Run the whole suite**

Run: `./check`
Expected: `✓ 10 checks passed`. `40` prints the three-run session line, the always tier at 137 lines, and worst cases of 216 (backend) and 149 (react): in Task 4 `http.md` lost a line and `stacks/node/rules/typescript.md` gained one.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(rules)!: load domain and stack rules only for matching paths"
```

---

### Task 6: Document charter 3.0 and archive this plan

The last task of the slice: the README is authoritative for what the kit does, and becomes so for 3.0.

**Files:**
- Modify: `README.md`, `checks/60-readme.sh`, `docs/backlog.md`
- Move: `docs/superpowers/plans/2026-10-13-foundation.md` → `docs/superpowers/plans/archive/`

- [ ] **Step 1: Let `60` skip every migration section**

In `checks/60-readme.sh`, replace

```bash
# The migration section names 1.x paths on purpose, so it is the one part not checked. It is
# the README's last section: everything from its heading down is dropped.
promised="$(sed '/^## Migrating from 1\.x/,$d' README.md)"
```

with

```bash
# The migration sections name old paths on purpose, so they are the one part not checked. They
# close the README: everything from the first of them down is dropped.
promised="$(sed '/^## Migrating from /,$d' README.md)"
```

and, in the stale-path search below it, widen the pattern to 2.x paths as well:
`(dev-kit|charter)/(tsconfig|prettier|rules|sh|ignore)([^a-z]|$)` → `(dev-kit|charter)/((tsconfig|prettier|rules|sh|ignore)([^a-z]|$)|(common|backend|ui|testing)/)`.

Run: `./check 60` — expected PASS (nothing in the README has moved yet).

- [ ] **Step 2: Rewrite the README**

Keep every section that is still true (Install's registry and git forms, GitHub Packages, Verification, Releasing). Rewrite or add the following, under these headings and in this order. Every path in a code block must exist — `./check 60` fails otherwise.

1. **`# charter`** and the intro: the rules an application is written by, in modules — `core` for every project, domains (`backend`) for principles that hold in any language, stacks (`typescript`, `node`, `react`, `vitest`) for a language's tools. Rules load by tier, so a session reads `core` always and the rest only where it works. Keep the sentence that the public `charter` package is an unrelated project.
2. **Starting a project**: the paste-in prompt, with `charter` throughout and step 2 reading `npx charter init <modules>`, the tsconfig, the Prettier key, the ignore files and a `./run` frame.
3. **Install**: `"devDependencies": { "charter": "^2.4.0" }` stays as it is — Task 7 moves it. The git form becomes `github:<owner>/charter#vX.Y.Z`.
4. **Modules** (replaces "Sections"): a table — module, kind, for, brings:

   | Module | Kind | For | Brings |
   | --- | --- | --- | --- |
   | `core` | — | every project | six rules, loaded always; the commit-msg hook; `lib.sh`; ignore files |
   | `backend` | domain | HTTP services | three rules, by path |
   | `typescript` | stack | any TypeScript workspace | one rule, by path; the base tsconfig; Prettier; a lint config |
   | `node` | stack | Node services | one rule, by path; the NodeNext tsconfig; a lint config |
   | `react` | stack | bundled browser applications | one rule, by path; the browser tsconfig; a lint config; the `frontend-design` and `playwright` plugins |
   | `vitest` | stack | a Vitest suite | a lint config |

   Then: a workspace takes a domain and its stacks; `node` and `react` never share a workspace, because their import rules contradict.
5. **Onboarding a project** (replaces the section of that name and "A repository with both a backend and a UI"): `npx charter init backend typescript node vitest` for one workspace; for two:

   ```bash
   npx charter init backend typescript node vitest --workspace server
   npx charter init typescript react vitest --workspace web
   ```

   then the resulting `charter.json`, and what `init` writes: the modules into `charter.json`; `@node_modules/charter/core/rules.md` into the root `CLAUDE.md`; the `SessionStart` hook and the modules' plugins into `.claude/settings.json`; `.claude/rules/charter/` into `.gitignore`; then `sync`, `need_plugins` and `need_hooks`. Commit `charter.json`, `CLAUDE.md`, `.claude/settings.json` and `.gitignore`; never commit `.claude/rules/charter/`. Start sessions anywhere in the repository: rules are scoped by path, not by directory.
6. **Rules** (replaces the Rules subsection): the three tiers — always (`core`, through the one import), by path (every module rule, through `sync`), by task (none yet; skills arrive in 3.1). `sync`: what it reads, what it writes (`.claude/rules/charter/<workspace>/<module>/<rule>.md`, the root as `@root`), that it prefixes each pattern with the workspace's path, deletes what the kit dropped, prints nothing, and refuses without writing. The rule table: module, rule, `paths:`, covers — the six module rules with the globs of spec §3, and `core`'s six rules as "always". Remove the "must be installed as a real directory" paragraph's claim about imports of indexes; keep that `npm link` and `file:` installs are not supported for the `core` import.
7. **TypeScript, Prettier, Lint, Commit messages**: the 3.0 specifiers and paths — `charter/stacks/node/tsconfig`, `charter/stacks/react/tsconfig`, `charter/stacks/typescript/tsconfig`, `"prettier": "charter/stacks/typescript/prettier"`, `.oxlintrc.json` extending `./node_modules/charter/stacks/<stack>/oxlint.json` (one of `typescript`, `node`, `react`, plus `vitest`). The lint exceptions table's "Section" column becomes "Stack" with `typescript`, `node`, `react`, `vitest`. The commit-msg paragraph: the wrapper calls `node_modules/charter/core/hooks/commit-msg`; before the kit is installed it lets a commit through and says nothing was checked; `need_hooks` rewrites a wrapper an older kit wrote, `dev-kit`'s included.
8. **The `./run` skeleton**: `source node_modules/charter/core/lib.sh` in both code blocks; `CHARTER_NODE_MIN` and `CHARTER_NODE_HINT`.
9. **Ignore files**: `node_modules/charter/core/ignore/…`.
10. **Adding a module**: a rule every project needs goes in `core/rules/` with its import in `core/rules.md`; any other rule goes in a module's `rules/` and opens with the fixed `paths:` block (show it); a new module is a directory under `domains/` or `stacks/` with a name no other module has. `./check 40` holds the budgets: 60 lines a file, 150 for `core`, 225 for a workspace's worst case.
11. **Migrating from 2.x** (new, directly above "Migrating from 1.x"): the four steps of spec §4, with `npm uninstall dev-kit` then `npm install -D charter@^3`; the paths table of spec §4 with `dev-kit/…` on the left and `charter/…` on the right; plus `DEVKIT_NODE_MIN` → `CHARTER_NODE_MIN` and `DEVKIT_NODE_HINT` → `CHARTER_NODE_HINT`.

Run: `./check 60`
Expected: PASS, with at least 8 promised paths.

- [ ] **Step 3: Record what this release leaves unproven**

Add as the newest entry in `docs/backlog.md`, directly after the file's introduction:

```markdown
## The sync hook has never run on Windows

- Where: the `SessionStart` hook `charter init` writes, `node "$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs" sync`
- Found: 2026-10-13, while designing 3.0
- Priority: P2 — some consuming projects are developed on Windows
- Problem: the command relies on `"$CLAUDE_PROJECT_DIR"` being expanded, which depends on the
  shell Claude Code runs hooks through on Windows. Nothing here has run it there. Start a
  session on a Windows checkout and look for `.claude/rules/charter/`.
- Impact: if the variable is not expanded, `sync` never runs on that machine and no path rule
  loads there — silently, since the hook's error is shown to the person, not the model.
```

- [ ] **Step 4: Run the whole suite and commit**

Run: `./check` — expected `✓ 10 checks passed`.

```bash
git add README.md checks/60-readme.sh docs/backlog.md
git commit -m "docs: document charter 3.0"
```

- [ ] **Step 5: Archive the plan**

```bash
git mv docs/superpowers/plans/2026-10-13-foundation.md docs/superpowers/plans/archive/
git commit -m "docs: archive the 3.0 plan"
```

---

### Task 7: Release 3.0.0

**Files:**
- Modify: `package.json` (`version`), `README.md` (the install range)

- [ ] **Step 1: Bump both copies of the version**

`package.json`: `"version": "3.0.0"`. `README.md`, under Install: `"devDependencies": { "charter": "^3.0.0" }`.

- [ ] **Step 2: Run the whole suite**

Run: `./check`
Expected: `✓ 10 checks passed`; `60` reports `the install range matches 3.0.0`.

- [ ] **Step 3: Commit**

```bash
git add package.json README.md
git commit -m "chore: release 3.0.0"
```

- [ ] **Step 4: Hand over the owner's steps**

These publish or rename things outside this repository, so they are the owner's, in this order, and are not done by the executor:

1. Rename the GitHub repository to `charter`.
2. Merge `feat/charter-3` into `main` by rebase and `git merge --ff-only`.
3. Tag `v3.0.0` on the release commit and push the tag.
4. Publish to the private registry, naming it: `npm publish --registry <private registry URL>`.
5. Create the GitHub release `v3.0.0 — charter: rules by tier, domains and stacks`, ending with an "Upgrading" section that restates the README's "Migrating from 2.x".
