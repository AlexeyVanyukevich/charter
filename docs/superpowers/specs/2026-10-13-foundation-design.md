# dev-kit 3.0 — load tiers, domains and stacks

Status: **designed**, 2026-10-13. Not built.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-13, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** 3.0 lays the kit out and delivers its rules the way it does. For
> **what** the kit provides today, read `README.md`. The release sequence this belongs to is in
> `2026-10-13-roadmap-design.md`.

---

## 1. Goal

**A rule loads only when the work in front of Claude needs it, and the kit is laid out so that
rules hold in any language and tools are a separate, per-stack concern.**

This is the roadmap's release 3.0. It delivers the three load tiers, `dev-kit sync` behind a
`SessionStart` hook, the manifest, the new `init`, and the domain and stack layout. It moves
backend's three task rules to the path tier, which takes the backlog entry "Rules for particular
tasks and files load in every session".

The roadmap gives the reasons for the tiers, for synced git-ignored copies over links or
committed copies, and for the npm package as the vehicle. They are not repeated here.

## 2. Layout

**Only `core/` loads always. Every rule file outside `core/` carries `paths:` and reaches a
project through `sync`.** `./check` enforces both halves.

```
core/                    the always tier, for every project
  rules.md               the index — the one @ import a project writes
  rules/                 commits, documentation, writing, review, backlog, testing
  hooks/commit-msg
  lib.sh
  ignore/                gitignore, prettierignore
domains/
  backend/rules/         http.md, layout.md, database-tests.md
stacks/
  typescript/            tsconfig.json, prettier.json, oxlint.json, rules/typescript.md
  node/                  tsconfig.json, oxlint.json, rules/typescript.md
  react/                 tsconfig.json, oxlint.json, plugins.json, rules/typescript.md
  vitest/                oxlint.json
bin/dev-kit.mjs          init, sync
```

| 2.x | 3.0 |
| --- | --- |
| `common/rules/` except `typescript.md`; `testing/rules/testing.md` | `core/rules/` |
| `common/hooks/`, `common/lib.sh`, `common/ignore/` | `core/` |
| `common/` tsconfig, prettier, oxlint, `rules/typescript.md` | `stacks/typescript/` |
| `backend/rules/` http, layout, database-tests | `domains/backend/rules/` |
| `backend/` tsconfig, oxlint, `rules/typescript.md` | `stacks/node/` |
| `ui/` | `stacks/react/` |
| `testing/oxlint.json` | `stacks/vitest/` |

Decisions that depart from the roadmap's sketch:

- **`node` and `vitest` are stacks.** The NodeNext tsconfig and the lint exceptions for Fastify
  and Kysely belong to Node, not to the backend domain; `testing`'s lint config is Vitest's.
- **No `domains/frontend/`.** No UI rule today holds in every language — `ui`'s one rule is
  bundler resolution, which is the stack's. The directory arrives with its first rule.
- **No `upgrade` command.** Every 3.0 config is reached by `extends` or a path; nothing is
  copied. The command arrives with the first config a tool cannot inherit.
- **`testing.md` stays in `core`** until the development phase takes it in 3.2.
- **No `version` in the manifest.** For JavaScript, `package.json` and the lockfile pin it; a
  second copy arrives in 4.0 with delivery outside npm.

One content change: `http.md` says "every request body is a TypeBox schema". It becomes "a
schema that rejects unknown fields", so the domain names no library; the TypeBox requirement
already lives in `stacks/node/rules/typescript.md`.

## 3. The path tier

### Globs

Each pattern is relative to the workspace root. `sync` adds the prefix (below).

| Rule | `paths:` |
| --- | --- |
| `domains/backend/rules/http.md` | `src/*`, `src/modules/**`, `src/shared/**` |
| `domains/backend/rules/layout.md` | `src/**` |
| `domains/backend/rules/database-tests.md` | `tests/integration/**` |
| `stacks/typescript/rules/typescript.md` | `**/*.{ts,tsx,mts,cts}`, `**/tsconfig*.json` |
| `stacks/node/rules/typescript.md` | `**/*.{ts,mts,cts}`, `**/tsconfig*.json` |
| `stacks/react/rules/typescript.md` | `**/*.{ts,tsx}` |

`http.md` covers routes, schemas, shared helpers and the entry points at `src/`, where the error
handler is registered. The TypeScript rules cover tsconfig files because they say how to extend
one.

**`layout.md` is scoped wide on purpose.** It is needed before Claude creates a module, and a
path rule loads only once a matching file is read. A narrow glob risks a module created before
its rule arrived; `src/**` loads it as soon as Claude reads any source file, which it does
before adding one. The cost: it saves tokens only in sessions that never touch `src/`. The real
saving in backend is `http.md` and `database-tests.md`, 37 of the 60 lines.

