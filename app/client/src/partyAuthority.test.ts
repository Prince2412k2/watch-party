import test from 'node:test'
import assert from 'node:assert/strict'
import { canManagePartyMedia, partyRoleForUser, shouldOpenPartyPlayer } from './partyAuthority.ts'
import type { PartySession } from './types.ts'

const watching: PartySession = { id: 'A1B2C3D4', hostId: 'host', stage: 'watching', mediaItemId: 'movie' }

test('approved/current shell members follow watching state into the player', () => {
  assert.equal(shouldOpenPartyPlayer(watching, 'guest', '/movies'), true)
  assert.equal(shouldOpenPartyPlayer(watching, 'host', '/discover'), true)
  assert.equal(shouldOpenPartyPlayer(watching, 'waiting', '/movies'), false)
  assert.equal(shouldOpenPartyPlayer(watching, 'guest', '/party/A1B2C3D4'), false)
  assert.equal(shouldOpenPartyPlayer({ ...watching, stage: 'lobby' }, 'guest', '/movies'), false)
})

test('members follow the shared browser into the party surface', () => {
  // The browser is started from the popcorn widget in the home shell, so nobody
  // is on /party/* when the activity flips. Both the host who pressed the button
  // and every guest have to be pulled in, or the stream has no audience.
  const browser: PartySession = { id: 'A1B2C3D4', hostId: 'host', stage: 'browser' }
  assert.equal(shouldOpenPartyPlayer(browser, 'host', '/movies'), true)
  assert.equal(shouldOpenPartyPlayer(browser, 'guest', '/downloads'), true)
  // No mediaItemId is involved — unlike the player, this activity has no title.
  assert.equal(shouldOpenPartyPlayer({ ...browser, mediaItemId: null }, 'guest', '/movies'), true)
  assert.equal(shouldOpenPartyPlayer(browser, 'waiting', '/movies'), false)
  assert.equal(shouldOpenPartyPlayer(browser, 'guest', '/party/A1B2C3D4'), false)
})

test('room broadcasts do not promote a waiting socket to guest', () => {
  const session = { ...watching, guests: [{ userId: 'approved', name: 'Approved' }], waiting: [{ userId: 'waiting', name: 'Waiting' }] }
  assert.equal(partyRoleForUser(session, 'approved'), 'guest')
  assert.equal(partyRoleForUser(session, 'waiting'), null)
})

test('collaborative guests never manage canonical media settings', () => {
  assert.equal(canManagePartyMedia('host'), true)
  assert.equal(canManagePartyMedia('guest'), false)
})
