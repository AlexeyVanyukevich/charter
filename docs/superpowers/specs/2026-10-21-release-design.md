# charter — cutting a release

Status: **built**, 2026-10-21.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-21, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** a release is cut with `charter release` and the `charter-release`
> skill. For **what** the kit provides today, read `README.md`.

## 1. Context

`core/rules/commits.md` already tells every project what a release *is*: a
`chore: release X.Y.Z` commit that bumps every copy of the version, and a `vX.Y.Z` tag on it,
on `main`. It says nothing about how to pick the number, what to call the release, or what its
notes say. The kit's own README answers those for the kit alone, under "Releasing".

The 3.3.1 release showed the gap. The README says the notes end with an "Upgrading" section,
and every release up to 3.3.0 used *What's new → Fixes → Upgrading*. The 3.3.1 notes opened with
"Upgrade", had no "Upgrading" section, and spent a section on the kit's own checks, which no
consumer runs. The convention existed and the release ignored it, because nothing put it in
front of whoever was cutting the release.

Two requirements follow, and they pull apart:

- **A person must be able to cut a release alone,** with no agent session. The procedure cannot
  live only in instructions an agent reads.
- **An agent cutting one must follow the same procedure,** without loading it into every
  session. A release happens about once a week, and `core` is at 139 of its 150-line budget.

## 2. Decisions

### One procedure, run by a command, documented for people, driven by a skill

| Part | Holds | Who uses it |
| --- | --- | --- |
| `charter release` | the mechanical steps: gates, the proposed number, the notes skeleton, the bump, the commit, the tag | a person, or the skill |
| README, "Releasing" | the whole procedure as a person runs it, the number, the title, the notes' sections, push and publish | a person; the skill points at it |
| `charter-release` skill | the judgement: drafting the title and notes, asking at each decision | an agent |

The mechanical steps are code, so `./check` tests them, and a person and an agent get the same
commit and tag. Picking the number and writing the notes are judgement, which code can propose
and a person decides. Push and publish stay plain `git` and `gh` commands: wrapping them adds a
layer that hides what leaves the machine.

### `charter release`

Three forms. The first two write nothing.

- **`charter release`** — runs the gates and prints, in order: the last `vX.Y.Z` tag; every
  commit since, grouped by type; the proposed number and the commits that make it so.
- **`charter release notes [<version>]`** — prints a notes skeleton to stdout: *What's new*
  with each `feat` subject, *Fixes* with each `fix` subject, *Known gaps* and *Upgrading* as
  headed placeholders. The commits it left out go to stderr, so `> notes.md` captures only the
  notes. `<version>` defaults to the proposal.
- **`charter release <X.Y.Z | patch | minor | major>`** — runs the gates, bumps every copy of
  the version, commits `chore: release X.Y.Z` with those files and nothing else, and puts a
  lightweight `vX.Y.Z` tag on the commit. It does not push.

**The gates,** each a refusal with its cause, before anything is written:

- the branch is `main`, and the working tree is clean;
- where an `origin` remote exists, `main` is level with `origin/main` after a fetch; with none,
  the command says it skipped the check;
- no plan sits in `docs/superpowers/plans/` outside `archive/`: a slice in progress does not
  ship;
- the version is greater than the last tag's, and no tag of that name exists;
- `release.verify` from `charter.json`, when set, passes. When it is not set, the command says
  the project's checks were not run.

**The proposal** reads the commit subjects since the last tag: a `!` before the colon makes it
major, a `feat` minor, anything else patch. It is a proposal. A project's "Releasing" section
can say otherwise — the kit's does, by what a consumer has to change — and the person decides.

**Every copy of the version** is `package.json`, its lockfile through
`npm version <version> --no-git-tag-version`, and each file listed in `release.files` in
`charter.json`, where the old version string is replaced exactly. A listed file without the
old version is refused: the list has gone stale. A tracked file outside the list that still
holds the old version is reported, not changed — a search for `3.3.1` also finds text that
merely mentions it.

