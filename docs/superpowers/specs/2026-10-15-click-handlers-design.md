# charter — click handlers in hand-written HTML

Status: **proposed**, 2026-10-15.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-15, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** the `html` stack checks click handlers as it does. For **what** the
> kit provides today, read `README.md`.

---

## 1. Goal

**A click handler on an element a keyboard cannot reach is reported by the `html` stack's
checks, as `jsx-a11y` reports it in JSX.**

The backlog entry "Nothing static catches a click handler on a non-interactive element in HTML"
records the gap the `html` stack left on purpose (spec `2026-10-14-html-design.md` §2): a
`<div onclick="…">` passes both html-validate and `charter scan`, and only a keyboard-only
journey that happens to reach it finds it.

## 2. What the tools report today

Probed on 2026-10-15 with html-validate 11.16.2 under the kit's config, and with `charter scan`
(axe-core 4.14.0 in jsdom 30.1.2):

| Markup | html-validate | `charter scan` |
| ------ | ------------- | -------------- |
| `<div onclick>`, `<span onmousedown>` | — | — |
| `<span role="button" onclick>`, with or without `tabindex` and `onkeydown` | `prefer-native-element` | — |
| `<button type="button" onclick>`, `<a href onclick>`, `<input type="checkbox" onclick>`, `<summary onclick>` | — | — |

So the gap is narrower than the entry says. html-validate's `a11y` preset already reports a
role that has a native element, `button` among them. What nothing reports is:

- a handler on an element with **no role** that is not a native control;
- a handler on an element with a role that has **no native element** — `tab`, `menuitem`,
  `treeitem`, `switch` — which a keyboard cannot reach without `tabindex`, or cannot use
  without a key handler.

These are the cases `jsx-a11y`'s `no-static-element-interactions`,
`interactive-supports-focus` and `click-events-have-key-events` cover in JSX.

## 3. Decisions

### A rule in html-validate, not in `charter scan`

The rule is a custom html-validate rule, shipped by the stack as an html-validate plugin, not a
check added to `charter scan`.

- It is an element-level lint, which is html-validate's job in this stack (spec
  `2026-10-14-html-design.md` §2); axe-core's is ARIA.
- It reports where html-validate reports: the same run, formatters, line and column, editor
  integrations, and `<!-- [html-validate-disable-next charter/clickable-control] -->` for the
  rare deliberate case. `charter scan` has no way to silence one finding.
- It needs no DOM: html-validate's parse is enough, so the rule costs nothing per file.

The cost is a dependency on html-validate's plugin API (`Rule`, `this.on("dom:ready")`,
`this.report`), which has been stable across its majors; and a rule of the kit's own, which a
project cannot look up in html-validate's documentation. The README documents it instead.

`charter scan` was the alternative: no plugin API, but a finding no editor shows and no comment
silences, printed under axe-core's name format.

### What the rule reports

`charter/clickable-control` looks at every element with an inline `onclick`, `onmousedown` or
`onmouseup` attribute.

- **A native control passes:** `<a href>`, `<area href>`, `<button>`, `<input>` other than
  `type="hidden"`, `<select>`, `<textarea>`, `<summary>`, `<option>`, and `<audio>` or `<video>`
  with `controls`.
- **Any other element with no `role` is reported:** "`<div>` has a click handler but is not a
  control: use a `<button>`, or another native control."
- **Any other element with a `role` is reported unless it has `tabindex` of 0 or more and an
  `onkeydown` or `onkeyup` handler:** "`<div role="tab">` has a click handler but no
  `tabindex`" or "… but no key handler". A role with a native element is also reported by
  `prefer-native-element`; the two say different things and both stand.

Handlers attached from a script (`addEventListener`) are invisible to any static check and stay
the keyboard journey's to find. `<label onclick>` is reported: a label is not a control, and its
click already reaches its control.

### How the plugin loads

`stacks/html/htmlvalidate.json` gains:

```json
{
  "extends": ["html-validate:standard", "html-validate:a11y"],
  "plugins": ["./plugin.mjs"],
  "rules": { "input-missing-label": "error", "charter/clickable-control": "error" }
}
```

html-validate resolves a relative plugin path against the config file that names it, so a
project's `.htmlvalidate.json` extending the kit's config by file path, as the README already
says, loads the rule with no change of its own and no new `exports` entry (probed).

`stacks/html/plugin.mjs` takes `Rule` from html-validate **resolved from the project**, through
`createRequire` on the working directory's `package.json`, as `charter scan` takes axe-core and
jsdom. The kit declares no dependencies, and a plugin that imported `html-validate` by name would
resolve it beside the kit's real path, which for the fixture's `file:` install is this repository,
where html-validate is not installed (probed: it fails; resolved from the project, it works).

### Release

A rule a consuming project's check starts failing on: minor, and the release's "Upgrading"
section says so.

## 4. Checks

Written before the code.

- **`./check 95`**: four files join `tests/fixture/html/`, one row each in the existing dataset,
  so each of the rule's three reports and its native-control list has a row of its own: with any
  one of them removed, a row fails. The `charter scan` column is `-` by intent; the check
  confirms it.

  | File | html-validate | `charter scan` |
  | ---- | ------------- | -------------- |
  | `click-static.html` — `<div onclick>`, `<span onmousedown>` | `charter/clickable-control` | `-` |
  | `click-role.html` — a `role="tab"` in a `tablist`, with `onclick` and `onkeydown`, no `tabindex` | `charter/clickable-control` | `-` |
  | `click-keys.html` — the same `tab` with `tabindex="0"` and no key handler | `charter/clickable-control` | `-` |
  | `click-controls.html` — `<a href>`, `<button>`, a checkbox, `<select>`, `<option>`, `<textarea>` and `<summary>` with handlers, and a `tab` with `tabindex="0"` and `onkeydown` | `-` | `-` |

  The existing rows must not move: no file there carries a handler.
- **`./check 10`**: unchanged — `stacks/html/plugin.mjs` is held by its "every file in a module
  ships" loop.

## 5. Documents

The last task updates `README.md` — the Markup section's "a click handler on a `<div>` is caught
by neither tool" and a paragraph on `charter/clickable-control`. It deletes the backlog entry,
archives the plan and gives this spec the status **built**.

## 6. Not in scope

- **Handlers attached from scripts.** No static check sees them.
- **A rule per `jsx-a11y` rule.** One rule with two messages covers the three; a project
  silences it per element.
- **Making `prefer-native-element` and this rule exclusive.** A `<span role="button" onclick>`
  gets both findings.

## 7. Unproven

- That the native-control list is complete for what hand-written markup uses. It follows HTML's
  interactive content, minus `<label>`, `<iframe>` and `<embed>`. `<area href>`, `<audio
  controls>` and `<video controls>` are in it untested: no fixture carries them.
- That html-validate keeps resolving a relative plugin path against the extended config file in
  later majors. The probe ran 11.16.2.
