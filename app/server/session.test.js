import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const databasePath = join(tmpdir(), `watchparty-session-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath

const {
  createSession, deleteSession, persistSession, randomConnectedGuest,
  transferHost, reclaimOriginalHost, validateSyncCommand, authorizeSyncCommand,
  beginMediaGeneration, applyStallReport,
  validateSubtitlePreferences, DEFAULT_SUBTITLE_PREFERENCES,
} = await import('./session.js')
const { loadParty } = await import('./party-store.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

function fresh() {
  return createSession({ hostId: 'host', hostName: 'Host', hostSocketId: 's1' })
}

test('validateSyncCommand rejects non-finite and negative positions', () => {
  assert.equal(validateSyncCommand({ positionTicks: Infinity }).error, 'invalid positionTicks')
  assert.equal(validateSyncCommand({ positionTicks: -1 }).error, 'invalid positionTicks')
  assert.deepEqual(validateSyncCommand({ positionTicks: 12 }).value, { positionTicks: 12 })
})

test('subtitle preferences accept only the complete bounded protocol object', () => {
  assert.deepEqual(validateSubtitlePreferences(DEFAULT_SUBTITLE_PREFERENCES).value, DEFAULT_SUBTITLE_PREFERENCES)
  assert.equal(validateSubtitlePreferences({ ...DEFAULT_SUBTITLE_PREFERENCES, delayMs: 10001 }).error, 'invalid delayMs')
  assert.equal(validateSubtitlePreferences({ ...DEFAULT_SUBTITLE_PREFERENCES, fontFamily: 'comic' }).error, 'invalid fontFamily')
  assert.equal(validateSubtitlePreferences({ ...DEFAULT_SUBTITLE_PREFERENCES, textColor: 'red' }).error, 'invalid textColor')
  assert.equal(validateSubtitlePreferences({ ...DEFAULT_SUBTITLE_PREFERENCES, extra: true }).error, 'invalid subtitlePreferences')
})

test('authorizeSyncCommand rejects stale versions and duplicate command ids', () => {
  const sess = fresh()
  try {
    sess.schedule.version = 4
    assert.equal(authorizeSyncCommand(sess, { baseVersion: 3, commandId: 'one' }).error, 'stale schedule')
    assert.equal(authorizeSyncCommand(sess, { baseVersion: 4, commandId: 'one' }).ok, true)
    assert.equal(authorizeSyncCommand(sess, { baseVersion: 4, commandId: 'one' }).error, 'duplicate command')
  } finally { deleteSession(sess.id) }
})

test('beginMediaGeneration invalidates old stall reports', () => {
  const sess = fresh()
  try {
    const old = sess.mediaGeneration
    assert.equal(applyStallReport(sess, 'guest', { stalled: true, mediaGeneration: old }), true)
    beginMediaGeneration(sess)
    assert.equal(sess.stalled.size, 0)
    assert.equal(applyStallReport(sess, 'guest', { stalled: true, mediaGeneration: old }), false)
  } finally { deleteSession(sess.id) }
})

test('a timed-out stall remains in fallback until recovery is reported', () => {
  const sess = fresh()
  try {
    applyStallReport(sess, 'guest', { stalled: true, mediaGeneration: sess.mediaGeneration })
    sess.stallFallback.add('guest')
    sess.stalled.delete('guest')
    assert.equal(applyStallReport(sess, 'guest', { stalled: true, mediaGeneration: sess.mediaGeneration }), false)
    assert.equal(applyStallReport(sess, 'guest', { stalled: false, mediaGeneration: sess.mediaGeneration }), true)
    assert.equal(sess.stallFallback.has('guest'), false)
  } finally { deleteSession(sess.id) }
})

test('create, save, reload, and delete preserve only durable state', async () => {
  const sess = createSession({
    hostId: 'owner', hostName: 'Owner', hostToken: 'host-token',
    hostDeviceId: 'host-device', hostSocketId: 'host-socket', mediaItemId: 'movie',
  })
  sess.playback = { PlaySessionId: 'play-session' }
  sess.subtitlePreferences = {
    delayMs: 750, fontScalePercent: 130, verticalPosition: 'top',
    fontFamily: 'serif', textColor: '#FFE66D', backgroundOpacityPercent: 40,
  }
  sess.browse = { stack: [{ id: 'folder', name: 'Folder', type: 'CollectionFolder' }] }
  sess.guests.push({
    userId: 'guest', name: 'Guest', token: 'guest-token', deviceId: 'guest-device',
    joinedAt: 123, socketId: 'guest-socket', telemetry: { drift: 10 },
  })
  sess.waiting.push({ userId: 'waiting', socketId: 'waiting-socket' })
  sess.approved.add('guest')
  sess.messages.push({ userId: 'guest', text: 'hello', timestamp: 456 })
  sess.collaborativeControl = true
  sess.syncMode = 'dragging'
  sess.intent = { playing: true }
  sess.pos = 42
  sess.playT0 = 99
  sess.effPlaying = true
  sess.stalled.add('guest')
  sess.reports.set('guest', { drift: 10 })
  sess.hostDisconnectTimer = setTimeout(() => {}, 60_000)

  try {
    persistSession(sess)
    const stored = loadParty(sess.id)
    assert.equal(stored.hostSocketId, undefined)
    assert.equal(stored.waiting, undefined)
    assert.equal(stored.guests[0].socketId, undefined)
    assert.equal(stored.guests[0].telemetry, undefined)
    assert.equal(stored.stalled, undefined)
    assert.equal(stored.reports, undefined)
    assert.equal(stored.hostDisconnectTimer, undefined)

    const reloadedModule = await import(`./session.js?reload=${Date.now()}`)
    const loaded = reloadedModule.getSession(sess.id)
    assert.equal(loaded.hostSocketId, null)
    assert.equal(loaded.guests[0].socketId, null)
    assert.deepEqual(loaded.waiting, [])
    assert.deepEqual([...loaded.approved], ['owner', 'guest'])
    assert.deepEqual(loaded.playback, sess.playback)
    assert.deepEqual(loaded.subtitlePreferences, sess.subtitlePreferences)
    assert.deepEqual(loaded.browse, sess.browse)
    assert.deepEqual(loaded.messages, sess.messages)
    assert.equal(loaded.collaborativeControl, true)
    assert.equal(loaded.syncMode, 'dragging')
    assert.deepEqual(loaded.intent, { playing: true })
    assert.equal(loaded.pos, 42)
    assert.equal(loaded.playT0, 99)
    assert.equal(loaded.effPlaying, true)

    reloadedModule.deleteSession(sess.id)
    assert.equal(loadParty(sess.id), null)
  } finally {
    clearTimeout(sess.hostDisconnectTimer)
    deleteSession(sess.id)
  }
})

test('randomConnectedGuest selects only connected guests', () => {
  const sess = fresh()
  try {
    sess.guests.push(
      { userId: 'offline', socketId: 's-offline' },
      { userId: 'first', socketId: 's-first' },
      { userId: 'second', socketId: 's-second' },
    )
    const connected = socketId => socketId !== 's-offline'
    assert.equal(randomConnectedGuest(sess, connected, () => 0).userId, 'first')
    assert.equal(randomConnectedGuest(sess, connected, () => 0.999).userId, 'second')
    assert.equal(randomConnectedGuest(sess, () => false), null)
  } finally { deleteSession(sess.id) }
})

test('host transfer persists ownership and original host can reclaim it', () => {
  const sess = createSession({
    hostId: 'owner', hostName: 'Owner', hostToken: 'owner-token',
    hostDeviceId: 'owner-device', hostSocketId: null,
  })
  sess.guests.push({
    userId: 'guest', name: 'Guest', token: 'guest-token', deviceId: 'guest-device',
    socketId: 'guest-socket', joinedAt: 1,
  })

  try {
    assert.equal(transferHost(sess, 'guest', 'guest-socket', 'new-guest-token'), true)
    assert.equal(sess.hostId, 'guest')
    assert.equal(sess.originalHostId, 'owner')
    assert.equal(sess.guests.some(guest => guest.userId === 'owner'), true)
    assert.equal(loadParty(sess.id).hostId, 'guest')

    assert.equal(reclaimOriginalHost(sess, {
      socketId: 'owner-socket', token: 'fresh-owner-token',
      deviceId: 'fresh-owner-device', name: 'Owner Again',
    }), true)
    assert.equal(sess.hostId, 'owner')
    assert.equal(sess.guests.some(guest => guest.userId === 'owner'), false)
    assert.equal(sess.guests.some(guest => guest.userId === 'guest'), true)
    assert.equal(loadParty(sess.id).hostId, 'owner')
    assert.equal(reclaimOriginalHost(sess, {}), false)
  } finally { deleteSession(sess.id) }
})
