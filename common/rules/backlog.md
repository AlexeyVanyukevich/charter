# Backlog

**Anything found and not fixed goes in `docs/backlog.md`** — a bug noticed on the way past, a
missing test, a document that has drifted, a shortcut taken on purpose. Not the chat, not the
commit message, not a bare `TODO`: those are read once or never, and the finding goes with them.

**Record what is outside the task; do not fix it in passing.** A fix nobody asked for is an
unreviewed change inside an unrelated commit. If it blocks the task, it is part of the task.

One entry per finding, newest first. The entry below illustrates the format; its paths are
invented:

    ## Cancelling a paid order skips the refund
    - Where: `src/modules/order/order.service.ts`, `cancel()`
    - Found: 2026-09-29, while adding order notes
    - Problem: status becomes `cancelled`; no refund row is written. Cancel any paid order.
    - Impact: every paid cancellation needs a manual refund

**Write it for someone who was not there:** what is wrong, how to see it, what it costs. "Clean
up the thing from the review" is a note to yourself, and it expires with your memory.

**Fixing an entry deletes it, in the same commit as the fix.** The file lists what is wrong
today; git remembers the rest. A code comment may point at an entry, never stand in for one.

Read the backlog before planning a slice. An entry touching the same code is either taken into
the plan or left there knowingly — never rediscovered halfway through.
