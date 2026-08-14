// What a lost room is allowed to say, and to whom.
//
// The surface these back exists because a dropped party was silent: chat
// stopped arriving, playback stopped following the host, and nothing said so.

import test from 'node:test'
import assert from 'node:assert/strict'
import type { PartyUser } from '../types.ts'
import {
  orderFaces,
  reconnectLabel,
  retryBackoffMs,
  shouldShowReconnect,
} from './partyReconnect.ts'

const user = (userId: string, name = userId): PartyUser => ({ userId, name })

test('the surface needs a room to be cut off from', () => {
  assert.equal(shouldShowReconnect(true, false), true)
  // A socket that is down while nobody is in a party is not a lost room, it is
  // a page that has not needed one yet.
  assert.equal(shouldShowReconnect(false, false), false)
  assert.equal(shouldShowReconnect(true, true), false)
  assert.equal(shouldShowReconnect(false, true), false)
})

test('the attempt count waits until a drop is worth naming', () => {
  // Most drops are a blip; "attempt 1" would make one look like a fault.
  assert.equal(reconnectLabel(0), 'Reconnecting…')
  assert.equal(reconnectLabel(1), 'Reconnecting…')
  assert.equal(reconnectLabel(2), 'Reconnecting…')
  assert.equal(reconnectLabel(3), 'Reconnecting… (attempt 3)')
})

test('the host leads the faces', () => {
  const faces = orderFaces([user('a'), user('host'), user('b')], 'host')
  assert.deepEqual(faces.map(f => f.userId), ['host', 'a', 'b'])
})

test('a room with no known host still lists everyone', () => {
  // hostId is optional on the session, and losing the socket is exactly when
  // the session may be half-known.
  const faces = orderFaces([user('a'), user('b')], undefined)
  assert.deepEqual(faces.map(f => f.userId), ['a', 'b'])
  assert.deepEqual(orderFaces([], 'host'), [])
})

test('the backoff starts fast and stops growing', () => {
  assert.equal(retryBackoffMs(0), 1000)
  assert.equal(retryBackoffMs(1), 2000)
  assert.equal(retryBackoffMs(2), 4000)
  assert.equal(retryBackoffMs(3), 8000)
  assert.equal(retryBackoffMs(4), 15000)
  // Capped: past half a minute a tighter loop fixes nothing and only leans on a
  // server that is already struggling.
  assert.equal(retryBackoffMs(50), 15000)
})
