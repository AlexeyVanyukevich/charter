# Sessions started in a workspace — implementation plan

Spec: `docs/superpowers/specs/2026-10-15-workspace-sessions-design.md`. Each task writes its
check first, sees it fail, then builds until `./check` passes, and ends in one commit holding the
check and the code.

The backlog entry "A session started in a workspace runs no sync and may read no `core`" is this
slice; task 3 deletes it. "The sync hook has never run on Windows" covers the workspace hook too
and is left there knowingly; task 3 says so in it.

## Task 1 — `sync` walks up, and prints `core` below the root

- `checks/75-sync.sh`: the cases of spec §4. See them fail.
- `bin/sync.mjs`: the root search; `bin/charter.mjs`'s `sync` command prints `core` when the
  root found is not `CLAUDE_PROJECT_DIR`.
- Commit: `feat(sync): find the root from a workspace and print core there`

## Task 2 — `init` writes the workspace's hook

- `checks/70-init.sh`: the cases of spec §4. See them fail.
- `bin/charter.mjs`: the workspace settings, merged as the root's are.
- `checks/40-rules.sh`: the `server` workspace and its three live sessions.
- Commit: `feat(init): give each workspace its own sync hook`

## Task 3 — documents

- `README.md`, as spec §5 gives it.
- `docs/backlog.md`: the entry is deleted; a new one records plugins in a workspace session
  (spec §6); the Windows entry names the workspace hook too.
- The spec's status becomes **built**; this plan moves to `docs/superpowers/plans/archive/`.
- Commit: `docs: document workspace sessions`
