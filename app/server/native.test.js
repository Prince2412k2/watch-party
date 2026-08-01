import test from 'node:test'
import assert from 'node:assert/strict'
import { buildNativeStreamTarget, mint, verify } from './native.js'

test('native stream targets the selected Jellyfin media source', () => {
  const target = buildNativeStreamTarget({
    baseUrl: 'http://jellyfin:8096',
    itemId: 'movie/item',
    mediaSourceId: '4k source',
    jellyfinToken: 'secret token',
  })

  assert.equal(
    target,
    'http://jellyfin:8096/Videos/movie%2Fitem/stream?static=true&mediaSourceId=4k%20source&api_key=secret%20token',
  )
})

const SECRET = 'test-only-native-stream-secret'
const JELLYFIN_TOKEN = 'super-secret-jellyfin-access-token'

function futurePayload(overrides = {}) {
  return {
    itemId: 'movie', mediaSourceId: 'movie', purpose: 'stream',
    userId: 'user-1', jellyfinToken: JELLYFIN_TOKEN, baseUrl: 'http://jellyfin:8096',
    exp: Date.now() + 60_000,
    ...overrides,
  }
}

test('mint/verify round-trips the payload for a valid token', () => {
  const payload = futurePayload()
  const token = mint(payload, SECRET)
  assert.deepEqual(verify(token, SECRET), payload)
})

test('verify rejects a tampered token', () => {
  const token = mint(futurePayload(), SECRET)
  const [id, mac] = token.split('.')
  // Flip the mac's last character — same length, different bytes.
  const flipped = mac.slice(0, -1) + (mac.at(-1) === 'A' ? 'B' : 'A')
  assert.equal(verify(`${id}.${flipped}`, SECRET), null)
  // A different, but otherwise validly-minted, id also fails against this mac.
  const other = mint(futurePayload(), SECRET).split('.')[0]
  assert.equal(verify(`${other}.${mac}`, SECRET), null)
})

test('verify rejects an expired token', () => {
  const token = mint(futurePayload({ exp: Date.now() - 1 }), SECRET)
  assert.equal(verify(token, SECRET), null)
})

test('verify fails closed on malformed input', () => {
  assert.equal(verify(undefined, SECRET), null)
  assert.equal(verify(null, SECRET), null)
  assert.equal(verify(42, SECRET), null)
  assert.equal(verify('', SECRET), null)
  assert.equal(verify('no-dot-here', SECRET), null)
  assert.equal(verify('.', SECRET), null)
  assert.equal(verify('.trailing-mac-only', SECRET), null)
  assert.equal(verify('leading-id-only.', SECRET), null)
  // A well-formed but never-minted id, with a mac that doesn't even match it.
  assert.equal(verify('bogus-id.bogus-mac', SECRET), null)
})

test('the Jellyfin token never appears in the minted token or the URL it rides in', () => {
  const token = mint(futurePayload(), SECRET)
  const url = `https://app.example/api/library/native/file?token=${encodeURIComponent(token)}`

  assert.equal(token.includes(JELLYFIN_TOKEN), false)
  assert.equal(url.includes(JELLYFIN_TOKEN), false)
  // Nor any encoding of it survives — the old bug was base64url(JSON), so
  // check that transform specifically rather than just the raw substring.
  const asBase64url = Buffer.from(JELLYFIN_TOKEN).toString('base64url')
  assert.equal(token.includes(asBase64url), false)

  // But the server can still recover it from the id alone.
  assert.equal(verify(token, SECRET).jellyfinToken, JELLYFIN_TOKEN)
})