### The workspace prefix

`sync` writes each pattern with the workspace's path in front: for workspace `server`,
`src/modules/**` becomes `server/src/modules/**`. The root workspace, `.`, gets none.

### `dev-kit sync`

- **Reads** the manifest at the project root and the installed kit at `node_modules/dev-kit`.
- **Writes** a mirror at `.claude/rules/dev-kit/<workspace>/<module>/<rule>.md`. The root
  workspace's directory is `@root`; a nested workspace keeps its path (`server/api/…`). Two
  workspaces' rules never collide, because a deeper workspace's rules sit one level deeper.
- **Computes everything before writing anything.** An invalid manifest, an unknown module or a
  missing workspace directory leaves every file as it was, prints the cause to stderr and exits
  1. Otherwise it writes only files whose content changed, deletes files the kit no longer
  ships, and removes emptied directories. It touches nothing outside `.claude/rules/dev-kit/`.
- **Prints nothing to stdout on success.** Claude Code adds a `SessionStart` hook's stdout to
  the context, so anything printed there costs tokens in every session. A non-zero exit is shown
  to the person, not the model.
- **Reads `paths:` without a YAML parser.** The kit fixes the block's form — the first line
  `---`, then `paths:`, then one `  - "<pattern>"` line per pattern, then `---` — and `./check`
  holds every rule outside `core` to it. The rest of the file is copied unchanged.
- **Has no dependencies** and reads a handful of files: tens of milliseconds per session start.

## 4. The consuming project

### The manifest, `dev-kit.json`, at the root

```json
{ "workspaces": { ".": ["backend", "typescript", "node", "vitest"] } }
```

A repository with a Node server and a React client:

```json
{
  "workspaces": {
    "server": ["backend", "typescript", "node", "vitest"],
    "web": ["typescript", "react", "vitest"]
  }
}
```

`core` is implied. Module names are unique across `domains/` and `stacks/`.

### `npx dev-kit init [<module…>] [--workspace <dir>]`

It still adds what is missing and changes nothing that is set:

- **The manifest:** adds the modules to the workspace's entry, creating the file if needed.
  Nothing is removed.
- **The root `CLAUDE.md`:** adds `@node_modules/dev-kit/core/rules.md`. Workspace `CLAUDE.md`
  imports are no longer needed: rules are scoped by path, so one session at the root works on
  every workspace without loading the others' rules.
- **`.claude/settings.json`:** adds the `SessionStart` hook unless a hook with the same command
  is there, and turns on the plugins in each named module's `plugins.json`. The hook has no
  matcher, so it runs on `startup`, `resume`, `clear` and `compact`:

  ```
  node "$CLAUDE_PROJECT_DIR/node_modules/dev-kit/bin/dev-kit.mjs" sync
  ```

- **`.gitignore`:** adds `.claude/rules/dev-kit/`.
- **Then** runs `sync`, `need_plugins` and `need_hooks` — the last always now, because the
  commit rule is in `core`.

Changes from 2.x: `init` with no modules is valid and brings `core` alone; the refusal of
backend and ui in one directory goes, because nothing loads by directory any more; a workspace
named `@root` is refused. The other refusals stay — not the repository root, unknown module,
workspace outside the repository or missing.

### The commit-msg wrapper

The wrapper `need_hooks` writes calls `node_modules/dev-kit/common/hooks/commit-msg` and lets the
commit through when that file is missing, so that a commit before `npm install` is not blocked.
After an upgrade to 3.0 that file never exists: **every project's hook would stop enforcing the
commit rule, silently.** `need_hooks` would not repair it, because it returns as soon as it
recognises its own wrapper.

So, in 3.0:

- `need_hooks` rewrites its own wrapper when the content differs. A project's own hook is still
  never touched.
- The wrapper still lets the commit through when the script is missing, but says on stderr that
  nothing was checked and how to fix it.

### Paths

Specifiers follow the filesystem, so a reader learns one layout:

| 2.x | 3.0 |
| --- | --- |
| `dev-kit/common/tsconfig` | `dev-kit/stacks/typescript/tsconfig` |
| `dev-kit/backend/tsconfig` | `dev-kit/stacks/node/tsconfig` |
| `dev-kit/ui/tsconfig` | `dev-kit/stacks/react/tsconfig` |
| `dev-kit/common/prettier` | `dev-kit/stacks/typescript/prettier` |
| `node_modules/dev-kit/{common,backend,ui,testing}/oxlint.json` | `node_modules/dev-kit/stacks/{typescript,node,react,vitest}/oxlint.json` |
| `node_modules/dev-kit/common/lib.sh` | `node_modules/dev-kit/core/lib.sh` |
| `node_modules/dev-kit/common/ignore/…` | `node_modules/dev-kit/core/ignore/…` |
| `@…/dev-kit/{common,backend,ui,testing}/rules.md` | `@node_modules/dev-kit/core/rules.md` at the root; the rest through `init` |

