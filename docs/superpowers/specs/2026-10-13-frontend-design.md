# charter 3.1 — the `frontend` domain

Status: **built**, 2026-10-14.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-13, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** the `frontend` domain says what it says. For **what** the kit
> provides today, read `README.md`.

---

## 1. Goal

**A UI workspace's sessions read the accessibility rules a linter cannot enforce, at the moment
they touch UI code or browser journeys, and nothing else.**

The roadmap placed `domains/frontend/` for "UI principles (path-scoped)"; the 3.0 spec deferred
the directory until it had a first rule that holds in any language. This slice gives it two.

### The consumers

Two kinds of UI workspace take the domain, and the rules are written for both:

- **The component kit** — a shared React component library with its own repository, designed
  on 2026-10-12 and not yet built. Its design makes the markup the API: each component's
  reference HTML is a contract the React output must match, the CSS selects on native and ARIA
  states, and a playground page shows every component in every theme.
- **The applications** — three, each of which will build its UI on the component kit instead of
  its own copies of the same components.

### The source

"Why Accessibility Is An Operational Capability, Not A Feature", Smashing Magazine, June 2026
(<https://www.smashingmagazine.com/2026/06/why-accessibility-operational-capability-not-feature/>).
Its argument, as it bears on the kit:

- Accessibility is a continuous property of the system, like security, not a periodic audit.
  The WebAIM Million run it cites found detectable WCAG failures on 95.9% of home pages.
- Generated UI fails it by default: models emit `<div onClick>` because most training code
  does, and reviewers judge pixels. One generated 29-line sidebar it cites had ten failures and a
  flat accessibility tree — "same pixels."
- The remedy is to **constrain generation with persistent repository rules** and **verify
  with tooling in the pipeline**, not to ban generation. That is what this kit is.
- Its practices: lint (`jsx-a11y`), automated scans in CI, accessibility in the definition of
  done and in review, semantic elements by default, keyboard and focus as engineering concerns,
  tested widget primitives instead of hand-rolled comboboxes, menus, tabs and dialogs, and
  accessibility specified at design handoff. And: no tool replaces a screen reader or a person
  who uses one.

## 2. What a tool already enforces

**A tool beats a rule** (roadmap §2). The `react` stack turns on oxlint's `jsx-a11y` plugin.
Probed on 2026-10-13 with oxlint 1.88.0 and `stacks/react/oxlint.json`, these fire as errors:

`alt-text`, `anchor-has-content`, `anchor-is-valid`, `aria-props`, `aria-role`,
`autocomplete-valid`, `click-events-have-key-events`, `control-has-associated-label`,
`heading-has-content`, `html-has-lang`, `iframe-has-title`, `interactive-supports-focus`,
`label-has-associated-control`, `lang`, `media-has-caption`, `mouse-events-have-key-events`,
`no-access-key`, `no-aria-hidden-on-focusable`, `no-autofocus`, `no-distracting-elements`,
`no-noninteractive-tabindex`, `no-redundant-roles`, `no-static-element-interactions`,
`prefer-tag-over-role`, `role-has-required-aria-props`, `role-supports-aria-props`, `scope`,
`tabindex-no-positive`.

Every markup failure the article lists — click handlers on non-buttons, missing labels, invalid
ARIA, unlabelled icons — is among them. **The rules below repeat none of it.** No check proves
today that `jsx-a11y` fires at all, so this slice adds one (§5).

What lint cannot see is what spans more than one element or more than one moment: a widget's
keyboard model, state that changes, where focus goes, what is announced, how a page assembles.
That is the rule's whole content.

## 3. Decisions

### One domain, one new stack, one rule in `react`

| Module | File | `paths:` | Covers |
| ------ | ---- | -------- | ------ |
| `frontend` (new) | `rules/accessibility.md` | `src/**`, `**/*.css` | The target, widgets, state, focus, announcements, page structure |
| `frontend` (new) | `rules/journeys.md` | `tests/ui/**` | Role queries, the axe scan, the keyboard journey, what review states |
| `playwright` (new) | `rules/journeys.md` | `tests/ui/**` | `page.getByRole`, `@axe-core/playwright` |
| `react` | `rules/widgets.md` | `**/*.tsx` | React Aria, and which of its layers; lint findings are fixed, not silenced |

Each layer names only what is true at its level:

- **The domain** names no language's library, package or API. It says *what*: a tested
  primitive library, a query by role, an axe-core scan. It does name the web platform —
  `<dialog>`, `aria-*`, `outline` — because every frontend stack renders to it.
- **`playwright`** is JavaScript, but no framework's. Its rule holds unchanged for a React, Vue
  or Svelte workspace.
- **`react`** carries only what is React's or JSX's: React Aria and `jsx-a11y`.

A second JavaScript framework would add its own stack beside `react` — its widget library, its
template linter — and reuse both `frontend` and `playwright` as they are.

`tests/ui/` is where `core/rules/testing.md` already puts browser journeys. `**/*.css` is there
because the component kit keeps its CSS at the workspace root, outside `src/`, and the focus
indicator and state selectors live in it.

### A stack that takes `frontend` brings an element-level linter

The domain rule repeats nothing lint catches (§2), so it holds only where such a linter runs.
For `react` that is `jsx-a11y`, already in its lint config. A future framework stack meets the
same condition before it is paired with `frontend`. For Vue that is not yet free: oxlint 1.88.0
has a `vue` plugin but no accessibility one, so a `vue` stack would need
`eslint-plugin-vuejs-accessibility` beside it.

### The target is WCAG 2.2 AA

The article names no level. 2.2 is the current W3C Recommendation; AA is the level
procurement, the European Accessibility Act and most US settlements ask for. A failure against
it is a bug and goes in the backlog. It is not an enhancement for later.

### Behaviour is borrowed; look and API are owned

The first draft said composite widgets are "never written by hand". That forbade the component
kit, which is the article's own highest-leverage practice: one accessible component, reused
everywhere. What must not be written for the occasion is a widget's **behaviour** — keyboard
model, focus handling, ARIA wiring. Its markup, styling and API are the project's.

Behaviour comes from one of two tested sources:

- **The platform.** `<dialog>` opened with `showModal()` traps focus, sits in the top layer and
  returns focus to its opener; `<details>`, `<select>` and the `popover` attribute carry their
  own. Browser vendors test these against assistive technology. The component kit's Dialog is
  built this way and stays so.
- **A primitive library, which the stack names,** for what the platform lacks: tabs, menus,
  comboboxes, listboxes, date pickers.

### In the `react` stack: React Aria, through its hooks in a component kit

React Aria is the library. It was chosen over Radix UI and Headless UI, the article's other
examples, because it covers the most widgets and offers behaviour without markup. It ships in
two layers:

- `react-aria` — hooks such as `useTabList` and `useComboBox` that return props to spread onto
  elements the caller renders;
- `react-aria-components` — styled-by-you components that render their own DOM.

The component kit's design makes its reference HTML the contract. The hooks keep that contract
intact: the kit renders the contract's elements and spreads React Aria's props onto them. The
components would render React Aria's DOM, and the contract would describe somebody else's
markup. An application with no kit may use the components.

### A `playwright` stack, beside `vitest`

Browser journeys are written in Playwright whatever the framework, so their calls belong to
neither `frontend` nor `react`. They get a stack of their own, the way `vitest` is the stack for
a Vitest suite. Its rule names the calls the domain's journeys rule describes: `page.getByRole`
for the query, and `@axe-core/playwright`'s `AxeBuilder` for the scan. Both rules load on the
same files; the domain's says what a journey must prove, the stack's how it is written in
JavaScript.

The stack brings a rule and nothing else. oxlint has no Playwright plugin, so there is no lint
config to ship; one arrives with the first rule it can enforce.

A UI workspace now writes `frontend typescript react vitest playwright`.

### An application builds on its component kit

A widget the application's component kit has is used from the kit, never rewritten in the
application. A widget the kit lacks is added to the kit, as the kit's design already requires.
The rule cannot name the kit, which is the consuming project's choice, so it reads the name
from the project's own `CLAUDE.md`.

### Rules Claude "already knows" are kept here

The roadmap cuts rules that teach what Claude can derive. Focus return and live regions are
knowable, but the article's evidence is that generated UI omits them by default. A rule that
corrects a default is what the roadmap keeps.

### Release 3.1.0

A new module is minor. The roadmap's requirements release, also numbered 3.1, moves to 3.2,
and later rows shift with it. The roadmap is a record and is not edited.

## 4. The rule text

`domains/frontend/rules/accessibility.md` — 37 lines of body:

```markdown
---
paths:
  - "src/**"
  - "**/*.css"
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
```

`domains/frontend/rules/journeys.md` — 16 lines of body:

```markdown
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
excluded for one selector with a backlog entry, never switched off for the suite.

**Each flow has a journey driven by the keyboard alone,** asserting where focus lands after
each step that moves it.

**A UI change's review lists, under what is still unproven, what was not tried:** a screen
reader, 200% zoom, a 320 px wide viewport. Not trying one is allowed; not saying so is not.
```

`stacks/react/rules/widgets.md` — 9 lines of body:

```markdown
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
```

`stacks/playwright/rules/journeys.md` — 9 lines of body:

```markdown
---
paths:
  - "tests/ui/**"
---
# Browser journeys in Playwright

Find by role with `page.getByRole('button', { name: 'Save' })`, and scan with
`@axe-core/playwright`:

    const { violations } = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze()
    expect(violations).toEqual([])

`WCAG_TAGS` is one shared constant. A known failure is left out with `.exclude(selector)`.
```

### Budget

`./check 40` counts a workspace's worst case: `core` plus every rule of its modules, as if every
glob matched. A UI workspace, `frontend typescript react vitest playwright`, comes to 137 + 37
+ 16 + 9 (playwright) + 4 + 8 + 9 (react) = **220 of 225**. Moving the journeys calls out of
`react` changed no total, only where the lines live. A backend workspace is unchanged.

**Five lines are left.** The next UI rule will not fit until something moves out of the always
tier — `testing.md`, which the development release takes, is the planned candidate.

## 5. Checks

Written before the rules, as the README's "Adding a module" requires.

- **`./check 40`**: the UI worst case becomes `frontend typescript react vitest playwright`,
  and its message says so. Everything else — the `paths:` block, the 60-line cap — already
  applies to any file under `domains/*/rules/` and `stacks/*/rules/`.
- **`./check 70`**: `init frontend` is today's example of an *unknown* module; it becomes
  `init mobile`, and the expected list gains `frontend` and `playwright`. A new case runs
  `init frontend typescript react vitest playwright --workspace apps/web` and asserts that the
  synced `apps/web/frontend/accessibility.md` carries `  - "apps/web/src/**"`, and that
  `apps/web/frontend/journeys.md` and `apps/web/playwright/journeys.md` both exist. Two modules
  ship a rule of the same name for the first time; the mirror keeps them apart by module
  directory, and nothing has proved that yet.
- **`./check 90`**: a fixture `lint/a11y.tsx` with `<div onClick>`. Under `react` it fires
  exactly `jsx-a11y(click-events-have-key-events) jsx-a11y(no-static-element-interactions)`;
  under `typescript` alone, nothing. This proves the claim §2 rests on.

## 6. Documents

The last task updates `README.md`: the modules table (`frontend`, `playwright`), the rules
table, the `init` and `charter.json` examples (`web` takes `frontend` and `playwright`), the
budget sentence, and the `^3.1.0` range at release. It archives the plan and gives this spec the status **built**.

## 7. Not in scope

- **Accessibility at design handoff.** The article's third pattern — a UI slice's spec states
  focus order, labels, heading structure, states and error behaviour — belongs in the
  requirement template of the requirements release. A path rule cannot reach it: specs live at
  the repository root, and `sync` prefixes a UI workspace's globs. Recorded in the backlog.
- **Moving the `frontend-design` and `playwright` Claude Code plugins** out of the `react`
  stack — the first to `frontend`, the second to the new `playwright` stack, where they now
  belong. Moving them changes what an existing `react` workspace gets on its next `init`, so it
  is its own change. Recorded in the backlog.
- **An axe check in CI that the kit runs.** The kit has no browser and no UI to scan; the scan
  belongs to each consuming project's journeys, which the rule requires.
- **Testing with disabled users.** The article insists on it; no rule can do it. The review
  line in `journeys.md` keeps the gap visible.

## 8. Unproven

- That `jsx-a11y` under oxlint matches `eslint-plugin-jsx-a11y` rule for rule. §2 lists what
  fired, not what is missing.
- That a session in a UI workspace follows the focus and announcement rules better with them
  than without. Nothing measures rule adherence today.
- `src/**` assumes a UI workspace keeps its code in `src/`, as the backend rules do.
- That React Aria's hook props, spread onto the component kit's contract markup, leave the
  contract test passing. The hooks add `id`, `role`, `aria-*`, `tabIndex` and handlers, which
  is what the contract describes, but no component has been built that way yet.
- That `**/*.css` stays cheap. The glob also matches CSS under `node_modules`, which a session
  rarely reads.
