# Review

**A session ends with a review of everything it changed** — one list at the end, covering
the whole session, not a report per change.

**The review shows the changes themselves, not a description of them.** A file list is an
index, not a review: the reader cannot approve what they have not been shown. Show a
modified file side by side, the old text beside the new; show a new file as its content.

Alongside the content, state:

- **What was verified** — the command that ran and the output it produced. A suite not run
  against this tree proves nothing about it.
- **What was decided without being asked** — every deviation from the plan or the
  instruction, and why. This is what a reader cannot reconstruct alone.
- **What is still unproven** — anything documented but untested, skipped, or working only
  on the machine it was written on.

**A passing suite is not approval.** Checks prove the code does what the checks say. They
cannot tell whether the work was the work that was wanted.

**Report gaps as plainly as successes.** A review that reads as uniformly successful is a
review that has been edited, and every later one is read in that light.