### Migrating from 2.x

A README section, done by hand:

1. `npm install -D dev-kit@^3`.
2. Change each path by the table, including the `source` line in `./run`. A `./run` still
   pointing at `common/lib.sh` fails loudly, not silently.
3. Delete the 2.x section imports from every `CLAUDE.md`.
4. Run `npx dev-kit init <modules> [--workspace <dir>]` for each workspace. It writes the
   manifest, the hook and the `.gitignore` line, and rewrites the commit-msg wrapper.

`init` could delete the dead imports of step 3 itself. It does not, because that breaks its rule
of changing nothing that is set, and three projects are on 2.x.

## 5. Budgets

Lines are counted in a rule's body. Claude Code strips frontmatter before loading a rule, so
`paths:` blocks do not count.

| Budget | Limit | In 3.0 |
| --- | --- | --- |
| one rule file | 60 | unchanged |
| the always tier, `core/rules/` | **150** | 137 |
| one workspace's worst case: `core` plus every path rule of its modules, as if every glob matched | 225 | backend + typescript + node + vitest: 216; typescript + react + vitest: 149 |

225 stays, but as the ceiling of the worst case, not what loads in every session. What a session
loads now depends on the files it touches.

## 6. Verification

Each check still runs the tool a consumer would run, against `tests/fixture`.

- **10-package:** ships `bin`, `core`, `domains` and `stacks`. The stale-path search also
  catches 2.x paths in shipped files.
- **20-tsconfig, 30-prettier, 90-lint:** the fixture moves to the new specifiers and paths; the
  assertions are unchanged.
- **40-rules:**
  - the `core` index imports exactly `core/rules/`;
  - every rule outside `core` opens with the fixed `paths:` block;
  - module names are unique;
  - the budgets of §5 hold.

  The live session runs in a scratch consumer holding the unpacked `npm pack` tarball, set up by
  a real `npx dev-kit init`, so the hook, the manifest and `sync` are tested together:
  1. a fact from `core` is known at once;
  2. `forbidden_origin`, from `http.md`, is unknown after reading a file outside its globs;
  3. it is known after reading a file under `src/modules/`.

  Cases 2 and 3 run three times each.
- **75-sync**, new:
  - the workspace prefix is written;
  - a rule the kit stopped shipping is deleted;
  - stdout is empty on success;
  - nothing is written when the manifest is invalid;
  - a second run changes nothing.

  It prints its run time and does not assert one: a timing threshold would fail on a slow
  machine and prove nothing.
- **70-init:**
  - the manifest, the `core` import, the hook, the `.gitignore` line, plugins from modules;
  - `init` with no modules;
  - the `@root` refusal;
  - a second run changes nothing;
  - a nested workspace.
- **50-lib, 80-commit-msg:**
  - the new paths;
  - `need_hooks` rewrites its own outdated wrapper and leaves a project's own hook alone;
  - the wrapper warns when the script is missing.

## 7. Evidence

Probed on 2026-10-13 with Claude Code 2.1.287, in addition to the roadmap's §5. The scratch
project imitated a pnpm install — the package under `node_modules/.pnpm/`, `node_modules/dev-kit`
a link to it — because pnpm was not installed on the machine. The copies were deleted before
each session, so only the hook wrote them.

| Run | Always-on fact, imported through the link | Scoped rule, after reading `src/other.ts` | Scoped rule, after reading a routes file |
| --- | --- | --- | --- |
| 1 | loaded | not loaded | loaded |
| 2 | loaded | not loaded | loaded |
| 3 | loaded | not loaded | loaded |

## 8. Release

**3.0.0.** Every path a consuming project writes changes.

- **README:** the modules, onboarding and `./run` sections are rewritten. "Migrating from 2.x"
  joins "Migrating from 1.x". 60-readme skips everything from the first migration heading down.
- **Backlog:** "Rules for particular tasks and files load in every session" is deleted by the
  commit that moves backend's rules. A new entry records that the hook is untested on Windows —
  the one gap this release knowingly leaves.
- **The plan's last task** updates the README and archives the plan.
- **The GitHub release** is titled `v3.0.0 — …` and ends with an "Upgrading" section that
  restates the migration steps.

## 9. Unproven

- The hook on Windows. Its command runs `node`, not a shell script, but it still relies on
  `"$CLAUDE_PROJECT_DIR"` being expanded, which depends on the shell Claude Code runs hooks
  through there. It has not run on Windows.
- A real pnpm install, as opposed to its imitated layout.
- That the tiers save tokens in practice. Line counts are a proxy; measuring context use is a
  later addition to `./check`.
