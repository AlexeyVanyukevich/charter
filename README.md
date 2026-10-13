# charter

The rules an application is written by, and the tooling configuration that goes with them,
for the projects on this machine. They come in modules: `core` for every project; domains
(`backend`) for principles that hold in any language; stacks (`typescript`, `node`, `react`,
`vitest`) for a language's tools. Rules load by tier, so a session reads `core` always and the
rest only where it works.

This is never published to the public npm registry. A package called `charter` on the public
registry is an unrelated project and is not this one.

## Starting a project

In a new project's directory, paste this into the first Claude Code session, with the first line
describing the project and `<kit source>` naming where the kit comes from — the private registry
and its URL, or the git repository and its newest tag:

```text
Set this project up with charter. It is <a Node service | a web application | both, in
workspaces><, with tests>.

1. Create package.json if there is none. Install charter as a devDependency from
   <kit source>. If you cannot reach it, stop and ask me; do not install a package named
   charter from the public registry.
2. Read node_modules/charter/README.md and follow it for this project's modules:
   `npx --no charter init <modules>`, the tsconfig, the Prettier key, the ignore files, and a
   ./run frame that calls need_node, need_deps, need_plugins and need_hooks.
3. Run ./run, then show me every file you created or changed.
```

The prompt only installs the kit and hands over to the README that comes with it, so the steps
it follows are always the installed release's.

## Install

From the private registry — the normal way:

```json
"devDependencies": { "charter": "^3.0.0" }
```

with the registry in the consuming project's `.npmrc`:

```
registry=<private registry URL>
```

The package is unscoped, so it cannot be routed by scope the way `@scope:registry=` would
route one. That line redirects the whole project, which is what a registry proxying the public
one upstream is built for.

Over git — the fallback, for a machine that cannot reach the registry:

```json
"devDependencies": { "charter": "github:<owner>/charter#vX.Y.Z" }
```

`<owner>` is the account that holds the repository, and `vX.Y.Z` the newest release tag. No
`.npmrc` is needed for this form, and it installs the same tree at a pinned tag.

**Once the repository is private, git has to sign in to GitHub, and npm does not do it.** npm
fetches this form with git, over HTTPS and then over SSH, so a machine whose SSH key is on an
account with access installs it as it is. Anywhere else, a developer hands git the GitHub CLI's
login, once per machine:

```bash
gh auth login
gh auth setup-git
```

`setup-git` points git at the GitHub CLI for `github.com`; it stores no token of its own.

In GitHub Actions the workflow's own token reads only its own repository. A consumer's workflow
needs a token that can read this one — a fine-grained personal access token with read access
to its contents, kept as a secret — and gives it to git, not npm:

```yaml
- uses: actions/checkout@v5
  with:
    persist-credentials: false
- run: gh auth setup-git
  env:
    GH_TOKEN: ${{ secrets.CHARTER_TOKEN }}
- run: npm ci
  env:
    GH_TOKEN: ${{ secrets.CHARTER_TOKEN }}
```

`GH_TOKEN` is the GitHub CLI's own variable and wins over `GITHUB_TOKEN`, so git gets the
secret while npm keeps the workflow's token for GitHub Packages. **Without
`persist-credentials: false` the install fails:** checkout leaves the workflow's token in the
repository's git config, git sends it ahead of any credential helper, and GitHub answers
"Repository not found".

## Modules

| Module | Kind | For | Brings |
| ------ | ---- | --- | ------ |
| `core` | — | every project | six rules, loaded always; the commit-msg hook; `lib.sh`; ignore files |
| `backend` | domain | HTTP services | three rules, by path |
| `typescript` | stack | any TypeScript workspace | one rule, by path; the base tsconfig; Prettier; a lint config |
| `node` | stack | Node services | one rule, by path; the NodeNext tsconfig; a lint config |
| `react` | stack | bundled browser applications | one rule, by path; the browser tsconfig; a lint config; the `frontend-design` and `playwright` plugins |
| `vitest` | stack | a Vitest suite | a lint config |

`core` needs no naming: every project has it. A workspace takes a domain and its stacks — a
Node service writes `backend`, `typescript`, `node` and `vitest`. **`node` and `react` never
share a workspace,** because their import rules contradict: NodeNext wants a `.js` extension
on a relative import, a bundler wants none. `init` refuses the pair.

## Onboarding a project

Once the kit is installed, one command per workspace records its modules and wires the project:

```bash
npx --no charter init backend typescript node vitest
```

A repository with a server and a web workspace runs it once per directory, at the repository
root:

