import { randomUUID } from 'crypto'
import { authenticate } from './jellyfin.js'

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
      deviceId,
    }
    const { accessToken: _, deviceId: __, ...safe } = req.session.jellyfin
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
    deviceId: `wp-test-${randomUUID().slice(0, 8)}`,
  }
  const { accessToken: _, deviceId: __, ...safe } = req.session.jellyfin
  res.json(safe)
}

export function me(req, res) {
  if (!req.session.jellyfin) return res.status(401).json({ error: 'not authenticated' })
  const { accessToken: _, deviceId: __, ...safe } = req.session.jellyfin
  res.json(safe)
}

export function logout(req, res) {
  req.session.destroy(() => res.json({ ok: true }))
}

export function requireAuth(req, res, next) {
  if (!req.session.jellyfin) return res.status(401).json({ error: 'not authenticated' })
  next()
}

export function getJellyfin(req) {
  const j = req.session.jellyfin
  return { baseUrl: process.env.JELLYFIN_URL, token: j.accessToken, userId: j.userId, deviceId: j.deviceId }
}
