# Backlog

What is known to be wrong and not yet fixed, newest first. The rule for this file is the kit's
own [`core/rules/backlog.md`](../core/rules/backlog.md): one entry per finding, deleted by
the commit that fixes it.

Each entry also carries a priority, P1 first. The entries below came out of one review and the
prompt audits that followed it, so they are ordered by priority rather than by date.

Some entries concern the `superpowers` plugin rather than the kit. They are recorded here because
the plugin still loads in this repository and in projects onboarded before the kit stopped
turning it on.

## `./check 40`'s workspace session answered wrongly once in 24

- Where: `checks/40-rules.sh`, the live session started in `server/`
- Found: 2026-10-15, in the full run before the 3.3.0 release
- Priority: P4
- Problem: run 3, after reading `server/src/modules/issues/issue.routes.ts`, answered only
  `2026-09-29`, with no second line at all; a session without `http.md` answers `NONE` there.
  The other 23 workspace sessions that day passed, 12 of them straight after on the same tree.
  Either the model dropped the line or `http.md` did not load that once: the check keeps only
  the answer, so it cannot tell which.
- Impact: a full `./check` can fail with nothing to blame; if the rule did not load, a session
  started in a workspace sometimes works without its path rules

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
