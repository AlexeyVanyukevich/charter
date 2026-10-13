# dev-kit — a commit-msg hook and a lint config per section

Status: **designed**, 2026-10-13. Not built.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-13, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** the kit enforces its rules and lints the way it does. For **what**
> the kit provides today, read `README.md`.

---

## 1. Goal

**A commit message that breaks the commit rule, an `any`, or a bug a linter can see fails,
instead of landing.**

Two rules are enforced today only by prose: the commit message (`common/rules/commits.md` —
format, subject line only, no trailer) and no `any` in hand-written code
(`common/rules/typescript.md`). Claude Code reads instructions as context, not configuration it
must obey, and a consuming project's prompt audit found no commit-msg hook there. Nothing fails
when either rule is broken.

Beyond those two, the kit ships no lint at all, so each consuming project lints differently or
not at all. Each section therefore brings a lint config of bug-catching rules, loaded the way
its rules are: a project takes the sections it needs and nothing from the others.

The prose stays. It is what makes the first attempt right; the tools catch the attempt that is
not.

## 2. Decisions

| Question | Decision |
| -------- | -------- |
| Enforce commits in git or in Claude Code? | **A git `commit-msg` hook.** It catches every author, not only Claude |
| Hook in shell or a package? | **Bash, no dependencies.** Not commitlint or husky |
| Who installs the hook on a clone? | **`need_hooks`** in `common/lib.sh`, called by `./run` after `need_deps` |
| How is it installed? | **A short wrapper** in the hooks directory that runs the kit's script |
| A `commit-msg` hook already there? | **Left alone**, with a note. Never overwritten |
| Which linter? | **oxlint**, not ESLint with typescript-eslint |
| Which rules? | **oxlint's `correctness` and `suspicious` categories**, three named rules, and a measured list turned off |
| Rules that need type information? | **On**, through `oxlint-tsgolint` and `options.typeAware` in the config |
| Per section? | **Each section ships `oxlint.json`.** `backend` and `ui` extend `common`'s, as their tsconfigs do; `testing` stands alone |
| Backend's `Kysely<any>` in migrations? | **`backend/oxlint.json`** turns `no-explicit-any` off under `**/migrations/**` |
| Does this repository lint itself? | **No.** Its checks run the configs against the fixture |

### Git, not a Claude Code hook

A PreToolUse hook sees only Claude's commits, and has to dig the message out of a shell command
that may use `-m`, `-F`, a heredoc or an editor. A `commit-msg` hook receives the final message
as a file, whoever wrote it. When Claude's commit is refused, Claude reads git's error and
retries, which is the behaviour wanted.

### A wrapper, not a symlink or a copy

A copy goes stale when the kit is upgraded. A symlink depends on the executable bit surviving
`npm pack`, and dangles when `node_modules` is removed. The wrapper calls `bash` on the kit's
script, so the bit does not matter, and exits 0 when the kit is not installed. A fresh clone can
therefore still commit before its first `npm install`:

```sh
#!/bin/sh
# dev-kit commit-msg
f=node_modules/dev-kit/common/hooks/commit-msg
[ -f "$f" ] || exit 0
exec bash "$f" "$@"
```

Git runs hooks from the top of the working tree, where a workspace manager hoists the kit, so
the relative path holds in a repository with workspaces as well.

### oxlint, not typescript-eslint

typescript-eslint 8.71.2, the newest on 2026-10-13, declares `typescript >=4.8.4 <6.1.0` as a
peer. The fixture, and the projects it stands for, are on TypeScript 7. oxlint 1.88.0 has no
TypeScript peer and ships one package. Its type-aware rules run in `oxlint-tsgolint`, whose
major version follows TypeScript's: 7.0.2004 on that date. A type-aware run over a 159-file
consuming project took half a second.

Spikes on 2026-10-13 confirmed:

