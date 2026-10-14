#!/usr/bin/env node
// Onboards a project and keeps its path-scoped rules current:
//
//   charter init [<module…>] [--workspace <dir>]   records the modules in charter.json, imports
//                                                  core, wires the sync hook, then syncs
//   charter sync                                   mirrors the modules' rules into the project
//   charter scan <file or directory…>              runs axe-core over static HTML files
//
// init adds what is missing and changes nothing that is set. Spec:
// docs/superpowers/specs/2026-10-13-foundation-design.md.

import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'
import { KitError, findModules } from './modules.mjs'
import { scan } from './scan.mjs'
import { manifestFile, normalizeWorkspace, readManifest, sync } from './sync.mjs'

const kit = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const usage =
  'Usage: charter init [<module…>] [--workspace <dir>]  |  charter sync  |  charter scan <file or directory…>'
const settingsFile = join('.claude', 'settings.json')
const coreImport = '@node_modules/charter/core/rules.md'
const ignored = '.claude/rules/charter/'
const hookCommand = 'node "$CLAUDE_PROJECT_DIR/node_modules/charter/bin/charter.mjs" sync'
// Their TypeScript rules contradict each other on relative imports, so no workspace takes both.
const exclusive = ['node', 'react']

function fail(message, hint) {
  console.error(`✗ ${message}`)
  if (hint) console.error(`  ${hint}`)
  process.exit(1)
}

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)

function guard(action) {
  try {
    return action()
  } catch (error) {
    if (error instanceof KitError) fail(error.message, error.hint)
    throw error
  }
}

function parse(argv) {
  let parsed
  try {
    parsed = parseArgs({ args: argv, allowPositionals: true, options: { workspace: { type: 'string' } } })
  } catch (error) {
    fail(error.message, usage)
  }
  const [command, ...names] = parsed.positionals
  if (command === 'sync') {
    if (names.length > 0 || parsed.values.workspace !== undefined) fail('sync takes no arguments.', usage)
    return { command }
  }
  if (command === 'scan') {
    if (names.length === 0 || parsed.values.workspace !== undefined) fail('scan takes the files or directories to scan.', usage)
    return { command, paths: names }
  }
  if (command !== 'init') fail(command ? `Unknown command: ${command}.` : 'No command given.', usage)
  return { command, names: [...new Set(names)], workspace: parsed.values.workspace ?? '.' }
}

// Returns the workspace's key in charter.json. Refuses before anything is written.
function check(names, workspace, modules) {
  // Run anywhere else, the settings would land where no session reads them. The root is where
  // the kit is installed.
  if (!existsSync(join('node_modules', 'charter'))) {
    fail(
      'This is not the repository root: there is no node_modules/charter here.',
      'Run charter init at the repository root, where the kit is installed.',
    )
  }
  const unknown = names.filter((name) => !modules.has(name))
  if (unknown.length > 0) {
    fail(`Unknown module: ${unknown.join(', ')}.`, `The modules are ${[...modules.keys()].join(', ')}.`)
  }
  const dir = resolve(workspace)
  const fromRoot = relative(process.cwd(), dir)
  if (fromRoot === '..' || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot)) {
    fail(`${workspace} is outside this repository.`, 'Run charter init at the repository root.')
  }
  if (!existsSync(dir) || !statSync(dir).isDirectory()) {
    fail(`${workspace} is not a directory.`, 'Create the workspace first, then run this again.')
  }
  const key = normalizeWorkspace(fromRoot.split(sep).join('/'))
  if (key === '@root') fail('A workspace cannot be named @root.', 'charter uses that name for the root.')
  return key
}

function readSettings() {
  if (!existsSync(settingsFile)) return {}
  let settings
  try {
    settings = JSON.parse(readFileSync(settingsFile, 'utf8'))
  } catch {
    fail(`${settingsFile} is not valid JSON.`, 'Fix it, then run this again.')
  }
  if (!isObject(settings)) fail(`${settingsFile} does not hold a JSON object.`, 'Fix it, then run this again.')
  if (settings.enabledPlugins !== undefined && !isObject(settings.enabledPlugins)) {
    fail(`enabledPlugins in ${settingsFile} is not an object.`, 'Fix it, then run this again.')
  }
  if (settings.hooks !== undefined && !isObject(settings.hooks)) {
    fail(`hooks in ${settingsFile} is not an object.`, 'Fix it, then run this again.')
  }
  if (settings.hooks?.SessionStart !== undefined && !Array.isArray(settings.hooks.SessionStart)) {
    fail(`hooks.SessionStart in ${settingsFile} is not a list.`, 'Fix it, then run this again.')
  }
  return settings
}

