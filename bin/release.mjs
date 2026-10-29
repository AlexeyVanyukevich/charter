// charter release: the gates a release must pass, the commits since the last tag, and the
// version they propose; a skeleton of the release's notes; and the cut — every copy of the
// version bumped, one commit, a tag, never a push. Only the cut writes, and only once every gate
// and refusal has passed. Spec: docs/superpowers/specs/2026-10-21-release-design.md.

import { execFileSync, spawnSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { KitError } from './modules.mjs'
import { manifestFile } from './sync.mjs'

const git = (root, ...args) =>
  execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()
const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)
const plans = 'docs/superpowers/plans'

export function repositoryRoot(cwd) {
  try {
    return git(cwd, 'rev-parse', '--show-toplevel')
  } catch {
    throw new KitError('This is not a git repository.', "Run charter release in the project's repository.")
  }
}

// charter.json's optional release key: { verify, files }, both optional too.
export function releaseSettings(root) {
  const file = join(root, manifestFile)
  if (!existsSync(file)) return {}
  let manifest
  try {
    manifest = JSON.parse(readFileSync(file, 'utf8'))
  } catch {
    throw new KitError(`${manifestFile} is not valid JSON.`, 'Fix it, then run this again.')
  }
  const release = manifest?.release
  if (release === undefined) return {}
  const shape = 'It reads "release": { "verify": "<command>", "files": ["<path>", …] }, both optional.'
  if (!isObject(release)) throw new KitError(`"release" in ${manifestFile} is not an object.`, shape)
  if (release.verify !== undefined && typeof release.verify !== 'string') {
    throw new KitError(`release.verify in ${manifestFile} is not a string.`, shape)
  }
  if (release.files !== undefined && (!Array.isArray(release.files) || release.files.some((f) => typeof f !== 'string'))) {
    throw new KitError(`release.files in ${manifestFile} is not a list of paths.`, shape)
  }
  return release
}

const semver = /^(\d+)\.(\d+)\.(\d+)$/
const compare = (a, b) => {
  const [x, y] = [a, b].map((v) => v.match(semver).slice(1).map(Number))
  return x[0] - y[0] || x[1] - y[1] || x[2] - y[2]
}

export function bump(version, level) {
  const [major, minor, patch] = version.match(semver).slice(1).map(Number)
  if (level === 'major') return `${major + 1}.0.0`
  if (level === 'minor') return `${major}.${minor + 1}.0`
  return `${major}.${minor}.${patch + 1}`
}

// The newest vX.Y.Z tag reachable from HEAD, or null before the first release.
function lastTag(root) {
  const tags = git(root, 'tag', '--merged', 'HEAD', '--list', 'v*')
    .split('\n')
    .filter((tag) => semver.test(tag.slice(1)))
  return tags.sort((a, b) => compare(b.slice(1), a.slice(1)))[0] ?? null
}

function packageVersion(root) {
  const file = join(root, 'package.json')
  const version = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')).version : undefined
  return typeof version === 'string' && semver.test(version) ? version : '0.0.0'
}

const conventional = /^(\w+)(\([^)]*\))?(!)?: /
const kind = (subject) => {
  const match = subject.match(conventional)
  return { type: match?.[1] ?? null, breaking: Boolean(match?.[3]) }
}

// Everything the person, or the skill, decides from: the base version, the commits since it in
// the order they are shown — breaking, feat, fix, the rest — and the proposal.
export function survey(root) {
  const tag = lastTag(root)
  const previous = tag ? tag.slice(1) : packageVersion(root)
  const log = git(root, 'log', '--format=%s', tag ? `${tag}..HEAD` : 'HEAD')
  const subjects = log === '' ? [] : log.split('\n')
  const rank = (subject) => {
    const { type, breaking } = kind(subject)
    return breaking ? 0 : type === 'feat' ? 1 : type === 'fix' ? 2 : 3
  }
  const ordered = subjects.map((subject, i) => ({ subject, i })).sort((a, b) => rank(a.subject) - rank(b.subject) || a.i - b.i)
  const commits = ordered.map(({ subject }) => subject)
  const breaking = commits.filter((subject) => kind(subject).breaking)
  const features = commits.filter((subject) => kind(subject).type === 'feat')
  const level = breaking.length > 0 ? 'major' : features.length > 0 ? 'minor' : 'patch'
  const because = level === 'major' ? breaking : level === 'minor' ? features : []
  return { tag, previous, commits, level, because, proposed: bump(previous, level) }
}

