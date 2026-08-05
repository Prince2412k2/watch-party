// HTTP client for the browser container's control agent.
//
// Every function here resolves — none of them throw. A wedged or missing
// container has to read as "the browser is unavailable", never as an exception
// escaping into a socket handler that is also responsible for chat and playback.
import { browserConfig } from './config.js'

async function call(method, path, body, { timeoutMs } = {}) {
  const config = browserConfig()
  if (!config.enabled) return { ok: false, error: 'unavailable', status: 0 }

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs ?? config.requestTimeoutMs)
  try {
    const response = await fetch(`${config.agentUrl}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${config.agentToken}`,
        ...(body ? { 'content-type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    })
    let payload = null
    try {
      payload = await response.json()
    } catch {
      payload = null
    }
    if (!response.ok) {
      return { ok: false, status: response.status, error: payload?.error || `agent ${response.status}`, body: payload }
    }
    return { ok: true, status: response.status, body: payload }
  } catch (error) {
    // A connection refused / DNS failure / abort all mean the same thing to a
    // caller: there is no browser to be had right now.
    return { ok: false, status: 0, error: error.name === 'AbortError' ? 'timeout' : 'unreachable' }
  } finally {
    clearTimeout(timer)
  }
}

export function status() {
  return call('GET', '/status')
}

export function startSession({ url, token, lkUrl, kbps, fps }) {
  return call('POST', '/session/start', { url, token, lkUrl, kbps, fps }, { timeoutMs: 15_000 })
}

export function stopSession(reason = 'stop') {
  return call('POST', '/session/stop', { reason }, { timeoutMs: 15_000 })
}

export function navigate(url) {
  return call('POST', '/session/navigate', { url })
}

export function sendInput(events, { focus = false } = {}) {
  // Deliberately short: input is worthless once it is stale, and a slow agent
  // must not hold a socket handler open.
  return call('POST', '/input', { events, focus }, { timeoutMs: 2_000 })
}
