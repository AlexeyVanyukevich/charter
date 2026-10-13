# Code layout

Modules are organised by entity, and each splits into four files. The directory takes the
plural and the files the singular — `modules/issues/issue.routes.ts`:

    src/modules/<entities>/
      <entity>.routes.ts       HTTP: the route table and its hooks
      <entity>.schemas.ts      TypeBox schemas, shared by validation and the API document
      <entity>.service.ts      business rules and validation
      <entity>.repository.ts   SQL

**Not every module needs all four.** One that computes rather than stores has no repository;
one that is a single endpoint may be routes alone. Creating an empty file to complete the set
is worse than leaving it out.

A module may add a file for a rule worth isolating. Where the interesting bugs live in a
calculation, pull it out of the service as a pure function that takes values and returns
values — it is then testable without a database, which is the whole point.

**A pure computational core must not import from `db/`.** A `grep` for `db/` in such a file
comes back empty, and that is the test.

Cross-cutting helpers live in `src/shared/`, database wiring in `src/db/`, entry points at `src/`.
