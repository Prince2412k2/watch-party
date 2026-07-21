import test from 'node:test'
import assert from 'node:assert/strict'

const {
  loginViewer, listSessions, deleteSession, setControlLock,
  giveControl, resetControl, controlStatus,
} = await import('./admin.js')

const config = {
  internalUrl: 'http://neko.internal:8080',
  apiToken: 'test-token',
  userPassword: 'test-password',
}

function jsonResponse(status, body, headers = {}) {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: { get: name => headers[name.toLowerCase()] ?? null },
    json: async () => body,
  }
}

function makeFetch(response) {
  const calls = []
  const fetchImpl = async (url, options) => {
    calls.push({ url, options })
    return response
  }
  fetchImpl.calls = calls
  return fetchImpl
}

test('loginViewer posts credentials and returns cookie and token without password', async () => {
  const fetchImpl = makeFetch(jsonResponse(200, { id: 'sess-1', token: 'sess-token-1' }, { 'set-cookie': 'NEKO_SESSION=abc; Path=/' }))
  const result = await loginViewer('wp-user1', config, fetchImpl)
  assert.equal(fetchImpl.calls.length, 1)
  assert.equal(fetchImpl.calls[0].url, `${config.internalUrl}/api/login`)
  assert.equal(fetchImpl.calls[0].options.method, 'POST')
  const sentBody = JSON.parse(fetchImpl.calls[0].options.body)
  assert.equal(sentBody.username, 'wp-user1')
  assert.equal(sentBody.password, config.userPassword)
  assert.deepEqual(result, { sessionId: 'sess-1', cookie: 'NEKO_SESSION=abc; Path=/', token: 'sess-token-1' })
  assert.ok(!JSON.stringify(result).includes(config.userPassword))
})

test('listSessions sends bearer token and maps state fields', async () => {
  const fetchImpl = makeFetch(jsonResponse(200, [
    { id: 's1', profile: { name: 'wp-a' }, state: { is_connected: true, is_watching: false } },
    { id: 's2', profile: { name: 'wp-b' }, state: { is_connected: false, is_watching: false } },
  ]))
  const result = await listSessions(config, fetchImpl)
  assert.equal(fetchImpl.calls[0].url, `${config.internalUrl}/api/sessions`)
  assert.equal(fetchImpl.calls[0].options.headers.authorization, `Bearer ${config.apiToken}`)
  assert.deepEqual(result, [
    { id: 's1', username: 'wp-a', isConnected: true, isWatching: false },
    { id: 's2', username: 'wp-b', isConnected: false, isWatching: false },
  ])
})

test('deleteSession issues DELETE with bearer', async () => {
  const fetchImpl = makeFetch(jsonResponse(204, null))
  await deleteSession('sess-1', config, fetchImpl)
  assert.equal(fetchImpl.calls[0].url, `${config.internalUrl}/api/sessions/sess-1`)
  assert.equal(fetchImpl.calls[0].options.method, 'DELETE')
  assert.equal(fetchImpl.calls[0].options.headers.authorization, `Bearer ${config.apiToken}`)
})

test('setControlLock posts locked_controls', async () => {
  const fetchImpl = makeFetch(jsonResponse(204, null))
  await setControlLock(true, config, fetchImpl)
  assert.equal(fetchImpl.calls[0].url, `${config.internalUrl}/api/room/settings`)
  const sentBody = JSON.parse(fetchImpl.calls[0].options.body)
  assert.deepEqual(sentBody, { locked_controls: true })
})

test('giveControl and resetControl hit the right paths', async () => {
  const fetchImpl = makeFetch(jsonResponse(204, null))
  await giveControl('sess-7', config, fetchImpl)
  assert.equal(fetchImpl.calls[0].url, `${config.internalUrl}/api/room/control/give/sess-7`)

  const resetFetch = makeFetch(jsonResponse(204, null))
  await resetControl(config, resetFetch)
  assert.equal(resetFetch.calls[0].url, `${config.internalUrl}/api/room/control/reset`)
})

test('controlStatus maps host fields', async () => {
  // Live-confirmed shape (Neko 3.1.4): {"has_host":true,"host_id":"..."}
  const fetchImpl = makeFetch(jsonResponse(200, { has_host: true, host_id: 'sess-9' }))
  const result = await controlStatus(config, fetchImpl)
  assert.deepEqual(result, { hasHost: true, hostSessionId: 'sess-9' })

  const noneFetch = makeFetch(jsonResponse(200, { has_host: false }))
  const noneResult = await controlStatus(config, noneFetch)
  assert.deepEqual(noneResult, { hasHost: false, hostSessionId: null })
})

test('non-2xx responses throw with status in message', async () => {
  const fetchImpl = makeFetch(jsonResponse(401, { error: 'unauthorized' }))
  await assert.rejects(listSessions(config, fetchImpl), /401/)
})

test('4xx/5xx on loginViewer throws', async () => {
  const fetchImpl = makeFetch(jsonResponse(500, {}))
  await assert.rejects(loginViewer('wp-user1', config, fetchImpl), /500/)
})
