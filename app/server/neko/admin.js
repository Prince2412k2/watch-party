import { nekoConfig } from './config.js'

function defaultFetch(...args) {
  return fetch(...args)
}

async function assertOk(response, label) {
  if (!response.ok) {
    throw new Error(`neko admin: ${label} failed with status ${response.status}`)
  }
  return response
}

export async function loginViewer(username, config = nekoConfig(), fetchImpl = defaultFetch) {
  const response = await fetchImpl(`${config.internalUrl}/api/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, password: config.userPassword }),
  })
  await assertOk(response, 'loginViewer')
  const cookie = response.headers.get('set-cookie') || null
  const body = await response.json().catch(() => ({}))
  return { sessionId: body.id ?? body.sessionId ?? null, cookie }
}

export async function listSessions(config = nekoConfig(), fetchImpl = defaultFetch) {
  const response = await fetchImpl(`${config.internalUrl}/api/sessions`, {
    headers: { authorization: `Bearer ${config.apiToken}` },
  })
  await assertOk(response, 'listSessions')
  const body = await response.json()
  return (Array.isArray(body) ? body : []).map(entry => ({
    id: entry.id,
    username: entry.profile?.name ?? null,
    isConnected: Boolean(entry.state?.is_connected),
    isWatching: Boolean(entry.state?.is_watching),
  }))
}

export async function deleteSession(sessionId, config = nekoConfig(), fetchImpl = defaultFetch) {
  const response = await fetchImpl(`${config.internalUrl}/api/sessions/${sessionId}`, {
    method: 'DELETE',
    headers: { authorization: `Bearer ${config.apiToken}` },
  })
  await assertOk(response, 'deleteSession')
}

export async function setControlLock(locked, config = nekoConfig(), fetchImpl = defaultFetch) {
  const response = await fetchImpl(`${config.internalUrl}/api/room/settings`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${config.apiToken}` },
    body: JSON.stringify({ locked_controls: locked }),
  })
  await assertOk(response, 'setControlLock')
}

export async function giveControl(sessionId, config = nekoConfig(), fetchImpl = defaultFetch) {
  const response = await fetchImpl(`${config.internalUrl}/api/room/control/give/${sessionId}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${config.apiToken}` },
  })
  await assertOk(response, 'giveControl')
}

export async function resetControl(config = nekoConfig(), fetchImpl = defaultFetch) {
  const response = await fetchImpl(`${config.internalUrl}/api/room/control/reset`, {
    method: 'POST',
    headers: { authorization: `Bearer ${config.apiToken}` },
  })
  await assertOk(response, 'resetControl')
}

export async function controlStatus(config = nekoConfig(), fetchImpl = defaultFetch) {
  const response = await fetchImpl(`${config.internalUrl}/api/room/control`, {
    headers: { authorization: `Bearer ${config.apiToken}` },
  })
  await assertOk(response, 'controlStatus')
  // Shape confirmed live (Neko 3.1.4): {"has_host":false} or
  // {"has_host":true,"host_id":"<sessionId>"} — see A0 spike decision record.
  const body = await response.json().catch(() => ({}))
  return { hasHost: Boolean(body.has_host), hostSessionId: body.host_id ?? null }
}
