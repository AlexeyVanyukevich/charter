# Backlog

What is known to be wrong and not yet fixed, newest first. The rule for this file is the kit's
own [`core/rules/backlog.md`](../core/rules/backlog.md): one entry per finding, deleted by
the commit that fixes it.

Each entry also carries a priority, P1 first. The entries below came out of one review and the
prompt audits that followed it, so they are ordered by priority rather than by date.

Some entries concern the `superpowers` plugin rather than the kit. They are recorded here because
the plugin still loads in this repository and in projects onboarded before the kit stopped
turning it on.

## `init` writes JSON that Prettier rejects

- Where: `bin/charter.mjs`, `init`, the two `JSON.stringify(…, null, 2)` writes
- Found: 2026-10-14, while adding `html` to a project already set up with three modules
- Priority: P4
- Problem: `JSON.stringify` puts every array element on its own line, and Prettier joins an
  array that fits on one. In a project with `"."` set to `frontend typescript playwright`, run
  `npx --no charter init html`, then `npx prettier --check charter.json`: it fails. The
  project's `./run check` fails with it. `.claude/settings.json` goes through the same write.
- Impact: every `init` that adds a module leaves the consuming project failing its own check
  until someone runs `prettier --write`

## Nothing static catches a click handler on a non-interactive element in HTML

- Where: `stacks/html/htmlvalidate.json`; `bin/scan.mjs`
- Found: 2026-10-14, while adding the `html` stack
- Priority: P4
- Problem: `jsx-a11y` flags `<div onClick>` in JSX, but neither html-validate nor axe-core
  flags `<div onclick="…">` in an `.html` file. Add one to `tests/fixture/html/fragment.html`
  and run `./check 95`: both tools still report nothing for it.
- Impact: in hand-written markup, the commonest generated-UI failure is found only by a
  keyboard-only journey that happens to reach it

## Accessibility is not part of a UI slice's spec

- Where: the requirement template, which the requirements release adds
- Found: 2026-10-14, deferred on purpose by `2026-10-13-frontend-design.md` §7
- Priority: P3
- Problem: the article the `frontend` domain came from asks a UI design to state focus order,
  labels, heading structure, states and error behaviour before it is built. No rule reaches a
  spec: specs live at the repository root, and `sync` prefixes a UI workspace's globs.
- Impact: those decisions are made during implementation, by whoever writes the component

## The `frontend-design` and `playwright` plugins still come from `react`

- Where: `stacks/react/plugins.json`
- Found: 2026-10-14, deferred on purpose by `2026-10-13-frontend-design.md` §7
- Priority: P5
- Problem: neither plugin is React's. `frontend-design` belongs to the `frontend` domain and the
  `playwright` plugin to the `playwright` stack, which now exists. A Vue workspace taking
  `frontend` and `playwright` would get neither.
- Impact: moving them changes what an existing `react` workspace gets from its next `init`, so
  it needs its own release note

## A session started in a workspace runs no sync and may read no `core`

- Where: `README.md` "Onboarding a project"; `checks/40-rules.sh`
- Found: 2026-10-13, in the final review of 3.0, with live sessions
- Priority: P2
- Problem: a session started in a subdirectory does not fire the root `.claude/settings.json`
  `SessionStart` hook, and in `-p` mode does not load the root `CLAUDE.md`'s `core` import.
  Start `claude` in `server/` of an onboarded repository and look for the always-on rules. The
  README now says to start at the root; nothing enforces it, and the live session in
  `checks/40-rules.sh` covers only a root session.
- Impact: a session started in a workspace silently has no synced path rules and may have no
  `core`

## The hook prints a raw Node "Cannot find module" before `npm install`

- Where: the `SessionStart` hook `charter init` writes
- Found: 2026-10-13, in the final review of 3.0
- Priority: P4
- Problem: on a fresh clone `node_modules/charter` does not exist yet, so the hook's `node`
  command fails. Clone an onboarded project, start a session before `npm install`, and read the
  hook output.
- Impact: every session start shows Node's stack-like error instead of "run npm install"

## `checks/75-sync.sh` does not assert that a dropped workspace's mirror is removed

- Where: `checks/75-sync.sh`, the case that drops a workspace from `charter.json`
- Found: 2026-10-13, in the final review of 3.0
- Priority: P5
- Problem: `server/api`'s mirror directory is not asserted gone after its workspace is dropped,
  only the other pruned paths are.
- Impact: a regression that leaves a nested workspace's mirror behind passes

## `sync` writes and prunes through symlinks

- Where: `bin/charter.mjs`, `sync()`
- Found: 2026-10-13, in the final review of 3.0
- Priority: P4
- Problem: a symlink at a wanted mirror path is written through, and a symlinked
  `.claude/rules/charter` root is pruned through. Replace the root with a link to another
  directory and run `charter sync`. The spec says `sync` touches nothing outside
  `.claude/rules/charter/`.
- Impact: files outside the mirror can be overwritten or deleted

## `init` writes before `sync` can refuse

- Where: `bin/charter.mjs`, `init()`
- Found: 2026-10-13, in the final review of 3.0
- Priority: P4
- Problem: `sync` refuses over another workspace already in `charter.json` (a missing
  directory, an unknown module) or a malformed `plugins.json`, but only after `init` has written
  `charter.json`, `CLAUDE.md`, `settings.json` and `.gitignore`; `need_hooks` then never runs.
  Record a workspace, delete its directory, run `init` for another.
- Impact: a refused `init` leaves partial changes and no commit-msg hook; each write is additive
  and re-runnable, so rerunning after the fix completes it

## No test that a project's other hook events survive `init`'s merge

- Where: `bin/charter.mjs`, `init()`; `checks/70-init.sh`
- Found: 2026-10-13, in the final review of 3.0
- Priority: P5
- Problem: the code spreads `settings.hooks` to keep other events, but no case has a
  project with, say, a `PreToolUse` hook and checks it after `init`.
- Impact: a regression that drops a project's other hooks passes

## The sync hook has never run on Windows

- Where: the `SessionStart` hook `charter init` writes, `node "$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs" sync`
- Found: 2026-10-13, while designing 3.0
- Priority: P2 — some consuming projects are developed on Windows
- Problem: the command relies on `"$CLAUDE_PROJECT_DIR"` being expanded, which depends on the
  shell Claude Code runs hooks through on Windows. Nothing here has run it there. Start a
  session on a Windows checkout and look for `.claude/rules/charter/`.
- Impact: if the variable is not expanded, `sync` never runs on that machine and no path rule
  loads there — silently, since the hook's error is shown to the person, not the model.

## Two `superpowers` skills give opposite review ranges

- Where: the `superpowers` skills `requesting-code-review`, line 28, and
  `subagent-driven-development`, line 290
- Found: 2026-10-12, by the prompt audit of this repository
- Priority: P6 — the plugin's to fix; nothing here can
- Problem: the first takes `BASE_SHA=$(git rev-parse HEAD~1)`. The second says never use
  `HEAD~1`, because it drops every commit of a multi-commit task but the last.
- Impact: a review following the first leaves a multi-commit task's earlier commits unreviewed.
  Already raised upstream: issue obra/superpowers#2403, with the fix in pull request #2381, both
  open on 2026-10-13. Delete this entry once a release carrying the fix is installed here.
