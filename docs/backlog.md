# Backlog

What is known to be wrong and not yet fixed, newest first. The rule for this file is the kit's
own [`core/rules/backlog.md`](../core/rules/backlog.md): one entry per finding, deleted by
the commit that fixes it.

Each entry also carries a priority, P1 first. The entries below came out of one review and the
prompt audits that followed it, so they are ordered by priority rather than by date.

Some entries concern the `superpowers` plugin rather than the kit. They are recorded here because
the plugin still loads in this repository and in projects onboarded before the kit stopped
turning it on.

## `need_plugins` may not match a Windows short-name path

- Where: `core/lib.sh`, `need_plugins`, the `real` helper that resolves `projectPath` and `.`
- Found: 2026-10-20, while making `./check 50` run on Windows; a suspicion, not an observed
  failure
- Priority: P5 — only a project reached through an 8.3 short name, such as one under a `TEMP`
  of a user name longer than eight characters
- Problem: `real` uses `fs.realpathSync`, which on Windows keeps 8.3 short names:
  `C:/PROGRA~1` resolves to `C:\PROGRA~1`, where `fs.realpathSync.native` gives
  `C:\Program Files`. If Claude Code records `projectPath` in the long form, a project opened
  through a short path never matches its own entries. What Claude Code records on Windows was
  not seen: the machine it was found on had no plugin installed.
- Impact: if so, `need_plugins` installs every enabled plugin again on each run in such a
  project, and whether `claude plugin install` tolerates that is untested.
  Confirm by installing a plugin at project scope from a short-name path and reading
  `claude plugin list --json`; the fix would be `realpathSync.native`.

## The kit needs Git Bash on Windows

- Where: the session-start hook `charter init` writes (`hookCommand` in `bin/charter.mjs`),
  `core/lib.sh`, and `init`'s run of `need_plugins` and `need_hooks`
- Found: 2026-10-20, deciding how to fix the sync hook on Windows without Git Bash; a
  requirement taken on purpose and stated in the README, under Install
- Priority: P5 — Git for Windows brings Git Bash, and most Windows developers have it
- Problem: without Git Bash, `init` stops before `need_plugins`, saying bash cannot be run;
  `./run` cannot start; and the agent runs the hook through PowerShell, which cannot parse it,
  so the session starts without its path rules and only the person sees a hook error.
- Impact: a Windows developer without Git for Windows works without path rules until they read
  the README. The hook alone can drop its shell in Claude Code's exec form: `command: "node"`
  with `args: ["-e", <program>, "node_modules/charter/bin/charter.mjs"]`, the program checking
  for the kit in Node to keep the "Run npm install" message. Probed 2026-10-20 on Windows 11
  with Claude Code 2.1.251 and the shell forced to PowerShell, it synced at the root and in a
  workspace and kept the message. It needs Claude Code 2.1.139, which added `args`: 2.1.138
  runs bare `node`, which fails reading the hook's input as a program. Worth doing together with
  `lib.sh` and `init`, since the hook alone leaves the rest needing bash.

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
