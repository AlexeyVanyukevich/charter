# charter — where a project keeps its backlog

Status: **approved**, 2026-10-30.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-30, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** the backlog rule comes in two forms chosen in `charter.json`. For
> **what** the kit provides today, read `README.md`.

---

## 1. Goal

**A project chooses where its backlog lives — GitHub issues or `docs/backlog.md` — in
`charter.json`, and every session it starts reads the rule for that choice and no other.**

The branch `feat/backlog-issues` rewrote `core/rules/backlog.md` so that every finding becomes a
GitHub issue. That suits this repository: public, on GitHub, one maintainer. It does not suit
every consuming project. A project hosted elsewhere, or with no remote, has nowhere to put a
finding; a session with no network or no `gh` login cannot follow the rule; and a project that
upgrades from 3.4.1 would find its `docs/backlog.md` contradicted by its own rules. `core` is
loaded by every project, so today one form is forced on all of them.

## 2. What is known

From the workspace-sessions spec of 2026-10-15, §2, probed with Claude Code 2.1.287:

- **A rule with no `paths:`, written into `.claude/rules/` by a `SessionStart` hook, does not
  load in the session whose hook wrote it** (its probe E). A rule that loads always cannot be
  delivered through the mirror: every first session on a fresh clone, and every session
  `./check 40` starts, would lose it.
- **A `SessionStart` hook's stdout reaches the session's context** (its probe F). This is how a
  workspace session reads `core` today.
- **The root `CLAUDE.md`'s import is fixed text.** It names `core/rules.md`, the same file in
  every project, so it cannot differ between projects.

The root hook runs `charter sync` at every session start, and `sync` already reads
`charter.json`. It is the one place that both knows the project's choice and reaches the session.

## 3. Decisions

### A `backlog` key in `charter.json`

```json
{ "workspaces": { ".": [] }, "backlog": "github" }
```

It takes `"file"` or `"github"`. Absent means `"file"` (§7). It is a key of the
repository, not of a workspace: one project has one backlog. `readManifest` refuses any other
value, so `sync` and `init` refuse it before writing anything, with the cause and the two valid
values.

### Two forms of the rule, outside `core/rules/`

`core/rules/backlog.md` moves to `core/backlog/github.md`, and `core/backlog/file.md` is added.
`core/rules.md` stops importing `backlog.md`, so the import in the root `CLAUDE.md` carries
`core` without it.

- **`file.md`** is the rule as 3.4.1 shipped it — `docs/backlog.md`, one entry per finding,
  newest first, deleted by the commit that fixes it — plus the security carve-out of the GitHub
  form: a security finding is never written into the file, which a public repository publishes on
  push.
- **`github.md`** is the rule on `feat/backlog-issues`, plus the review line that branch added to
  `core/rules/review.md`: the session review links each issue it raised. That line moves here and
  out of `review.md`. In the file form the entry is in the diff, so the review rule needs no
  addition; only the GitHub form creates something no diff shows.

Each form keeps its own example entry with its own date, `2026-09-29` for `file.md` and
`2026-09-30` for `github.md`. A session's answer to "the date of the backlog rule's example"
then names the form it read.

### `sync` prints the chosen form, at the root as well

Run from a hook, `sync` prints the chosen form to stdout, after one line naming it:

```text
charter: this project keeps its backlog in GitHub issues ("backlog": "github" in charter.json).
Its rule follows.

<core/backlog/github.md>
```

A workspace session already gets `core` this way; the form follows the other `core` rules, in
the same output. A root session, which printed nothing until now, prints this alone. When a hook
wrote a skill, the text goes in `additionalContext`, as a workspace's `core` does today. `sync`
run by hand still prints nothing.

`coreText` becomes `coreText(kit, backlog)`, so a workspace session reads the same six rules a
root session does.

### `init` asks a project on GitHub to choose

The choice is only a real one where issues can work. So `init` raises it when, after its run,
`charter.json` still has no `backlog` key and the repository's `origin` remote is on
`github.com` (`git remote get-url origin`, over HTTPS or SSH). It prints, after its other lines:

```text
? This repository is on GitHub, and its backlog is docs/backlog.md, the default. Choose:
    GitHub issues:   npx --no charter init <the same arguments> --backlog github
    keep the file:   npx --no charter init <the same arguments> --backlog file
```

