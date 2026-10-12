#!/usr/bin/env node
// Onboards a project: turns on the Claude Code plugins its sections need, in the root
// .claude/settings.json, and imports their rules into CLAUDE.md. Adds what is missing and
// changes nothing that is set. Spec: docs/superpowers/specs/2026-10-12-onboarding-design.md.

import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'

const kit = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const usage = 'Usage: dev-kit init <section…> [--workspace <dir>]'
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
  if (command !== 'init') fail(command ? `Unknown command: ${command}.` : 'No command given.', usage)
  if (sections.length === 0) fail('Name at least one section.', usage)
  return { sections: [...new Set(sections)], workspace: parsed.values.workspace ?? '.' }
}

// Every refusal happens here, before anything is written.
function check({ sections, workspace }) {
  // Run anywhere else, the settings would land where no session reads them and the imports
  // would point at a node_modules that is not there. The root is where the kit is installed.
  if (!existsSync(join('node_modules', 'dev-kit'))) {
    fail(
      'This is not the repository root: there is no node_modules/dev-kit here.',
      'Run dev-kit init at the repository root, where the kit is installed.',
    )
  }
  const valid = readdirSync(kit)
    .filter((name) => existsSync(join(kit, name, 'rules.md')))
    .sort()
  const unknown = sections.filter((section) => !valid.includes(section))
  if (unknown.length > 0) {
    fail(`Unknown section: ${unknown.join(', ')}.`, `The sections are ${valid.join(', ')}.`)
  }
  if (sections.includes('backend') && sections.includes('ui')) {
    fail(
      'backend and ui cannot load in the same directory.',
      'Give each its own workspace: dev-kit init backend --workspace <dir>, and the same for ui.',
    )
  }
  const dir = resolve(workspace)
  const fromRoot = relative(process.cwd(), dir)
  if (fromRoot === '..' || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot)) {
    fail(`${workspace} is outside this repository.`, 'Run dev-kit init at the repository root.')
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
  const file = join(kit, section, 'plugins.json')
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : []
}

const options = parse(process.argv.slice(2))
const dir = check(options)
const settings = readSettings()

const enabled = settings.enabledPlugins ?? {}
const plugins = [...new Set(options.sections.flatMap(pluginsOf))]
const newPlugins = plugins.filter((id) => !Object.hasOwn(enabled, id))

// The import climbs from the workspace back to the root, where node_modules is hoisted.
const up = relative(dir, process.cwd()).split(sep).join('/')
const imports = options.sections.map(
  (section) => `@${up ? `${up}/` : ''}node_modules/dev-kit/${section}/rules.md`,
)
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

const lib = join(kit, 'common', 'lib.sh')
const run = spawnSync('bash', ['-c', 'source "$1" && need_plugins', 'need_plugins', lib], {
  stdio: 'inherit',
})
process.exit(run.status ?? 1)
