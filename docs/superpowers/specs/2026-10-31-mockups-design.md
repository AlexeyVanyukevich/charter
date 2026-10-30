# charter 3.6 — mockups before UI code

Status: **built**, 2026-10-31.

> **This is a decision record, not a description of the system.**
>
> It states what was decided on 2026-10-31, before any of it was built. It is not revised as
> the code moves on.
>
> Read it to learn **why** a UI slice is mocked up before it is built, and why Figma arrives as
> a module of its own. For **what** the kit provides today, read `README.md`.

---

## 1. Goal

**A slice that changes what a user sees is mocked up, and the person approves the mockup,
before its spec is approved and before any of its code is written.**

Generated UI is judged by its pixels, and today the person first sees the pixels after the code
exists. A picture costs less to change than code, and the person can judge it without running
anything. The kit already makes a UI slice's spec state its accessibility (`core`'s
documentation rule); it says nothing about how the screens should look.

### Two layers

- **The practice** — when a mockup is made, what it decides, what the spec keeps of it, how it
  is approved. It holds in any design tool, so it lives in the `frontend` domain and names none.
- **The tool** — Figma, the first one. It needs an account, a login on every machine, and a
  seat that Figma sells, so no project gets it by taking `frontend`. It is a module of its own,
  `figma`, which a workspace names to opt in.

## 2. The facts this rests on

Checked on 2026-10-31 against Figma's help centre and the plugin marketplace:

- Figma publishes a Claude Code plugin, `figma@claude-plugins-official`, listed in the
  marketplace `need_plugins` already installs from. It bundles Figma's remote MCP server
  (`https://mcp.figma.com/mcp`) and Figma's own skills for using its tools.
- The server reads designs, and — remote server only — **writes to the canvas**: an agent can
  create and edit frames from a file's components and variables.
- Each person authenticates once per machine: `/mcp`, select `figma`, Authenticate, allow access
  in the browser. A non-interactive session cannot run that flow.
- Writing outside one's drafts needs a **Full seat**. Writing is **free during a beta** and
  "will eventually become a usage-based paid feature", with no date given.
- "Code to canvas", which captures a running UI as layers, produces flat layers with no library
  connection. It turns code into a picture, which is the wrong direction for this slice.

## 3. Decisions

### The practice is a skill, not a rule

A rule loads always or by path. Neither fits:

- **By path** loads when a session reads `src/**` — after the code exists, which is too late.
  Specs live at the repository root, and `sync` prefixes a UI workspace's globs with the
  workspace's path, so a rule cannot be scoped to them either. The 3.1 spec hit the same wall
  for accessibility at design handoff.
- **Always**, in `core`, costs every project lines, backend ones included. It also does not
  fit: `./check 40` puts a UI workspace's worst case at **224 of 225** lines today.

A skill loads when the task calls for it — "design this screen", "write the spec for the
settings page" — and costs no rule budget. `frontend` ships it as `skills/mockup/`; `sync`
mirrors it as `.claude/skills/charter-mockup/`.

### `sync` mirrors the skills of the modules a project names

Today `sync` mirrors `core`'s skills alone, and `./check 40` fails if any module ships one.
From this slice on it mirrors, once at the root, the skills of `core` and of every module
any workspace in `charter.json` names. A skill whose module no workspace names any more is
deleted with the other `charter-*` directories the project no longer gets.

Skills mirror at the root because a session finds them from where it starts up to the
repository root. A skill's directory name is unique across the kit, since `charter-<name>`
holds no module; `./check 40` enforces it.

### `figma` is a stack that brings one plugin

`stacks/figma/plugins.json` lists `figma@claude-plugins-official`, and `figma` ships nothing
else. `init` turns the plugin on in the workspace's settings like any other module's, and
`need_plugins` installs it. A UI workspace writes
`frontend typescript react vitest playwright figma`.

It is a stack, not a domain, because it is one vendor's tool. `init` does not refuse `figma`
without `frontend`: the plugin works alone, and nothing contradicts.

The login cannot be automated, and the README says so: once per machine, `/mcp`, then
Authenticate.

### The mockup is assembled from the component kit

A mockup drawn freehand describes a screen the code may not be able to build. The skill has
the agent build frames from the components and variables in the component kit's design library.
Where the kit lacks a component, the agent draws it as a new kit component and the spec names
it, which matches the `frontend` rule that a missing widget is added to the kit.

### The spec keeps a picture, not only a link

A spec is frozen once it is approved; a design file keeps changing. A link alone would make the
decision record show today's design, not the one approved, and only to a reader with access to
the file. So the spec's "Mockups" section has, for each screen, the frame's link (for working)
and a PNG exported as approved (the record), at
`docs/superpowers/specs/YYYY-MM-DD-<topic>/<screen>.png`. Implementation follows the PNG.

### The mockup decides look; the spec decides behaviour

A frame shows layout, hierarchy, copy and visual states. It cannot show focus order, accessible
names or what is announced. Those stay in the spec's accessibility section, which `core`
already requires. The skill says so, so that an approved mockup is not taken as an approved
interface.

### Without a design tool, the agent asks

