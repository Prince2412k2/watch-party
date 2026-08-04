import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

// A private database per run: these tests write real lease rows.
const databasePath = join(tmpdir(), `watchparty-browser-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath
process.env.BROWSER_ENABLED = '1'
process.env.BROWSER_AGENT_TOKEN = 'test-token'
process.env.LIVEKIT_API_KEY = 'devkey'
process.env.LIVEKIT_API_SECRET = 'secret-that-is-long-enough-for-jwt'

const service = await import('./service.js')
const lease = await import('./lease.js')
const { createSession, deleteSession, getSession, approveGuest, addToWaiting, publicSession } =
  await import('../session.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

function party() {
  const session = createSession({ hostId: 'host', hostName: 'Host', hostSocketId: 'sock-host' })
  addToWaiting(session, { userId: 'guest', name: 'Guest', socketId: 'sock-guest' })
  approveGuest(session, 'guest')
  return session
}

function cleanup(session) {
  lease.forceClear()
  deleteSession(session.id)
}

// ── input sanitising ───────────────────────────────────────────────────────

test('sanitizeEvents keeps well-formed pointer, scroll, key and text events', () => {
  const clean = service.sanitizeEvents([
    { type: 'move', x: 10.6, y: 20.2 },
    { type: 'down', x: 5, y: 5, button: 3 },
    { type: 'scroll', dy: 120 },
    { type: 'key', key: 'ctrl+l' },
    { type: 'text', text: 'hello' },
  ])
  assert.deepEqual(clean, [
    { type: 'move', x: 11, y: 20, button: 1 },
    { type: 'down', x: 5, y: 5, button: 3 },
    { type: 'scroll', dy: 120 },
    { type: 'key', key: 'ctrl+l' },
    { type: 'text', text: 'hello' },
  ])
})

test('sanitizeEvents drops shell-injection attempts in key names', () => {
  // The agent turns this into an argv entry for xdotool. It validates too, but
  // this is the layer that has to assume the client is hostile.
  const clean = service.sanitizeEvents([
    { type: 'key', key: 'a; rm -rf /' },
    { type: 'key', key: '$(whoami)' },
    { type: 'key', key: 'ctrl+alt+shift+super+Delete' },
  ])
  assert.deepEqual(clean, [{ type: 'key', key: 'ctrl+alt+shift+super+Delete' }])
})

test('sanitizeEvents rejects unknown types, non-finite coordinates and empty text', () => {
  assert.deepEqual(service.sanitizeEvents([
    { type: 'exec', cmd: 'ls' },
    { type: 'move', x: NaN, y: 1 },
    { type: 'move', x: 1 },
    { type: 'text', text: '' },
    'not an object',
    null,
  ]), [])
})

test('sanitizeEvents bounds batch size and text length', () => {
  const many = Array.from({ length: 200 }, () => ({ type: 'move', x: 1, y: 1 }))
  assert.equal(service.sanitizeEvents(many).length, 64)
  const [long] = service.sanitizeEvents([{ type: 'text', text: 'x'.repeat(1000) }])
  assert.equal(long.text.length, 256)
})

// ── url handling ───────────────────────────────────────────────────────────

test('normalizeUrl accepts http(s) and assumes https for a bare host', () => {
  assert.equal(service.normalizeUrl('https://youtube.com/watch?v=1'), 'https://youtube.com/watch?v=1')
  assert.equal(service.normalizeUrl('example.com'), 'https://example.com/')
  assert.equal(service.normalizeUrl('  http://example.com  '), 'http://example.com/')
})

test('normalizeUrl rejects non-http schemes and junk', () => {
  for (const value of [
    'file:///etc/passwd',
    'javascript:alert(1)',
    'data:text/html,<script>',
    'chrome://settings',
    '',
    '   ',
    null,
    'x'.repeat(3000),
  ]) {
    assert.equal(service.normalizeUrl(value), null, `expected ${String(value).slice(0, 24)} to be rejected`)
  }
})

// ── control lease ──────────────────────────────────────────────────────────

test('the host drives by default and a guest can be granted and reclaimed', () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: 'https://example.com', driverUserId: 'host', requests: [] }

  assert.equal(service.isDriver(session, 'host'), true)
  assert.equal(service.isDriver(session, 'guest'), false)

  assert.deepEqual(service.requestControl({ partyId: session.id, userId: 'guest', name: 'Guest' }), { ok: true })
  assert.deepEqual(session.browser.requests, [{ userId: 'guest', name: 'Guest' }])

  assert.deepEqual(service.grantControl({ partyId: session.id, hostUserId: 'host', targetUserId: 'guest' }), { ok: true })
  assert.equal(service.isDriver(session, 'guest'), true)
  assert.equal(service.isDriver(session, 'host'), false)
  assert.deepEqual(session.browser.requests, [], 'granting clears the pending request')

  assert.deepEqual(service.reclaimControl({ partyId: session.id, hostUserId: 'host' }), { ok: true })
  assert.equal(service.isDriver(session, 'host'), true)
  cleanup(session)
})

test('a guest cannot grant themselves control', () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: null, driverUserId: 'host', requests: [] }

  const result = service.grantControl({ partyId: session.id, hostUserId: 'guest', targetUserId: 'guest' })
  assert.deepEqual(result, { error: 'not host' })
  assert.equal(service.isDriver(session, 'host'), true)
  cleanup(session)
})

test('a non-member cannot be granted control or request it', () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: null, driverUserId: 'host', requests: [] }

  assert.deepEqual(
    service.grantControl({ partyId: session.id, hostUserId: 'host', targetUserId: 'stranger' }),
    { error: 'not a party member' }
  )
  assert.deepEqual(
    service.requestControl({ partyId: session.id, userId: 'stranger', name: 'Nobody' }),
    { error: 'not a party member' }
  )
  cleanup(session)
})

test('control returns to the host when the driver leaves', () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: null, driverUserId: 'guest', requests: [{ userId: 'guest', name: 'Guest' }] }

  service.handleMemberGone(session.id, 'guest')
  assert.equal(session.browser.driverUserId, 'host')
  assert.deepEqual(session.browser.requests, [])
  cleanup(session)
})

test('control follows the host through a host change', () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: null, driverUserId: 'host', requests: [] }

  service.handleHostChanged(session.id, 'guest', 'host')
  assert.equal(session.browser.driverUserId, 'guest')
  cleanup(session)
})

test('a host change does not steal control from a guest who was driving', () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: null, driverUserId: 'guest', requests: [] }

  service.handleHostChanged(session.id, 'somebody-else', 'host')
  assert.equal(session.browser.driverUserId, 'guest')
  cleanup(session)
})

test('control operations are refused when no browser is running', () => {
  const session = party()
  for (const call of [
    () => service.requestControl({ partyId: session.id, userId: 'guest', name: 'Guest' }),
    () => service.grantControl({ partyId: session.id, hostUserId: 'host', targetUserId: 'guest' }),
    () => service.reclaimControl({ partyId: session.id, hostUserId: 'host' }),
  ]) {
    assert.deepEqual(call(), { error: 'the shared browser is not running' })
  }
  cleanup(session)
})

// ── forwarding ─────────────────────────────────────────────────────────────

test('input from a non-driver is refused by the server, not merely hidden in the UI', async () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: null, driverUserId: 'host', requests: [] }

  const result = await service.forwardInput({
    partyId: session.id, userId: 'guest', events: [{ type: 'click', x: 1, y: 1 }],
  })
  assert.deepEqual(result, { error: 'not driving' })
  cleanup(session)
})

test('input is refused while the stream is still starting', async () => {
  const session = party()
  lease.acquireLease(session.id)
  session.browser = { state: 'starting', url: null, driverUserId: 'host', requests: [] }

  const result = await service.forwardInput({
    partyId: session.id, userId: 'host', events: [{ type: 'click', x: 1, y: 1 }],
  })
  assert.deepEqual(result, { error: 'the shared browser is still starting' })
  cleanup(session)
})

// ── exclusivity ────────────────────────────────────────────────────────────

test('a second party is refused without being told who holds the browser', async () => {
  const first = party()
  const second = createSession({ hostId: 'host2', hostName: 'Host Two', hostSocketId: 'sock-2' })
  lease.acquireLease(first.id)
  lease.markActive(first.id)
  first.browser = { state: 'active', url: null, driverUserId: 'host', requests: [] }

  const result = await service.startBrowser({ partyId: second.id, userId: 'host2' })
  assert.match(result.error, /in use/i)
  assert.doesNotMatch(result.error, new RegExp(first.id, 'i'), 'the refusal must not name the occupying party')
  assert.doesNotMatch(result.error, /Host\b/, 'the refusal must not name the occupying host')
  assert.equal(second.browser, null, 'a refused start must not put the party on the browser activity')
  assert.equal(second.stage, 'lobby')

  cleanup(first)
  deleteSession(second.id)
})

test('only the host can start or stop the browser', async () => {
  const session = party()
  assert.deepEqual(await service.startBrowser({ partyId: session.id, userId: 'guest' }), { error: 'not host' })
  assert.equal(lease.getLease(), null, 'a refused start must not take the lease')
  assert.deepEqual(await service.stopBrowser({ partyId: session.id, userId: 'guest' }), { error: 'not host' })
  cleanup(session)
})

test('a refused start leaves a playing party alone', async () => {
  const holder = party()
  lease.acquireLease(holder.id)
  lease.markActive(holder.id)

  const watching = createSession({ hostId: 'host3', hostName: 'Three', hostSocketId: 'sock-3', mediaItemId: 'movie-1' })
  let leftActivity = false

  const result = await service.startBrowser({
    partyId: watching.id,
    userId: 'host3',
    onActivityEnter: () => { leftActivity = true },
  })

  assert.ok(result.error)
  assert.equal(leftActivity, false, 'a party must not lose its movie to a start that was refused')
  assert.equal(watching.stage, 'watching')
  assert.equal(watching.mediaItemId, 'movie-1')

  cleanup(holder)
  deleteSession(watching.id)
})

// ── teardown ───────────────────────────────────────────────────────────────

test('teardown clears the lease and the activity even when the agent is unreachable', async () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: 'https://example.com', driverUserId: 'host', requests: [] }
  session.stage = 'browser'

  // Nothing is listening on BROWSER_AGENT_URL in this test run, so the stop call
  // genuinely fails — which is the case that matters: a party must still be able
  // to end.
  await service.teardownBrowser(session.id, 'test')

  assert.equal(lease.getLease(), null)
  assert.equal(session.browser, null)
  assert.equal(session.stage, 'lobby', 'the party falls back to the lobby, not a dead browser')
  cleanup(session)
})

test('teardown is idempotent and safe for a party that never had a browser', async () => {
  const session = party()
  await service.teardownBrowser(session.id, 'first')
  await service.teardownBrowser(session.id, 'second')
  await service.teardownBrowser('NOSUCHID', 'third')
  assert.equal(session.stage, 'lobby')
  cleanup(session)
})

test('concurrent teardowns share one in-flight operation', async () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  session.browser = { state: 'active', url: null, driverUserId: 'host', requests: [] }

  const first = service.teardownBrowser(session.id, 'a')
  const second = service.teardownBrowser(session.id, 'b')
  assert.equal(first, second, 'a second teardown joins the first rather than racing it')
  await first
  assert.equal(lease.getLease(), null)
  cleanup(session)
})

// ── the monitor ────────────────────────────────────────────────────────────

test('the monitor reclaims the browser when its party is gone', async () => {
  const session = party()
  lease.acquireLease(session.id)
  lease.markActive(session.id)
  const partyId = session.id
  deleteSession(partyId)          // as if the party ended without tearing down

  await service.tick()
  assert.equal(lease.getLease(), null)
})

// ── what clients are told ──────────────────────────────────────────────────

test('party state carries browser availability and the current activity', () => {
  const session = party()
  const idle = publicSession(session)
  assert.equal(idle.browserAvailable, true, 'availability comes from the server, not the client build')
  assert.equal(idle.browser, null)
  assert.equal(idle.stage, 'lobby')

  session.stage = 'browser'
  session.browser = {
    state: 'active', url: 'https://example.com', driverUserId: 'guest',
    requests: [{ userId: 'g2', name: 'Two' }], error: null, focused: true,
    screen: { w: 1280, h: 720 },
  }
  const active = publicSession(session)
  assert.equal(active.stage, 'browser')
  assert.deepEqual(active.browser, {
    state: 'active',
    url: 'https://example.com',
    driverUserId: 'guest',
    requests: [{ userId: 'g2', name: 'Two' }],
    error: null,
    screen: { w: 1280, h: 720 },
  })
  assert.equal('focused' in active.browser, false, 'internal bookkeeping stays server-side')
  cleanup(session)
})

// ── the screen size clients need to map a click ─────────────────────────────

test('the remote screen size is in the first broadcast, not only once streaming', async () => {
  // Gating a client's input on a field that arrives late (or not at all, against
  // an older server) disabled driving with nothing on screen to explain it. So the
  // configured size has to be in the state clients see FIRST — asserted on the
  // actual broadcast, because with no agent reachable this start then tears down.
  const session = party()
  const states = []
  service.initBrowserService({
    to: () => ({ emit: (event, payload) => { if (event === 'party:state') states.push(payload) } }),
  })

  await service.startBrowser({ partyId: session.id, userId: 'host' })
  service.initBrowserService(null)

  const first = states[0]
  assert.ok(first, 'starting the browser broadcasts party state')
  assert.equal(first.stage, 'browser')
  assert.deepEqual(first.browser.screen, { w: 1280, h: 720 },
    'clients can map a click from the moment they are told the browser exists')

  cleanup(session)
})
