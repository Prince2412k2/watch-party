import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { DatabaseSync } from 'node:sqlite'

const databasePath = join(tmpdir(), `watchparty-profile-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath

const { validateDisplayName, validateAvatar, DISPLAY_NAME_MAX } = await import('./profile.js')
const { getProfile, saveProfile } = await import('./profile-store.js')
const { createSession, deleteSession, publicSession, addToWaiting, approveGuest, effectiveName } =
  await import('./session.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

/* ── display names (FR-005) ─────────────────────────────────────────────── */

test('a display name is trimmed and kept', () => {
  assert.deepEqual(validateDisplayName('   Prince   '), { value: 'Prince' })
})

test('an empty display name clears rather than errors — the account name takes over', () => {
  assert.deepEqual(validateDisplayName('    '), { value: null })
  assert.deepEqual(validateDisplayName(''), { value: null })
  assert.deepEqual(validateDisplayName(null), { value: null })
  assert.deepEqual(validateDisplayName(undefined), { value: null })
})

test('a display name must be a single line', () => {
  const control = ['a\nb', 'a\rb', 'a\tb', `a${String.fromCharCode(0)}b`, `a${String.fromCharCode(0x7f)}b`]
  for (const value of control) {
    assert.ok(validateDisplayName(value).error, `expected ${JSON.stringify(value)} to be rejected`)
  }
})

test('a display name is length-limited by code point, so emoji count once each', () => {
  assert.deepEqual(validateDisplayName('x'.repeat(DISPLAY_NAME_MAX)).value, 'x'.repeat(DISPLAY_NAME_MAX))
  assert.ok(validateDisplayName('x'.repeat(DISPLAY_NAME_MAX + 1)).error)
  assert.ok(validateDisplayName('\u{1f642}'.repeat(DISPLAY_NAME_MAX)).value)
  assert.ok(validateDisplayName('\u{1f642}'.repeat(DISPLAY_NAME_MAX + 1)).error)
})

test('a display name must be a string', () => {
  for (const value of [7, true, {}, []]) assert.ok(validateDisplayName(value).error)
})

/* ── avatar configuration (FR-006, SC-012) ──────────────────────────────── */

test('a valid avatar configuration is normalised, not echoed', () => {
  const { value, error } = validateAvatar({
    selections: { head: 'hm1-p-000001' },
    colors: { skin: '#e8b98c' },
    background: 'transparent',
  })
  assert.equal(error, undefined)
  // Hex is stored the way the manifest writes its own defaults: no '#', uppercase.
  assert.deepEqual(value, {
    selections: { head: 'hm1-p-000001' },
    colors: { skin: 'E8B98C' },
    background: 'transparent',
  })
})

test('an unknown part id is rejected rather than stored', () => {
  assert.ok(validateAvatar({ selections: { head: 'hm1-p-999999' } }).error)
})

test('a part belonging to another slot is rejected', () => {
  // hm1-p-000001 is a head; offering it as a body must not pass.
  assert.ok(validateAvatar({ selections: { body: 'hm1-p-000001' } }).error)
})

test('unknown slots and colour slots are rejected', () => {
  assert.ok(validateAvatar({ selections: { hat: 'hm1-p-000001' } }).error)
  assert.ok(validateAvatar({ colors: { eyes: 'AABBCC' } }).error)
})

test('a malformed colour is rejected', () => {
  for (const hex of ['nothex', 'AABBC', 'AABBCCDD', '#12345', 12, null]) {
    assert.ok(validateAvatar({ colors: { skin: hex } }).error, `expected ${hex} to be rejected`)
  }
})

test('junk shapes are rejected', () => {
  assert.ok(validateAvatar([]).error)
  assert.ok(validateAvatar('avatar').error)
  assert.ok(validateAvatar({ nope: true }).error)
  assert.ok(validateAvatar({ selections: 'head' }).error)
})

test('an avatar that overrides nothing is stored as nothing, not as an empty override', () => {
  assert.deepEqual(validateAvatar({}), { value: null })
  assert.deepEqual(validateAvatar({ selections: {}, colors: {} }), { value: null })
  assert.deepEqual(validateAvatar(null), { value: null })
})

/* ── storage (FR-001, FR-012, SC-005) ───────────────────────────────────── */

test('a saved profile round-trips, and clearing both fields removes it', () => {
  const avatar = { selections: { head: 'hm1-p-000001' }, colors: { skin: 'E8B98C' } }
  saveProfile('store-user', { displayName: 'Stored', avatar })
  assert.deepEqual(getProfile('store-user'), { displayName: 'Stored', avatar })

  // Reset to the derived default (FR-012) — the row goes away entirely.
  saveProfile('store-user', { displayName: null, avatar: null })
  assert.deepEqual(getProfile('store-user'), { displayName: null, avatar: null })
})

test('a user who never saved anything reads as the default case, not a missing record', () => {
  assert.deepEqual(getProfile('never-seen-this-user'), { displayName: null, avatar: null })
})

test('a saved profile is on disk, so it survives a restart', () => {
  saveProfile('durable-user', { displayName: 'Durable', avatar: { colors: { hair: '4A3728' } } })

  // A second connection to the same file is what a restarted process sees.
  const reopened = new DatabaseSync(databasePath)
  try {
    const row = reopened
      .prepare('SELECT display_name, avatar FROM user_profiles WHERE user_id = ?')
      .get('durable-user')
    assert.equal(row.display_name, 'Durable')
    assert.deepEqual(JSON.parse(row.avatar), { colors: { hair: '4A3728' } })
  } finally { reopened.close() }
})

/* ── sharing within a party (FR-013, FR-014) ────────────────────────────── */

test('a display name replaces the account name for every member of a party payload', () => {
  saveProfile('p-host', { displayName: 'The Host' })
  saveProfile('p-guest', { displayName: 'The Guest', avatar: { colors: { skin: 'E8B98C' } } })
  const sess = createSession({
    hostId: 'p-host', hostName: 'root', hostToken: 't', hostDeviceId: 'd', hostSocketId: 's',
  })
  try {
    addToWaiting(sess, { userId: 'p-guest', name: 'guest-account', socketId: 'gs', token: 't', deviceId: 'd' })
    approveGuest(sess, 'p-guest')

    const pub = publicSession(sess)
    assert.equal(pub.hostName, 'The Host')
    assert.equal(pub.guests[0].name, 'The Guest')
    // The avatar rides along; a member with nothing saved sends null and the
    // client derives from userId instead.
    assert.deepEqual(pub.guests[0].avatar, { colors: { skin: 'E8B98C' } })
    assert.equal(pub.hostAvatar, null)
  } finally {
    deleteSession(sess.id)
    saveProfile('p-host', {})
    saveProfile('p-guest', {})
  }
})

test('clearing a display name falls back to the Jellyfin account name', () => {
  saveProfile('fallback-user', { displayName: 'Temporary' })
  assert.equal(effectiveName('fallback-user', 'account-name'), 'Temporary')
  saveProfile('fallback-user', {})
  assert.equal(effectiveName('fallback-user', 'account-name'), 'account-name')
})

test('a display name is presentation only — userId still identifies the member', () => {
  saveProfile('impersonator', { displayName: 'root' })
  const sess = createSession({
    hostId: 'real-root', hostName: 'root', hostToken: 't', hostDeviceId: 'd', hostSocketId: 's',
  })
  try {
    addToWaiting(sess, { userId: 'impersonator', name: 'mallory', socketId: 'gs', token: 't', deviceId: 'd' })
    approveGuest(sess, 'impersonator')

    const pub = publicSession(sess)
    // Both render as "root", and that is cosmetic: host authority is keyed on
    // userId, which the display name cannot touch.
    assert.equal(pub.guests[0].name, 'root')
    assert.equal(pub.hostId, 'real-root')
    assert.notEqual(pub.guests[0].userId, pub.hostId)
  } finally {
    deleteSession(sess.id)
    saveProfile('impersonator', {})
  }
})
