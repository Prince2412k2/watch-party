import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  ADMIN_REVALIDATION_MS, createRequireAdmin, requireAdmin, requireAuth,
} from './auth.js'

function ctx(session) {
  const res = {
    statusCode: null,
    body: null,
    status(code) { this.statusCode = code; return this },
    json(payload) { this.body = payload; return this },
  }
  let nexted = false
  return { req: { session, sessionID: 'session-id' }, res, next: () => { nexted = true }, wasNexted: () => nexted }
}

test('requireAdmin rejects an anonymous request with 401', async () => {
  const c = ctx({})
  await requireAdmin(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, 401)
  assert.equal(c.wasNexted(), false)
})

test('requireAdmin rejects a signed-in non-admin with 403', async () => {
  const c = ctx({ jellyfin: { userId: 'u1', isAdmin: false, adminCheckedAt: Date.now() } })
  await requireAdmin(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, 403)
  assert.equal(c.wasNexted(), false)
})

test('requireAdmin rejects a session with no isAdmin field at all', async () => {
  // A session shaped by an older login must fail closed, not pass.
  const c = ctx({ jellyfin: { userId: 'u1' } })
  await requireAdmin(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, 403)
  assert.equal(c.wasNexted(), false)
})

test('requireAdmin passes a recently verified Jellyfin administrator through', async () => {
  const c = ctx({ jellyfin: { userId: 'u1', isAdmin: true, adminCheckedAt: Date.now() } })
  await requireAdmin(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, null)
  assert.equal(c.wasNexted(), true)
})

test('requireAdmin rejects a revoked administrator after the role cache expires', async () => {
  const now = 1_000_000
  const middleware = createRequireAdmin({ now: () => now, getAdminStatus: async () => false })
  const jellyfin = {
    userId: 'u1', accessToken: 'token', isAdmin: true,
    adminCheckedAt: now - ADMIN_REVALIDATION_MS - 1,
  }
  const c = ctx({ jellyfin })

  await middleware(c.req, c.res, c.next)

  assert.equal(c.res.statusCode, 403)
  assert.equal(c.wasNexted(), false)
  assert.equal(jellyfin.isAdmin, false)
  assert.equal(jellyfin.adminCheckedAt, now)
})

test('requireAdmin admits a stale administrator only after successful revalidation', async () => {
  let checks = 0
  const middleware = createRequireAdmin({
    now: () => 1_000_000,
    getAdminStatus: async () => { checks++; return true },
  })
  const c = ctx({ jellyfin: { userId: 'u1', accessToken: 'token', isAdmin: true, adminCheckedAt: 0 } })

  await middleware(c.req, c.res, c.next)

  assert.equal(checks, 1)
  assert.equal(c.wasNexted(), true)
})

test('requireAdmin revalidates stale non-admin status', async () => {
  const middleware = createRequireAdmin({
    now: () => 1_000_000,
    getAdminStatus: async () => true,
  })
  const c = ctx({ jellyfin: { userId: 'u1', accessToken: 'token', isAdmin: false, adminCheckedAt: 0 } })

  await middleware(c.req, c.res, c.next)

  assert.equal(c.req.session.jellyfin.isAdmin, true)
  assert.equal(c.wasNexted(), true)
})

test('requireAdmin coalesces concurrent refreshes for one session user', async () => {
  let checks = 0
  let release
  const pending = new Promise(resolve => { release = resolve })
  const middleware = createRequireAdmin({
    now: () => 1_000_000,
    getAdminStatus: async () => { checks++; return pending },
  })
  const session = { jellyfin: { userId: 'u1', accessToken: 'token', isAdmin: true, adminCheckedAt: 0 } }
  const first = ctx(session)
  const second = ctx(session)

  const requests = [
    middleware(first.req, first.res, first.next),
    middleware(second.req, second.res, second.next),
  ]
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(checks, 1)
  release(true)
  await Promise.all(requests)
  assert.equal(first.wasNexted(), true)
  assert.equal(second.wasNexted(), true)
})

test('requireAdmin bounds a stalled Jellyfin role refresh', async () => {
  const middleware = createRequireAdmin({
    now: () => 1_000_000,
    getAdminStatus: async () => new Promise(() => {}),
    refreshTimeoutMs: 10,
  })
  const c = ctx({ jellyfin: { userId: 'u1', accessToken: 'token', isAdmin: true, adminCheckedAt: 0 } })

  await middleware(c.req, c.res, c.next)

  assert.equal(c.res.statusCode, 502)
  assert.equal(c.wasNexted(), false)
})

test('requireAuth still admits a non-admin — adding and searching stay open', () => {
  const c = ctx({ jellyfin: { userId: 'u1', isAdmin: false } })
  requireAuth(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, null)
  assert.equal(c.wasNexted(), true)
})
