# Documentation

`docs/architecture.md` is **authoritative for what the project does today**. With the README it
is the whole onboarding path. Read it before changing behaviour.

Every slice gets a design document, `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, and
an implementation plan, `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`. Write and approve the
spec before touching code. A slice is a change that leaves a design decision to make; a bounded
change — one file, nothing left to decide — gets neither document. **The spec of a slice that
changes a user interface also states its accessibility:** focus order, each control's accessible
name, heading structure, every state and how it is announced, and what an error does.

Both are dated artefacts, and **neither is revised once the slice ships**:

- A **spec** becomes a decision record — read afterwards for *why* a decision went the way it
  did, never for what the system does. Give it a status line and a banner saying so.
- A **plan** moves to `docs/superpowers/plans/archive/` once executed. It is spent scaffolding,
  kept for provenance and outside the reading path.

**The last task of every slice updates `docs/architecture.md`, and, where running or deploying
changed, `README.md`. Then it archives the plan.** Not a follow-up, not a later cleanup — a
task in the plan, with the same standing as the code.

Where a spec disagrees with `docs/architecture.md`, **the living document is right and the
older one is stale.** Correct the architecture document; never send a reader to a spec to learn
what the code does.
