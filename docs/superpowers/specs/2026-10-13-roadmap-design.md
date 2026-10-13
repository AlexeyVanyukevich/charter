# dev-kit — roadmap: phases, domains and stacks

Status: **designed**, 2026-10-13. Not built.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-13, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** the kit is shaped and delivered the way it is, and in what order it
> grows. Each release below gets its own spec and plan. For **what** the kit provides today,
> read `README.md`.

---

## 1. Goal

**One versioned set of utilities that a new or existing application installs to get the rules
it is written by — requirements, development and verification — at the lowest token cost that
keeps those rules followed.**

The kit today is a package a consuming project imports from `node_modules`: rules through `@`
imports in `CLAUDE.md`, configs through `extends`. Two things stop that scaling:

- **Every rule loads in every session.** Claude Code's memory docs: imports "don't reduce its
  context cost, because imported files also load at launch." A backend session reads 216 lines
  of kit rules, and the 60 lines of `http.md`, `layout.md` and `database-tests.md` matter only
  when Claude touches routes, module layout or database tests.
- **Each Claude Code mechanism needs its own bridge out of `node_modules`.** Imports load at
  launch; `.claude/rules/` and `.claude/skills/` expect files in the project; a plugin cannot
  carry rules at all. Every new mechanism the kit adopts would add another bridge and another
  check.

The application may be in any language. JavaScript and TypeScript come first; no other stack is
planned until a real project needs one.

## 2. Decisions

### One kit, one version, modules inside

The work splits into three concerns — requirements, development (backend and frontend, with
unit, integration and end-to-end tests) and verification (proof that it works, or a bug
report). They ship as **modules of one package with one version**, not three packages.

Three packages would mean three releases, a compatibility matrix between them, and three copies
of the shared core — the commit rule, the review rule, the evidence format each phase hands to
the next. Nothing is gained while one maintainer owns all three. A module that grows its own
audience can be split out then.

### Phases run as roles with their own context

At any moment the work is in one phase. A session writing requirements does not need the HTTP
contract; a verification session does not need the module layout. Each phase is therefore a
skill or a subagent (`.claude/agents/`), so its instructions load only while it runs, and a
subagent's work happens in its own context window rather than the main session's. A phase whose
work is routine, such as reading logs or collecting evidence, can name a cheaper model.

### Phases hand over through files in the repository

The phases are connected by artefacts, not by conversation:

- a requirement carries acceptance criteria with identifiers (`AC-12`);
- a test names the criterion it covers;
- a verification report gives each criterion its evidence — a command's output, an end-to-end
  trace, a screenshot — or a bug report.

This makes "it was verified" checkable by a tool: `dev-kit verify` lists criteria with no test
and tests with no evidence. Verification is the kit's existing review rule
(`common/rules/review.md`) turned from prose into a contract.

### A tool beats a rule

Whatever a tool can check leaves the prose: types, lint, the commit-msg hook, coverage
thresholds, traceability. A check is more reliable than an instruction and costs no tokens. The
kit already works this way for commits and for lint; the rule shrinks to what a tool cannot see.

### Three load tiers, each with a budget

Every rule is placed in exactly one tier:

| Tier | Mechanism | Loads |
| --- | --- | --- |
| Always | `@` import from `CLAUDE.md` | at launch, in every session, including `-p`, CI and cloud |
| By path | `.claude/rules/` file with `paths:` frontmatter | when Claude reads or edits a matching file |
| By task | skill or subagent | when the task calls for it |

`./check` measures each tier separately. The always-on budget is set in the 3.0 spec; the aim
is well under today's 216 lines. Today's single 225-line budget was taken from Claude Code's
guidance of "under 200 lines per CLAUDE.md file"; it was a heuristic, and it counted only the
kit's lines, not the consuming project's own.

### Rules that teach Claude what it already knows are cut

Claude knows each language's idioms. Claude Code's own trim check for `CLAUDE.md` cuts what
Claude can derive and keeps "conventions that differ from tool defaults". A rule saying "format Go with gofmt" spends tokens on nothing; a stack
carries only where the consuming projects' conventions depart from the default.