### `charter.json` gains an optional `release` key

```json
{
  "workspaces": { ".": [] },
  "release": { "verify": "./check", "files": ["README.md"] }
}
```

Both fields are optional. `init` writes the manifest object back whole, so it keeps the key.
`sync` reads only `workspaces`. This repository sets both: `./check` is its verification command,
and the README carries the install range that `./check 60` holds to `"version"`.

### The skill is in `core`, and `sync` delivers it

The skill lives in the package at `core/skills/release/SKILL.md`. Every project has `core`, so
every project gets it; no module has to be named.

`sync` mirrors it to `.claude/skills/charter-release/SKILL.md` at the repository root. Claude
Code reads project skills from `.claude/skills/` in the starting directory and every parent up
to the repository root, so one copy at the root serves a session started in any workspace.

Only `core` has skills in this slice. A module's skills, and per-workspace skill directories,
are left to the slice that first needs one.

### The directory is `charter-release`, and the `charter-` prefix belongs to the kit

The skill's command is its directory name: `/charter-release`. A bare `release` would collide
with a skill the consuming project may already have. The prefix matches the rules mirror,
`.claude/rules/charter/`.

`sync` owns every `.claude/skills/charter-*` directory. It writes the ones the kit ships and
deletes the ones it no longer ships. A consuming project that names its own skill `charter-…`
loses it; the README says so. Nothing else under `.claude/skills/` is read, written or deleted.

### Each mirrored skill ignores itself

`sync` writes a `.gitignore` holding `*` into each skill directory it mirrors. Git then ignores
the directory, that file included, with no line in the project's `.gitignore`.

The alternative was a second line written by `init`, as `.claude/rules/charter/` is. That needs
every existing consumer to run `init` again, and one that does not commits the mirror on its
next `git add .`. A self-ignoring directory is a known pattern; pytest's cache directory does
the same. The rules mirror keeps its `init` line: moving it changes a working mechanism, outside
this slice.

### Claude may load the skill itself

The skill does not set `disable-model-invocation`. "I think it makes sense to create a new
release" should reach it as surely as `/charter-release` does. Its description names the
triggers: releasing, cutting, tagging or shipping a version. Loading it commits nothing; every
step that leaves the machine waits for the person (§3).

### This repository uses its own command and skill

The kit follows its own `core`. This repository gains the `charter.json` above and a
`SessionStart` hook running `node "$CLAUDE_PROJECT_DIR/bin/charter.mjs" sync`. With no modules,
`sync` mirrors no rule; it mirrors `core`'s skill from the working tree. The kit's `CLAUDE.md`
keeps importing `core/rules.md` directly. Its releases run `node bin/charter.mjs release`.

## 3. The procedure

The README states it for a person; the skill follows it and says, at each step, what it ran.
**Nothing is committed until the person has agreed the number, the title and the notes**, so
disagreeing never means undoing a commit.

1. **Look.** `charter release`. A failed gate stops the release and says which.
2. **The number.** The proposal, and why. The project's "Releasing" section decides over it.
   The skill asks when the two disagree or a change sits between two levels. A person who names
   another number gets that number; the skill says once if it goes against the section.
3. **Title and notes.** `charter release notes <version> > <file>`, outside the repository or
   ignored by it, then written up:
   - Title: `vX.Y.Z — <what a consumer would notice>`, lowercase after the dash, about 70
     characters at most. Not "fixes" or "improvements": name them.
   - Sections, in order: *What's new* (minor and major only), *Fixes*, *Known gaps* (only when a
     consumer can hit one), *Upgrading* (always, and always last).
   - *Upgrading* is never empty. At its least it says to move the dependency to the new version
     and that nothing else changes.
   - A `test`, `docs` or backlog commit is left out unless it changes what a consumer reads or
     runs. Nothing the consumer cannot see — the project's own checks, its plans — appears.
