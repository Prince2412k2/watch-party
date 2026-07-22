import test from 'node:test'
import assert from 'node:assert/strict'

process.env.NEKO_ENABLED = 'true'

const { isAllowedNekoRequest, authorizeNekoUpgrade, nekoMembershipGate, nekoAllowListGate } = await import('./proxy.js')

function url(path) {
  const u = new URL(path, 'http://internal')
  return { pathname: u.pathname, searchParams: u.searchParams }
}

test('allow-list: static assets, ws, root are allowed', () => {
  for (const path of ['/neko/', '/neko', '/neko/js/app.4919abb0.js', '/neko/css/app.abc123.css',
    '/neko/favicon.ico', '/neko/apple-touch-icon.png', '/neko/site.webmanifest',
    '/neko/safari-pinned-tab.svg', '/neko/api/ws', '/neko/api/webrtc/config']) {
    const { pathname, searchParams } = url(path)
    assert.equal(isAllowedNekoRequest(pathname, searchParams), true, path)
  }
})

test('allow-list: metrics, profile, room control, legacy ws are denied', () => {
  for (const path of ['/neko/metrics', '/neko/api/profile', '/neko/api/room/control',
    '/neko/api/room/control/reset', '/neko/ws', '/neko/api/sessions']) {
    const { pathname, searchParams } = url(path)
    assert.equal(isAllowedNekoRequest(pathname, searchParams), false, path)
  }
})

test('allow-list: usr/pwd query params deny even an otherwise-allowed path', () => {
  for (const q of ['usr=a', 'pwd=b']) {
    const { pathname, searchParams } = url(`/neko/api/ws?${q}`)
    assert.equal(isAllowedNekoRequest(pathname, searchParams), false, q)
  }
})

test('allow-list: token query param is allowed ONLY on the ws endpoint (our client\'s own session token)', () => {
  const ws = url('/neko/api/ws?token=abc')
  assert.equal(isAllowedNekoRequest(ws.pathname, ws.searchParams), true)

  const other = url('/neko/js/app.js?token=abc')
  assert.equal(isAllowedNekoRequest(other.pathname, other.searchParams), false)
})

function makeDeps({ leaseState = 'active', partyId = 'p1', member = true } = {}) {
  return {
    lease: { getLease: () => (leaseState ? { partyId, state: leaseState } : null) },
    getSession: (id) => (id === partyId ? { id: partyId } : null),
    isMember: () => member,
  }
}

function makeRes() {
  return {
    statusCode: null,
    status(code) { this.statusCode = code; return this },
    end() { return this },
  }
}

test('nekoMembershipGate: 403 when no active lease', () => {
  const gate = nekoMembershipGate(makeDeps({ leaseState: null }))
  const res = makeRes()
  let called = false
  gate({ session: { jellyfin: { userId: 'u1' } } }, res, () => { called = true })
  assert.equal(res.statusCode, 403)
  assert.equal(called, false)
})

test('nekoMembershipGate: 403 when not a member of the active-lease party', () => {
  const gate = nekoMembershipGate(makeDeps({ member: false }))
  const res = makeRes()
  gate({ session: { jellyfin: { userId: 'u1' } } }, res, () => {})
  assert.equal(res.statusCode, 403)
})

test('nekoMembershipGate: next() called for an active-lease member', () => {
  const gate = nekoMembershipGate(makeDeps())
  const res = makeRes()
  let called = false
  gate({ session: { jellyfin: { userId: 'u1' } } }, res, () => { called = true })
  assert.equal(called, true)
  assert.equal(res.statusCode, null)
})

test('nekoAllowListGate: forwards allow-listed path, 403s a denied one', () => {
  const res1 = makeRes()
  let called = false
  nekoAllowListGate({ originalUrl: '/neko/js/app.js' }, res1, () => { called = true })
  assert.equal(called, true)

  const res2 = makeRes()
  nekoAllowListGate({ originalUrl: '/neko/metrics' }, res2, () => {})
  assert.equal(res2.statusCode, 403)
})

test('authorizeNekoUpgrade: disabled -> 403', () => {
  process.env.NEKO_ENABLED = 'false'
  try {
    const decision = authorizeNekoUpgrade({ url: '/neko/api/ws', session: { jellyfin: { userId: 'u1' } } }, makeDeps())
    assert.deepEqual(decision, { ok: false, status: 403 })
  } finally {
    process.env.NEKO_ENABLED = 'true'
  }
})

test('authorizeNekoUpgrade: unauthenticated -> 401', () => {
  const decision = authorizeNekoUpgrade({ url: '/neko/api/ws', session: {} }, makeDeps())
  assert.deepEqual(decision, { ok: false, status: 401 })
})

test('authorizeNekoUpgrade: non-member -> 403', () => {
  const decision = authorizeNekoUpgrade({ url: '/neko/api/ws', session: { jellyfin: { userId: 'u1' } } }, makeDeps({ member: false }))
  assert.deepEqual(decision, { ok: false, status: 403 })
})

test('authorizeNekoUpgrade: inactive lease -> 403', () => {
  const decision = authorizeNekoUpgrade({ url: '/neko/api/ws', session: { jellyfin: { userId: 'u1' } } }, makeDeps({ leaseState: 'starting' }))
  assert.deepEqual(decision, { ok: false, status: 403 })
})

test('authorizeNekoUpgrade: disallowed path -> 403 even for an active-lease member', () => {
  const decision = authorizeNekoUpgrade({ url: '/neko/ws', session: { jellyfin: { userId: 'u1' } } }, makeDeps())
  assert.deepEqual(decision, { ok: false, status: 403 })
})

test('authorizeNekoUpgrade: permitted active-lease member -> ok', () => {
  const decision = authorizeNekoUpgrade({ url: '/neko/api/ws', session: { jellyfin: { userId: 'u1' } } }, makeDeps())
  assert.deepEqual(decision, { ok: true })
})
