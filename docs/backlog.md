# Backlog

What is known to be wrong and not yet fixed, newest first. The rule for this file is the kit's
own [`common/rules/backlog.md`](../common/rules/backlog.md): one entry per finding, deleted by
the commit that fixes it.

Each entry also carries a priority, P1 first. The entries below came out of one review and the
prompt audits that followed it, so they are ordered by priority rather than by date.

Some entries concern the `superpowers` plugin rather than the kit. They are recorded here because
the plugin still loads in this repository and in the projects onboarded before `common` stopped
turning it on.

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
