import test from 'node:test'
import assert from 'node:assert/strict'

const originalChrome = Object.getOwnPropertyDescriptor(globalThis, 'chrome')
const originalFetch = globalThis.fetch
const listeners = []
const changeListeners = []
let saved = {}
let displayName = 'Admin'
const clone = value => structuredClone(value)
const storage = value => ({
  async get(keys) { const data = value(); return Object.fromEntries((typeof keys === 'string' ? [keys] : keys || Object.keys(data)).filter(key => key in data).map(key => [key, clone(data[key])])) },
  async set(values) { Object.assign(value(), clone(values)); for (const listener of changeListeners) listener({}, 'local') },
  async remove(keys) { for (const key of typeof keys === 'string' ? [keys] : keys) delete value()[key] },
  async setAccessLevel() {},
})
Object.defineProperty(globalThis, 'chrome', { configurable: true, value: {
  runtime: { id: 'test-extension', getURL: path => `chrome-extension://test-extension${path}`, onInstalled: { addListener() {} }, onConnect: { addListener() {} }, onMessage: { addListener(listener) { listeners.push(listener) } } },
  storage: { local: storage(() => saved), session: storage(() => ({})), onChanged: { addListener(listener) { changeListeners.push(listener) } } },
} })
globalThis.fetch = async (url, options = {}) => {
  const path = new URL(url).pathname
  const body = options.body ? JSON.parse(options.body) : {}
  if (path.endsWith('/health')) return Response.json({ ok: true, protocol: 3 })
  if (path.endsWith('/login')) return body.password === 'valid-pass' ? Response.json({ token: 'a'.repeat(64), user: { userId: 'admin-id', name: 'Admin', isAdmin: true }, expiresAt: Date.now() + 100_000 }) : Response.json({ error: 'Invalid credentials' }, { status: 401 })
  if (path.endsWith('/me')) {
    if (options.method === 'PATCH') displayName = body.name
    return Response.json({ user: { userId: 'admin-id', name: displayName, isAdmin: true }, expiresAt: Date.now() + 100_000, session: null })
  }
  throw new Error(`Unexpected request ${path}`)
}
await import('../src/background.ts')

const sender = { id: 'test-extension', url: 'chrome-extension://test-extension/popup.html' }
function send(type, values = {}, source = sender) {
  return new Promise(resolve => { const handled = listeners[0]({ channel: 'watchparty', type, ...values }, source, resolve); if (handled === false) resolve(null) })
}
test.after(() => {
  globalThis.fetch = originalFetch
  if (originalChrome) Object.defineProperty(globalThis, 'chrome', originalChrome)
  else delete globalThis.chrome
})
test.beforeEach(() => { saved = { setup: { server: 'https://old.example', name: 'Original', username: 'admin' }, connection: { server: 'https://old.example', token: 'old-token', user: { userId: 'admin-id', name: 'Original', isAdmin: true } } }; displayName = 'Admin' })

test('incorrect credentials do not change any saved setup or login', async () => {
  const before = clone(saved)
  const result = await send('save-settings', { server: 'https://new.example', name: 'New name', username: 'admin', password: 'wrong-pass' })
  assert.match(result.error, /Invalid credentials/)
  assert.deepEqual(saved, before)
})
test('a different username cannot reuse the old validated login without a password', async () => {
  const before = clone(saved)
  const result = await send('save-settings', { server: 'https://old.example', name: 'Changed', username: 'different', password: '' })
  assert.match(result.error, /password/)
  assert.deepEqual(saved, before)
})
test('valid credentials save a verified admin session and display name, not the password', async () => {
  const result = await send('save-settings', { server: 'https://new.example', name: 'New name', username: 'admin', password: 'valid-pass' })
  assert.equal(result.error, undefined)
  assert.equal(saved.setup.server, 'https://new.example')
  assert.equal(saved.connection.user.isAdmin, true)
  assert.equal(saved.connection.user.name, 'New name')
  assert.equal(JSON.stringify(saved).includes('valid-pass'), false)
})
test('server verification repairs a stale cached admin flag', async () => {
  saved.connection.user.isAdmin = false
  const result = await send('status')
  assert.equal(result.value.isAdmin, true)
  assert.equal(saved.connection.user.isAdmin, true)
})
test('content scripts cannot use the trusted storage broker to read credentials', async () => {
  const result = await send('storage-get', { area: 'local', keys: 'connection' }, { id: 'test-extension', url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' })
  assert.equal(result, null)
})
