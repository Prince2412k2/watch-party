import { createHash, randomBytes } from 'node:crypto'
import { db } from './db.js'
import { requireAuth } from './auth.js'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { authenticate } from './jellyfin.js'
import { allSessions, persistSession } from './session.js'

db.exec(`CREATE TABLE IF NOT EXISTS extension_devices (
  id TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, user_id TEXT NOT NULL,
  name TEXT NOT NULL, expires_at INTEGER NOT NULL
)`)
const columns = new Set(db.prepare('PRAGMA table_info(extension_devices)').all().map(column => column.name))
if (!columns.has('is_admin')) db.exec('ALTER TABLE extension_devices ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0')
if (!columns.has('party_id')) db.exec('ALTER TABLE extension_devices ADD COLUMN party_id TEXT')
const codes = new Map()
const inviteAttempts = new Map()
const hash = value => createHash('sha256').update(value).digest('hex')
const identity = row => ({ userId: row.user_id, name: row.name, token: null, deviceId: `extension-${row.id}`, extensionAdmin: row.is_admin === 1, extensionPartyId: row.party_id, expiresAt: row.expires_at })

function inviteRateLimit(req, res, next) {
  const now = Date.now()
  for (const [key, value] of inviteAttempts) if (value.until <= now) inviteAttempts.delete(key)
  const entry = inviteAttempts.get(req.ip) ?? { count: 0, until: now + 5 * 60_000 }
  if (++entry.count > 60 || inviteAttempts.size > 10_000) return res.status(429).set('Retry-After', '300').json({ error: 'Too many invite attempts. Please try again in a few minutes.' })
  inviteAttempts.set(req.ip, entry)
  next()
}

function createCredential({ userId, name, isAdmin = false, partyId = null }) {
  db.prepare('DELETE FROM extension_devices WHERE expires_at <= ?').run(Date.now())
  const token = randomBytes(32).toString('hex')
  const id = randomBytes(12).toString('hex')
  const expiresAt = Date.now() + 30 * 24 * 60 * 60_000
  db.prepare('INSERT INTO extension_devices (id, token_hash, user_id, name, expires_at, is_admin, party_id) VALUES (?, ?, ?, ?, ?, ?, ?)')
    .run(id, hash(token), userId, name, expiresAt, isAdmin ? 1 : 0, partyId)
  return { token, user: { userId, name, isAdmin }, expiresAt, partyId }
}

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
  app.get('/api/extension/download', (_req, res) => {
    const archive = fileURLToPath(new URL('../client/extension/watchparty-youtube.zip', import.meta.url))
    if (!existsSync(archive)) return res.status(503).json({ error: 'Extension package is not built. Run npm run build:extension in app/client.' })
    res.download(archive, 'watchparty-youtube.zip')
  })
  app.post('/api/extension/login', ...(rateLimit ? [rateLimit] : []), async (req, res) => {
    const { username, password } = req.body ?? {}
    if (typeof username !== 'string' || typeof password !== 'string' || !username.trim() || !password) return res.status(400).json({ error: 'Admin username and password are required' })
    try {
      const data = await authenticate(username.trim(), password, `extension-${randomBytes(8).toString('hex')}`)
      if (!data.User?.Policy?.IsAdministrator) return res.status(403).json({ error: 'Only administrators can create parties. Guests can join with an invite code instead.' })
      res.set('Cache-Control', 'no-store').json(createCredential({ userId: data.User.Id, name: data.User.Name, isAdmin: true }))
    } catch (error) {
      res.status(error.status === 401 ? 401 : 502).json({ error: error.status === 401 ? 'Invalid admin username or password' : 'Could not reach the account server' })
    }
  })
  app.post('/api/extension/join-invite', inviteRateLimit, (req, res) => {
    const code = typeof req.body?.code === 'string' ? req.body.code.replace(/[\s-]/g, '').toUpperCase() : ''
    if (!/^[A-F0-9]{12}$/.test(code)) return res.status(400).json({ error: 'Enter the 12-character party invite code' })
    const party = [...allSessions()].find(party => party.externalMedia && party.inviteCode === code)
    if (!party) return res.status(404).json({ error: 'Invite code not found. Ask the host for the code for this party.' })
    const existing = extensionIdentity(req.body.token)
    if (existing?.extensionAdmin || existing?.extensionPartyId === party.id) {
      party.approved.add(existing.userId)
      persistSession(party)
      return res.set('Cache-Control', 'no-store').json({ token: req.body.token, user: { userId: existing.userId, name: existing.name, isAdmin: existing.extensionAdmin }, expiresAt: existing.expiresAt, partyId: party.id, media: party.externalMedia })
    }
    const name = typeof req.body.name === 'string' ? req.body.name.trim().replace(/[\r\n\t]/g, ' ').slice(0, 32) : ''
    const credential = createCredential({ userId: `extension-guest-${randomBytes(12).toString('hex')}`, name: name || `Guest ${randomBytes(2).toString('hex').toUpperCase()}`, partyId: party.id })
    party.approved.add(credential.user.userId)
    persistSession(party)
    res.set('Cache-Control', 'no-store').json({ ...credential, media: party.externalMedia })
  })
  app.post('/api/extension/pair-code', requireAuth, (req, res) => {
    const now = Date.now()
    for (const [code, entry] of codes) if (entry.expiresAt <= now || entry.user.userId === req.session.jellyfin.userId) codes.delete(code)
    if (codes.size >= 1000) return res.status(429).json({ error: 'Please try again later' })
    const code = randomBytes(9).toString('hex').toUpperCase()
    const { userId, name, isAdmin } = req.session.jellyfin
    const expiresAt = now + 5 * 60_000
    codes.set(hash(code), { user: { userId, name, isAdmin: isAdmin === true }, expiresAt })
    res.set('Cache-Control', 'no-store').json({ code, expiresAt })
  })
  app.post('/api/extension/pair', ...(rateLimit ? [rateLimit] : []), (req, res) => {
    const code = typeof req.body?.code === 'string' ? req.body.code.replace(/[\s-]/g, '').toUpperCase() : ''
    const key = hash(code)
    const entry = codes.get(key)
    if (!entry || entry.expiresAt <= Date.now()) return res.status(400).json({ error: 'Pairing code is invalid or expired' })
    codes.delete(key)
    res.set('Cache-Control', 'no-store').json(createCredential(entry.user))
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
  if (!value || value.provider !== 'youtube') return null
  try {
    const url = new URL(value.url ?? `https://www.youtube.com/watch?v=${value.videoId}`)
    if (url.origin !== 'https://www.youtube.com' || url.username || url.password) return null
    const videoId = url.pathname === '/watch' ? url.searchParams.get('v') : /^\/shorts\/([A-Za-z0-9_-]{11})\/?$/.exec(url.pathname)?.[1] ?? null
    if ((url.pathname === '/watch' || url.pathname.startsWith('/shorts/')) && !/^[A-Za-z0-9_-]{11}$/.test(videoId ?? '')) return null
    url.hash = ''
    if (url.href.length > 2000) return null
    return { provider: 'youtube', videoId, url: url.href, title: typeof value.title === 'string' ? value.title.trim().slice(0, 200) : '', playbackRate: 1 }
  } catch { return null }
}

export const EXTERNAL_RATES = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
