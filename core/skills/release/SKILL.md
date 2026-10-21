---
description: Cut a release of this project — pick the version, agree the title and notes with the person, then commit, tag, push and publish the GitHub release. Use when the person asks to release, cut, tag, ship or publish a version, or says a release is due.
---

# Cutting a release

A release is one `chore: release X.Y.Z` commit on `main` and a `vX.Y.Z` tag on it, as core's
commit rule says. `charter release` does the mechanical part; you do the judgement; the person
decides. **Nothing is committed until the person has agreed the number, the title and the
notes.** Show every command you run.

First read the project's "Releasing" section, in `docs/architecture.md` or `README.md`, if it
has one. Where it differs from this skill, it wins — including the command that runs the kit:
`npx --no charter release` unless it names another.

## 1. Look

Run `charter release`. It prints each gate, the commits since the last tag, and a proposed
version. A `✗` gate stops the release: tell the person which and what would fix it, and fix
nothing unasked. A `–` line is a gate that could not be judged; say so.

## 2. The number

Give the proposal and why. It reads commit types only; the project's "Releasing" section
decides, usually by what a consumer has to do: nothing → patch, something new to use → minor,
something they wrote that breaks → major. Ask when the two disagree or a change sits between two
levels, naming the commits that make it so. A number the person names is the number; if it goes
against the section, say so once.

## 3. Title and notes

`charter release notes <version> > <file>`, with the file outside the repository, as in the
system's temporary directory: inside, it dirties the tree and the cut refuses. Its stderr gives
the title's form and the commits it left out. Write them up from the commits, reading a diff
where a subject does not say what a consumer sees:

- Title: `vX.Y.Z — <what a consumer would notice>`, lowercase after the dash, about 70
  characters at most. Name the changes; never "fixes" or "improvements".
- Sections, in order: *What's new* (minor and major only), *Fixes*, *Known gaps* (only when a
  consumer can hit one), *Upgrading* (always, and always last).
- An entry says what changed for a consumer and what they do about it, not which file moved.
- *Upgrading* is never empty. At its least: move the dependency to the new version; nothing
  else changes.
- Leave out `test`, `docs` and backlog commits unless they change what a consumer reads or runs.
  Nothing a consumer cannot see — the project's own checks, its plans — appears.
- Where the last release's notes follow this form, match their voice: `gh release view <tag>`.

## 4. Agree

Show the version, the title, the whole notes, and the notes file's path. Then wait. The person
can:

- **accept** — go on;
- **ask for changes** in their own words — redraft, and show all of it again, as often as asked;
- **write their own**, typed or by editing the file — use their text exactly as written, never
  reworded to fit this form. You may point out a gap once, such as a missing *Upgrading*; their
  text wins;
- **stop** — nothing has been written, so nothing needs undoing.

## 5. Cut

`charter release <version>`. It runs the gates again, bumps `package.json`, its lockfile and
each file in `charter.json`'s `release.files`, commits them alone, and tags the commit. It lists
tracked files that still hold the old version and changes none of them: read each, and tell the
person which are real copies of the version. Those mean `release.files` is incomplete; propose
the fix, and do not amend the release commit unasked.

A refusal stops the release: show it, and stop.

## 6. Publish

Each step after its own yes, showing the title and notes once more before the second:

1. `git push origin main vX.Y.Z`
2. `gh release create vX.Y.Z --title "<title>" --notes-file <file>`

Without `gh`, or with a remote that is not GitHub, print the title and notes for the person to
publish, and stop. A person who stops after the cut has a local commit and tag: say that
`git tag -d vX.Y.Z` and `git reset --hard HEAD~1` drop them, and run neither.

No step publishes to a package registry.

## 7. Review

End as core's review rule asks: the release commit's diff (`git show`), every command run and
its output, each gate that could not be judged, and everything decided without being asked.
