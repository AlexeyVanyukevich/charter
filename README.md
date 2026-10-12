# dev-kit

Shared conventions and tooling configuration for the projects on this machine, in four
sections — `common`, `backend`, `ui`, `testing`. A project loads the sections it needs, and
nothing from the others comes with them.

This is never published to the public npm registry. A package called `dev-kit` on the public
registry is an unrelated project and is not this one.

## Starting a project

In a new project's directory, paste this into the first Claude Code session, with the first line
describing the project and `<kit source>` naming where the kit comes from — the private registry
and its URL, or the git repository and its newest tag:

```text
Set this project up with dev-kit. It is a <backend | ui | backend and ui in workspaces>
project<, with tests>.

1. Create package.json if there is none. Install dev-kit as a devDependency from
   <kit source>. If you cannot reach it, stop and ask me; do not install a package named
   dev-kit from the public registry.
2. Read node_modules/dev-kit/README.md and follow it for this project's sections:
   `npx dev-kit init`, the tsconfig, the Prettier key, the ignore files, and a ./run frame
   that calls need_node, need_deps and need_plugins.
3. Run ./run, then show me every file you created or changed.
```

The prompt only installs the kit and hands over to the README that comes with it, so the steps
it follows are always the installed release's.

## Install

From the private registry — the normal way:

```json
"devDependencies": { "dev-kit": "^2.2.1" }
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
"devDependencies": { "dev-kit": "github:AlexeyVanyukevich/dev-kit#v2.2.1" }
```

No `.npmrc` is needed for this form, and it installs the same tree at a pinned tag.

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
    GH_TOKEN: ${{ secrets.DEV_KIT_TOKEN }}
- run: npm ci
  env:
    GH_TOKEN: ${{ secrets.DEV_KIT_TOKEN }}
```

`GH_TOKEN` is the GitHub CLI's own variable and wins over `GITHUB_TOKEN`, so git gets the
secret while npm keeps the workflow's token for GitHub Packages. **Without
`persist-credentials: false` the install fails:** checkout leaves the workflow's token in the
repository's git config, git sends it ahead of any credential helper, and GitHub answers
"Repository not found".

## Sections

| Section | For | Brings |
| ------- | --- | ------ |
| `common` | every project | six rules, the TypeScript base, Prettier, the `./run` skeleton, ignore files, the `superpowers` plugin |
| `backend` | Node services | four rules, the NodeNext tsconfig |
| `ui` | bundled browser applications | one rule, the browser tsconfig, the `frontend-design` and `playwright` plugins |
| `testing` | any project with a test suite | one rule |

**No section loads another.** A backend project with tests writes `common`, `backend` and
`testing` as three lines; nothing arrives that it did not name. A section's rules come as one
line; its configuration — tsconfig, Prettier, `./run`, ignore files — is still taken one piece
at a time, and a project that wants none of it writes none of it.

### A repository with both a backend and a UI

Load `common` and `testing` in the root `CLAUDE.md`, `backend` in the server workspace's
`CLAUDE.md`, and `ui` in the web workspace's. Claude Code reads a subdirectory's `CLAUDE.md`
when it works on files there, so each workspace gets its own section and not the other's.

**An import is relative to the `CLAUDE.md` that holds it,** and a workspace manager hoists the
kit to the root `node_modules`. A workspace one level down therefore imports one level up —
written as `@node_modules/…` it loads nothing, and says nothing:

```markdown
@../node_modules/dev-kit/backend/rules.md
```

Start sessions at the repository root. A session started inside a workspace treats the root's
`node_modules` as outside the project and does not follow the import at all.

Loading all four at the root is the obvious move and the wrong one: every session would read
both, and the rules budget assumes no session does.

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

## The modules

### TypeScript

```json
{ "extends": "dev-kit/backend/tsconfig" }
```

`dev-kit/common/tsconfig` carries the strictness: `strict`, `noUncheckedIndexedAccess`,
`exactOptionalPropertyTypes`, `target: ES2023`. `dev-kit/backend/tsconfig` adds NodeNext
resolution and Node types; `dev-kit/ui/tsconfig` adds the DOM lib, bundler resolution and
`jsx: react-jsx`. A workspace that is neither extends `dev-kit/common/tsconfig` directly.

None of the three sets `outDir`, `rootDir` or `include`. Those describe one project's directory
layout, and a shared base that guesses them is a base every project has to override.

### Prettier

In the consuming project's `package.json`:

```json
{ "prettier": "dev-kit/common/prettier" }
```

`semi: false`, `singleQuote: true`, `printWidth: 100`.

### Rules

One line per section in the consuming project's `CLAUDE.md`, and only the sections that
project needs:

```markdown
@node_modules/dev-kit/common/rules.md
@node_modules/dev-kit/backend/rules.md
@node_modules/dev-kit/ui/rules.md
@node_modules/dev-kit/testing/rules.md
```

| Section | Rule | Covers |
| ------- | ---- | ------ |
| common | `typescript.md` | Compiler strictness, no `any` in hand-written code |
| common | `commits.md` | Conventional Commits, the subject line as the whole message, rebase-only merges, release commits |
| common | `documentation.md` | `architecture.md` is authoritative; specs and plans are dated records |
| common | `writing.md` | Refer to projects by role; name something only when the name is load-bearing |
| common | `review.md` | A session ends by showing everything it changed, and what it decided alone |
| common | `backlog.md` | Findings left unfixed go in `docs/backlog.md`, one entry each, deleted by the fix |
| backend | `typescript.md` | NodeNext's `.js` imports, the `typebox` package, the one accepted `any` |
| backend | `http.md` | The one error shape, its codes, `additionalProperties: false`, 4xx translation |
| backend | `layout.md` | `modules/<entity>/` and its four files; `shared/`, `db/` |
| backend | `database-tests.md` | Integration tests against a real PostgreSQL, started by Testcontainers |
| ui | `typescript.md` | Bundler resolution: no extension on relative imports |
| testing | `testing.md` | Tests first, datasets over test bodies, derived facts, where tests live |

A section's `rules.md` is a heading and one `@rules/<rule>.md` line per file in its `rules/`.
No section imports another, so a project gets exactly the sections it names.

**The kit must be installed as a real directory** — from the registry or over git, as above.
`npm link` and a `file:` dependency install a symlink, and Claude Code does not follow an
index's imports through a symlink that leads out of the project: the session reads the section
headings and none of the rules.

These are **filesystem paths, not module specifiers**. They never touch npm's resolver, which
is why they appear in no `exports` map and why adding a rule needs no `package.json` change.

### The `./run` skeleton

```bash
source node_modules/dev-kit/common/lib.sh
```

Defines `step`, `ok`, `note`, `die`, `load_env_file`, `need_docker`, `need_node`, `need_deps`,
`need_plugins`, `need_env` and `with_github_token`, plus the colour variables. Sourcing is
inert: no shell options set, no directory changed, nothing run.

**`./run` is what installs dependencies, so it cannot source out of `node_modules` before the
kit is there.** Keep a short bootstrap *above* the `source` line, and test for the file rather
than the directory: a checkout installed before it took the kit has `node_modules` without it.

```bash
[ -f node_modules/dev-kit/common/lib.sh ] ||
  GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}" npm install
