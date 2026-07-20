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
  CREATE TABLE IF NOT EXISTS neko_lease (
    key TEXT PRIMARY KEY,
    partyId TEXT NOT NULL,
    hostName TEXT,
    state TEXT NOT NULL,
    leaseId TEXT NOT NULL,
    sessions TEXT NOT NULL,
    acquiredAt INTEGER NOT NULL
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

const upsertLease = db.prepare(`
  INSERT INTO neko_lease (key, partyId, hostName, state, leaseId, sessions, acquiredAt)
  VALUES ('global', ?, ?, ?, ?, ?, ?)
  ON CONFLICT(key) DO UPDATE SET
    partyId = excluded.partyId,
    hostName = excluded.hostName,
    state = excluded.state,
    leaseId = excluded.leaseId,
    sessions = excluded.sessions,
    acquiredAt = excluded.acquiredAt
`)
const selectLease = db.prepare("SELECT * FROM neko_lease WHERE key = 'global'")
const deleteLease = db.prepare("DELETE FROM neko_lease WHERE key = 'global'")

export function saveLease(row) {
  upsertLease.run(
    row.partyId,
    row.hostName ?? null,
    row.state,
    row.leaseId,
    JSON.stringify(row.sessions ?? []),
    row.acquiredAt,
  )
}

export function loadLease() {
  const row = selectLease.get()
  if (!row) return null
  let sessions = []
  try {
    sessions = JSON.parse(row.sessions)
  } catch {
    sessions = []
  }
  return {
    partyId: row.partyId,
    hostName: row.hostName,
    state: row.state,
    leaseId: row.leaseId,
    sessions,
    acquiredAt: row.acquiredAt,
  }
}

export function clearLease() {
  deleteLease.run()
}
