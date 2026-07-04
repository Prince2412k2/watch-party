// qBittorrent WebUI API v2 client. Unlike the *arr services this has no API key
// — it uses a cookie session: POST /api/v2/auth/login with a form body returns a
// session cookie we capture and replay on subsequent calls, re-logging in on a
// 403 (session expiry). The cookie lives only in this module's memory; it is
// never sent to, or surfaced in any response reaching, the client.
//
// Version compatibility: the login/session/action surface differs between
// qBittorrent 4.x and 5.x, and getting it wrong silently breaks EVERY download
// operation (torrents never list, pause/resume/remove no-op). We normalize:
//   • login success — 4.x answers `200 "Ok."`; 5.x answers `204 No Content`
//     (empty body). Any 2xx that isn't an explicit "Fails." counts as success.
//   • session cookie — 4.x names it `SID`; 5.x names it `QBT_SID_<port>`. We
//     capture whichever *SID cookie is set and replay it verbatim.
//   • pause/resume — 5.0 renamed the endpoints to stop/start (the old paths
//     404). We try the modern verb first and fall back to the legacy one.

import { qbitConfig } from './config.js'
import { NotConfiguredError } from './arr.js'

const DEFAULT_TIMEOUT_MS = 8000

// In-memory session cookie as a full `name=value` pair (the name varies by
// qBittorrent version, so we can't assume it's `SID`). Single shared session.
let sessionCookie = null

function base() {
  return qbitConfig().baseUrl.replace(/\/$/, '')
}

async function timedFetch(url, opts, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), timeoutMs)
  try {
    return await fetch(url, { ...opts, signal: ctrl.signal })
  } catch (err) {
    const msg = err.name === 'AbortError' ? 'qbittorrent request timed out' : 'qbittorrent unreachable'
    throw Object.assign(new Error(msg), { status: 504, upstream: true })
  } finally {
    clearTimeout(timer)
  }
}

// Log in and capture the session cookie. Throws on bad creds / unreachable.
async function login() {
  const cfg = qbitConfig()
  if (!cfg.configured) throw new NotConfiguredError('qbittorrent')

  const form = new URLSearchParams({ username: cfg.user, password: cfg.pass ?? '' })
  const res = await timedFetch(`${base()}/api/v2/auth/login`, {
    method: 'POST',
    // Referer must match the WebUI host or qBittorrent rejects the login (CSRF).
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', Referer: base() },
    body: form.toString(),
  })
  const text = (await res.text().catch(() => '')).trim()
  // Success is any 2xx (4.x → 200 "Ok.", 5.x → 204 empty) that isn't an explicit
  // "Fails." Bad creds surface as 200 "Fails." (4.x) or 401/403 (5.x).
  if (!res.ok || /^fails\.?$/i.test(text)) {
    throw Object.assign(new Error('qbittorrent login failed'), { status: res.status === 200 ? 403 : res.status, upstream: true })
  }
  // Cookie name is `SID` (4.x) or `QBT_SID_<port>` (5.x) — capture whichever is
  // present and keep the full name=value pair to replay verbatim.
  const setCookie = res.headers.get('set-cookie') || ''
  const m = setCookie.match(/(QBT_SID_\d+|SID)=([^;]+)/i)
  if (!m) throw Object.assign(new Error('qbittorrent login: no session cookie'), { status: 502, upstream: true })
  sessionCookie = `${m[1]}=${m[2]}`
  return sessionCookie
}

// Perform an authenticated request, logging in if we have no cookie and
// re-logging in once on a 403 (expired session). `_retried` guards the recursion.
async function authed(path, { method = 'GET', form, timeoutMs = DEFAULT_TIMEOUT_MS } = {}, _retried = false) {
  const cfg = qbitConfig()
  if (!cfg.configured) throw new NotConfiguredError('qbittorrent')
  if (!sessionCookie) await login()

  const opts = {
    method,
    headers: { Cookie: sessionCookie, Referer: base() },
  }
  if (form) {
    opts.headers['Content-Type'] = 'application/x-www-form-urlencoded'
    opts.body = new URLSearchParams(form).toString()
  }

  const res = await timedFetch(`${base()}${path}`, opts, timeoutMs)

  if (res.status === 403 && !_retried) {
    sessionCookie = null
    await login()
    return authed(path, { method, form, timeoutMs }, true)
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '')
    throw Object.assign(new Error(`qbittorrent ${method} ${path} → ${res.status}`), { status: res.status, body: text, upstream: true })
  }
  const ct = res.headers.get('content-type') || ''
  return ct.includes('application/json') ? res.json() : res.text()
}

// ── Public API ────────────────────────────────────────────────────────────────

// Lightweight reachability + version probe for the health route. Never throws.
export async function qbitPing(timeoutMs = 4000) {
  try {
    const version = await authed('/api/v2/app/version', { timeoutMs })
    return { reachable: true, version: typeof version === 'string' ? version.trim() : undefined }
  } catch {
    return { reachable: false }
  }
}

export function torrentsInfo() {
  return authed('/api/v2/torrents/info')
}

// qBittorrent 5.0 renamed pause→stop and resume→start; the old paths 404 there,
// and the new paths don't exist on 4.x. Try the modern verb, fall back to the
// legacy one on a 404 so pause/resume work across both major versions.
async function actionWithFallback(modernPath, legacyPath, hashes) {
  try {
    return await authed(modernPath, { method: 'POST', form: { hashes } })
  } catch (err) {
    if (err?.status === 404) return authed(legacyPath, { method: 'POST', form: { hashes } })
    throw err
  }
}

// pause/resume/delete all take a `hashes` string ("|"-joined, or "all").
export function pause(hashes) {
  return actionWithFallback('/api/v2/torrents/stop', '/api/v2/torrents/pause', hashes)
}

export function resume(hashes) {
  return actionWithFallback('/api/v2/torrents/start', '/api/v2/torrents/resume', hashes)
}

export function remove(hashes, deleteFiles = false) {
  return authed('/api/v2/torrents/delete', {
    method: 'POST',
    form: { hashes, deleteFiles: deleteFiles ? 'true' : 'false' },
  })
}
