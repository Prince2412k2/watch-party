import { test } from 'node:test'
import assert from 'node:assert/strict'

import { requireAdmin, requireAuth } from './auth.js'

function ctx(session) {
  const res = {
    statusCode: null,
    body: null,
    status(code) { this.statusCode = code; return this },
    json(payload) { this.body = payload; return this },
  }
  let nexted = false
  return { req: { session }, res, next: () => { nexted = true }, wasNexted: () => nexted }
}

test('requireAdmin rejects an anonymous request with 401', () => {
  const c = ctx({})
  requireAdmin(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, 401)
  assert.equal(c.wasNexted(), false)
})

test('requireAdmin rejects a signed-in non-admin with 403', () => {
  const c = ctx({ jellyfin: { userId: 'u1', isAdmin: false } })
  requireAdmin(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, 403)
  assert.equal(c.wasNexted(), false)
})

test('requireAdmin rejects a session with no isAdmin field at all', () => {
  // A session shaped by an older login must fail closed, not pass.
  const c = ctx({ jellyfin: { userId: 'u1' } })
  requireAdmin(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, 403)
  assert.equal(c.wasNexted(), false)
})

test('requireAdmin passes a Jellyfin administrator through', () => {
  const c = ctx({ jellyfin: { userId: 'u1', isAdmin: true } })
  requireAdmin(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, null)
  assert.equal(c.wasNexted(), true)
})

test('requireAuth still admits a non-admin — adding and searching stay open', () => {
  const c = ctx({ jellyfin: { userId: 'u1', isAdmin: false } })
  requireAuth(c.req, c.res, c.next)
  assert.equal(c.res.statusCode, null)
  assert.equal(c.wasNexted(), true)
})
