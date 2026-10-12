# Commits

[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`, with
`feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore` or `revert`.

Pick the type by the *intent* of the change, not the file extension. A test added as part of a
new endpoint belongs to that endpoint's `feat` commit; `test` is for commits whose whole point
is coverage. Scope is optional and lowercase; omit it when the change is repository-wide.

Subject: imperative mood, lowercase first letter, no trailing period, 72 characters or fewer.
Describe the change, not the file you edited.

**The subject line is the whole message. No body, no footers, no `Co-Authored-By` trailer** —
including on commits written by an agent. A change that seems to need a paragraph is a change
that wants splitting, and reasoning that outlives the commit belongs in `docs/architecture.md`
or a spec, where someone will find it.

Each commit leaves the repository compiling and tells one story. Move bottom-up through the
dependency graph — schema, then service, then HTTP — so no commit references a module that does
not exist yet. Keep a module's tests in the commit that adds the module. Keep unrelated changes
apart: a dependency bump and a bug fix are two commits.

**Merge by rebase — never squash, never a merge commit.** A squash folds commits that each tell
one story into one, and both write a subject this rule forbids. `main` is the only long-lived
branch and always passes. Work on a short-lived `<type>/<slug>` branch, typed as above, and keep
it current by rebasing onto `main`, not by merging `main` in. A release is a `vX.Y.Z` tag on
`main`, not a branch, on the `chore: release X.Y.Z` commit that bumps every copy of the version.
