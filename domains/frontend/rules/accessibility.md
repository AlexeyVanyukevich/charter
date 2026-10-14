---
paths:
  - "src/**"
  - "**/*.css"
  - "**/*.html"
---
# Accessibility

**The interface meets WCAG 2.2 at level AA, and a failure against it is a bug.** It goes in
the backlog like any other, not on a list of improvements for later.

Lint checks one element at a time: a `div` with a click handler, a missing `alt`, an invalid
ARIA attribute. What it cannot see is below, and it is where generated UI fails — the pixels
match and the accessibility tree is empty.

**A composite widget's behaviour — keyboard model, focus, ARIA wiring — comes from the
platform or the primitive library the stack names, never from code written for the occasion.**
Its markup, styling and API are the project's own. `<dialog>` with `showModal()`, `<details>`
and `popover` are the platform's; tabs, menus, comboboxes and listboxes are the library's. A
hand-rolled one passes lint and fails at the keyboard.

**An application uses the component kit its `CLAUDE.md` names.** A widget the kit has is
never rewritten in the application; one it lacks is added to the kit.

**State lives on the element, not only in the styling.** Open, selected, pressed, current,
invalid, busy: each is the native property or `aria-*` attribute, set from the same value that
drives the visuals. A chevron that turns while `aria-expanded` does not is closed to a screen
reader.

**Focus is moved on purpose, never lost.**

- Opening a dialog or menu moves focus into it; closing returns focus to what opened it.
- Removing the focused element moves focus to its nearest neighbour, or its list.
- A client-side route change moves focus to the new page's `h1`.
- `outline: none` comes with a replacement indicator at least as visible.

**Outcomes are announced, not only shown.** A field's error is tied to it with `aria-invalid`
and `aria-describedby`; a submit that fails moves focus to the first error or to a summary. A
result that arrives without navigation goes through a live region that was in the page before
the message was written into it. Colour is never the only signal.

**A page has one `h1`, headings that skip no level, and a `main` landmark.** Every component can
be valid while the page assembled from them is not.
