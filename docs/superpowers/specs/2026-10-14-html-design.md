# charter 3.2 — the `html` stack

Status: **built**, 2026-10-14.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-14, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** the `html` stack is shaped as it is. For **what** the kit provides
> today, read `README.md`.

---

## 1. Goal

**A workspace whose product is hand-written HTML has its markup checked element by element, and
its sessions read the `frontend` domain's accessibility rule when they edit that markup.**

The backlog entry "The `frontend` domain never reaches a project's HTML" found two gaps:

- `domains/frontend/rules/accessibility.md` loads on `src/**` and `**/*.css`. An `.html` file
  outside `src/` — the component kit's reference contracts — loads nothing.
- The rule leaves its element-level half to lint, and only `react` brings a linter that reads
  markup, and only markup written as JSX. A workspace taking `frontend typescript playwright`
  passes `aria-selected="maybe"` in `contract/tabs.html`.

## 2. What a tool can catch in a static HTML file

Probed on 2026-10-14 against six hand-written files, with html-validate 11.16.2, and with
axe-core 4.14.0 run inside jsdom 30.1.2 under the journeys rule's five WCAG tags:

| Defect | html-validate | axe-core under jsdom |
| ------ | ------------- | -------------------- |
| `aria-selected="maybe"` | — | `aria-valid-attr-value` |
| `role="buton"` | — | `aria-roles` |
| `aria-labelled="x"` | — | `aria-valid-attr` |
| `<img>` without `alt` | `wcag/h37` | `image-alt` |
| an empty `<button>` | `text-content` | `button-name` |
| an `<input>` with no label | `input-missing-label`, when turned on | `label` |
| a `<button>` with no `type` | `no-implicit-button-type` | — |
| `<div onclick>` | — | — |
| low colour contrast | — | incomplete, never a violation: jsdom has no layout |

**Neither tool is enough alone.** html-validate does not validate ARIA at all — the backlog's
own reproduction passes it under every preset. axe-core validates ARIA but not the HTML content
model, a `<button>` that submits a form by default, or a duplicate `id` outside ARIA wiring.
Both are taken.

**Nothing static catches a click handler on a non-interactive element.** `jsx-a11y` does in
JSX; in HTML the gap stays, and the keyboard-only journey `journeys.md` already requires is what
finds it. Recorded in the backlog.

## 3. Decisions

### A new stack, `html`

Both tools are JavaScript packages, and the domain names no language's tools, so they belong to
a stack. `html` is for any workspace that keeps hand-written `.html` files: the component kit's
contracts and playground beside `react`, or a static site with no framework at all. It sits
beside the other stacks the way `vitest` does: a workspace takes it for what it has.

A component kit writes `frontend typescript react html vitest playwright`; a markup-only one
writes `frontend typescript html playwright`.

### The stack brings tools, not a rule

It ships `htmlvalidate.json` and the `charter scan` command, and **no rule file**. A tool beats a
rule, and a rule saying "run the linter" is the project's `./run`, not a session's reading: the
README already says the kit does not wire lint into `./run`. The UI budget, at 220 of 225, is
untouched.

### `**/*.html` joins the accessibility rule's paths

`domains/frontend/rules/accessibility.md` gains `"**/*.html"`. Its body is unchanged, so its
line count is too: `./check 40` counts bodies, not the `paths:` block. Like `**/*.css`, the glob
also matches files under `node_modules`, which a session rarely reads.

### html-validate: `standard` and `a11y`, plus `input-missing-label`

`stacks/html/htmlvalidate.json`:

```json
{
  "extends": ["html-validate:standard", "html-validate:a11y"],
  "rules": { "input-missing-label": "error" }
}
```

Not `recommended`: it adds style rules — `doctype-style`, `void-style`, `attr-case`,
`no-inline-style`, `no-trailing-whitespace` — and the first two contradict Prettier, which
writes `<!doctype html>` and `<br />`. Style is Prettier's job, as in the oxlint configs.
`standard` is the HTML specification's content model; `a11y` is the accessibility preset.
`input-missing-label` is in neither and catches what the domain names first: a missing label.
A page Prettier formatted passes the config with no finding (probed).

A consumer's `.htmlvalidate.json` extends it by file path, as html-validate allows:

```json
{ "root": true, "extends": ["./node_modules/charter/stacks/html/htmlvalidate.json"] }
```