### The npm package is the vehicle; the content does not depend on it

The package stays the single source, and a project pins its version — in `package.json` today.
This is how updates ship: as versions a project moves to deliberately.

The content is laid out so that nothing in it assumes npm. A later release adds delivery
without Node (§4, 4.0); only the vehicle changes.

**A Claude Code plugin was rejected as the vehicle.** Three facts from the plugin docs, each
fatal to a requirement:

- A plugin cannot ship rules or a `CLAUDE.md`: "A CLAUDE.md at the plugin root isn't loaded as
  context."
- Versions cannot differ per project. Marketplaces are registered once per user — "a
  marketplace you add in one project is available in every project" — so two projects on one
  machine cannot sit on different versions without a separately named plugin per version.
- A project-enabled plugin loads only after the workspace trust dialog: "Trusting a parent
  folder or running with `-p` isn't enough." Cloud sessions never show the dialog, so CI and
  headless sessions would run without the rules.

**Copies a project owns and edits were rejected.** They drift from the kit, and the kit stops
being a single point.

**Copies refreshed automatically and committed were rejected.** Each developer's refresh would
write their own installed version into tracked files, so a team mid-upgrade would flip the
files back and forth, and a Windows checkout with `core.autocrlf` would see every file as
changed.

### Path and task tiers are synced, git-ignored copies

A `SessionStart` hook in the project's committed `.claude/settings.json` runs `dev-kit sync`,
which mirrors the installed version's path-scoped rules into `.claude/rules/dev-kit/` and its
skills into `.claude/skills/`. Both are git-ignored. Each machine's copies match its own
installed version, so nothing generated is committed and nothing churns.

Copies, not links: a committed symlink is a one-line text file on a Windows checkout without
`core.symlinks`, and some consuming projects are developed on Windows. Junctions avoid the
privilege problem but could not be tested from the machine this was designed on.

The hook covers the first session of a fresh clone, once `npm install` has run — the same
precondition the `@` imports have. It does not cover always-on rules (§5), which is why that
tier stays an import.

### Domain × stack, composed per workspace

The kit separates **what** from **with what**:

- a **domain** holds principles that hold in any language: `backend` (the HTTP error contract,
  module-per-entity layout, database tests against a real engine) and `frontend`;
- a **stack** holds a language's tool configs and its few departures from idiom: `typescript`,
  `react`.

A project declares each workspace as a domain plus stacks in a committed manifest:

```json
{
  "version": "3.0.0",
  "workspaces": { "server": ["backend", "typescript"], "web": ["frontend", "react"] }
}
```

The manifest is named and placed in the 3.0 spec. `sync` writes each workspace's `paths:` with
that workspace's prefix as it copies the rule, so a rule written once for `src/modules/**`
loads for `server/src/modules/**` in one project and for `src/modules/**` in another. Rules are
scoped by path rather than by session, so one session at the repository root can work on both
workspaces. Today's restriction — backend and ui may never load in one directory — and the
per-workspace `CLAUDE.md` imports both go away.

### Configs a tool reads are committed, and written only on purpose

A config CI must read (a tsconfig, a lint config) lives in the repository. Where the tool
resolves `extends` from a package, the project keeps extending the kit, as it does today. Where
it cannot, the config is a committed copy, written only by an explicit `dev-kit init` or
`dev-kit upgrade` — never by the hook. The version is pinned once per project, so every
developer writes the same copy.

### Stacks are added for a real project, not in advance

Each stack costs little text but real verification: `./check` runs the actual tools against a
fixture, so a stack needs a fixture and its toolchain wherever the checks run. A stack nobody
uses is a promise nobody is keeping. `typescript` and `react` exist in all but name; no other
stack is planned.

## 3. Layout

```
dev-kit/
  core/            rules for every project, the commit-msg hook, the evidence format
  phases/
    requirements/  the requirements skill, the requirement template with criterion identifiers
    development/   the test-first loop, the criterion-to-test rule
    verification/  the verification agent, the report and bug-report templates
  domains/
    backend/       HTTP contract, layout principles, database tests (path-scoped)
    frontend/      UI principles (path-scoped)
  stacks/
    typescript/    tsconfig, Prettier, oxlint, TypeScript rules
    react/         React rules, the lint plugin config
  bin/dev-kit      init, sync, upgrade, verify
```

