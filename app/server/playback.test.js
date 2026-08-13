import test from 'node:test'
import assert from 'node:assert/strict'
import express from 'express'

const { registerPlaybackRoutes } = await import('./playback.js')

const ITEM = 'a'.repeat(32)
const OTHER = 'b'.repeat(32)

// Jellyfin, as far as these routes are concerned: record what was POSTed where,
// and with whose token.
//
// [origin] is the test server's own, and requests to it are passed straight
// through to the real fetch. Without that this stub eats the test's OWN calls
// before they ever reach express, and every assertion below is made against a
// server that was never asked anything.
function fakeJellyfin(origin) {
  const calls = []
  const original = globalThis.fetch
  globalThis.fetch = async (url, init) => {
    if (String(url).startsWith(origin)) return original(url, init)
    calls.push({
      path: new URL(url).pathname,
      auth: init?.headers?.['X-Emby-Authorization'] ?? '',
      body: JSON.parse(init?.body ?? '{}'),
    })
    // 200 with a body, not 204: `new Response('', {status: 204})` is invalid —
    // a no-content response may not carry one.
    return new Response('{}', {
      status: 200,
      headers: { 'content-type': 'application/json' },
    })
  }
  return { calls, restore: () => { globalThis.fetch = original } }
}

function startServer({ authenticated = true } = {}) {
  const app = express()
  app.use(express.json())
  app.use((req, _res, next) => {
    req.session = authenticated
      ? { jellyfin: { userId: 'user-a', accessToken: 'token-a', deviceId: 'dev' } }
      : {}
    next()
  })
  registerPlaybackRoutes(app)
  return new Promise((resolve) => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, origin: `http://127.0.0.1:${server.address().port}` })
    })
  })
}

const post = (origin, path, body) =>
  fetch(`${origin}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })

test('each route reports to its Jellyfin endpoint, on the caller\'s own token', async (t) => {
  const { server, origin } = await startServer()
  const jf = fakeJellyfin(origin)
  t.after(() => { jf.restore(); server.close() })

  const routes = [
    ['/api/playback/started', '/Sessions/Playing'],
    ['/api/playback/progress', '/Sessions/Playing/Progress'],
    ['/api/playback/stopped', '/Sessions/Playing/Stopped'],
  ]
  for (const [route, jellyfinPath] of routes) {
    const response = await post(origin, route, {
      itemId: ITEM,
      positionTicks: 6_000_000_000,
      playSessionId: 'play-session',
    })
    assert.equal(response.status, 200, route)
    const call = jf.calls.at(-1)
    assert.equal(call.path, jellyfinPath)
    assert.equal(call.body.ItemId, ITEM)
    assert.equal(call.body.PositionTicks, 6_000_000_000)
    assert.equal(call.body.PlaySessionId, 'play-session')
    // Whose history this is comes from the session, never from the body.
    assert.match(call.auth, /Token="token-a"/)
  }
})

test('a body cannot name someone else, or a position out of any real range', async (t) => {
  const { server, origin } = await startServer()
  const jf = fakeJellyfin(origin)
  t.after(() => { jf.restore(); server.close() })

  // Whatever the body says about identity is ignored — there is no field for it,
  // and the token it is sent with is the session's.
  await post(origin, '/api/playback/progress', {
    itemId: ITEM,
    positionTicks: 1,
    userId: 'someone-else',
    UserId: 'someone-else',
  })
  const call = jf.calls.at(-1)
  assert.match(call.auth, /Token="token-a"/)
  assert.equal(call.body.UserId, undefined)
  assert.equal(call.body.userId, undefined)

  const rejected = [
    { positionTicks: 1 },                              // no item
    { itemId: 'not-an-id', positionTicks: 1 },
    { itemId: ITEM, positionTicks: -1 },
    // JSON carries no NaN — a client that computes one sends null, and reading
    // that as 0 would report the viewer back at the beginning and wipe their
    // resume point. Refused instead.
    { itemId: ITEM, positionTicks: Number.NaN },
    { itemId: ITEM },
    { itemId: ITEM, positionTicks: 1e18 },             // past any real runtime
    { itemId: ITEM, positionTicks: 1, mediaSourceId: '../../etc' },
  ]
  const before = jf.calls.length
  for (const body of rejected) {
    const response = await post(origin, '/api/playback/progress', body)
    assert.equal(response.status, 400, JSON.stringify(body))
  }
  assert.equal(jf.calls.length, before, 'nothing rejected reached Jellyfin')
})

test('started may omit a position; nothing else may', async (t) => {
  const { server, origin } = await startServer()
  const jf = fakeJellyfin(origin)
  t.after(() => { jf.restore(); server.close() })

  // Starting at the beginning is what starting means.
  const started = await post(origin, '/api/playback/started', { itemId: ITEM })
  assert.equal(started.status, 200)
  assert.equal(jf.calls.at(-1).body.PositionTicks, 0)

  for (const route of ['/api/playback/progress', '/api/playback/stopped']) {
    const response = await post(origin, route, { itemId: ITEM })
    assert.equal(response.status, 400, route)
  }
})

test('reporting requires a session', async (t) => {
  const { server, origin } = await startServer({ authenticated: false })
  const jf = fakeJellyfin(origin)
  t.after(() => { jf.restore(); server.close() })

  const response = await post(origin, '/api/playback/progress', {
    itemId: ITEM,
    positionTicks: 1,
  })
  assert.equal(response.status, 401)
  assert.equal(jf.calls.length, 0)
})

test('a Jellyfin failure is reported, not thrown, and never takes playback down', async (t) => {
  const { server, origin } = await startServer()
  const original = globalThis.fetch
  globalThis.fetch = async (url, init) =>
    String(url).startsWith(origin)
      ? original(url, init)
      : new Response('nope', { status: 500 })
  t.after(() => { globalThis.fetch = original; server.close() })

  const response = await post(origin, '/api/playback/progress', {
    itemId: OTHER,
    positionTicks: 42,
  })
  assert.equal(response.status, 502)
})
