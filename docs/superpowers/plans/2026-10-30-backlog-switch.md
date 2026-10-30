# Where a project keeps its backlog — implementation plan

Spec: `docs/superpowers/specs/2026-10-30-backlog-switch-design.md`. Each task writes its check
first, sees it fail, then builds until `./check` passes, and ends in one commit holding the check
and the code. The branch is `feat/backlog-switch`, on top of `feat/backlog-issues`.

Open issues read before planning: "`./check 40` can fail on a session that read nothing, and
hides why" (#43) touches the live session task 1 extends; it is left open knowingly. No other
open issue touches `sync`, `init` or the backlog rule.

## Task 1 — `sync` delivers the form `charter.json` chooses

- `checks/75-sync.sh`: the cases of spec §4; the made-up kit gains `core/backlog/file.md` and
  `github.md`. `checks/40-rules.sh`: the budget, the two date guards, the per-rule cap over
  `core/backlog/`, and the consumer onboarded with `--backlog github` answering `2026-09-30`.
  See them fail.
- `core/rules/backlog.md` → `core/backlog/github.md`, its example dated `2026-09-30`, with the
  review line moved in from `core/rules/review.md`; `core/backlog/file.md` added;
  `core/rules.md` stops importing the backlog rule.
- `bin/sync.mjs`: `readManifest` validates `backlog`; `coreText(kit, backlog)`; the form's text.
  `bin/charter.mjs`: `sync` prints the form from a hook, at the root and below it.
- Commit: `feat(sync): deliver the backlog rule charter.json chooses`

## Task 2 — `init` asks a project on GitHub to choose

- `checks/70-init.sh`: the cases of spec §4. See them fail.
- `bin/charter.mjs`: `--backlog`, its refusals, the question.
- Commit: `feat(init): ask a project on github where its backlog lives`

## Task 3 — `charter release` leaves `docs/backlog.md` alone again

- `checks/85-release.sh`: the fixture writes `docs/backlog.md` again. `bin/release.mjs`: back in
  the dated list.
- Commit: `revert(release): leave docs/backlog.md out of the stray-copy report`

## Task 4 — this repository chooses GitHub

- `charter.json`: `"backlog": "github"`.
- Commit: `chore: keep this repository's backlog in github issues`

## Task 5 — documents

- `README.md`, as spec §5 gives it.
- The spec's status becomes **built**; this plan moves to `docs/superpowers/plans/archive/`.
- Commit: `docs: document where a project keeps its backlog`
