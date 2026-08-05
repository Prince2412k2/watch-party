// A database this process cannot write must switch the shared browser OFF, not
// break the app. This is a real configuration on a dev box (the party database is
// a bind mount owned by the container's user) and it used to be fatal: adding the
// lease table made party-store.js throw at import, which took down everything
// that transitively imports session.js — subtitles, playback, chat.
import test from 'node:test'
import assert from 'node:assert/strict'
import { chmodSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { DatabaseSync } from 'node:sqlite'

const databasePath = join(tmpdir(), `watchparty-readonly-${process.pid}-${Date.now()}.sqlite`)

// A valid database that already has the core schema, so the party_sessions DDL is
// a no-op and only the browser's own table needs a write.
{
  const seed = new DatabaseSync(databasePath)
  seed.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS party_sessions (
      id TEXT PRIMARY KEY,
      state TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
  `)
  seed.close()
}
chmodSync(databasePath, 0o444)

process.env.PARTY_DB_PATH = databasePath
process.env.BROWSER_ENABLED = '1'
process.env.BROWSER_AGENT_TOKEN = 'test-token'

// Importing at all is half the assertion: this used to throw.
const store = await import('../party-store.js')
const { browserConfig } = await import('./config.js')

test.after(() => {
  try {
    chmodSync(databasePath, 0o644)
  } catch { /* already gone */ }
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

test('a read-only database leaves the lease unavailable rather than throwing', () => {
  assert.equal(store.leaseStorageReady(), false)
  assert.equal(store.loadLease(), null)
  // Both of these are no-ops, not exceptions — teardown paths call them.
  store.saveLease({ partyId: 'X' })
  store.clearLease()
  assert.equal(store.loadLease(), null)
})

test('the shared browser reports as unavailable when its lease cannot be stored', () => {
  const config = browserConfig()
  assert.equal(config.flagSet, true, 'the deployment did ask for the feature')
  assert.equal(config.enabled, false, 'but it cannot be honoured, so it is off')
})

test('the rest of the party store still works read-only', () => {
  // The point of the whole exercise: parties still load. A browser that cannot
  // store its lease must cost the app nothing else.
  assert.deepEqual(store.loadParties(), [])
  assert.equal(store.loadParty('NOPE'), null)
})