```bash
npx --no charter init backend typescript node vitest --workspace server
npx --no charter init typescript react vitest --workspace web
```

`init` with no modules is valid and brings `core` alone. It writes the modules into
`charter.json` at the root, which `sync` reads:

```json
{
  "workspaces": {
    "server": ["backend", "typescript", "node", "vitest"],
    "web": ["typescript", "react", "vitest"]
  }
}
```

and then adds what is missing, changing nothing that is set:

- `@node_modules/charter/core/rules.md` in the root `CLAUDE.md`. A workspace needs no
  `CLAUDE.md` import of its own: rules are scoped by path, for a session started at the root.
- in `.claude/settings.json`, a `SessionStart` hook that runs `charter sync`, and the plugins
  of the named modules, which are listed in a module's `plugins.json`. Only `react` has one:
  `frontend-design` and `playwright`. A plugin set to `false` stays off.
- `.claude/rules/charter/` in `.gitignore`.

It then runs `sync`, `need_plugins` and `need_hooks`. Running it again adds only what is
missing. It refuses to run away from the repository root (where `node_modules/charter` is), on
an unknown module, on a workspace that is missing or outside the repository, on a workspace
named `@root`, and on `node` and `react` in one workspace.

Commit `charter.json`, `CLAUDE.md`, `.claude/settings.json` and `.gitignore`. **Never commit
`.claude/rules/charter/`:** it is a mirror that `sync` rebuilds at every session start. Start
sessions at the repository root, not in a workspace: a session started in a workspace runs no
sync hook and may not read `core`. Rules are scoped by path, so one root session can work on
every workspace without loading the others' rules.

**A committed plugin is turned on, not downloaded.** Each clone installs it once:
`need_plugins`, in the `./run` frame below, does that.

## Rules

Rules load in three tiers:

- **Always** — `core`, through the one import in the root `CLAUDE.md`.
- **By path** — every other module's rules. A rule loads once Claude reads a file that matches
  its `paths:`. `charter sync` delivers them.
- **By task** — none yet. Skills arrive in 3.1.

`charter sync` takes no arguments and prints nothing on success. Its root is `CLAUDE_PROJECT_DIR`,
which the hook sets, and otherwise the working directory. It reads `charter.json` and writes a
mirror at `.claude/rules/charter/<workspace>/<module>/<rule>.md`, with the root workspace as
`@root`. It prefixes each pattern with the workspace's path — for the workspace `server`,
`src/modules/**` becomes `server/src/modules/**` — and copies the rest of the rule unchanged.
It deletes mirrored files the kit no longer ships. An invalid manifest, an unknown module or a
missing workspace directory is refused before anything is written, with the cause on stderr.

| Module | Rule | `paths:` | Covers |
| ------ | ---- | -------- | ------ |
| `core` | `commits.md` | always | Conventional Commits, the subject line as the whole message, rebase-only merges, release commits |
| `core` | `documentation.md` | always | `architecture.md` is authoritative; specs and plans are dated records |
| `core` | `writing.md` | always | Refer to projects by role; name something only when the name is load-bearing |
| `core` | `review.md` | always | A session ends by showing everything it changed, and what it decided alone |
| `core` | `backlog.md` | always | Findings left unfixed go in `docs/backlog.md`, one entry each, deleted by the fix |
| `core` | `testing.md` | always | Tests first, datasets over test bodies, derived facts, where tests live |
| `backend` | `http.md` | `src/*`, `src/modules/**`, `src/shared/**` | The one error shape, its codes, `additionalProperties: false`, 4xx translation |
| `backend` | `layout.md` | `src/**` | `modules/<entities>/` and its four singular files; `shared/`, `db/` |
| `backend` | `database-tests.md` | `tests/integration/**` | Integration tests against a real PostgreSQL, started by Testcontainers |
| `typescript` | `typescript.md` | `**/*.{ts,tsx,mts,cts}`, `**/tsconfig*.json` | Compiler strictness, no `any` in hand-written code |
| `node` | `typescript.md` | `**/*.{ts,mts,cts}`, `**/tsconfig*.json` | NodeNext's `.js` imports, the `typebox` package, the one accepted `any` |
| `react` | `typescript.md` | `**/*.{ts,tsx}` | Bundler resolution: no extension on relative imports |

**`core` must be installed as a real directory** — from the registry or over git, as above.
`npm link` and a `file:` dependency install a symlink, and Claude Code does not follow an
import through a symlink that leads out of the project: the session reads the `core` heading
and none of its rules.

The import is a **filesystem path, not a module specifier**. It never touches npm's resolver,
which is why it appears in no `exports` map and why adding a rule needs no `package.json`
change.

