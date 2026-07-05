import test from 'node:test'
import assert from 'node:assert/strict'

import { createSession, deleteSession, validateSyncCommand, authorizeSyncCommand, beginMediaGeneration, applyStallReport } from './session.js'

function fresh() {
  return createSession({ hostId: 'host', hostName: 'Host', hostSocketId: 's1' })
}

test('validateSyncCommand rejects non-finite and negative positions', () => {
  assert.equal(validateSyncCommand({ positionTicks: Infinity }).error, 'invalid positionTicks')
  assert.equal(validateSyncCommand({ positionTicks: -1 }).error, 'invalid positionTicks')
  assert.deepEqual(validateSyncCommand({ positionTicks: 12 }).value, { positionTicks: 12 })
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