// Each gate is { ok: true | false | null, text }: null is a gate that could not be judged here
// and says why. release.verify runs only when every other gate passed; its output goes to stderr.
export function gates(root, settings, commits) {
  const results = []
  const gate = (ok, text) => results.push({ ok, text })
  const branch = git(root, 'branch', '--show-current')
  gate(branch === 'main', branch === 'main' ? 'on main' : `on main — this is ${branch || 'a detached HEAD'}`)
  const dirty = git(root, 'status', '--porcelain')
  gate(dirty === '', dirty === '' ? 'the working tree is clean' : 'the working tree is clean — commit or stash what git status lists')
  if (git(root, 'remote').split('\n').includes('origin')) {
    try {
      git(root, 'fetch', '-q', 'origin', 'main')
      const level = git(root, 'rev-parse', 'HEAD') === git(root, 'rev-parse', 'origin/main')
      gate(level, level ? 'level with origin/main' : 'level with origin/main — pull or push until it is')
    } catch (error) {
      gate(false, `level with origin/main — fetching it failed: ${String(error.stderr ?? error.message).trim()}`)
    }
  } else {
    gate(null, 'no origin remote: main was not compared with it')
  }
  const open = existsSync(join(root, plans))
    ? readdirSync(join(root, plans)).filter((entry) => statSync(join(root, plans, entry)).isFile())
    : []
  gate(
    open.length === 0,
    open.length === 0
      ? `no plan outside ${plans}/archive/`
      : `no plan outside ${plans}/archive/ — a slice is in progress: ${open.join(', ')}`,
  )
  gate(commits.length > 0, commits.length > 0 ? 'something to release' : 'something to release — no commit since the last tag')
  if (!settings.verify) {
    gate(null, `no release.verify in ${manifestFile}: the project's checks were not run`)
  } else if (results.some((result) => result.ok === false)) {
    gate(null, 'release.verify not run: a gate above failed')
  } else {
    const run = spawnSync('bash', ['-c', settings.verify], { cwd: root, stdio: ['ignore', 2, 2] })
    gate(run.status === 0, run.status === 0 ? 'release.verify passed' : `release.verify failed — ${settings.verify} exited ${run.status ?? run.error?.message}`)
  }
  return results
}

const mark = ({ ok }) => (ok === true ? '✓' : ok === false ? '✗' : '–')

// Prints the gates, the commits and the proposal. Returns whether every gate passed.
export function show(root) {
  const settings = releaseSettings(root)
  const { tag, commits, level, because, proposed } = survey(root)
  const results = gates(root, settings, commits)
  console.log('Gates:')
  for (const result of results) console.log(`  ${mark(result)} ${result.text}`)
  console.log(`\nSince ${tag ?? 'the first commit'}, ${commits.length} commit${commits.length === 1 ? '' : 's'}:`)
  for (const subject of commits) console.log(`  ${subject}`)
  if (commits.length > 0) {
    console.log(`\nProposed: ${proposed}`)
    console.log(because.length > 0 ? `  ${level}, for: ${because.join('; ')}` : '  patch: nothing new and nothing breaking')
  }
  return results.every((result) => result.ok !== false)
}

// The version a release takes: one given outright, or the last one bumped by a level.
export function target(previous, wanted) {
  if (['patch', 'minor', 'major'].includes(wanted)) return bump(previous, wanted)
  if (semver.test(wanted)) return wanted
  throw new KitError(`"${wanted}" is not a version.`, 'Give X.Y.Z, or patch, minor or major.')
}

// Prints the notes' skeleton to stdout, and to stderr the title's form and every commit the
// skeleton left out, so that > notes.md captures the notes alone. The person writes them up.
export function notes(root, wanted) {
  const { previous, commits, proposed } = survey(root)
  const version = wanted === undefined ? proposed : target(previous, wanted)
  const news = commits.filter((subject) => kind(subject).breaking || kind(subject).type === 'feat')
  const fixes = commits.filter((subject) => !news.includes(subject) && kind(subject).type === 'fix')
  const sections = []
  if (news.length > 0) sections.push(`## What's new\n\n${news.map((subject) => `- ${subject}`).join('\n')}`)
  if (fixes.length > 0) sections.push(`## Fixes\n\n${fixes.map((subject) => `- ${subject}`).join('\n')}`)
  sections.push(
    '## Known gaps\n\n<What a consumer can hit that this release does not fix. Delete this section if there is nothing.>',
  )
  sections.push(
    `## Upgrading\n\nMove the dependency to \`^${version}\` and run \`npm install\`. <What else a consumer has to change, or: Nothing else changes.>`,
  )
  console.log(sections.join('\n\n'))
  console.error(`Title: v${version} — <what a consumer would notice>`)
  for (const subject of commits.filter((subject) => !news.includes(subject) && !fixes.includes(subject))) {
    console.error(`Left out: ${subject}`)
  }
}

