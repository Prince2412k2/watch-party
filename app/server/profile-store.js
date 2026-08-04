import { db } from './db.js'

db.exec(`
  CREATE TABLE IF NOT EXISTS user_profiles (
    user_id TEXT PRIMARY KEY,
    display_name TEXT,
    avatar TEXT,
    updated_at INTEGER NOT NULL
  );
`)

const upsert = db.prepare(`
  INSERT INTO user_profiles (user_id, display_name, avatar, updated_at)
  VALUES (?, ?, ?, ?)
  ON CONFLICT(user_id) DO UPDATE SET
    display_name = excluded.display_name,
    avatar = excluded.avatar,
    updated_at = excluded.updated_at
`)
const remove = db.prepare('DELETE FROM user_profiles WHERE user_id = ?')
const selectOne = db.prepare('SELECT display_name, avatar FROM user_profiles WHERE user_id = ?')

const EMPTY = Object.freeze({ displayName: null, avatar: null })

/** Always resolves — a user who has never saved anything is the default case,
    not a missing record, so callers never branch on existence. */
export function getProfile(userId) {
  const row = selectOne.get(userId)
  if (!row) return EMPTY
  let avatar = null
  if (row.avatar) {
    try {
      avatar = JSON.parse(row.avatar)
    } catch {
      avatar = null
    }
  }
  return { displayName: row.display_name ?? null, avatar }
}

/** Both fields are replaced, not merged — the profile page always sends the
    whole profile, and a row with nothing in it is just the default case, so
    clearing both removes the row rather than storing two nulls. */
export function saveProfile(userId, { displayName = null, avatar = null } = {}) {
  if (displayName === null && avatar === null) {
    remove.run(userId)
    return EMPTY
  }
  upsert.run(userId, displayName, avatar === null ? null : JSON.stringify(avatar), Date.now())
  return { displayName, avatar }
}