- a config `extends` another by a path relative to itself;
- an extended config's `overrides` apply;
- a section config that names only its own `plugins` adds them to `common`'s rather than
  replacing them, and a project extending two sections gets both sets, in either order;
- `options.typeAware` in a config does what `--type-aware` does on the command line, and
  without `oxlint-tsgolint` installed the run fails, naming the package.

### Which rules, measured

`correctness` is oxlint's default category: code that is wrong. `suspicious` is code that is
probably wrong. `pedantic`, `style`, `restriction` and `perf` are opinions, and Prettier already
owns formatting.

To these the kit adds three rules from other categories:

- `typescript/no-explicit-any`, the rule;
- `typescript/no-misused-promises` and `typescript/switch-exhaustiveness-check`, for the two
  type-aware bug classes `correctness` leaves out: a promise passed where nothing awaits it,
  and a union case left unhandled.

`correctness` already carries `no-floating-promises` and `await-thenable`.

Both categories were run, every plugin on, against the three consuming projects on the author's
machine: 211, 457 and 428 findings. The rules below produced most of them and were read case
by case. Each is turned off, or given an option, in the section where it fires:

| Rule | Findings | Section | Why |
| ---- | -------: | ------- | --- |
| `react/react-in-jsx-scope` | 438 | ui | Wrong under `jsx: react-jsx`, which the ui tsconfig sets |
| `typescript/no-unsafe-type-assertion` | 202 | common | Flags every `as` cast; a cast is a decision, not a bug |
| `vitest/require-mock-type-parameters` | 64 | testing | Style |
| `unicorn/no-array-sort`, `no-array-reverse` | 59 | common | A preference for `toSorted()`, not a bug |
| `vitest/no-conditional-expect` | 38 | testing | The testing rule's dataset runner checks rows differently by design |
| `unicorn/consistent-function-scoping` | 36 | common | Style |
| `oxc/no-async-endpoint-handlers` | 29 | backend | Written for Express; Fastify awaits an async handler |
| `vitest/valid-expect` | 19 | testing | Option `maxArgs: 2`: Vitest's `expect` takes a message |
| `import/no-unassigned-import` | 17 | common | Flags side-effect imports such as a stylesheet |
| `import/no-named-as-default-member` | 11 | common | Flags `pg.types`, the normal use of a CommonJS default export |
| `promise/always-return` | 7 | common | Style |
| `eslint/no-shadow`, `no-underscore-dangle` | 8 | common | Style |
| `typescript/no-misused-promises` | 5 | ui | Option `checksVoidReturn.attributes: false`: an async handler in a JSX attribute is the React idiom |

With these, the three projects have 36, 49 and 78 findings. Of those, 58 are unnecessary type
assertions, which `oxlint --fix` removes, and 16 are explicit `any`. The rest were sampled and
read as real: unhandled promises, a non-exhaustive switch, `toThrow()` with no expected error,
a numeric sort without a comparator. **A project adopting the kit's lint should expect a few
dozen findings, mostly fixable mechanically.**

The list is a starting point, not a closed set. A rule that proves noisy in use is turned off
in its section in a patch release, with the reason beside it in the table that ships in the
README.

### The migration exception is an approximation

The backend rule allows exactly `Kysely<any>`, and only in a migration. A lint override can only
turn the rule off for a set of files, so any `any` in a migration passes. Migrations are short
and written to one pattern, so the gap is accepted rather than closed with a custom rule.

### Considered and not adopted

A plan for moving a TypeScript 7 project onto oxlint proposed more than this spec takes. Each
part was checked on 2026-10-13 and left out:

- **`--type-check`.** Marked experimental in oxlint 1.88.0's help text, and it repeats the
  `tsc --noEmit` a project already runs.
- **`@oxlint/migrate`.** It converts an ESLint config; neither the kit nor its fixture has one.
- **A pre-commit lint through Husky and lint-staged, running `oxlint --fix`.** It adds the
  dependencies this spec avoids, and needs oxlint on every machine that commits. The lint runs
  where a project runs its other checks.
