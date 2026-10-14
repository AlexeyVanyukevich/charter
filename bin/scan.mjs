// Runs axe-core over hand-written HTML files, each parsed by jsdom, under the WCAG tags the
// journeys rule names. Both come from the project, never from beside the kit: the kit declares
// no dependencies. Spec: docs/superpowers/specs/2026-10-14-html-design.md.

import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { KitError } from './modules.mjs'

const tags = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']
// They judge a whole document, so a fragment — a file with no <html> tag — always fails them.
const documentRules = ['document-title', 'html-has-lang']

function load(root) {
  const require = createRequire(join(root, 'package.json'))
  try {
    return { axeSource: readFileSync(require.resolve('axe-core'), 'utf8'), jsdom: require('jsdom') }
  } catch {
    throw new KitError('charter scan needs axe-core and jsdom in this project.', 'npm install -D axe-core jsdom')
  }
}

// A directory gives its .html files, past node_modules and dot-directories; a file gives itself.
function collect(path) {
  if (!existsSync(path)) throw new KitError(`${path} does not exist.`, 'Name an HTML file or a directory holding some.')
  if (!statSync(path).isDirectory()) return [path]
  return readdirSync(path, { withFileTypes: true })
    .filter((entry) => entry.name !== 'node_modules' && !entry.name.startsWith('.'))
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap((entry) => {
      const child = join(path, entry.name)
      if (entry.isDirectory()) return collect(child)
      return entry.name.endsWith('.html') ? [child] : []
    })
}

// Prints each violation as `<file>: <rule> — <help>` and returns how many files had one.
export async function scan(root, paths) {
  const files = paths.flatMap(collect)
  const { axeSource, jsdom } = load(root)
  let failed = 0
  for (const file of files) {
    const source = readFileSync(file, 'utf8')
    const dom = new jsdom.JSDOM(source, { runScripts: 'outside-only', virtualConsole: new jsdom.VirtualConsole() })
    try {
      dom.window.eval(axeSource)
      const fragment = !/<html[\s>]/i.test(source)
      const rules = Object.fromEntries(documentRules.map((id) => [id, { enabled: !fragment }]))
      const { violations } = await dom.window.axe.run(dom.window.document, {
        runOnly: { type: 'tag', values: tags },
        rules,
      })
      for (const { id, help, nodes } of violations) {
        console.log(`${file}: ${id} — ${help}${nodes.length > 1 ? ` (${nodes.length} elements)` : ''}`)
      }
      if (violations.length > 0) failed++
    } finally {
      dom.window.close()
    }
  }
  return failed
}
