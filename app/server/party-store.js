import { mkdirSync } from 'fs'
import { dirname, join } from 'path'
import { DatabaseSync } from 'node:sqlite'

const databasePath = process.env.PARTY_DB_PATH
  || (process.env.WP_TEST_MODE === '1'
    ? join('/tmp', `watchparty-test-${process.pid}.sqlite`)
    : join(process.cwd(), 'data/watchparty.sqlite'))

mkdirSync(dirname(databasePath), { recursive: true })

const db = new DatabaseSync(databasePath)
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS party_sessions (
    id TEXT PRIMARY KEY,
    state TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  );
`)

const upsert = db.prepare(`
  INSERT INTO party_sessions (id, state, updated_at)
  VALUES (?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    state = excluded.state,
    updated_at = excluded.updated_at
`)
const remove = db.prepare('DELETE FROM party_sessions WHERE id = ?')
const selectAll = db.prepare('SELECT state FROM party_sessions ORDER BY updated_at')
const selectOne = db.prepare('SELECT state FROM party_sessions WHERE id = ?')

export function saveParty(session) {
  upsert.run(session.id, JSON.stringify(session), Date.now())
}

export function removeParty(id) {
  remove.run(id)
}

export function loadParties() {
  return selectAll.all().flatMap(({ state }) => {
    try {
      return [JSON.parse(state)]
    } catch {
      return []
    }
  })
}

export function loadParty(id) {
  const row = selectOne.get(id)
  if (!row) return null
  try {
    return JSON.parse(row.state)
  } catch {
    return null
  }
}

// ── Shared-browser lease ────────────────────────────────────────────────────
//
// At most one row (id = 1). The shared browser is a single global instance, so
// "who holds it" is one row, not a row per party. Persisted rather than kept in
// memory so a server restart can tell the difference between "nobody is using the
// browser" and "a party was using it and we just lost track of them".
//
// Created separately from the schema above, and a failure here is NOT fatal:
// everything else in the app works without this table, so a database this process
// cannot write — a read-only bind mount, a stale root-owned file on a dev box —
// must degrade the shared browser to "unavailable" rather than take chat, joins
// and playback down with it. `leaseStorageReady()` is what the browser's config
// consults to decide the feature is off.

let upsertLease = null
let selectLease = null
let deleteLease = null

try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS browser_lease (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      state TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
  `)
  upsertLease = db.prepare(`
    INSERT INTO browser_lease (id, state, updated_at)
    VALUES (1, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      state = excluded.state,
      updated_at = excluded.updated_at
  `)
  selectLease = db.prepare('SELECT state FROM browser_lease WHERE id = 1')
  deleteLease = db.prepare('DELETE FROM browser_lease WHERE id = 1')
} catch (error) {
  console.warn(
    `party-store: browser_lease is unavailable (${error.message}) — the shared browser will report as unavailable`
  )
}

export function leaseStorageReady() {
  return upsertLease !== null
}

export function saveLease(lease) {
  if (!upsertLease) return
  upsertLease.run(JSON.stringify(lease), Date.now())
}

export function loadLease() {
  if (!selectLease) return null
  const row = selectLease.get()
  if (!row) return null
  try {
    return JSON.parse(row.state)
  } catch {
    // A corrupt row would otherwise wedge the browser as permanently busy.
    deleteLease?.run()
    return null
  }
}

export function clearLease() {
  deleteLease?.run()
}
