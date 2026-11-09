import { createHash, randomBytes } from 'node:crypto'
import { db } from './db.js'
import { requireAuth } from './auth.js'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

db.exec(`CREATE TABLE IF NOT EXISTS extension_devices (
  id TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, user_id TEXT NOT NULL,
  name TEXT NOT NULL, expires_at INTEGER NOT NULL
)`)
const codes = new Map()
const hash = value => createHash('sha256').update(value).digest('hex')
const identity = row => ({ userId: row.user_id, name: row.name, token: null, deviceId: `extension-${row.id}` })

export function extensionIdentity(token) {
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) return null
  const row = db.prepare('SELECT * FROM extension_devices WHERE token_hash = ? AND expires_at > ?').get(hash(token), Date.now())
  return row ? identity(row) : null
}

export function requireExtension(req, res, next) {
  const user = extensionIdentity(req.headers.authorization?.replace(/^Bearer /, ''))
  if (!user) return res.status(401).json({ error: 'Extension pairing expired or was revoked. Pair again in Watch Party.' })
  req.extensionUser = user
  next()
}

export function registerExtensionRoutes(app, { rateLimit, onRevoke = () => {} } = {}) {
  // An extension iframe embedded on YouTube still uses CORS for fetch, even
  // though its top-level popup may have a granted host permission. Never allow
  // credentials here: pairing/session-management routes remain cookie-scoped.
  app.use('/api/extension', (req, res, next) => {
    const origin = req.headers.origin
    if (typeof origin === 'string' && /^chrome-extension:\/\/[a-p]{32}$/.test(origin)) {
      res.set('Access-Control-Allow-Origin', origin)
      res.vary('Origin')
      res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type')
      res.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
      if (req.method === 'OPTIONS') return res.status(204).end()
    }
    next()
  })
  app.get('/api/extension/download', requireAuth, (_req, res) => {
    const archive = fileURLToPath(new URL('../client/extension/watchparty-youtube.zip', import.meta.url))
    if (!existsSync(archive)) return res.status(503).json({ error: 'Extension package is not built. Run npm run build:extension in app/client.' })
    res.download(archive, 'watchparty-youtube.zip')
  })
  app.post('/api/extension/pair-code', requireAuth, (req, res) => {
    const now = Date.now()
    for (const [code, entry] of codes) if (entry.expiresAt <= now || entry.user.userId === req.session.jellyfin.userId) codes.delete(code)
    if (codes.size >= 1000) return res.status(429).json({ error: 'Please try again later' })
    const code = randomBytes(9).toString('hex').toUpperCase()
    const { userId, name } = req.session.jellyfin
    const expiresAt = now + 5 * 60_000
    codes.set(hash(code), { user: { userId, name }, expiresAt })
    res.set('Cache-Control', 'no-store').json({ code, expiresAt })
  })
  app.post('/api/extension/pair', ...(rateLimit ? [rateLimit] : []), (req, res) => {
    const code = typeof req.body?.code === 'string' ? req.body.code.replace(/[\s-]/g, '').toUpperCase() : ''
    const key = hash(code)
    const entry = codes.get(key)
    if (!entry || entry.expiresAt <= Date.now()) return res.status(400).json({ error: 'Pairing code is invalid or expired' })
    codes.delete(key)
    db.prepare('DELETE FROM extension_devices WHERE expires_at <= ?').run(Date.now())
    const token = randomBytes(32).toString('hex')
    const id = randomBytes(12).toString('hex')
    const expiresAt = Date.now() + 30 * 24 * 60 * 60_000
    db.prepare('INSERT INTO extension_devices VALUES (?, ?, ?, ?, ?)').run(id, hash(token), entry.user.userId, entry.user.name, expiresAt)
    res.set('Cache-Control', 'no-store').json({ token, user: entry.user, expiresAt })
  })
  app.get('/api/extension/devices', requireAuth, (req, res) => {
    res.json(db.prepare('SELECT id, name, expires_at AS expiresAt FROM extension_devices WHERE user_id = ? AND expires_at > ?').all(req.session.jellyfin.userId, Date.now()))
  })
  app.delete('/api/extension/devices/:id', requireAuth, (req, res) => {
    const row = db.prepare('SELECT * FROM extension_devices WHERE id = ? AND user_id = ?').get(req.params.id, req.session.jellyfin.userId)
    if (row) {
      db.prepare('DELETE FROM extension_devices WHERE id = ?').run(row.id)
      onRevoke(`extension-${row.id}`)
    }
    res.json({ ok: true })
  })
}

export function parseExternalMedia(value) {
  if (!value || value.provider !== 'youtube' || typeof value.videoId !== 'string' || !/^[A-Za-z0-9_-]{11}$/.test(value.videoId)) return null
  return { provider: 'youtube', videoId: value.videoId, title: typeof value.title === 'string' ? value.title.trim().slice(0, 200) : '', playbackRate: 1 }
}

export const EXTERNAL_RATES = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
