# charter — sessions started in a workspace

Status: **built**, 2026-10-15.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-15, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** a workspace carries its own sync hook. For **what** the kit provides
> today, read `README.md`.

---

## 1. Goal

**A session started in a workspace reads `core` and its workspace's path rules, from the first
session on a fresh clone, as a session started at the root does.**

The backlog entry "A session started in a workspace runs no sync and may read no `core`" (P2)
found it in the 3.0 review; the README now says to start at the root, and nothing enforces it.
Starting `claude` in the directory one works in is a habit, and the failure is silent.

## 2. What a workspace session loads

Probed on 2026-10-15 with Claude Code 2.1.287 in `-p` mode, in a scratch consumer holding the
packed kit, onboarded with `init backend typescript node vitest --workspace server`. Each
session read `server/src/modules/issues/issue.routes.ts` and was asked for three facts: one only
`core` holds (through the root `CLAUDE.md`'s import), one only `http.md` holds (through the
mirror), and a codeword written into the root `CLAUDE.md` itself. The mirror was deleted before
each session unless the row says otherwise, so only a hook could have written it.

| Probe | `core` | `http.md` | root `CLAUDE.md` | root hook ran |
| ----- | ------ | --------- | ---------------- | ------------- |
| A — started at the root | yes | yes | yes | yes |
| B — started in `server/` | no | no | yes | no |
| C — started in `server/`, mirror left in place | no | yes | yes | — |
| D — as C, `core` also copied into the mirror as rules with no `paths:`, import removed | yes | yes | yes | — |
| E — started at the root, a root hook writing `core` into the mirror as in D, import removed | **no** | yes | yes | yes |
| F — started in `server/`, a hook in `server/.claude/settings.json` running the root's `sync` and printing `core` | yes | yes | yes | — |
| G — as A, with F's workspace hook in place | yes | yes | yes | the workspace hook did not run |

What follows from it:

- **The root `CLAUDE.md` loads from a workspace; its `@node_modules/…` import does not** — the
  imported file lies outside the directory the session started in (B).
- **The root's `.claude/rules/` loads from a workspace**, and a `server/`-prefixed glob matches
  a file the session reads as `src/…` (C). So the mirror is already right for a workspace
  session; only the hook that writes it is missing.
- **The root's `SessionStart` hook does not run from a workspace** (B); a hook in the
  workspace's own `.claude/settings.json` does (F), and does not run from the root (G).
- **A rule with no `paths:`, written by a hook, does not load in the session whose hook wrote
  it** (E), while a path rule does — it loads at the first matching read, after the hook. Moving
  `core` out of the import and into the mirror would lose it in every first session on a fresh
  clone, and in every session `./check 40` starts.
- **A `SessionStart` hook's stdout reaches the session's context** (F).

## 3. Decisions

### Each workspace gets its own sync hook

`charter init <modules…> --workspace <dir>` also writes `<dir>/.claude/settings.json`, merged as
the root's is: other settings and hooks kept, the hook added when missing, nothing rewritten that
is already right. The command is the root hook's, pointing at the kit from the workspace:

```sh
f="$CLAUDE_PROJECT_DIR/../node_modules/charter/bin/charter.mjs"; if [ -f "$f" ]; then node "$f" sync; else echo "charter: $f is missing, so no path rule was synced. Run npm install." >&2; exit 1; fi
```

with one `..` per level of the workspace's path — `../..` for `apps/web`. The root workspace
`.` gets no second hook. This reverses one rule of 3.0's `init`, that it writes nothing into a
workspace; it is the one place a workspace session reads settings from.

### `sync` finds the root by walking up

`sync`'s root becomes the nearest directory, from `CLAUDE_PROJECT_DIR` (or the working directory)
upwards, that holds `charter.json`. A root session finds it at once, as today. A workspace
session finds the repository root, and syncs the same mirror a root session would: one mirror,
read from either place (§2, C).

### Below the root, `sync` prints `core`

When `sync` runs from a hook — `CLAUDE_PROJECT_DIR` is set — and the root it found is not
`CLAUDE_PROJECT_DIR`, the session is a workspace session the import does not reach, so `sync`
prints `core`'s rules to stdout, which the session reads (§2, F):

```text
charter: this session started in server/, below the repository root, where CLAUDE.md's import
of core does not reach. core's rules follow.

<every core/rules/*.md, in core/rules.md's order>
```

A root session, and `sync` run by hand, still print nothing on success.

### What does not change

The root hook, the import, and the mirror's layout and prefixes. A root session reads exactly
what it reads today. The README still recommends starting at the root, now as the cheaper path
rather than the only working one.

### Release

A new file a consuming project commits per workspace, and new `sync` output: minor. The
release's "Upgrading" section says to rerun `init` for each workspace.

## 4. Checks

Written before the code.

- **`./check 70`**: `init --workspace server` writes `server/.claude/settings.json` holding
  exactly the workspace hook with `..`; `--workspace apps/web` gets `../..`; a second run changes
  nothing; a workspace's own settings and hooks survive; the root workspace gets no second file.
  The assertion that `init` writes nothing into a workspace narrows to "nothing but
  `.claude/settings.json`". The workspace hook, run through `sh` with `CLAUDE_PROJECT_DIR` set to
  the workspace, syncs the root's mirror and prints `core`; without the kit it says to run
  `npm install`.
- **`./check 75`**: `sync` with `CLAUDE_PROJECT_DIR` set to a workspace writes the root's mirror
  and prints every `core` rule, preceded by the line naming the workspace; with it set to the
  root, it prints nothing; run by hand from a workspace, it syncs the root and prints nothing.
- **`./check 40`**: the scratch consumer also onboards a `server` workspace; the live session
  runs three times from `server/` as it does from the root, with the mirror deleted before each:
  `core` at once, `http.md` only in a matching file.

## 5. Documents

The last task updates `README.md` — Onboarding (the workspace's `.claude/settings.json`, what to
commit, why the root is still the recommended start) and the `sync` paragraph (it walks up; it
prints `core` below the root). It deletes the backlog entry, archives the plan, and gives this
spec the status **built**.

## 6. Not in scope

- **Plugins in a workspace session.** `enabledPlugins` lives in the root's settings, and
  `need_plugins` installs for the root's path; a workspace session gets neither. Recorded in the
  backlog when this ships.
- **Sessions started in a directory that is not a recorded workspace**, as `server/src/`. It has
  no settings of its own, so no hook runs; it reads what B reads.
- **Interactive sessions that approve the external import.** Claude Code may offer to follow the
  root's import from a workspace; one that accepts reads `core` twice.

## 7. Unproven

- That interactive sessions load the same as `-p` ones. Every probe ran `-p`.
- That a workspace with its own `node_modules/charter` — not hoisted to the root — is served:
  the hook points at the root's.
- Windows, as for the root hook.
