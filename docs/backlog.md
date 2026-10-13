# Backlog

What is known to be wrong and not yet fixed, newest first. The rule for this file is the kit's
own [`common/rules/backlog.md`](../common/rules/backlog.md): one entry per finding, deleted by
the commit that fixes it.

Each entry also carries a priority, P1 first. The entries below came out of one review and the
prompt audits that followed it, so they are ordered by priority rather than by date.

Some entries concern the `superpowers` plugin rather than the kit. They are recorded here because
the plugin still loads in this repository and in the projects onboarded before `common` stopped
turning it on.

## Rules a tool could enforce are enforced only by prose

- Where: `common/rules/commits.md` (subject format, no body, no trailer);
  `common/rules/typescript.md` (no `any`)
- Found: 2026-10-12, while reviewing the rules against Anthropic's guidance on instruction size;
  confirmed by a consuming project's prompt audit, which found no commit-msg hook there
- Priority: P4 — more reliable than prose, and costs a new module plus its check
- Problem: Claude Code reads instructions as context, not configuration it must obey; "to block
  an action regardless of what Claude decides, use a PreToolUse hook"
  (https://code.claude.com/docs/en/memory). Nothing fails when a commit message or a type breaks
  the rule.
- Impact: a violation lands without anything failing. A commit-msg hook and a lint rule against
  explicit `any` would catch it; each is a new module with its own check, so a minor release.

## Rules for particular tasks and files load in every session

- Where: `backend/rules/http.md`, `layout.md`, `database-tests.md`;
  `common/rules/documentation.md`; the example entry in `common/rules/backlog.md`
- Found: 2026-10-12, while reviewing the rules against Anthropic's guidance on instruction size
- Priority: P5 — the largest saving, and the most disruptive; do it once the 2.2.2 trim no longer
  leaves room under the 225-line budget
- Problem: an `@` import loads at launch, so splitting rules into files only organises them; it
  saves nothing. The 59 backend lines matter only when Claude touches routes, module layout or
  database tests. The slice-docs workflow and the backlog entry format matter only while doing
  those tasks. Claude Code's docs send content like this to path-scoped rules (`.claude/rules/`
  files with `paths:` frontmatter) or skills. `@` imports can deliver neither.
- Impact: every backend session pays about a quarter of its rules budget for rules most tasks
  never use. Moving them changes how the kit is delivered:
  - consumers link the files into `.claude/rules/` and `.claude/skills/`, or the kit ships as a
    Claude Code plugin;
  - the live-session test in `checks/40-rules.sh`, which reads back `forbidden_origin` from
    `http.md`, has to change;
  - a rule moved into a skill loads only when Claude judges it relevant.

  That is a minor or major release.

## This repository does not follow its own documentation rule

- Where: the repository root; `docs/superpowers/plans/`
- Found: 2026-10-12, while auditing the rules
- Priority: P6 — low; the rules address consuming projects, and this one loads none of them
- Problem: there is no `CLAUDE.md` importing the kit's rules, no `docs/architecture.md`, and both
  executed plans still sit in `docs/superpowers/plans/` rather than `archive/`. The README fills
  the architecture role, as the specs' banners say.
- Impact: none until the kit is meant to follow itself. Decide whether it is; if so, add the
  imports and do what the rule asks.

## Two `superpowers` skills give opposite review ranges

- Where: the `superpowers` skills `requesting-code-review`, line 28, and
  `subagent-driven-development`, line 290
- Found: 2026-10-12, by the prompt audit of this repository
- Priority: P6 — the plugin's to fix; nothing here can
- Problem: the first takes `BASE_SHA=$(git rev-parse HEAD~1)`. The second says never use
  `HEAD~1`, because it drops every commit of a multi-commit task but the last.
- Impact: a review following the first leaves a multi-commit task's earlier commits unreviewed.
  Raise it with the plugin's maintainers.