source node_modules/dev-kit/common/lib.sh
```

The token in that line matters only to a project with packages on GitHub Packages, below, and
is the one place its source is restated: `with_github_token` cannot be called before the kit is
installed. Without a token, a project that needs one fails here with npm's `401`. The line
gives git nothing: a private kit installed over git needs git signed in first, as under Install.

`need_node` reads `DEVKIT_NODE_MIN` (default `24`) and `DEVKIT_NODE_HINT`. `need_env` returns
non-zero when it created `.env`, so a caller can print its own notes only on the first run.
**Under `set -e` a bare `need_env` therefore ends the script on exactly that run** — call it as
`need_env || note "…"`.

`need_plugins` reads the settings with `node`, so it comes after `need_node`; beside
`need_deps` is the natural place:

```bash
need_node
need_deps
need_plugins
```

It installs, at project scope, each plugin `.claude/settings.json` turns on and this machine
lacks for the repository, registering the official marketplace first on a machine where Claude
Code has never run. With nothing missing it prints nothing. Without Claude Code — CI — it notes
the skip and returns zero.

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
cp node_modules/dev-kit/common/ignore/gitignore .gitignore
cp node_modules/dev-kit/common/ignore/prettierignore .prettierignore
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

A rule goes in the `rules/` of the section whose every project needs it, with its import in
that section's `rules.md`. `./check 40` fails until both exist, and fails if the section's
session load passes 225 lines.

## Releasing

A release is one `chore: release X.Y.Z` commit on `main` and the `vX.Y.Z` tag on it. The commit
changes the version in three places and nothing else: `"version"` in `package.json`, and the
`^X.Y.Z` range and the `#vX.Y.Z` pin under Install, above.

**The README's pins move with every release, patch included.** A consumer copies the install
line as written, and a pin left behind installs the previous release without anything failing.

Pick the number by what a consumer has to do. Reworded rules or a fixed function: patch. A new
rule, module or `lib.sh` function: minor. A path a consumer writes that moves or disappears:
major, with a migration section like the one below.

The GitHub release is titled `vX.Y.Z — <what changed>` and ends with an "Upgrading" section that
says what a consumer has to change, or that nothing has to.

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
