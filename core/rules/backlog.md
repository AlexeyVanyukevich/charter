# Backlog

**Anything found and not fixed is raised as a GitHub issue** with `gh issue create` — a bug
noticed on the way past, a missing test, a document that has drifted, a shortcut taken on
purpose. Not the chat, not the commit message, not a bare `TODO`, not a file in the repository:
those are read once or never, and the finding goes with them. **A security finding is never a
public issue:** it goes in a draft security advisory, which only maintainers can read.

**Record what is outside the task; do not fix it in passing.** A fix nobody asked for is an
unreviewed change inside an unrelated commit. If it blocks the task, it is part of the task.

One issue per finding. The issue below illustrates the format; its paths are invented:

    Title: Cancelling a paid order skips the refund
    Where: `src/modules/order/order.service.ts`, `cancel()`
    Found: 2026-09-29, while adding order notes
    Problem: status becomes `cancelled`; no refund row is written. Cancel any paid order.
    Impact: every paid cancellation needs a manual refund

**Write it for someone who was not there:** what is wrong, how to see it, what it costs. "Clean
up the thing from the review" is a note to yourself, and it expires with your memory.

**The fix's subject ends `, fixes #<number>`,** and GitHub closes the issue when the commit
reaches `main`. A code comment may point at an issue by its number, never stand in for one.

Read the open issues before planning a slice. One touching the same code is either taken into
the plan or left open knowingly — never rediscovered halfway through.
