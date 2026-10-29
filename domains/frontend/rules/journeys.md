---
paths:
  - "tests/ui/**"
---
# Browser journeys

**A journey finds elements by role and accessible name, never by CSS class, DOM path or test
id.** A query for the button named Save fails the moment it becomes a `div` or loses its label
— an accessibility check on every journey, for free. An element with no role and no name is
usually the bug.

**Every page state a journey reaches is scanned with axe-core,** tagged `wcag2a`, `wcag2aa`,
`wcag21a`, `wcag21aa`, `wcag22aa`, and any violation fails the journey. A known failure is
excluded for one selector with an issue raised for it, never switched off for the suite.

**Each flow has a journey driven by the keyboard alone,** asserting where focus lands after
each step that moves it.

**A UI change's review lists, under what is still unproven, what was not tried:** a screen
reader, 200% zoom, a 320 px wide viewport. Not trying one is allowed; not saying so is not.