### `charter scan`: axe-core over static files

```bash
npx --no charter scan <file or directory…>
```

- A directory is walked for `*.html`, skipping `node_modules` and dot-directories.
- Each file is parsed by jsdom with scripts off, and axe-core runs on it with the tags
  `wcag2a`, `wcag2aa`, `wcag21a`, `wcag21aa`, `wcag22aa` — the journeys rule's.
- **A fragment is not a page.** A file with no `<html` tag is a fragment, and `document-title`
  and `html-has-lang`, which judge a whole document, are off for it. A file with one gets every
  rule.
- Each violation prints as `<file>: <rule id> — <help text>`, once per rule per file, with the
  count of nodes when there is more than one. Any violation exits 1. No violation prints nothing
  and exits 0, like `sync`.
- jsdom's own console — "Not implemented: HTMLCanvasElement" — is silenced; it is noise about
  the parser, not the markup.

### The consumer installs the tools

`checks/10-package.sh` holds that the kit declares no `dependencies` and no
`peerDependencies`: it exists so consumers stop inheriting things. So `scan` imports
`axe-core` and `jsdom` **from the project**, resolved from the working directory's
`package.json`, never from beside the kit — which is also what makes it work from the fixture,
whose kit is a symlink. Missing either, it refuses:

```text
✗ charter scan needs axe-core and jsdom in this project.
  npm install -D axe-core jsdom
```

The README tells a project to install `html-validate axe-core jsdom` with the stack, as it does
`oxlint` with the others.

### Release 3.2.0

A new module and a new command: minor.

## 4. Checks

Written before the code.

- **`./check 95`**, new — `checks/95-html.sh`, reading `tests/fixture/html/`. One dataset,
  two tools, exact output, the way `./check 90` holds oxlint:

  | File | html-validate | `charter scan` |
  | ---- | ------------- | -------------- |
  | `tabs.html` — `aria-selected="maybe"` on a typed button | `-` | `aria-valid-attr-value` |
  | `labels.html` — `<img>` without `alt`, an unlabelled `<input>` | `input-missing-label wcag/h37` | `image-alt label` |
  | `aria.html` — `role="buton"`, `aria-labelled` | `-` | `aria-roles aria-valid-attr` |
  | `button.html` — an empty, untyped `<button>` | `no-implicit-button-type text-content` | `button-name` |
  | `page.html` — a full document, Prettier-formatted | `-` | `-` |
  | `fragment.html` — a clean fragment | `-` | `-` |
  | `untitled.html` — a document with no `<head>` and no `lang` | `element-required-attributes element-required-content` | `document-title html-has-lang` |

  Plus: `scan` on the directory reports every file the rows expect, so walking is proven; and
  `scan` in a scratch project with no `node_modules` exits 1 naming `npm install -D axe-core
  jsdom`.
- **`./check 70`**: the unknown-module list gains `html`; the `apps/web` case asserts
  `apps/web/frontend/accessibility.md` carries `  - "apps/web/**/*.html"`.
- **`./check 10`**: unchanged — `stacks/html/htmlvalidate.json` is held by its "every file in a
  module ships" loop.
- The fixture's `devDependencies` gain `html-validate`, `axe-core` and `jsdom`.

## 5. Documents

The last task updates `README.md`: the opening module list, the modules table, the rules table's
`accessibility.md` paths, the sentence that `frontend` holds only beside a stack bringing an
element-level checker, a `### Markup` section under Configuration, the CLI's commands. It
deletes the backlog entry, records the `<div onclick>` gap, archives the plan, and gives this
spec the status **built**.

## 6. Not in scope

- **Moving `jsx-a11y`'s promise into `html`.** `react` keeps its own; JSX is not HTML.
- **Vue or Svelte templates.** They are neither HTML files nor JSX; their stacks bring their own
  checker (spec `2026-10-13-frontend-design.md` §3).
- **Colour contrast without a browser.** It needs layout; the journeys' axe scan in a real
  browser covers it.

## 7. Unproven

- That axe-core under jsdom reports nothing a browser would not. The probe found no false
  violation, on six files.
- That `scan` stays fast on a large tree. Each file gets a fresh jsdom window.
- That the `<html` test for a document holds for every file a project has, such as a template
  with the tag built by a server-side include.
