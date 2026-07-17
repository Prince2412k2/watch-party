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
