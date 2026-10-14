// Mirrors each workspace's path-scoped rules into .claude/rules/charter/, writing the workspace's
// path in front of every pattern. Computes everything before writing anything, and prints
// nothing: a SessionStart hook's stdout goes into the session's context. Spec §3.

import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  rmdirSync,
  statSync,
  writeFileSync,
} from 'node:fs'
import { dirname, isAbsolute, join, posix, relative, resolve, sep } from 'node:path'
import { KitError, findModules } from './modules.mjs'

export const manifestFile = 'charter.json'
export const rulesDir = join('.claude', 'rules', 'charter')
const rootName = '@root'

export function normalizeWorkspace(key) {
  const cleaned = posix.normalize(key.replaceAll('\\', '/')).replace(/\/+$/, '')
  return cleaned === '' ? '.' : cleaned
}

export function readManifest(root) {
  const file = join(root, manifestFile)
  if (!existsSync(file)) {
    throw new KitError(`There is no ${manifestFile} at ${root}.`, 'Run npx charter init at the repository root.')
  }
  let manifest
  try {
    manifest = JSON.parse(readFileSync(file, 'utf8'))
  } catch {
    throw new KitError(`${manifestFile} is not valid JSON.`, 'Fix it, then run this again.')
  }
  const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)
  if (!isObject(manifest) || !isObject(manifest.workspaces)) {
    throw new KitError(
      `${manifestFile} has no "workspaces" object.`,
      'It reads { "workspaces": { ".": ["<module>", …] } }.',
    )
  }
  for (const [key, names] of Object.entries(manifest.workspaces)) {
    if (!Array.isArray(names) || names.some((name) => typeof name !== 'string')) {
      throw new KitError(`In ${manifestFile}, workspace "${key}" is not a list of module names.`)
    }
  }
  return manifest
}

// The nearest directory from start upwards that holds charter.json: the root itself for a session
// started there, the repository root for one started in a workspace.
export function findRoot(start) {
  let dir = resolve(start)
  for (;;) {
    if (existsSync(join(dir, manifestFile))) return dir
    const parent = dirname(dir)
    if (parent === dir) {
      throw new KitError(
        `There is no ${manifestFile} in ${start} or any directory above it.`,
        'Run npx charter init at the repository root.',
      )
    }
    dir = parent
  }
}

// core's rules in its index's order, for a session the root CLAUDE.md's import does not reach.
export function coreText(kit) {
  const index = readFileSync(join(kit, 'core', 'rules.md'), 'utf8')
  const files = [...index.matchAll(/^@(rules\/\S+\.md)\r?$/gm)].map((match) => match[1])
  return files.map((file) => readFileSync(join(kit, 'core', file), 'utf8').trimEnd()).join('\n\n')
}

// The block's form is fixed so that no YAML parser is needed: ---, paths:, one   - "<pattern>"
// line or more, then ---. ./check holds every rule outside core/ to it.
function parseRule(text, name) {
  const lines = text.split(/\r?\n/)
  const patterns = []
  let i = 2
  while (i < lines.length && /^ {2}- "[^"]+"$/.test(lines[i])) {
    patterns.push(lines[i].slice(5, -1))
    i++
  }
  if (lines[0] !== '---' || lines[1] !== 'paths:' || patterns.length === 0 || lines[i] !== '---') {
    throw new KitError(
      `${name} does not open with a paths: block.`,
      'A rule outside core/ starts with ---, paths:, one   - "<pattern>" line per pattern, then ---.',
    )
  }
  // The body is the original bytes after the closing line and its own terminator, unchanged.
  let offset = 0
  for (let k = 0; k <= i; k++) {
    offset += lines[k].length
    if (text.startsWith('\r\n', offset)) offset += 2
    else if (text.startsWith('\n', offset)) offset += 1
  }
  return { patterns, body: text.slice(offset) }
}

// init passes the manifest it is about to write, so that whatever sync would refuse is refused
// before init writes anything.
export function plan(root, kit, manifest = readManifest(root)) {
  const modules = findModules(kit)
  const wanted = new Map()
  for (const [key, names] of Object.entries(manifest.workspaces)) {
    // Absolute keys are refused before normalizing, which would turn "/" into the root.
    const slashed = key.replaceAll('\\', '/')
    if (slashed.startsWith('/') || /^[A-Za-z]:/.test(slashed)) {
      throw new KitError(`Workspace "${key}" is outside the repository.`, 'Name it by its path from the root.')
    }
    const workspace = normalizeWorkspace(key)
    if (workspace === rootName) {
      throw new KitError(`A workspace cannot be named ${rootName}.`, 'charter uses that name for the root.')
    }
    if (workspace === '..' || workspace.startsWith('../') || isAbsolute(workspace)) {
      throw new KitError(`Workspace "${key}" is outside the repository.`, 'Name it by its path from the root.')
    }
    const dir = join(root, workspace)
    if (!existsSync(dir) || !statSync(dir).isDirectory()) {
      throw new KitError(`Workspace "${key}" is not a directory.`, `Create it, or remove it from ${manifestFile}.`)
    }
    const out = workspace === '.' ? rootName : workspace
    for (const name of names) {
      const home = modules.get(name)
      if (!home) {
        throw new KitError(
          `Unknown module "${name}" in ${manifestFile}.`,
          `The modules are ${[...modules.keys()].join(', ')}.`,
        )
      }
      const rules = join(kit, home, 'rules')
      if (!existsSync(rules)) continue
      for (const file of readdirSync(rules).filter((f) => f.endsWith('.md')).sort()) {
        const { patterns, body } = parseRule(readFileSync(join(rules, file), 'utf8'), `${home}/rules/${file}`)
        const prefixed = patterns.map((pattern) => (workspace === '.' ? pattern : `${workspace}/${pattern}`))
        const content = `---\npaths:\n${prefixed.map((p) => `  - "${p}"`).join('\n')}\n---\n${body}`
        wanted.set(join(rulesDir, ...out.split('/'), name, file), content)
      }
    }
  }
  return wanted
}

const isLink = (path) => lstatSync(path, { throwIfNoEntry: false })?.isSymbolicLink() ?? false

export function sync(root, kit) {
  const wanted = plan(root, kit)
  // A symlink in the mirror, the mirror itself included, is removed as a link and never followed:
  // writing or pruning through it would reach outside .claude/rules/charter/.
  const mirror = join(root, rulesDir)
  if (isLink(mirror)) rmSync(mirror)
  for (const [path, content] of wanted) {
    const file = join(root, path)
    let at = mirror
    for (const part of relative(mirror, file).split(sep)) {
      at = join(at, part)
      if (isLink(at)) rmSync(at)
    }
    if (existsSync(file) && readFileSync(file, 'utf8') === content) continue
    mkdirSync(dirname(file), { recursive: true })
    writeFileSync(file, content)
  }
  prune(join(root, rulesDir), root, wanted)
}

// Deletes every file under dir the mirror no longer holds, then each directory that leaves empty.
function prune(dir, root, wanted) {
  if (!existsSync(dir)) return
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry)
    // lstat: a symlink is removed as a link, never followed out of the mirror.
    if (lstatSync(path).isDirectory()) {
      prune(path, root, wanted)
      if (readdirSync(path).length === 0) rmdirSync(path)
    } else if (!wanted.has(relative(root, path))) {
      rmSync(path)
    }
  }
}