## Configuration

### TypeScript

```json
{ "extends": "charter/stacks/node/tsconfig" }
```

`charter/stacks/typescript/tsconfig` carries the strictness: `strict`, `noUncheckedIndexedAccess`,
`exactOptionalPropertyTypes`, `target: ES2023`. `charter/stacks/node/tsconfig` adds NodeNext
resolution and Node types; `charter/stacks/react/tsconfig` adds the DOM lib, bundler resolution and
`jsx: react-jsx`. A workspace that takes neither stack extends `charter/stacks/typescript/tsconfig`
directly.

None of the three sets `outDir`, `rootDir` or `include`. Those describe one project's directory
layout, and a shared base that guesses them is a base every project has to override.

### Prettier

In the consuming project's `package.json`:

```json
{ "prettier": "charter/stacks/typescript/prettier" }
```

`semi: false`, `singleQuote: true`, `printWidth: 100`.

### Commit messages

`need_hooks`, in the `./run` frame below, installs a `commit-msg` hook into the repository's
hooks directory, wherever `core.hooksPath` points. `init` installs it too, because the commit
rule is in `core`. The hook refuses a message that breaks `commits.md` and says which part:

```text
✗ This commit message breaks the commit rule: the subject starts with a capital letter.
```

It enforces the shape (`type(scope)!: subject`, one of the rule's types, a lowercase scope),
the single line with no body or trailer, a subject that does not start with a capital or end
with a period, and the 72-character limit. A message beginning `fixup! `, `squash! ` or
`amend! ` passes, because `git rebase --autosquash` folds it away before it reaches `main`.

The hooks directory holds a short wrapper that calls
`node_modules/charter/core/hooks/commit-msg`, so an upgrade of the kit upgrades the hook.
Until the kit is installed, the wrapper lets the commit through and says on stderr that
nothing was checked. `need_hooks` rewrites a wrapper an older kit wrote, `dev-kit`'s included,
when its content differs. **A project's own `commit-msg` hook is never replaced:** `need_hooks`
says so, and the project calls the kit's script from its own.

### Lint

Each stack brings an [oxlint](https://oxc.rs) config. A consuming project installs the
linter, plus `oxlint-tsgolint` at the major version of its TypeScript, which runs the rules
that need type information:

```bash
npm install -D oxlint oxlint-tsgolint@7
```

and writes `.oxlintrc.json` extending one of the stacks `typescript`, `node` or `react`, plus
`vitest` if it has a Vitest suite:

```json
{
  "extends": [
    "./node_modules/charter/stacks/node/oxlint.json",
    "./node_modules/charter/stacks/vitest/oxlint.json"
  ]
}
```

`node` and `react` already extend `typescript`, as their tsconfigs do. A workspace one level down
writes `../node_modules/…`: like the rule imports, these are filesystem paths, relative to the
config file. Run `npx oxlint --deny-warnings` wherever the project runs its other checks; the
kit does not wire it into `./run`.

The configs turn on oxlint's `correctness` and `suspicious` categories, which cover code that
is wrong or probably wrong. They also turn on `no-explicit-any` and two type-aware rules,
`no-misused-promises` and `switch-exhaustiveness-check`. `correctness` already has
`no-floating-promises` and `await-thenable`. Style is Prettier's job, and no style category is
on.

These rules are turned off, or given an option, because they flagged code that was not a bug:

| Rule | Stack | Why |
| ---- | ----- | --- |
| `typescript/no-unsafe-type-assertion` | typescript | Flags every `as` cast |
| `unicorn/no-array-sort`, `no-array-reverse` | typescript | A preference for `toSorted()` |
| `unicorn/consistent-function-scoping` | typescript | Style |
| `import/no-unassigned-import` | typescript | Flags side-effect imports such as a stylesheet |
| `import/no-named-as-default-member` | typescript | Flags the normal use of a CommonJS default export |
| `promise/always-return`, `eslint/no-shadow`, `no-underscore-dangle` | typescript | Style |
| `oxc/no-async-endpoint-handlers` | node | Written for Express; Fastify awaits an async handler |
| `no-explicit-any` under `**/migrations/**` | node | `Kysely<any>`, the node rule's one accepted `any` |
| `react/react-in-jsx-scope` | react | Wrong under `jsx: react-jsx` |
| `no-misused-promises`, `checksVoidReturn.attributes: false` | react | An async handler in a JSX attribute is the React idiom |
| `vitest/valid-expect`, `maxArgs: 2` | vitest | Vitest's `expect` takes a message |
| `vitest/no-conditional-expect` | vitest | A dataset runner checks rows differently by design |
| `vitest/require-mock-type-parameters` | vitest | Style |

**Expect a few dozen findings on adoption.** Three consuming projects, linted on 2026-10-13,
had 36, 49 and 78. Most were unnecessary type assertions, which `npx oxlint --fix` removes,
and explicit `any`. The rest, as far as a sample showed, were real bugs: unhandled promises,
a non-exhaustive switch.
A rule a project wants differently goes in its own `.oxlintrc.json` under `rules`, which wins
over the kit's.

### The `./run` skeleton

```bash
source node_modules/charter/core/lib.sh
```

Defines `step`, `ok`, `note`, `die`, `load_env_file`, `need_docker`, `need_node`, `need_deps`,
`need_plugins`, `need_hooks`, `need_env` and `with_github_token`, plus the colour variables.
Sourcing is inert: no shell options set, no directory changed, nothing run.

**`./run` is what installs dependencies, so it cannot source out of `node_modules` before the
kit is there.** Keep a short bootstrap *above* the `source` line, and test for the file rather
than the directory: a checkout installed before it took the kit has `node_modules` without it.

```bash
[ -f node_modules/charter/core/lib.sh ] ||
  GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}" npm install
source node_modules/charter/core/lib.sh
```

The token in that line matters only to a project with packages on GitHub Packages, below, and
is the one place its source is restated: `with_github_token` cannot be called before the kit is
installed. Without a token, a project that needs one fails here with npm's `401`. The line
gives git nothing: a private kit installed over git needs git signed in first, as under Install.

`need_node` reads `CHARTER_NODE_MIN`, the floor (default `24`): an older Node warns and the
script continues. `CHARTER_NODE_HINT` replaces the advice printed when Node is not installed at
all. `need_env` returns non-zero when it created `.env`, so a caller can print its own notes
only on the first run.
**Under `set -e` a bare `need_env` therefore ends the script on exactly that run** — call it as
`need_env || note "…"`.

`need_plugins` reads the settings with `node`, so it comes after `need_node`; beside
`need_deps` is the natural place, with `need_hooks` after it:

```bash
need_node
need_deps
need_plugins
need_hooks
```

It installs, at project scope, each plugin `.claude/settings.json` turns on and this machine
lacks for the repository, registering the official marketplace first on a machine where Claude
Code has never run. With nothing missing it prints nothing. Without Claude Code — CI — it notes
the skip and returns zero.

`need_hooks` installs the commit-msg hook, above, when it is missing or an older kit's.
Outside a git repository, or beside a project's own hook, it changes nothing and returns zero;
with the hook in place it prints nothing.

The scenarios stay in each project. Only the frame is shared.

### Packages from GitHub Packages

GitHub Packages wants a token even to install, public package or not. A project that depends on
one says so in its `.npmrc`, and nowhere else:

```
@owner:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```

`need_deps` reads that file: when it mentions `GITHUB_TOKEN`, it installs through
`with_github_token`, and otherwise exactly as before, so a project without such packages never
needs the GitHub CLI. `with_github_token <command…>` runs one command with a token: the
environment's `GITHUB_TOKEN` when there is one, as in GitHub Actions, otherwise the GitHub CLI's
login, which keeps it in the system's credential store. The token is handed to that command
only, never exported into the session.

A developer signs in once per machine:

```bash
gh auth login
gh auth refresh -s read:packages
```

In GitHub Actions the workflow's own `GITHUB_TOKEN` serves, given `permissions: packages: read`
and, on the package, access granted to the consuming repository under "Manage Actions access".

### Ignore files

```bash
cp node_modules/charter/core/ignore/gitignore .gitignore
cp node_modules/charter/core/ignore/prettierignore .prettierignore
```

These are **copied, not referenced** — neither format has an import or extends mechanism. They
are starting points a project appends its own entries to, and they change rarely.

## Verification

```bash
./check            # every check, in order
./check 20         # just the one whose name matches
```

`./check` is the only verification command. There is no test framework: each `checks/*.sh`
proves one module's contract by running the tool a consumer would actually run — `tsc` against
the fixture, `prettier` against a deliberately unformatted file — from `tests/fixture/`, a real
consumer project that installs this package by relative path.

## Adding a module

Write the check first. It is the only test this repository has, and a module that ships without
one is a promise nobody is keeping.

A rule every project needs goes in `core/rules/`, with its import in `core/rules.md`. Any other
rule goes in a module's `rules/` and opens with the fixed `paths:` block — the form `sync`
reads without a YAML parser:

```markdown
---
paths:
  - "src/**"
---
```

A new module is a directory under `domains/` or `stacks/`, with a name no other module has.
`./check 40` fails until each rule has its place, and holds the budgets: 60 lines a file, 150
for `core`, and 225 for a workspace's worst case — `core` plus every rule of its modules, as if
every glob matched.

## Releasing

A release is one `chore: release X.Y.Z` commit on `main` and the `vX.Y.Z` tag on it. The commit
changes the version in two places and nothing else: `"version"` in `package.json`, and the
`^X.Y.Z` range under Install, above. The git form names no version; whoever copies it picks the
newest tag.

**The README's range moves with every release, patch included.** A consumer copies the install
line as written, and a range left behind installs the previous release without anything failing
for them. `./check 60` fails until the range matches `"version"`.

Pick the number by what a consumer has to do. Reworded rules or a fixed function: patch. A new
rule, module or `lib.sh` function: minor. A path a consumer writes that moves or disappears:
major, with a migration section like the ones below.

The GitHub release is titled `vX.Y.Z — <what changed>` and ends with an "Upgrading" section that
says what a consumer has to change, or that nothing has to.

## Migrating from 2.x

The package was `dev-kit` until 3.0, and its four sections became modules. Do this by hand:

1. Replace the dependency: `npm uninstall dev-kit`, then `npm install -D charter@^3`.
2. Change each path by the table below, including the `source` line in `./run`. A `./run` still
   pointing at `common/lib.sh` fails loudly, not silently.
3. Delete the 2.x section imports from every `CLAUDE.md`.
4. Run `npx --no charter init <modules> [--workspace <dir>]` for each workspace. It writes
   `charter.json`, the hook and the `.gitignore` line, and rewrites the commit-msg wrapper.
5. On every other clone, after pulling: `npm install`, then `./run` (or `need_hooks`). Until
   then the old 2.x wrapper lets every commit through without checking it.

| 2.x | 3.0 |
| --- | --- |
| `dev-kit/common/tsconfig` | `charter/stacks/typescript/tsconfig` |
| `dev-kit/backend/tsconfig` | `charter/stacks/node/tsconfig` |
| `dev-kit/ui/tsconfig` | `charter/stacks/react/tsconfig` |
| `dev-kit/common/prettier` | `charter/stacks/typescript/prettier` |
| `node_modules/dev-kit/{common,backend,ui,testing}/oxlint.json` | `node_modules/charter/stacks/{typescript,node,react,vitest}/oxlint.json` |
| `node_modules/dev-kit/common/lib.sh` | `node_modules/charter/core/lib.sh` |
| `node_modules/dev-kit/common/ignore/…` | `node_modules/charter/core/ignore/…` |
| `@node_modules/dev-kit/{common,backend,ui,testing}/rules.md` | `@node_modules/charter/core/rules.md` at the root; the rest through `init` |

The `./run` variables are renamed too: `DEVKIT_NODE_MIN` is `CHARTER_NODE_MIN` and
`DEVKIT_NODE_HINT` is `CHARTER_NODE_HINT`.

## Migrating from 1.x

Every path changed in 2.0.0. Replace each 1.x line with its 2.0 counterpart:

| 1.x | 2.0 |
| --- | --- |
| `@node_modules/dev-kit/rules/commits.md`, `documentation.md`, `writing.md`, `review.md`, `backlog.md` | `@node_modules/dev-kit/common/rules.md` |
| `@node_modules/dev-kit/rules/typescript.md` | `common/rules.md`, plus `backend/rules.md` or `ui/rules.md` |
| `@node_modules/dev-kit/rules/http.md`, `layout.md` | `@node_modules/dev-kit/backend/rules.md` |
| `@node_modules/dev-kit/rules/testing.md` | `@node_modules/dev-kit/testing/rules.md`, plus `backend/rules.md` for the PostgreSQL rule |
| `dev-kit/tsconfig/base` | `dev-kit/common/tsconfig` |
| `dev-kit/tsconfig/node` | `dev-kit/backend/tsconfig` |
| `dev-kit/tsconfig/web` | `dev-kit/ui/tsconfig` |
| `dev-kit/prettier` | `dev-kit/common/prettier` |
| `node_modules/dev-kit/sh/lib.sh` | `node_modules/dev-kit/common/lib.sh` — in the bootstrap line too |
| `node_modules/dev-kit/ignore/…` | `node_modules/dev-kit/common/ignore/…` |

A project that imported only some of the 1.x rules now gets the whole section. The rule files
are still files at `<section>/rules/<rule>.md` and can be imported one at a time, but that is
outside the documented contract and nothing checks it.
