# Backlog

What is known to be wrong and not yet fixed, newest first. The rule for this file is the kit's
own [`core/rules/backlog.md`](../core/rules/backlog.md): one entry per finding, deleted by
the commit that fixes it.

Each entry also carries a priority, P1 first. The entries below came out of one review and the
prompt audits that followed it, so they are ordered by priority rather than by date.

Some entries concern the `superpowers` plugin rather than the kit. They are recorded here because
the plugin still loads in this repository and in projects onboarded before the kit stopped
turning it on.

## `./check` fails on Windows

- Where: `checks/10-package.sh`, `50-lib.sh`, `90-lint.sh` and `95-html.sh`
- Found: 2026-10-20, running `./check` in Git Bash on Windows 11, while narrowing the Windows
  sync hook entry; the four fail the same way on the tree before that change
- Priority: P2 — nobody can verify a change on Windows, where some consuming projects are
  developed
- Problem: `./check` stops at its first check, so run each `checks/*.sh` on its own to see all
  four. 10: line 58 pastes the path `require.resolve` returns, `C:\Users\…`, into a JavaScript
  string literal, where the backslashes are read as escapes. 95: `charter scan` of a directory
  reports Windows paths, `C:\…\site\aria.html`, where the check expects others. 50:
  `need_plugins` installs a plugin the stub reports already present, perhaps because its
  `projectPath` comparison meets a Windows path. 90: oxlint lints nothing under `typescript`;
  the cause is not known. Only 10 is certainly a fault of the check alone — 50 and 95 may be
  the kit misbehaving on Windows.
- Impact: a change made on Windows cannot be verified there, and any Windows fault in
  `need_plugins` or `scan` that 50 and 95 point at reaches consuming projects unseen

## `./check 40` proves rule loading only for Claude Code running Claude

- Where: `checks/40-rules.sh`, the live session check, which calls `claude -p` on the CLI's
  default model
- Found: 2026-10-19, while asking whether the kit could serve other models
- Priority: P5 — no consuming project uses another model or tool yet
- Problem: the rule text is tool-neutral, but every proof that a session follows it comes from
  Claude Code on a Claude model. Another model behind Claude Code — GLM or Qwen through an
  Anthropic-compatible endpoint, set by `ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL` — loads the
  same files, and nothing measures whether it obeys them. Another tool — Codex, Cursor, Copilot,
  Qwen Code — reads neither `CLAUDE.md`'s import, nor `.claude/rules/`, nor the `SessionStart`
  hook, and gets no rule at all.
- Impact: another model may ignore the rules with nothing failing; another tool gets none. Start
  by running the session check against the new model, and add a writer to `sync` only for a tool
  that cannot read the files the kit already writes.

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

## The sync hook does not run on Windows without Git Bash

- Where: the `SessionStart` hooks `charter init` writes, at the root and in each workspace, a
  POSIX shell line around `node "$f" sync` with
  `f="$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs"` (`$CLAUDE_PROJECT_DIR/../…` in a
  workspace)
- Found: 2026-10-13, while designing 3.0; narrowed 2026-10-20 by running it on Windows 11 with
  Claude Code 2.1.251
- Priority: P2 — some consuming projects are developed on Windows
- Problem: with Git Bash installed, the hook works at the root and in a workspace, and its
  missing-kit message reaches the session. Without Git Bash, Claude Code runs a hook with no
  `shell` field through PowerShell, where the line is a parse error at `if [ -f …`. Run the
  hook's command with `powershell.exe -Command` to see it.
- Impact: on a Windows machine without Git Bash, `sync` never runs and no path rule loads,
  silently, since the hook's error is shown to the person, not the model. The two candidate
  fixes are a hook in exec form, `node` with `args`, which loses the "Run npm install" message,
  and a command valid in both shells, which relies on Claude Code substituting
  `${CLAUDE_PROJECT_DIR}` itself. Neither is tested.

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