4. **Agree.** The skill shows the number, the title and the whole notes, and says where the
   notes file is. The person can:
   - **accept** — go on;
   - **ask for changes** in their own words — the skill redrafts and shows all of it again, as
     often as asked;
   - **write their own** — typed, or by editing the notes file and saying so. Their text is used
     as written, never reworded to fit the format. The skill may point out a gap once, such as a
     missing *Upgrading*; the person's text wins;
   - **stop** — nothing has been written, so nothing needs undoing.
5. **Cut.** `charter release <version>`: the commit and the tag, after the gates run again.
6. **Publish**, each after its own yes, showing the title and notes once more:
   `git push origin main vX.Y.Z`, then
   `gh release create vX.Y.Z --title "<title>" --notes-file <file>`. Without `gh`, or with a
   remote that is not GitHub, the skill prints the title and notes and stops. A person who stops
   here has a local commit and tag; the skill says how to drop them (`git tag -d`, `git reset`)
   and runs neither.
7. **Review**, as `core/rules/review.md` asks: the release commit's diff, the commands that ran
   and their output, and anything decided without being asked.

Publishing to a package registry is not a step. The kit itself is not published to one yet; the
backlog records it.

## 4. Checks

Written before the code, as datasets where one behaviour has many cases.

- **`85-release`**, new. Each case builds a repository in a temporary directory, with a bare
  repository as its `origin`.
  - The proposal: a table of commit subjects since the last tag and the number each set
    proposes — a `fix` alone, a `feat` among fixes, a `!`, no commits at all.
  - The gates: a table of states — another branch, a dirty tree, `main` behind `origin`, no
    `origin`, a plan outside `archive/`, a version not above the last tag, an existing tag, a
    failing `release.verify` — each refused with its cause and nothing written.
  - The bump: `package.json`, the lockfile and each listed file change, and nothing else; a
    listed file without the old version is refused; an unlisted tracked copy is reported.
  - The commit and tag: the subject passes the kit's commit-msg hook; the tag is lightweight
    and on the commit; nothing is pushed.
  - The notes: the skeleton's sections and order, `feat` and `fix` subjects in their sections,
    the rest on stderr.
- **`75-sync`** gains: the skill mirrored byte for byte to `.claude/skills/charter-release/`,
  with a `.gitignore` of `*` that `git check-ignore` confirms; a `charter-*` directory the kit
  does not ship, deleted; a project's own `release/` left alone; a symlink at or inside a
  mirrored skill directory removed as a link; nothing written on a refusal.
- **`40-rules`**, or a check beside it: every `SKILL.md` under 100 lines with a `description`,
  and a session in a fresh consumer that lists the skill — the probe below.

## 5. Unproven

- **A skill written by the first session's hook.** Claude Code watches `.claude/skills/` for
  changes, but a skills directory that did not exist when the session started needs
  `/reload-skills`. On a fresh clone, `sync` creates that directory inside `SessionStart`. Whether
  that counts as before the start is not documented. The plan probes it first, with Claude Code
  2.1.287. If the skill is missing in that session, the options are a `reloadSkills` hook output,
  if one exists, or a README line saying a fresh clone's first session needs `/reload-skills`.
- **A git-ignored skill.** Claude Code loads the git-ignored rules mirror. That it loads a
  git-ignored skill the same way is assumed, and probed with the above.
- **A lockfile in a workspace project.** `npm version` at the root updates the root lockfile.
  Whether it does so correctly with npm workspaces is assumed, and covered by one case in
  `85-release`.
- **A personal skill named `charter-release`** wins over the project's. Not handled; unlikely.

## 6. Rollout

A new command and skill are new behaviour, so this is **3.4.0**. A consumer moves the range and
runs `npm install`; the next session's hook mirrors the skill. Setting `release` in
`charter.json` is optional. *Upgrading* says so, and adds a `/reload-skills` line if the first
probe in §5 calls for one.

## 7. Not in scope

- Wrapping `git push` or `gh release create` in the command.
- Skills in modules other than `core`, and per-workspace skill directories.
- Publishing to a package registry.
- A `CHANGELOG.md`. The GitHub release holds the notes.
- Annotated or signed tags.
