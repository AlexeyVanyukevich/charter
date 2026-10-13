#!/usr/bin/env node
// Onboards a project: turns on the Claude Code plugins its sections need, in the root
// .claude/settings.json, and imports their rules into CLAUDE.md. Adds what is missing and
// changes nothing that is set. Spec: docs/superpowers/specs/2026-10-12-onboarding-design.md.

import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'
import { KitError, findModules } from './modules.mjs'
import { sync } from './sync.mjs'

const kit = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const usage = 'Usage: charter init <module…> [--workspace <dir>]  |  charter sync'
const settingsFile = join('.claude', 'settings.json')

function fail(message, hint) {
  console.error(`✗ ${message}`)
  if (hint) console.error(`  ${hint}`)
  process.exit(1)
}

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)

function parse(argv) {
  let parsed
  try {
    parsed = parseArgs({
      args: argv,
      allowPositionals: true,
      options: { workspace: { type: 'string' } },
    })
  } catch (error) {
    fail(error.message, usage)
  }
  const [command, ...sections] = parsed.positionals
  if (command === 'sync') {
    if (sections.length > 0 || parsed.values.workspace !== undefined) fail('sync takes no arguments.', usage)
    return { command }
  }
  if (command !== 'init') fail(command ? `Unknown command: ${command}.` : 'No command given.', usage)
  if (sections.length === 0) fail('Name at least one module.', usage)
  return { command, sections: [...new Set(sections)], workspace: parsed.values.workspace ?? '.' }
}

// Every refusal happens here, before anything is written.
function check({ sections, workspace }) {
  // Run anywhere else, the settings would land where no session reads them and the imports
  // would point at a node_modules that is not there. The root is where the kit is installed.
  if (!existsSync(join('node_modules', 'charter'))) {
    fail(
      'This is not the repository root: there is no node_modules/charter here.',
      'Run charter init at the repository root, where the kit is installed.',
    )
  }
  const unknown = sections.filter((name) => !modules.has(name))
  if (unknown.length > 0) {
    fail(`Unknown module: ${unknown.join(', ')}.`, `The modules are ${[...modules.keys()].join(', ')}.`)
  }
  if (sections.includes('node') && sections.includes('react')) {
    fail(
      'node and react cannot load in the same directory.',
      'Give each its own workspace: charter init node --workspace <dir>, and the same for react.',
    )
  }
  const dir = resolve(workspace)
  const fromRoot = relative(process.cwd(), dir)
  if (fromRoot === '..' || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot)) {
    fail(`${workspace} is outside this repository.`, 'Run charter init at the repository root.')
  }
  if (!existsSync(dir) || !statSync(dir).isDirectory()) {
    fail(`${workspace} is not a directory.`, 'Create the workspace first, then run this again.')
  }
  return dir
}

function readSettings() {
  if (!existsSync(settingsFile)) return {}
  let settings
  try {
    settings = JSON.parse(readFileSync(settingsFile, 'utf8'))
  } catch {
    fail(`${settingsFile} is not valid JSON.`, 'Fix it, then run this again.')
  }
  if (!isObject(settings)) {
    fail(`${settingsFile} does not hold a JSON object.`, 'Fix it, then run this again.')
  }
  if (settings.enabledPlugins !== undefined && !isObject(settings.enabledPlugins)) {
    fail(`enabledPlugins in ${settingsFile} is not an object.`, 'Fix it, then run this again.')
  }
  return settings
}

function pluginsOf(section) {
  const file = join(kit, modules.get(section), 'plugins.json')
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : []
}

const modules = findModules(kit)
const options = parse(process.argv.slice(2))
if (options.command === 'sync') {
  // The hook runs with the project root in CLAUDE_PROJECT_DIR, whatever directory the session
  // started in; by hand, sync runs at the root.
  try {
    sync(process.env.CLAUDE_PROJECT_DIR || process.cwd(), kit)
  } catch (error) {
    if (error instanceof KitError) fail(error.message, error.hint)
    throw error
  }
  process.exit(0)
}
const dir = check(options)
const settings = readSettings()

const enabled = settings.enabledPlugins ?? {}
const plugins = [...new Set(options.sections.flatMap(pluginsOf))]
const newPlugins = plugins.filter((id) => !Object.hasOwn(enabled, id))

// The import climbs from the workspace back to the root, where node_modules is hoisted.
const up = relative(dir, process.cwd()).split(sep).join('/')
// core loads from the root's CLAUDE.md; each module's index from its workspace's.
const indexOf = (name) => (name === 'core' ? 'core' : modules.get(name))
const atRoot = dir === process.cwd()
const imports = [...(atRoot ? ['core'] : []), ...options.sections]
  .filter((name) => existsSync(join(kit, indexOf(name), 'rules.md')))
  .map((name) => `@${up ? `${up}/` : ''}node_modules/charter/${indexOf(name)}/rules.md`)
const claudeFile = join(dir, 'CLAUDE.md')
const claude = existsSync(claudeFile) ? readFileSync(claudeFile, 'utf8') : ''
const present = new Set(claude.split('\n').map((line) => line.trimEnd()))
const newImports = imports.filter((line) => !present.has(line))

if (newPlugins.length > 0) {
  settings.enabledPlugins = {
    ...enabled,
    ...Object.fromEntries(newPlugins.map((id) => [id, true])),
  }
  mkdirSync('.claude', { recursive: true })
  writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`)
}
if (newImports.length > 0) {
  const block = `${newImports.join('\n')}\n`
  const head = claude.trim() === '' ? '' : `${claude}${claude.endsWith('\n') ? '' : '\n'}\n`
  writeFileSync(claudeFile, head + block)
}

const shown = relative(process.cwd(), claudeFile)
for (const id of plugins) {
  console.log(newPlugins.includes(id) ? `✓ enabled ${id}` : `  ${id} already set`)
}
for (const line of imports) {
  console.log(newImports.includes(line) ? `✓ ${shown}: ${line}` : `  ${shown} already has ${line}`)
}

// core carries the commit rule, and every project loads core, so every init installs the hook.
const lib = join(kit, 'core', 'lib.sh')
const run = spawnSync('bash', ['-c', 'source "$1" && need_plugins && need_hooks', 'charter', lib], {
  stdio: 'inherit',
})
process.exit(run.status ?? 1)