- **ESLint alongside oxlint**, with `eslint-plugin-oxlint` turning off the rules oxlint covers.
  Worth it only once the kit wants a rule oxlint lacks; none exists. If one does, that plugin is
  the way in.

Also left out:

- **The `pedantic` and `style` categories.** They are opinions, and would turn adopting the
  kit into a reformatting project.
- **Linting this repository.** It holds one `.mjs` file and Bash, and the root `package.json`
  has no dependencies; adding oxlint there would change that for one file. The checks below run
  every config against the fixture, which is where a broken config would show.

## 3. The hook

`common/hooks/commit-msg <file>`, Bash. It reads the message as git hands it over:

1. Drop everything from git's scissors line (`# ------------------------ >8 ------------------------`)
   down, then every line starting with `#`, then trailing blank lines.
2. A first line starting `fixup! `, `squash! ` or `amend! ` passes untested. These exist to be
   folded away by `git rebase --autosquash`, which the rebase-only workflow uses.
3. Otherwise, refuse unless all of these hold:

| Check | Refused example |
| ----- | --------------- |
| Exactly one non-empty line | a body, a blank line then `Co-Authored-By: …` |
| `type(scope)!: subject`, with the type one of `feat fix docs test refactor perf build ci chore revert`, the scope optional and `[a-z0-9-]`, and `!` optional | `feature: add x`, `fix(API): x` |
| A space after the colon, then a subject not starting with a capital | `fix: Add x` |
| No trailing period | `fix: add x.` |
| The line is 72 characters or fewer, counted as characters, not bytes | a 73-character line |

A refusal names the check that failed, prints the message as received, and exits 1. Git's own
`Merge branch …` and `Revert "…"` messages are refused like any other. The rules forbid merge
commits, and a revert is written `revert: …`.

## 4. `need_hooks`

Defined in `common/lib.sh`. A project's `./run` calls it after `need_deps`. `init` also runs it
after `need_plugins` when `common` is among the sections it was given.

1. Not inside a git working tree: return 0.
2. The hooks directory is `git rev-parse --git-path hooks`, which follows `core.hooksPath` and
   resolves correctly in a linked worktree. Create it when missing.
3. `commit-msg` present and carrying the `# dev-kit commit-msg` marker: return 0, silently.
4. `commit-msg` present without the marker: `note` that another hook is installed and the kit's
   is not, and return 0. **`./run` never fails over hooks.**
5. Otherwise write the wrapper, make it executable, and `ok` it.

## 5. The lint

Four files, one per section. Each names only its own plugins.

`common/oxlint.json` carries the categories, type-aware linting and the shared exceptions:

```json
{
  "plugins": ["typescript", "unicorn", "oxc", "import", "promise"],
  "categories": { "correctness": "error", "suspicious": "error" },
  "options": { "typeAware": true },
  "rules": {
    "typescript/no-explicit-any": "error",
    "typescript/no-misused-promises": "error",
    "typescript/switch-exhaustiveness-check": "error",
    "typescript/no-unsafe-type-assertion": "off",
    "unicorn/no-array-sort": "off",
    "unicorn/no-array-reverse": "off",
    "unicorn/consistent-function-scoping": "off",
    "import/no-unassigned-import": "off",
    "import/no-named-as-default-member": "off",
    "promise/always-return": "off",
    "eslint/no-shadow": "off",
    "eslint/no-underscore-dangle": "off"
  }
}
```

The other three add:

| Section | Plugins | Rules |
| ------- | ------- | ----- |
| `backend` | `node` | `oxc/no-async-endpoint-handlers` off; `no-explicit-any` off under `**/migrations/**` |
| `ui` | `react`, `jsx-a11y` | `react/react-in-jsx-scope` off; `no-misused-promises` with `checksVoidReturn.attributes: false` |
| `testing` | `vitest` | `valid-expect` with `maxArgs: 2`; `no-conditional-expect`, `require-mock-type-parameters` off |