const lockfiles = ['package-lock.json', 'npm-shrinkwrap.json']

// Bumps every copy of the version, commits them alone as chore: release X.Y.Z through the
// project's commit hooks, and tags that commit. Prints how to push; never pushes.
export function cut(root, wanted) {
  const settings = releaseSettings(root)
  const { tag, previous, commits } = survey(root)
  const version = target(previous, wanted)
  if (compare(version, previous) <= 0) {
    throw new KitError(`${version} is not above ${previous}, the last release.`, 'Give a higher version.')
  }
  if (git(root, 'tag', '--list', `v${version}`) !== '') {
    throw new KitError(`The tag v${version} already exists.`, 'Give another version, or delete the tag if it is wrong.')
  }
  if (!existsSync(join(root, 'package.json'))) throw new KitError('There is no package.json to bump.')
  const current = packageVersion(root)
  if (tag && current !== previous) {
    throw new KitError(
      `package.json says ${current}, but the last tag is ${tag}.`,
      'Bring package.json back to the last release, or tag the release it names.',
    )
  }
  const listed = settings.files ?? []
  for (const file of listed) {
    const path = join(root, file)
    if (!existsSync(path) || !readFileSync(path, 'utf8').includes(current)) {
      throw new KitError(
        `${file} does not hold ${current}, so release.files in ${manifestFile} has gone stale.`,
        `Remove ${file} from the list, or bring it back to ${current}.`,
      )
    }
  }
  const results = gates(root, settings, commits)
  const failed = results.filter((result) => result.ok === false)
  if (failed.length > 0) {
    throw new KitError(`A gate failed:\n${failed.map((result) => `  ✗ ${result.text}`).join('\n')}`, 'Run charter release to see every gate.')
  }

  // A tracked file outside the list may only mention the version, so it is reported, not changed.
  // Specs and plans are dated records: they mention versions as history, never copy one.
  const ours = new Set(['package.json', ...lockfiles, ...listed])
  const dated = [':!docs/superpowers/']
  let stray = []
  try {
    stray = git(root, 'grep', '-l', '-F', '-e', current, '--', '.', ...dated)
      .split('\n')
      .filter((file) => file !== '' && !ours.has(file))
  } catch {
    // git grep exits 1 when nothing matches.
  }

  const npm = spawnSync('npm', ['version', version, '--no-git-tag-version', '--ignore-scripts'], {
    cwd: root,
    encoding: 'utf8',
    shell: process.platform === 'win32',
  })
  if (npm.status !== 0) throw new KitError(`npm version ${version} failed: ${(npm.stderr || npm.error?.message || '').trim()}`)
  for (const file of listed) {
    const path = join(root, file)
    writeFileSync(path, readFileSync(path, 'utf8').replaceAll(current, version))
  }
  const files = ['package.json', ...lockfiles.filter((file) => existsSync(join(root, file))), ...listed]
  git(root, 'add', '--', ...files)
  const commit = spawnSync('git', ['commit', '-q', '-m', `chore: release ${version}`], { cwd: root, stdio: 'inherit' })
  if (commit.status !== 0) {
    throw new KitError(
      `The release commit failed; ${files.join(', ')} are bumped and staged, and nothing is tagged.`,
      'Fix what the hook said, then commit and tag by hand, or git restore --staged --worktree them.',
    )
  }
  git(root, 'tag', `v${version}`)
  console.log(`✓ committed chore: release ${version} — ${files.join(', ')}`)
  console.log(`✓ tagged v${version}`)
  for (const file of stray) console.log(`  ${file} still holds ${current}: check it, it was not changed`)
  console.log(`\nNothing is pushed. To publish: git push origin main v${version}`)
}
