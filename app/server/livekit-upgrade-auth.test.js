import test from 'node:test'
import assert from 'node:assert/strict'
import { AccessToken } from 'livekit-server-sdk'
import {
  isLiveKitUpgradePath, authorizeLiveKitUpgrade, createLiveKitTokenVerifier,
} from './livekit-upgrade-auth.js'

test('isLiveKitUpgradePath matches the mount exactly or a sub-path, not a prefix look-alike', () => {
  assert.equal(isLiveKitUpgradePath('/livekit'), true)
  assert.equal(isLiveKitUpgradePath('/livekit/rtc'), true)
  assert.equal(isLiveKitUpgradePath('/livekitfoo'), false)
  assert.equal(isLiveKitUpgradePath('/socket.io/'), false)
})

test('authorizeLiveKitUpgrade accepts an authenticated session with no access_token at all', async () => {
  const ok = await authorizeLiveKitUpgrade({
    session: { jellyfin: { userId: 'u1' } },
    accessToken: null,
    tokenVerifier: null,
  })
  assert.equal(ok, true)
})

test('authorizeLiveKitUpgrade rejects an anonymous upgrade with neither session nor token', async () => {
  const ok = await authorizeLiveKitUpgrade({ session: null, accessToken: null, tokenVerifier: null })
  assert.equal(ok, false)
})

test('authorizeLiveKitUpgrade falls back to a verified LiveKit access_token when there is no session', async () => {
  const tokenVerifier = createLiveKitTokenVerifier('test-key', 'test-secret')
  const jwt = await new AccessToken('test-key', 'test-secret', { identity: 'guest-1' }).toJwt()

  const ok = await authorizeLiveKitUpgrade({ session: null, accessToken: jwt, tokenVerifier })
  assert.equal(ok, true)
})

test('authorizeLiveKitUpgrade rejects a token signed with the wrong secret (forged/stolen)', async () => {
  const tokenVerifier = createLiveKitTokenVerifier('test-key', 'test-secret')
  const forged = await new AccessToken('test-key', 'not-the-real-secret', { identity: 'attacker' }).toJwt()

  const ok = await authorizeLiveKitUpgrade({ session: null, accessToken: forged, tokenVerifier })
  assert.equal(ok, false)
})

test('authorizeLiveKitUpgrade rejects a well-formed token when LiveKit credentials are not configured', async () => {
  // createLiveKitTokenVerifier returns null when either half of the key pair is missing —
  // never treat an unverifiable token as authorization.
  const jwt = await new AccessToken('test-key', 'test-secret', { identity: 'guest-1' }).toJwt()
  const ok = await authorizeLiveKitUpgrade({ session: null, accessToken: jwt, tokenVerifier: createLiveKitTokenVerifier(undefined, undefined) })
  assert.equal(ok, false)
})
