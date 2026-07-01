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