Today's sections map onto it:

| Today | Becomes |
| --- | --- |
| `common/rules/` commits, writing, backlog | `core/` |
| `common/rules/documentation.md` | `phases/requirements/` |
| `common/rules/review.md` | `phases/verification/` |
| `common/` tsconfig, Prettier, oxlint, `rules/typescript.md` | `stacks/typescript/` |
| `backend/rules/` http, layout, database-tests | `domains/backend/` |
| `backend/rules/typescript.md`, `backend/tsconfig.json` | `stacks/typescript/` |
| `ui/` | `domains/frontend/` and `stacks/react/` |
| `testing/rules/testing.md` | `phases/development/` |

`common/lib.sh`, the ignore files and the `./run` frame are placed in the 3.0 spec.

## 4. Releases

Each row is one slice with its own spec, plan and release.

| Release | Delivers | Token effect, estimated from today's line counts |
| --- | --- | --- |
| **3.0 — foundation** | the three tiers; `sync` through the hook; the manifest; `init` and `upgrade`; the domain and stack layout; backend's three rules move to the path tier | about 60 lines off a backend session |
| **3.1 — requirements** | the requirements skill and template with criterion identifiers; the spec-and-plan workflow becomes a skill | about 25 lines off every session |
| **3.2 — development** | unit, integration and end-to-end conventions; criterion identifiers in tests; coverage thresholds as a check | test rules move to the path tier |
| **3.3 — verification** | the verification agent; evidence reports; bug reports; `dev-kit verify` | verification runs in its own context |
| **4.0 — any language** | delivery without Node — a manifest and a release fetched from git — and the first stack outside JavaScript, when a project needs it | — |

3.0 changes every path a consuming project writes, so it is a major release, with a migration
section in the README. It also takes the backlog entry "Rules for particular tasks and files
load in every session", whose deferral this roadmap supersedes.

None of the token estimates has been measured. Measuring actual context use per phase — not
line counts — is a later addition to `./check`.

## 5. Evidence

Probed on 2026-10-13 with Claude Code 2.1.287, in a scratch project whose rules held facts no
session could guess. Each case ran once, with Bash, Grep and Glob disabled so the session could
not find the facts by searching.

**A `.claude/rules/` symlink into `node_modules` loads, and keeps its `paths:` scope.**

| Session | Unscoped rule | Scoped rule (`**/src/modules/**/*.routes.ts`) |
| --- | --- | --- |
| no file read | loaded | not loaded |
| read `src/other.ts` | loaded | not loaded |
| read `src/modules/issues/issue.routes.ts` | loaded | loaded |
| read `server/src/modules/orders/order.routes.ts` | loaded | loaded |

**A rule written by a `SessionStart` hook loads in that same session only if it is scoped.**
The copies were deleted before each session, so only the hook wrote them.

| Session | Unscoped rule | Scoped rule |
| --- | --- | --- |
| no file read | not loaded | not loaded |
| read a matching routes file | not loaded | loaded |
| read `src/other.ts` | not loaded | not loaded |

Unscoped rules are discovered at launch, before the hook runs; scoped rules are looked up when
a matching file is read. That result is why the always-on tier stays an import.

## 6. Unproven

Each is probed at the start of the release that depends on it:

- **3.0:** the hook on Windows; a pnpm install, where `node_modules/dev-kit` is itself a link;
  repeated runs of the absent and present cases, not one each.
- **3.1:** whether skills written by the hook load once it returns `reloadSkills`; whether a
  skill with `paths:` loads by itself on a match or only becomes available to choose.
- **3.3:** what a subagent loads of the project's instructions — `CLAUDE.md`, path-scoped rules.
- **Throughout:** that any of this costs fewer tokens in practice. Line counts are a proxy.

## 7. Not in scope

- A Go stack, or any stack beyond `typescript` and `react`.
- Delivering the kit as a Claude Code plugin. Revisit if plugins gain per-project versions and
  load in headless sessions.
