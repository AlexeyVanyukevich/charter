# Backlog

What is known to be wrong and not yet fixed, newest first. The rule for this file is the kit's
own [`core/rules/backlog.md`](../core/rules/backlog.md): one entry per finding, deleted by
the commit that fixes it.

Each entry also carries a priority, P1 first. The entries below came out of one review and the
prompt audits that followed it, so they are ordered by priority rather than by date.

Some entries concern the `superpowers` plugin rather than the kit. They are recorded here because
the plugin still loads in this repository and in projects onboarded before the kit stopped
turning it on.

## The next release's "Upgrading" section owes three notes

- Where: the GitHub release of the next `chore: release` commit, its "Upgrading" section
- Found: 2026-10-14 and 2026-10-15, while moving the plugins, adding `charter/clickable-control`
  and giving workspaces their own sync hook
- Priority: P3
- Problem: three changes since 3.2.0 ask something of a consumer, and nothing in the release
  steps prompts whoever writes the release to say so:
  - `frontend-design` now comes from the `frontend` domain and `playwright` from the
    `playwright` stack, not from `react`. A workspace onboarded before keeps both, since `init`
    turns nothing off; one onboarded after, with `react` alone, gets neither.
  - The `html` stack's config reports `charter/clickable-control`, so a project's markup check
    can start failing on the upgrade.
  - Each workspace gets its own sync hook only when `init` is rerun for it, and the new
    `<workspace>/.claude/settings.json` has to be committed.
- Impact: a consumer upgrades without knowing a check may fail, a plugin may be missing from a
  new workspace, or sessions started in a workspace still lack `core`

## A session started in a workspace has none of the root's plugins

- Where: `bin/charter.mjs`, `init()`; `core/lib.sh`, `need_plugins`
- Found: 2026-10-15, while giving workspaces their own sync hook
- Priority: P4
- Problem: `init` turns plugins on in the root's `.claude/settings.json` only, and
  `need_plugins` installs each at project scope for the root's path. A session started in
  `server/` reads `server/.claude/settings.json` and is a project of its own, so the plugins of
  its modules should be off there. Not yet observed: inferred from where the settings and the
  installs live. Onboard a UI workspace, start `claude` in it, and run `/plugin` to see.
- Impact: a UI session started in its workspace works without `frontend-design` and
  `playwright`

## The sync hook has never run on Windows

- Where: the `SessionStart` hooks `charter init` writes, at the root and in each workspace, a
  POSIX shell line around `node "$f" sync` with
  `f="$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs"` (`$CLAUDE_PROJECT_DIR/../…` in a
  workspace)
- Found: 2026-10-13, while designing 3.0
- Priority: P2 — some consuming projects are developed on Windows
- Problem: the command relies on a POSIX shell — `"$CLAUDE_PROJECT_DIR"` expanded, `if [ -f … ]`
  understood — which depends on the shell Claude Code runs hooks through on Windows. Nothing
  here has run it there. Start a session on a Windows checkout and look for
  `.claude/rules/charter/`.
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
  still open on 2026-10-15. The installed 6.4.1 and the newest release, 7.0.0 of 2026-10-10,
  both still carry line 28. Delete this entry once a release carrying the fix is installed here.
