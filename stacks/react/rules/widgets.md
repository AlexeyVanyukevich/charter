---
paths:
  - "**/*.tsx"
---
# Widgets in React

**The primitive library is React Aria.** A component kit that owns its markup uses the hooks
in `react-aria` — `useTabList`, `useMenu`, `useComboBox` — and spreads their props onto its own
elements. `react-aria-components` renders its own DOM, so it suits only an application with no
kit.

**A `jsx-a11y` finding is fixed, not silenced.** An `oxlint-disable` comment on one needs the
reason beside it, and is rare enough that review reads every one.