`backend` and `ui` extend `../common/oxlint.json`, as their tsconfigs extend `common`'s: each is
`common` plus what that kind of workspace needs. `testing` extends nothing, as no section's
rules load another's, so it is named beside whichever of the other three a project uses. Vitest
is the runner every consuming project uses; the testing rule names none, and a project on
another runner leaves `testing/oxlint.json` out.

A consuming project installs `oxlint` and `oxlint-tsgolint` at the major of its TypeScript, and
writes `.oxlintrc.json` naming one of `common`, `backend` or `ui`, plus `testing` if it loads
it:

```json
{
  "extends": [
    "./node_modules/dev-kit/backend/oxlint.json",
    "./node_modules/dev-kit/testing/oxlint.json"
  ]
}
```

As with the rule imports, these are **filesystem paths**, relative to the config file, so a
workspace one level down writes `../node_modules/…`. They need no `exports` entry. The project
runs `npx oxlint --deny-warnings` wherever it runs its other checks; the kit does not wire it
into `./run`, and takes no dependency on either package.

## 6. Verification

`checks/80-commit-msg.sh`:

- a dataset of messages, each a row with its expected result and, for a refusal, the check that
  should name it, run through `common/hooks/commit-msg` directly. It covers every refused example
  above, the `!` form, the autosquash prefixes, a 72- and a 73-character line, a subject with an
  em dash counted as one character, and a message with git's comments and scissors;
- `need_hooks` in a temporary repository:
  - it writes the wrapper, and a second run changes nothing;
  - a foreign `commit-msg` survives, with a note;
  - `core.hooksPath` is honoured;
  - outside a repository it returns 0;
- end to end, in a scratch consumer holding the unpacked `npm pack` tarball:
  - `git commit -m 'Fix: x'` fails, and `git commit -m 'fix: x'` succeeds;
  - with `node_modules` removed, both succeed.

`checks/90-lint.sh`, in the fixture, which gains `oxlint` and `oxlint-tsgolint` as
devDependencies and a `src/lint/` directory of small files, each holding one case. A dataset
row names a file, the sections whose configs are extended, and the rule expected to fire, or
none:

- **a rule of each kind fires:** an explicit `any` and a floating promise under `common`; a
  non-exhaustive switch and a misused promise under `common`; a focused test under
  `testing`;
- **each section's exceptions hold:** `Kysely<any>` in a `migrations/` file passes under
  `backend` and fails under `common`; JSX without a React import passes under `ui`; an async
  `onClick` passes under `ui` and fails under `common`; `expect(value, 'message')` passes under
  `testing`;
- **the shared exceptions hold:** an `as` cast and an in-place `sort` pass under `common`;
- **plugins merge:** `backend` with `testing`, in both orders, fires both a `typescript` and a
  `vitest` rule;
- **type-aware linting is real:** the floating-promise row fails when run with
  `oxlint-tsgolint` removed from `PATH` and the fixture, with oxlint's message naming the
  package.

`checks/50-lib.sh` adds `need_hooks` to the functions `lib.sh` must define.

## 7. Delivery

- `common/hooks/commit-msg`; `oxlint.json` in each of `common`, `backend`, `ui` and `testing`.
  They ship inside the section directories already listed in `files`.
- `need_hooks` in `common/lib.sh`. `bin/dev-kit.mjs` runs it after `need_plugins` when `common`
  is named.
- README:
  - "The modules" gains "Commit messages" and "Lint" sections. "Lint" carries the table of
    turned-off rules and the expected findings on adoption;
  - `need_hooks` joins the `./run` function list and its example;
  - the Sections table names what each section now brings.
- `docs/backlog.md`: the entry "Rules a tool could enforce are enforced only by prose" is deleted
  in the commit that completes this.
- A new module and a new `lib.sh` function: **2.4.0**, a minor release.