`<the same arguments>` is the run's own modules and `--workspace`, so a rerun adds only the
key. Either answer writes the key, and the question stops. Off GitHub, or with no `origin`, the
file is the only form that works, and `init` says nothing.

It is a printed question, not a prompt. `init` is often run by an agent, with no terminal to
answer in; the agent reads the question and puts it to the person. A prompt would also need a
terminal emulator in `./check 70`, which Git Bash on Windows does not have.

`--backlog <file|github>` writes the key when it is absent. When `charter.json` already holds
the other value, `init` refuses rather than change it, keeping its rule of changing nothing that
is set: the person edits `charter.json`. Any other value is refused. Both refusals come before
anything is written.

### This repository chooses GitHub

`charter.json` here gets `"backlog": "github"`. Its sessions already run `sync` from a
`SessionStart` hook (`.claude/settings.json`), so they read the GitHub form with no import of
their own.

### What reverses on `feat/backlog-issues`

That branch is not merged. This slice builds on it, and undoes two of its changes:

- the review line in `core/rules/review.md` moves into `github.md`, as above;
- `charter release` leaves `docs/backlog.md` out of the stray-copy report again, because the
  file form brings the file back. The commit `fix(release): stop treating docs/backlog.md as a
  dated document` is reverted.

### Release

A new optional key, new `sync` output at the root, and no change for a project that does not set
the key: minor. The notes' *Upgrading* says that a project wanting issues sets
`"backlog": "github"` and moves its open entries to issues by hand.

## 4. Checks

Written before the code.

- **`./check 75`**: from a hook at the root, `sync` prints the file form with no key, and the
  GitHub form with `"github"`; from a workspace's hook, `core` and then the chosen form; by hand,
  nothing either way. An unknown value is refused, the message naming both valid values, and
  nothing is written.
- **`./check 70`**: `init` refuses a manifest with an unknown `backlog`, an unknown
  `--backlog`, and a `--backlog` that contradicts the manifest, each before writing.
  `--backlog github` writes the key, and a second run with it changes nothing. With an `origin`
  on `github.com`, over HTTPS and over SSH, and no key, `init` prints the question, naming the
  run's own arguments; with the key set, with an `origin` elsewhere, and with no `origin`, it does
  not.
- **`./check 40`**: the line budget counts `core/rules/` plus the longer of the two forms. The
  example-date guard becomes two: `2026-09-29` only in `core/backlog/file.md`, `2026-09-30` only
  in `core/backlog/github.md`. The scratch consumer is onboarded with `--backlog github`, and the live
  sessions, at the root and in the workspace, must answer `2026-09-30`. That proves the key is
  read and the form reaches a root session through the hook. The default form is proven by
  check 75, which needs no model.
- **`./check 85`**: the cut's fixture writes `docs/backlog.md` holding the old version again, and
  it is not reported.

## 5. Documents

The last task updates `README.md`: the Modules row for `core` ("five rules, loaded always, and
the backlog rule `charter.json` chooses"), the Rules table, the `sync` paragraph (it prints the
backlog form, at the root too), "Onboarding a project" (the key, with its default), and the
release paragraph's dated records. It archives the plan and gives this spec the status
**built**.

## 6. Not in scope

- **Moving a consuming project's entries.** Switching a project from the file to issues is a
  person's job, done once; the kit does not post issues.
- **Hosts other than GitHub.** A GitLab or Bitbucket form is a third file and a third value when
  a project needs one.
- **Open issues touching this code, left open knowingly:** "`./check 40` can fail on a session
  that read nothing, and hides why" (#43) touches the live session this slice extends, and is not
  fixed by it; the Windows issues (#42, #45) do not touch it.

## 7. Settled on 2026-10-30, at approval

1. **The default when the key is absent is `"file"`.** Every project on 3.4.1 keeps the rule it
   has; no session posts to an outside service unless the project chose that; and a project not
   on GitHub works without a setting. `"github"` as the default was rejected: it would change
   the rule under every project that upgrades.
2. **`init` does not write the key unasked; it asks where the choice is real.** Writing
   `"backlog": "file"` on every run was rejected as noise for projects with one workable form;
   staying silent was rejected because a project on GitHub would never learn it has a choice.
   The question is §3's.