function pluginsOf(name, modules) {
  const file = join(kit, modules.get(name), 'plugins.json')
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : []
}

// Appends `line` after one blank line, unless a line already reads one of `same`.
function appendLine(file, line, same = [line]) {
  const text = existsSync(file) ? readFileSync(file, 'utf8') : ''
  if (text.split(/\r?\n/).some((existing) => same.includes(existing.trim()))) return false
  const head = text.trim() === '' ? '' : `${text}${text.endsWith('\n') ? '' : '\n'}\n`
  writeFileSync(file, `${head}${line}\n`)
  return true
}

function init({ names, workspace }) {
  const modules = guard(() => findModules(kit))
  const key = check(names, workspace, modules)
  const settings = readSettings()
  const manifest = existsSync(manifestFile) ? guard(() => readManifest(process.cwd())) : { workspaces: {} }
  const recorded = Object.keys(manifest.workspaces).find((k) => normalizeWorkspace(k) === key) ?? key
  const current = manifest.workspaces[recorded] ?? []
  const merged = [...current, ...names.filter((name) => !current.includes(name))]
  const clash = exclusive.filter((name) => merged.includes(name))
  if (clash.length > 1) {
    fail(
      `${clash.join(' and ')} cannot share a workspace.`,
      'Their TypeScript rules contradict each other. Give each its own: charter init <module…> --workspace <dir>.',
    )
  }

  // Nothing has been written up to here.
  if (!(recorded in manifest.workspaces) || merged.length > current.length) {
    manifest.workspaces[recorded] = merged
    writeFileSync(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`)
    console.log(`✓ ${manifestFile}: ${recorded} — ${merged.length > 0 ? merged.join(', ') : 'core only'}`)
  } else {
    console.log(`  ${manifestFile} already has ${recorded} with these modules`)
  }

  const enabled = settings.enabledPlugins ?? {}
  const plugins = [...new Set(merged.flatMap((name) => pluginsOf(name, modules)))]
  const newPlugins = plugins.filter((id) => !Object.hasOwn(enabled, id))
  const sessionStart = settings.hooks?.SessionStart ?? []
  const hooked = sessionStart.some(
    (entry) => Array.isArray(entry?.hooks) && entry.hooks.some((hook) => hook?.command === hookCommand),
  )
  if (newPlugins.length > 0) {
    settings.enabledPlugins = { ...enabled, ...Object.fromEntries(newPlugins.map((id) => [id, true])) }
  }
  if (!hooked) {
    settings.hooks = {
      ...settings.hooks,
      SessionStart: [...sessionStart, { hooks: [{ type: 'command', command: hookCommand }] }],
    }
  }
  if (newPlugins.length > 0 || !hooked) {
    mkdirSync('.claude', { recursive: true })
    writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`)
  }
  for (const id of plugins) console.log(newPlugins.includes(id) ? `✓ enabled ${id}` : `  ${id} already set`)
  console.log(hooked ? '  the sync hook is already set' : `✓ ${settingsFile}: SessionStart runs charter sync`)

  console.log(appendLine('CLAUDE.md', coreImport) ? `✓ CLAUDE.md: ${coreImport}` : `  CLAUDE.md already has ${coreImport}`)
  const ignoredNow = appendLine('.gitignore', ignored, [ignored, ignored.slice(0, -1)])
  console.log(ignoredNow ? `✓ .gitignore: ${ignored}` : `  .gitignore already has ${ignored}`)

  guard(() => sync(process.cwd(), kit))
  console.log('✓ synced the path-scoped rules')

  // core carries the commit rule, and every project loads core, so every init installs the hook.
  const lib = join(kit, 'core', 'lib.sh')
  const run = spawnSync('bash', ['-c', 'source "$1" && need_plugins && need_hooks', 'charter', lib], {
    stdio: 'inherit',
  })
  if (run.error) {
    fail(
      'bash could not be run',
      "init's files are written and synced, but need_plugins and need_hooks did not run: run them from ./run, or install bash (Git Bash on Windows).",
    )
  }
  process.exit(run.status ?? 1)
}

const options = parse(process.argv.slice(2))
if (options.command === 'sync') {
  // The hook runs with CLAUDE_PROJECT_DIR set to the directory the session started in, which is
  // the root when sessions start at the root, as the README says; by hand, sync runs in the
  // working directory.
  guard(() => sync(process.env.CLAUDE_PROJECT_DIR || process.cwd(), kit))
  process.exit(0)
}
if (options.command === 'scan') {
  let failed
  try {
    failed = await scan(process.cwd(), options.paths)
  } catch (error) {
    if (error instanceof KitError) fail(error.message, error.hint)
    throw error
  }
  process.exit(failed > 0 ? 1 : 0)
}
init(options)
