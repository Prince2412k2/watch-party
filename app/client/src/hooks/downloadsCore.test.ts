import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { arrQueueReady, parseHealth, serviceReady } from './downloadsCore.ts'
import { failureReasons, queueTitle } from './useFailingDownloads.ts'

test('health parsing keeps only the flags the UI is allowed to trust', () => {
  const health = parseHealth({
    services: {
      qbittorrent: { configured: true, reachable: true, version: '5.0' },
      radarr: { configured: true, reachable: false },
      sonarr: 'nope',
    },
  })
  assert.deepEqual(health.services?.qbittorrent, { configured: true, reachable: true })
  assert.deepEqual(health.services?.radarr, { configured: true, reachable: false })
  assert.equal(health.services?.sonarr, undefined)
})

test('an unparseable health response degrades to nothing configured', () => {
  for (const value of [null, undefined, 'down', 42, {}, { services: [] }]) {
    assert.deepEqual(parseHealth(value), { services: {} })
  }
})

test('a service is only usable when it is both configured and reachable', () => {
  const health = parseHealth({
    services: {
      qbittorrent: { configured: true, reachable: true },
      radarr: { configured: true, reachable: false },
      sonarr: { configured: false, reachable: true },
    },
  })
  assert.equal(serviceReady(health, 'qbittorrent'), true)
  // Configured but currently down: polling it would only produce errors.
  assert.equal(serviceReady(health, 'radarr'), false)
  assert.equal(serviceReady(health, 'sonarr'), false)
  // Before the first health response nothing is polled at all.
  assert.equal(serviceReady(null, 'qbittorrent'), false)
})

test('either *arr being usable is enough to poll the failing queue', () => {
  const only = (name: string) => parseHealth({ services: { [name]: { configured: true, reachable: true } } })
  assert.equal(arrQueueReady(only('radarr')), true)
  assert.equal(arrQueueReady(only('sonarr')), true)
  assert.equal(arrQueueReady(only('qbittorrent')), false)
  assert.equal(arrQueueReady(null), false)
})

test('a stuck queue item is still actionable without a title', () => {
  // The phone screen used to drop title-less records on the floor, which hid a
  // stuck download entirely instead of asking the user to deal with it.
  assert.equal(queueTitle({ id: 1, service: 'radarr', title: 'Dune (2021)' }), 'Dune (2021)')
  assert.equal(queueTitle({ id: 1, service: 'radarr' }), 'Untitled item')
  assert.equal(queueTitle({ id: 1, service: 'radarr', title: '   ' }), 'Untitled item')
})

test('a stuck queue item always states a reason', () => {
  assert.deepEqual(failureReasons({ id: 1, service: 'radarr', statusMessages: ['No files found'] }), ['No files found'])
  // *arr reports the reason in one of two fields depending on the failure.
  assert.deepEqual(failureReasons({ id: 1, service: 'radarr', statusMessages: [], errorMessage: 'Import failed' }), ['Import failed'])
  assert.deepEqual(failureReasons({ id: 1, service: 'sonarr' }), ['No reason given.'])
})

/* ── Polling ownership ────────────────────────────────────────────────────────
   The phone tab bar is mounted at the same time as whichever screen is showing,
   so any screen that owns a poller runs a second copy of it — that is how this
   app ended up polling the enriched-torrent endpoint twice every 2.5s and both
   *arr queues twice every 6s on the Downloads tab. This is the invariant that
   keeps it from coming back: each poller has exactly one consumer, the shared
   hub, and every surface reads from there via useDownloadsHub().

   Matches on the source tree so it holds for the .ts sources and for a
   transpiled .js copy alike (this host's node cannot run TypeScript directly). */
const srcRoot = join(dirname(fileURLToPath(import.meta.url)), '..')
const SOURCE = /\.(ts|tsx|js|jsx)$/
const IS_TEST = /\.test\.(ts|tsx|js|jsx)$/

function sourceFiles(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules') continue
    const full = join(dir, entry.name)
    if (entry.isDirectory()) sourceFiles(full, out)
    else if (SOURCE.test(entry.name) && !IS_TEST.test(entry.name)) out.push(full)
  }
  return out
}

/** Modules that import `member` as a *value* (a `import type` carries no poller). */
function importersOf(member: string, moduleName: string): string[] {
  // The specifier may or may not carry an extension depending on the tree.
  const pattern = new RegExp(
    `import\\s*\\{[^}]*\\b${member}\\b[^}]*\\}\\s*from\\s*['"][^'"]*${moduleName}(\\.[a-z]+)?['"]`,
  )
  return sourceFiles(srcRoot)
    .filter((file) => pattern.test(readFileSync(file, 'utf8')))
    .map((file) => file.slice(srcRoot.length + 1).replace(SOURCE, ''))
    .sort()
}

test('the download and queue pollers have exactly one consumer', () => {
  for (const [moduleName, member] of [['useTorrents', 'useTorrents'], ['useFailingDownloads', 'useFailingQueue']]) {
    assert.deepEqual(
      importersOf(member, moduleName),
      ['context/DownloadsContext'],
      `${member} must be mounted only by the shared hub — screens read useDownloadsHub() instead`,
    )
  }
})
