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
