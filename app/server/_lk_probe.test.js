import test from 'node:test'
import assert from 'node:assert/strict'

import {
  authorizeLiveKitUpgrade, createLiveKitTokenVerifier, isLiveKitUpgradePath,
  liveKitAccessToken,
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
    if (token === 'outsider') return { sub: 'not-a-member', video: { roomJoin: true, room: 'party-1' } }
    if (token === 'wrong-room') return { sub: 'user-1', video: { roomJoin: true, room: 'party-2' } }
    throw new Error('bad token')
  } }
  const party = { id: 'party-1', members: new Set(['user-1']) }
  const options = {
    tokenVerifier: verifier,
    getParty: room => room === party.id ? party : null,
    isPartyMember: (candidate, identity) => candidate.members.has(identity),
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
  // Party membership is now the only way in. The shared browser was the one
  // service identity that could join without being a member, and it is gone —
  // a validly signed token for a non-member must be refused.
  assert.equal(await authorizeLiveKitUpgrade({ session: {}, accessToken: 'outsider', ...options }), false)
  assert.equal(createLiveKitTokenVerifier('', ''), null)
})

test('a LiveKit token is found in the Authorization header, not just the query', () => {
  // The browser SDK can only use ?access_token= — a browser cannot set headers
  // on a WebSocket handshake. The Flutter SDK uses Authorization: Bearer,
  // because a native socket can. Reading only the query param meant every
  // native client authenticated as "no token", fell through to the cookie
  // check it also could not satisfy, and was rejected 401 forever.
  const q = new URL('http://x/livekit/rtc?access_token=from-query')
  assert.equal(liveKitAccessToken(q, {}), 'from-query')

  const bare = new URL('http://x/livekit/rtc?sdk=flutter')
  assert.equal(liveKitAccessToken(bare, { authorization: 'Bearer from-header' }), 'from-header')
  assert.equal(liveKitAccessToken(bare, { Authorization: 'bearer lower-case' }), 'lower-case')

  // The query param wins when both are present: it is what the browser sends,
  // and a proxy that adds its own Authorization must not shadow it.
  assert.equal(liveKitAccessToken(q, { authorization: 'Bearer other' }), 'from-query')

  // Anything that is not a Bearer token is not a token.
  assert.equal(liveKitAccessToken(bare, {}), null)
  assert.equal(liveKitAccessToken(bare, { authorization: 'Basic abc' }), null)
  assert.equal(liveKitAccessToken(bare, { authorization: 'Bearer' }), null)
})
