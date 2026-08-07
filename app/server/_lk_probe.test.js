import test from 'node:test'
import assert from 'node:assert/strict'

import {
  authorizeLiveKitUpgrade, createLiveKitTokenVerifier, isLiveKitUpgradePath,
} from './_lk_probe.js'

test('LiveKit upgrade path matching rejects prefix confusion', () => {
  assert.equal(isLiveKitUpgradePath('/livekit'), true)
  assert.equal(isLiveKitUpgradePath('/livekit/rtc'), true)
  assert.equal(isLiveKitUpgradePath('/livekitfoo'), false)
  assert.equal(isLiveKitUpgradePath('/livekit-rtc'), false)
})

test('LiveKit upgrades accept a session or verified token and reject anonymous requests', async () => {
  const verifier = { verify: async token => {
    if (token === 'member') return { sub: 'user-1', nbf: 100, video: { roomJoin: true, room: 'party-1' } }
    if (token === 'browser') return { sub: 'shared-browser', video: { roomJoin: true, room: 'party-1' } }
    if (token === 'wrong-room') return { sub: 'user-1', video: { roomJoin: true, room: 'party-2' } }
    throw new Error('bad token')
  } }
  const party = { id: 'party-1', members: new Set(['user-1']), browser: {} }
  const options = {
    tokenVerifier: verifier,
    getParty: room => room === party.id ? party : null,
    isPartyMember: (candidate, identity) => candidate.members.has(identity),
    isServiceIdentity: (identity, candidate) => identity === 'shared-browser' && Boolean(candidate.browser),
    isTokenRevoked: (_candidate, identity, notBefore) => identity === 'user-1' && notBefore <= 99,
  }

  assert.equal(await authorizeLiveKitUpgrade({ session: { jellyfin: {} } }), true)
  assert.equal(await authorizeLiveKitUpgrade({ session: {}, accessToken: null, ...options }), false)
  assert.equal(await authorizeLiveKitUpgrade({ session: {}, accessToken: 'bad', ...options }), false)
  assert.equal(await authorizeLiveKitUpgrade({ session: {}, accessToken: 'member', ...options }), true)
  assert.equal(await authorizeLiveKitUpgrade({
    session: {}, accessToken: 'member', ...options,
    isTokenRevoked: (_candidate, identity, notBefore) => identity === 'user-1' && notBefore <= 100,
  }), false)
  assert.equal(await authorizeLiveKitUpgrade({
    session: { jellyfin: { userId: 'different-user' } }, accessToken: 'member', ...options,
  }), false)
  assert.equal(await authorizeLiveKitUpgrade({ session: {}, accessToken: 'wrong-room', ...options }), false)
  party.members.delete('user-1')
  assert.equal(await authorizeLiveKitUpgrade({ session: {}, accessToken: 'member', ...options }), false)
  assert.equal(await authorizeLiveKitUpgrade({ session: {}, accessToken: 'browser', ...options }), true)
  party.browser = null
  assert.equal(await authorizeLiveKitUpgrade({ session: {}, accessToken: 'browser', ...options }), false)
  assert.equal(createLiveKitTokenVerifier('', ''), null)
})
