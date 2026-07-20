import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const databasePath = join(tmpdir(), `watchparty-routes-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath
process.env.NEKO_ENABLED = 'true'
process.env.NEKO_PUBLIC_WS = 'wss://example.test/neko/api/ws'
process.env.NEKO_USERNAME_SECRET = 'a-sufficiently-long-test-secret'

const { registerNekoRoutes, deriveUsername, scopeCookieToNeko, createSessionBroker } = await import('./routes.js')
const { createSession } = await import('../session.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

function makeSession(overrides = {}) {
  return createSession({
    hostId: 'host-1', hostToken: 't', hostDeviceId: 'd', hostName: 'Host',
    hostSocketId: 's1', mediaItemId: null, mediaSourceId: null,
    ...overrides,
  })
}

function makeReq({ params, session }) {
  return { params, session }
}
function makeRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: null,
    status(code) { this.statusCode = code; return this },
    json(body) { this.body = body; return this },
    setHeader(name, value) { this.headers[name] = value },
  }
  return res
}
function fakeApp() {
  const routes = {}
  return {
    post(path, handler) { routes[path] = handler },
    routes,
  }
}
function fakeIo() {
  return { on() {} }
}

function makeDeps({ leaseState = 'active', partyId, leaseId = 'lease-1', hasHost = false, hostSessionId = null } = {}) {
  const recordedSessions = new Map() // key -> nekoSessionId
  let sessionCounter = 0
  const deletedIds = []
  const lease = {
    getLease: () => (leaseState ? { partyId, state: leaseState, leaseId, hostName: 'Host' } : null),
    sessionsForUser: (pid, userId) => {
      const id = recordedSessions.get(`${pid}:${userId}`)
      return id ? [{ nekoSessionId: id }] : []
    },
    removeUserSession: (pid, userId, nekoSessionId) => {
      if (recordedSessions.get(`${pid}:${userId}`) === nekoSessionId) recordedSessions.delete(`${pid}:${userId}`)
    },
    recordUserSession: (pid, lid, userId, nekoSessionId) => {
      recordedSessions.set(`${pid}:${userId}`, nekoSessionId)
    },
  }
  const admin = {
    loginViewer: async (username) => {
      sessionCounter += 1
      return { sessionId: `neko-sess-${sessionCounter}`, cookie: `NEKO_SESSION=tok${sessionCounter}; HttpOnly; Secure; SameSite=None` }
    },
    deleteSession: async (id) => { deletedIds.push(id) },
    controlStatus: async () => ({ hasHost, hostSessionId }),
    giveControl: async () => {},
    resetControl: async () => {},
  }
  const controller = {
    currentController: async () => (hostSessionId ? { userId: 'controller-user', nekoSessionId: hostSessionId } : null),
  }
  return { lease, admin, controller, recordedSessions, deletedIds }
}

test('deriveUsername is deterministic and wp-prefixed', () => {
  const a = deriveUsername('p1', 'l1', 'u1', 'secret')
  const b = deriveUsername('p1', 'l1', 'u1', 'secret')
  const c = deriveUsername('p1', 'l1', 'u2', 'secret')
  assert.equal(a, b)
  assert.notEqual(a, c)
  assert.match(a, /^wp-[0-9a-f]+$/)
  assert.ok(a.length <= 40)
})

test('scopeCookieToNeko rewrites Path to /neko and keeps other attrs', () => {
  const rewritten = scopeCookieToNeko('NEKO_SESSION=abc; Path=/; HttpOnly; Secure; SameSite=None')
  assert.match(rewritten, /Path=\/neko/)
  assert.doesNotMatch(rewritten, /Path=\/;/)
  assert.match(rewritten, /HttpOnly/)
  assert.match(rewritten, /Secure/)
})

test('scopeCookieToNeko passes through null', () => {
  assert.equal(scopeCookieToNeko(null), null)
})

test('disabled neko -> 404', async () => {
  process.env.NEKO_ENABLED = 'false'
  try {
    const sess = makeSession()
    const deps = makeDeps({ partyId: sess.id })
    const app = fakeApp()
    registerNekoRoutes(app, fakeIo(), deps)
    const req = makeReq({ params: { id: sess.id }, session: { jellyfin: { userId: 'host-1' } } })
    const res = makeRes()
    await app.routes['/api/party/:id/browser/session'](req, res)
    assert.equal(res.statusCode, 404)
  } finally {
    process.env.NEKO_ENABLED = 'true'
  }
})

test('missing party -> 404', async () => {
  const deps = makeDeps({ partyId: 'nope' })
  const app = fakeApp()
  registerNekoRoutes(app, fakeIo(), deps)
  const req = makeReq({ params: { id: 'does-not-exist' }, session: { jellyfin: { userId: 'host-1' } } })
  const res = makeRes()
  await app.routes['/api/party/:id/browser/session'](req, res)
  assert.equal(res.statusCode, 404)
})

test('non-member -> 403', async () => {
  const sess = makeSession()
  const deps = makeDeps({ partyId: sess.id })
  const app = fakeApp()
  registerNekoRoutes(app, fakeIo(), deps)
  const req = makeReq({ params: { id: sess.id }, session: { jellyfin: { userId: 'stranger' } } })
  const res = makeRes()
  await app.routes['/api/party/:id/browser/session'](req, res)
  assert.equal(res.statusCode, 403)
})

test('lease not active for this party -> 409', async () => {
  const sess = makeSession()
  const deps = makeDeps({ partyId: 'someone-else', leaseState: 'active' })
  const app = fakeApp()
  registerNekoRoutes(app, fakeIo(), deps)
  const req = makeReq({ params: { id: sess.id }, session: { jellyfin: { userId: 'host-1' } } })
  const res = makeRes()
  await app.routes['/api/party/:id/browser/session'](req, res)
  assert.equal(res.statusCode, 409)
})

test('no lease at all -> 409', async () => {
  const sess = makeSession()
  const deps = makeDeps({ partyId: sess.id, leaseState: null })
  const app = fakeApp()
  registerNekoRoutes(app, fakeIo(), deps)
  const req = makeReq({ params: { id: sess.id }, session: { jellyfin: { userId: 'host-1' } } })
  const res = makeRes()
  await app.routes['/api/party/:id/browser/session'](req, res)
  assert.equal(res.statusCode, 409)
})

test('member of active-lease party -> 200 with cookie relayed and secret-free body', async () => {
  const sess = makeSession()
  const deps = makeDeps({ partyId: sess.id, hasHost: true, hostSessionId: 'neko-sess-1' })
  const app = fakeApp()
  registerNekoRoutes(app, fakeIo(), deps)
  const req = makeReq({ params: { id: sess.id }, session: { jellyfin: { userId: 'host-1' } } })
  const res = makeRes()
  await app.routes['/api/party/:id/browser/session'](req, res)
  assert.equal(res.statusCode, 200)
  assert.equal(res.body.wsUrl, process.env.NEKO_PUBLIC_WS)
  assert.equal(res.body.controllerUserId, 'controller-user')
  assert.match(res.headers['Set-Cookie'], /Path=\/neko/)
  const json = JSON.stringify(res.body)
  assert.doesNotMatch(json, /password/i)
  assert.doesNotMatch(json, /apiToken/i)
  assert.doesNotMatch(json, /token/i)
  assert.doesNotMatch(json, /leaseId/i)
})

test('concurrent POSTs for same user leave exactly one recorded session, no orphan', async () => {
  const sess = makeSession()
  const deps = makeDeps({ partyId: sess.id })
  const app = fakeApp()
  registerNekoRoutes(app, fakeIo(), deps)
  const req = () => makeReq({ params: { id: sess.id }, session: { jellyfin: { userId: 'host-1' } } })
  const results = await Promise.all([1, 2, 3].map(async () => {
    const res = makeRes()
    await app.routes['/api/party/:id/browser/session'](req(), res)
    return res
  }))
  for (const res of results) assert.equal(res.statusCode, 200)
  // exactly one mapping recorded for this user afterward
  const mapped = deps.lease.sessionsForUser(sess.id, 'host-1')
  assert.equal(mapped.length, 1)
})

test('createSessionBroker deletes a prior session before minting a new one', async () => {
  const deps = makeDeps({ partyId: 'p1' })
  const broker = createSessionBroker(deps)
  await broker.mintSession('p1', 'lease-1', 'u1')
  const firstId = deps.lease.sessionsForUser('p1', 'u1')[0].nekoSessionId
  await broker.mintSession('p1', 'lease-1', 'u1')
  assert.ok(deps.deletedIds.includes(firstId))
  assert.equal(deps.lease.sessionsForUser('p1', 'u1').length, 1)
})
