import test from 'node:test'
import assert from 'node:assert/strict'

const extensionOrigin = 'safari-web-extension://12345678-1234-1234-1234-123456789ABC'
const originalFetch = globalThis.fetch
let saved = {}
let onMessage, onInstalled, onRemoved
const opened = []
const navigations = []
globalThis.chrome = {
  runtime: {
    id: 'safari-test', getURL: path => `${extensionOrigin}/${path.replace(/^\//, '')}`,
    onInstalled: { addListener(listener) { onInstalled = listener } },
    onConnect: { addListener() {} },
    onMessage: { addListener(listener) { onMessage = listener } },
  },
  // Deliberately omit setAccessLevel, storage.session, and action.openPopup.
  storage: {
    local: {
      async get(keys) { return Object.fromEntries((typeof keys === 'string' ? [keys] : keys).filter(key => key in saved).map(key => [key, structuredClone(saved[key])])) },
      async set(values) { Object.assign(saved, structuredClone(values)) },
      async remove(keys) { for (const key of typeof keys === 'string' ? [keys] : keys) delete saved[key] },
    },
    onChanged: { addListener() {} },
  },
  tabs: { onRemoved: { addListener(listener) { onRemoved = listener } }, async create(options) { opened.push(options); return { id: 1 } }, async get() { return { url: 'https://www.youtube.com/' } }, async update(id, options) { navigations.push({ id, ...options }) } },
}
globalThis.fetch = async (_url, options) => {
  assert.equal(options.credentials, 'omit')
  assert.ok(options.signal instanceof AbortSignal)
  return Response.json({ ok: true, protocol: 3 })
}
await import('../src/background.ts')
const sender = { id: chrome.runtime.id, url: `${extensionOrigin}/popup.html` }
const send = (type, values = {}, source = sender) => new Promise(resolve => {
  if (onMessage({ channel: 'watchparty', type, ...values }, source, resolve) === false) resolve(null)
})
test.after(() => { globalThis.fetch = originalFetch; delete globalThis.chrome })
test.beforeEach(() => { saved = {}; opened.length = 0; navigations.length = 0 })

test('Safari worker starts and handles installation without setAccessLevel', async () => {
  assert.doesNotThrow(() => onInstalled())
  const status = (await send('status')).value
  assert.equal(status.configured, true)
  assert.equal(status.setup.server, 'https://watch.sniffkin.tech')
})
test('Safari bootstrap succeeds without storage.session', async () => {
  const result = await send('bootstrap')
  assert.equal(result.error, undefined)
  assert.equal(result.value.follow, '')
  assert.equal(result.value.setup.server, 'https://watch.sniffkin.tech')
})
test('a fresh install can submit a code to the default server without saving settings', async () => {
  const fetch = globalThis.fetch
  let requested
  globalThis.fetch = async (url, options) => {
    requested = { url, body: JSON.parse(options.body) }
    return Response.json({ error: 'Invite code not found' }, { status: 404 })
  }
  try {
    assert.match((await send('join-party', { code: 'AABB-CCDD-EEFF' })).error, /Invite code not found/)
    assert.equal(requested.url, 'https://watch.sniffkin.tech/api/extension/join-invite')
    assert.equal(requested.body.code, 'AABB-CCDD-EEFF')
    assert.equal(saved.setup, undefined)
  } finally { globalThis.fetch = fetch }
})
test('Safari session fallback preserves navigation and AV state across requests', async () => {
  await send('storage-set', { area: 'session', value: { 'follow-null': 'https://www.youtube.com/', 'av-party-user': { camera: false, mic: true } } })
  assert.equal((await send('bootstrap')).value.follow, 'https://www.youtube.com/')
  assert.deepEqual((await send('storage-get', { area: 'session', keys: ['av-party-user'] })).value['av-party-user'], { camera: false, mic: true })
  await send('storage-remove', { area: 'session', keys: ['av-party-user'] })
  assert.deepEqual((await send('storage-get', { area: 'session', keys: 'av-party-user' })).value, {})
})
test('Safari opens a settings tab when openPopup is unavailable', async () => {
  assert.equal((await send('open-settings')).error, undefined)
  assert.deepEqual(opened, [{ url: `${extensionOrigin}/popup.html#settings` }])
})
test('Safari health request works without AbortSignal.timeout', async () => {
  const descriptor = Object.getOwnPropertyDescriptor(AbortSignal, 'timeout')
  Object.defineProperty(AbortSignal, 'timeout', { configurable: true, value: undefined })
  try {
    saved.setup = { server: 'https://watch.example', name: 'Safari viewer' }
    assert.equal((await send('status')).value.connected, true)
  } finally { Object.defineProperty(AbortSignal, 'timeout', descriptor) }
})
test('Safari content scripts still cannot read credentials through the broker', async () => {
  assert.equal(await send('storage-get', { area: 'local', keys: 'connection' }, { ...sender, url: 'https://www.youtube.com/' }), null)
})
test('Safari follows shared pages through the tab API and stops when the party is cleared', async () => {
  saved.connection = { server: 'https://watch.example', user: { userId: 'viewer' } }
  saved.activeParty = { id: 'party', server: 'https://watch.example', userId: 'viewer', tabId: 17 }
  const source = { ...sender, url: `${extensionOrigin}/index.html`, tab: { id: 17 } }
  const url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
  assert.equal((await send('navigate-party', { partyId: 'party', url }, source)).error, undefined)
  assert.deepEqual(navigations, [{ id: 17, url }])
  assert.match((await send('navigate-party', { partyId: 'party', url: 'https://evil.example/' }, source)).error, /Only YouTube/)
  assert.match((await send('navigate-party', { partyId: 'party', url }, { ...source, tab: { id: 18 } })).error, /no longer/)
  delete saved.activeParty
  assert.match((await send('navigate-party', { partyId: 'party', url }, source)).error, /no longer/)
  assert.equal(navigations.length, 1)
})
test('closing the owning tab clears the active code and session cache; other tabs cannot clear it', async () => {
  saved.activeParty = { id: 'party', inviteCode: 'AABBCCDDEEFF', userId: 'viewer', tabId: 19 }
  await send('storage-set', { area: 'session', value: { 'follow-19': 'https://www.youtube.com/', 'av-party-viewer': { camera: true } } })
  await onRemoved(18)
  assert.equal(saved.activeParty.id, 'party')
  await onRemoved(19)
  assert.equal(saved.activeParty, null)
  assert.equal(saved.connection, null)
  assert.deepEqual((await send('storage-get', { area: 'session', keys: ['follow-19', 'av-party-viewer'] })).value, {})
})
