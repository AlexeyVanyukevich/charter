# Click handlers in hand-written HTML — implementation plan

Spec: `docs/superpowers/specs/2026-10-15-click-handlers-design.md`. Each task writes its check
first, sees it fail, then builds until `./check` passes, and ends in one commit holding the check
and the code.

The backlog entry "Nothing static catches a click handler on a non-interactive element in HTML"
is this slice; task 1 deletes it. The entry "The next release must say that `react` no longer
brings plugins" is left there knowingly: this slice cuts no release, and the release that ships
it adds its own line to the same "Upgrading" section.

## Task 1 — `charter/clickable-control`

- `tests/fixture/html/`: `click-static.html`, `click-role.html`, `click-controls.html`, as spec
  §4 gives them.
- `checks/95-html.sh`: the three rows. The directory-walk expectation lists what `charter scan`
  reports, which these files do not, so it stays. See it fail.
- `stacks/html/plugin.mjs`, and `stacks/html/htmlvalidate.json` naming it, as spec §3 gives them.
- `docs/backlog.md`: the entry this slice fixes is deleted.
- The spec rides in this commit.
- Commit: `feat(html): report click handlers on elements a keyboard cannot reach`

## Task 2 — documents

- `README.md`, Markup: the rule, what it reports, how to silence one finding; the sentence that
  a click handler on a `<div>` is caught by neither tool is corrected.
- The spec's status becomes **built**; this plan moves to `docs/superpowers/plans/archive/`.
- Commit: `docs: document the clickable-control rule`