A project that takes `frontend` but no design-tool module still gets the skill. The skill does
not pick a tool: it tells the person no design tool is configured and asks how they want to see
the screens. An HTML fallback was considered and left out (§7).

### Release 3.6.0

A new module and a new skill: minor.

## 4. The skill text

`domains/frontend/skills/mockup/SKILL.md`, with a 100-line limit:

```markdown
---
description: Mock up a UI change before it is built — draw its screens in the project's design tool from its component kit, and have the person approve them in the slice's spec. Use when designing or specifying a slice that changes what a user sees, or when the person asks for a mockup, wireframe or design before code.
---

# Mocking up a UI change

A slice that changes what a user sees is mocked up, and the person approves the mockup, before
its spec is approved and before any of its code is written.

## What the mockup decides

Layout, hierarchy, copy and visual states, for every screen the slice changes, in each state
the spec names: empty, loading, error, success, and one long and one short value.

Not behaviour. Focus order, accessible names and announcements belong in the spec's
accessibility section, and a frame cannot show them. A mockup approved without that section
is only half approved.

## How it is drawn

In the design tool this project's modules bring: the `figma` module brings Figma, with
Figma's own skills for its tools. Follow those for the mechanics. If the project has no design
tool, say so and ask the person how they want to see the screens; do not pick one.

Build screens from the component kit's components and variables in its design library, not
from shapes drawn freehand. A screen the kit cannot build is a promise the code will break. A
component the kit lacks is drawn as a new kit component and named in the spec as one.

Ask the person which file to draw in before creating one.

## What the spec records

A "Mockups" section with, for each screen, the frame's link and a PNG of it as approved, at
`docs/superpowers/specs/YYYY-MM-DD-<topic>/<screen>.png`. The link is for working on it; the
PNG is the record. The design file keeps changing after the spec is frozen, and not every
reader can open it.

## Approval

Show the person the frames, and wait. Revise until they approve. The mockup is approved as
part of the spec. Changing the design after that is a change to the spec while the slice is
open, and a new slice once it has shipped. Build to the PNG, not to the live frame.

## The review

Under what is still unproven, the session's review says where the built screen departs from
the approved mockup, and that it was compared at all.
```

## 5. Checks

Written before the code.

- **`./check 40`**: the skill loop covers `core/skills`, `domains/*/skills` and
  `stacks/*/skills` — the 100-line limit and the description apply to each. Skill directory
  names are unique across the kit. The guard that fails when a module ships skills goes. The
  summary counts 2 skills. The real-session part also asserts that a fresh session in a
  consumer whose workspace takes `frontend` lists `charter-mockup`.
- **`./check 70`**: the expected module list gains `figma`. A case runs
  `init frontend typescript react vitest playwright figma --workspace apps/web` and asserts that
  `apps/web/.claude/settings.json` turns on `figma@claude-plugins-official` and
  `.claude/skills/charter-mockup/SKILL.md` exists at the root.
- **`./check 75`**: a probe skill under a domain is mirrored when a workspace names the domain,
  is not mirrored when none does, and is deleted once `charter.json` drops the module. A probe
  skill under `core` stays as it is tested today.
- **Nothing checks a Figma round trip.** That needs an account, a login and a seat; see §8.

## 6. Documents

The last task updates `README.md`:

- the modules table: `frontend` gains "the `mockup` skill", and a `figma` row;
- "By task": `core` and `frontend` each ship one skill;
- the `sync` paragraph: it mirrors the skills of `core` and of the modules any workspace names;
- the UI workspace examples gain `figma`;
- under onboarding, the Figma login, once per machine, and the seat it needs to write;
- the `^3.6.0` range, at release.

It archives the plan and gives this spec the status **built**.

This slice changes no user interface — the kit has none — so it has no accessibility section
of its own.

## 7. Not in scope

- **An HTML mockup when there is no design tool.** It would need a place to keep the pages, a
  way to serve them and the `html` stack's rules applied to them. That is a slice of its own if
  Figma proves the practice worth having.
- **The component kit's Figma library.** It belongs to the component kit's project, with Code
  Connect mapping its frames to code, if wanted.
- **Code to canvas**, Figma's desktop server, and any other design tool.
- **Moving accessibility at design handoff into the skill.** `core`'s documentation rule already
  has it, and it holds for every UI slice, whether or not anyone draws a mockup.

## 8. Unproven

- **That a session loads the skill when it should.** It depends on the description alone. The
  real-session check proves the skill is listed, not that "design the settings page" triggers it.
- **That `figma@claude-plugins-official` keeps its id.** It is in the marketplace on 2026-10-31.
  `need_plugins` would fail on an unknown id, which is how a rename would show.
- **The Figma round trip itself:** writing frames from a library's components, and exporting a
  PNG of a frame through the plugin. Nobody has run either from this kit.
- **The cost.** Writing to the canvas is free during Figma's beta and will be billed by usage
  later. A Full seat is needed to write outside one's drafts.
- **Headless sessions.** `claude -p`, CI and other agents that cannot run the login have no
  Figma, and the skill cannot draw there.
- **Committed PNGs.** They add binary files to each consuming project's history. Nothing
  measures how much.
