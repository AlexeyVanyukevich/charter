# Backlog

What is known to be wrong and not yet fixed, newest first. The rule for this file is the kit's
own [`common/rules/backlog.md`](../common/rules/backlog.md): one entry per finding, deleted by
the commit that fixes it.

Each entry also carries a priority, P1 first. The entries below came out of one review and the
prompt audits that followed it, so they are ordered by priority rather than by date.

Some entries concern the `superpowers` plugin rather than the kit. They are recorded here because
the plugin still loads in this repository and in the projects onboarded before `common` stopped
turning it on.

## The README's install range stopped moving with releases

- Where: `README.md`, under Install, `"dev-kit": "^2.2.2"`
- Found: 2026-10-13, while documenting the lint configs
- Priority: P3 — harmless today, and the next release commit fixes it
- Problem: the Releasing section says the range moves with every release, patch included. The
  2.3.0 and 2.3.1 release commits changed only `package.json`, so the README still says
  `^2.2.2` against a package at 2.3.1. A caret range still installs 2.3.1.
- Impact: none until a major release, when a stale range installs the previous major without
  anything failing. Nothing checks the two versions agree. A `./check` that compares them would
  stop it recurring.

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
- Decided: 2026-10-13, deferred until the budget runs out; a backend session read 216 lines
  then. When it does, move `http.md`, `layout.md` and `database-tests.md` to path-scoped
  `.claude/rules/` files, since each maps to paths and loads predictably, and the slice-docs
  workflow and the backlog entry format to skills. `dev-kit init` links them in. First prove
  that Claude Code follows a `.claude/rules/` link into `node_modules`.

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
