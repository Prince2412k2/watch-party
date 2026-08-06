import { randomUUID } from 'crypto'
import { authenticate } from './jellyfin.js'

export const ADMIN_REVALIDATION_MS = 5 * 60 * 1000
export const ADMIN_REVALIDATION_TIMEOUT_MS = 3_000

export async function login(req, res) {
  const { username, password } = req.body || {}
  if (!username || !password) {
    return res.status(400).json({ error: 'username and password required' })
  }

  // Unique deviceId per browser session so Jellyfin tracks them separately
  const deviceId = `wp-${randomUUID().slice(0, 8)}`

  try {
    const data = await authenticate(username, password, deviceId)
    // Regenerate the session before storing the authenticated identity so a
    // pre-login session id can't be fixed onto the authenticated session.
    await new Promise((resolve, reject) =>
      req.session.regenerate((err) => (err ? reject(err) : resolve())))
    req.session.jellyfin = {
      accessToken: data.AccessToken,
      userId: data.User.Id,
      name: data.User.Name,
      isAdmin: data.User.Policy?.IsAdministrator ?? false,
      adminCheckedAt: Date.now(),
      deviceId,
    }
    const { accessToken: _, deviceId: __, adminCheckedAt: ___, ...safe } = req.session.jellyfin
    res.json(safe)
  } catch (err) {
    if (err.status === 401) return res.status(401).json({ error: 'Invalid username or password' })
    console.error('login error', err.message)
    res.status(502).json({ error: 'Could not reach media server' })
  }
}

// Dev-only login that bypasses Jellyfin so the headless sync harness can
// authenticate its socket without real credentials. 404 unless WP_TEST_MODE=1.
export function testLogin(req, res) {
  // Hard gate: never available in production, even if WP_TEST_MODE leaks in.
  if (process.env.NODE_ENV === 'production' || process.env.WP_TEST_MODE !== '1') {
    return res.status(404).end()
  }
  const name = (req.body?.name || '').trim() || 'tester'
  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
  const userId = `test-${slug || 'user'}-${randomUUID().slice(0, 8)}`
  req.session.jellyfin = {
    accessToken: 'test',
    userId,
    name,
    isAdmin: false,
    adminCheckedAt: Date.now(),
    deviceId: `wp-test-${randomUUID().slice(0, 8)}`,
  }
  const { accessToken: _, deviceId: __, adminCheckedAt: ___, ...safe } = req.session.jellyfin
  res.json(safe)
}

export function me(req, res) {
  if (!req.session.jellyfin) return res.status(401).json({ error: 'not authenticated' })
  const { accessToken: _, deviceId: __, adminCheckedAt: ___, ...safe } = req.session.jellyfin
  res.json(safe)
}

export function logout(req, res) {
  req.session.destroy(() => res.json({ ok: true }))
}

export function requireAuth(req, res, next) {
  if (!req.session.jellyfin) return res.status(401).json({ error: 'not authenticated' })
  next()
}

// Destructive servarr operations — deleting a title and its files, wiping the
// download client — are gated on the Jellyfin account's own administrator flag,
// which login already captures. Adding, searching, and downloading stay open to
// every signed-in member: the point of the app is that anyone in the house can
// ask for a title. Only the irreversible half is restricted.
async function fetchAdminStatus({ accessToken, userId }, { signal } = {}) {
  const baseUrl = process.env.JELLYFIN_URL || 'http://localhost:8096'
  const response = await fetch(`${baseUrl}/Users/${encodeURIComponent(userId)}`, {
    headers: { 'X-Emby-Token': accessToken },
    signal,
  })
  if (!response.ok) throw new Error(`Jellyfin GET /Users/${userId} returned ${response.status}`)
  const user = await response.json()
  return user.Policy?.IsAdministrator === true
}

export function createRequireAdmin({
  now = Date.now,
  getAdminStatus = fetchAdminStatus,
  refreshTimeoutMs = ADMIN_REVALIDATION_TIMEOUT_MS,
} = {}) {
  const refreshes = new Map()

  function refreshAdminStatus(key, jellyfin) {
    const current = refreshes.get(key)
    if (current) return current

    const controller = new AbortController()
    let timeout
    const refresh = Promise.race([
      getAdminStatus(jellyfin, { signal: controller.signal }),
      new Promise((_, reject) => {
        timeout = setTimeout(() => {
          controller.abort()
          reject(new Error('Jellyfin administrator check timed out'))
        }, refreshTimeoutMs)
      }),
    ]).finally(() => {
      clearTimeout(timeout)
      refreshes.delete(key)
    })
    refreshes.set(key, refresh)
    return refresh
  }

  return async function requireFreshAdmin(req, res, next) {
    const jellyfin = req.session.jellyfin
    if (!jellyfin) return res.status(401).json({ error: 'not authenticated' })
    if (typeof jellyfin.isAdmin !== 'boolean') {
      return res.status(403).json({ error: 'this action requires a Jellyfin administrator account' })
    }

    const roleAge = now() - jellyfin.adminCheckedAt
    if (Number.isFinite(roleAge) && roleAge >= 0 && roleAge <= ADMIN_REVALIDATION_MS) {
      if (jellyfin.isAdmin) return next()
      return res.status(403).json({ error: 'this action requires a Jellyfin administrator account' })
    }

    try {
      const refreshKey = `${req.sessionID ?? 'unknown'}:${jellyfin.userId}`
      jellyfin.isAdmin = await refreshAdminStatus(refreshKey, jellyfin)
      jellyfin.adminCheckedAt = now()
    } catch (error) {
      console.error('admin revalidation failed', error.message)
      return res.status(502).json({ error: 'could not verify Jellyfin administrator status' })
    }

    if (!jellyfin.isAdmin) {
      return res.status(403).json({ error: 'this action requires a Jellyfin administrator account' })
    }
    next()
  }
}

export const requireAdmin = createRequireAdmin()

export function getJellyfin(req) {
  const j = req.session.jellyfin
  return { baseUrl: process.env.JELLYFIN_URL, token: j.accessToken, userId: j.userId, deviceId: j.deviceId }
}
