# TypeScript on the backend

**A backend workspace resolves with `NodeNext`, and carries a `.js` extension on every relative
import,** even in a `.ts` file:

    import { localDate } from '../shared/nights.js'

A bundler workspace does not. An import copied in from one arrives without the extension and
breaks a build that type-checked a moment earlier.

**Request schemas are TypeBox, with `additionalProperties: false`. The package is `typebox`,
not `@sinclair/typebox`,** paired with `@fastify/type-provider-typebox`. The two publish
similar APIs under different names, and installing the wrong one produces type errors that
read as though the schema is at fault.

**The one accepted `any` is `Kysely<any>`, and only in a migration,** where Kysely's API demands it.
