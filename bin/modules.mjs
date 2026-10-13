// The modules a project's charter.json can name: every directory under domains/ and stacks/.
// core/ is not one — it loads in every project through the CLAUDE.md import.

import { existsSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

// A refusal the person can act on: the message says what is wrong, the hint what to do.
export class KitError extends Error {
  constructor(message, hint) {
    super(message)
    this.hint = hint
  }
}

export function findModules(kit) {
  const modules = new Map()
  for (const group of ['domains', 'stacks']) {
    const dir = join(kit, group)
    if (!existsSync(dir)) continue
    for (const name of readdirSync(dir).sort()) {
      if (!statSync(join(dir, name)).isDirectory()) continue
      if (modules.has(name)) {
        throw new KitError(
          `The module ${name} appears in both ${modules.get(name)} and ${group}/${name}.`,
          'Module names must be unique: charter.json names a module, not its directory.',
        )
      }
      modules.set(name, `${group}/${name}`)
    }
  }
  return modules
}
