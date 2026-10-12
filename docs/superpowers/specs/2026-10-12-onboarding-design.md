# dev-kit — onboarding a project's Claude Code plugins

Status: **designed**, 2026-10-12. Not built.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-12, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** the kit onboards projects the way it does. For **what** the kit
> provides today, read `README.md`.

---

## 1. Goal

**A project gets the Claude Code plugins its sections need, and no session outside it does.**

Until 2026-10-12 every plugin was installed at user scope, so it loaded in every session on the
machine, the desktop app's included. The plugins now sit at project scope in each consuming
project. Two moments have to work for that to hold:

1. **Creating a project.** Its sections are chosen; the plugins and rules those sections imply
   are written into the repository.
2. **Cloning one.** A committed `enabledPlugins` entry turns a plugin on but does not download
   it. Claude Code's documentation: "Committing that entry turns the plugin on for your
   collaborators but doesn't download it to their machines, so each collaborator also runs
   `claude plugin install <name>@<marketplace> --scope project` once." Without a step that does
   this, a fresh clone runs without its plugins and nothing says so.

`npx dev-kit init` covers the first; `need_plugins` in `common/lib.sh` covers the second.

## 2. Decisions

| Question | Decision |
| -------- | -------- |
| Script, Claude skill, or documentation? | **A script in the kit.** Deterministic, and `./check` can prove it |
| Node or Bash? | **Node**, one file with no dependencies. The kit already requires Node 24 |
| What does `init` write? | **`enabledPlugins` and the `CLAUDE.md` imports.** Nothing else |
| A file it would write already exists? | **Merge**: add what is missing, change nothing that is set |
| Repositories split into workspaces? | **Supported**, through `--workspace <dir>` |
| Where is a section's plugin list? | **`<section>/plugins.json`**, beside its `rules.md` |
| Who downloads plugins on a clone? | **`need_plugins`**, called by `./run` after `need_deps` |

### Plugins and imports only

`init` was first drawn as a full project generator: tsconfig, Prettier, ignore files and the
`./run` frame as well. It was cut back because those writers are where the cost is — merging a
tsconfig that carries comments, the `backend`/`ui` tsconfig conflict, per-workspace paths — and
each needs its own fixture, for a step a project takes once. They stay README steps. Adding them
later changes nothing written here.

The imports stay in because they come from the same list of sections as the plugins, and
writing one without the other lets them drift.

### Node, not Bash with `jq`

Merging `settings.json` safely means parsing it. Bash would need `jq` on every machine; Node is
already required. `need_plugins` stays in `lib.sh`, where `./run` can reach it, and calls `node`
for the one parse it needs.

### Data beside the section

The CLI knows no section by name. It accepts any directory with a `rules.md` and reads that
section's `plugins.json` when there is one; a section without the file brings no plugins. Adding a plugin to a section is a one-line data change, and adding a
section needs no change to the CLI.

## 3. `init`

```bash
npx dev-kit init <section…> [--workspace <dir>]
```

Run at the repository root.

| Section | `enabledPlugins` | Import |
| ------- | ---------------- | ------ |
| `common` | `superpowers@claude-plugins-official` | `@node_modules/dev-kit/common/rules.md` |
| `backend` | — | `@node_modules/dev-kit/backend/rules.md` |
| `ui` | `frontend-design@claude-plugins-official`, `playwright@claude-plugins-official` | `@node_modules/dev-kit/ui/rules.md` |
| `testing` | — | `@node_modules/dev-kit/testing/rules.md` |

`context7` is in no section. It is a documentation lookup with no tie to a kind of project, and
stays at user scope.

**`.claude/settings.json`**, always at the root. Created when missing. For each plugin of the
named sections, `"<id>": true` is added when the plugin has no entry; an entry already present,
`false` included, is left as it is, so an opt-out survives a re-run. Every other key is kept.
A file that is not valid JSON stops the run, naming the file; nothing is written.

**`CLAUDE.md`**, at the root or in the workspace. Created with only the import lines when
missing. Otherwise each line not already present verbatim is appended, after one blank line.

**Errors**, each a non-zero exit with a message and nothing written:

- a name with no `<name>/rules.md` in the kit — the message lists the valid sections;
- `backend` and `ui` named for the same directory — the message points to `--workspace`. The
  README already forbids loading both in one place; the rules budget assumes no session reads
  both;
- a `--workspace` directory that does not exist.

**Last**, `init` runs `need_plugins`, so the developer who onboarded the project has its plugins
at once, then prints what it added and what it left alone.

## 4. Workspaces

`--workspace <dir>` changes where `CLAUDE.md` is written and the prefix of its imports. The
prefix is the path from that directory back to the root: `@../node_modules/dev-kit/…` one level
down, `@../../node_modules/dev-kit/…` two. Plugins still go to the root `settings.json`, because
Claude Code enables a plugin per repository, not per directory.

A repository with a server and a web workspace is three runs:

```bash
npx dev-kit init common testing
npx dev-kit init backend --workspace server
npx dev-kit init ui --workspace web
```

## 5. `need_plugins`

Defined in `common/lib.sh`. A project's `./run` calls it after `need_deps`.

1. Read the plugin ids set to `true` in `.claude/settings.json`, with `node`. No file, or no
   such ids: return 0.
2. No `claude` on `PATH` — CI, or a machine without Claude Code: `note` it and return 0.
   **`./run` never fails over plugins.**
3. Read `claude plugin list --json`. A plugin is installed for this project when an entry has
   its id, `scope: "project"`, and a `projectPath` equal to this repository.
4. When a plugin to install is from `claude-plugins-official` and `claude plugin marketplace
   list --json` does not list that marketplace, register it:
   `claude plugin marketplace add anthropics/claude-plugins-official`. A machine where Claude
   Code has never run interactively lacks it.
5. `claude plugin install <id> --scope project` for each missing plugin, under one `step`. A
   failed install `die`s naming the plugin, after Claude Code's own message. Plugins from other
   marketplaces are not registered here; Claude Code's error says what is missing.

Nothing missing, nothing printed.

## 6. Verification

`checks/70-init.sh` runs `bin/dev-kit.mjs` in a temporary directory, with a stub `claude` first
on `PATH` that records its arguments:

- the first run writes the expected `settings.json` and `CLAUDE.md`;
- a second run leaves both byte-for-byte unchanged;
- a plugin set to `false` beforehand stays `false`;
- an unrelated key in `settings.json` survives;
- `--workspace` writes `@../…` one level down and `@../../…` two;
- an unknown section, `backend` with `ui`, and a missing workspace each exit non-zero and write
  nothing.

The same check drives `need_plugins` through the stub: only missing plugins are installed; the
marketplace is added only when absent; with no `claude` on `PATH` it returns 0 and prints a
note. `checks/50-lib.sh` adds `need_plugins` to the functions `lib.sh` must define.

## 7. Delivery

- `bin/dev-kit.mjs`; `package.json` gains `"bin": { "dev-kit": "bin/dev-kit.mjs" }`, and `bin`
  in `files`.
- `common/plugins.json`, `ui/plugins.json`. A section with no plugins has no file.
- `need_plugins` in `common/lib.sh`.
- README: an "Onboarding a project" section before "The modules"; `need_plugins` in the `./run`
  function list and its bootstrap example.
- A new module and a new `lib.sh` function: **2.3.0**, a minor release.
