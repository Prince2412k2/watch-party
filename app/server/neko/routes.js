// C10 — per-user Neko viewer-session broker + C12 — control socket events.
//
// The broker mints an opaque, lease-scoped Neko username per (partyId,
// leaseId, userId) and relays the resulting NEKO_SESSION cookie onto our own
// origin, scoped to /neko. Concurrent POSTs for the same (partyId, leaseId,
// userId) are serialized through an in-flight promise map so two overlapping
// requests can't each mint a session and race the lease's session mapping
// (findings #3/#4 of the neko-collab-browser plan).
import { createHmac } from 'node:crypto'
import * as defaultAdmin from './admin.js'
import * as defaultLease from './lease.js'
import * as defaultController from './controller.js'
import { nekoConfig, assertNekoEnabled } from './config.js'
import { getSession, isMember, findSessionForMember } from '../session.js'

// Neko usernames must be short and URL/charset safe; truncate the HMAC hex
// digest so `wp-<hex>` stays well under any reasonable length limit.
const USERNAME_HEX_LENGTH = 29 // 'wp-' + 29 hex chars = 32 total

export function deriveUsername(partyId, leaseId, userId, secret = nekoConfig().usernameSecret) {
  const digest = createHmac('sha256', secret).update(`${partyId}:${leaseId}:${userId}`).digest('hex')
  return `wp-${digest.slice(0, USERNAME_HEX_LENGTH)}`
}

// Rewrite the Set-Cookie's Path to /neko so it never travels to unrelated
// same-origin routes, while preserving every other attribute (HttpOnly,
// Secure, SameSite, expiry) Neko already set. When `secure` is false (plain
// http, e.g. local demo on localhost), the Secure attribute is stripped —
// browsers refuse to store a Secure cookie set over a non-https response.
export function scopeCookieToNeko(setCookieHeader, { secure = true } = {}) {
  if (!setCookieHeader) return null
  const parts = setCookieHeader.split(';').map(p => p.trim())
  let rest = parts.filter(p => !/^path=/i.test(p))
  if (!secure) {
    // Over plain http a `Secure` cookie is dropped, and `SameSite=None` REQUIRES
    // `Secure` (browsers reject None+non-Secure, silently discarding the cookie).
    // The embed is same-origin, so downgrade to Lax and drop Secure so the
    // relayed NEKO_SESSION cookie is actually stored and sent to the iframe.
    rest = rest.filter(p => !/^secure$/i.test(p) && !/^samesite=/i.test(p))
    rest.push('SameSite=Lax')
  }
  rest.push('Path=/neko')
  return rest.join('; ')
}

function keyFor(partyId, leaseId, userId) {
  return `${partyId}:${leaseId}:${userId}`
}

export function createSessionBroker({ admin = defaultAdmin, lease = defaultLease, controller = defaultController } = {}) {
  const inFlight = new Map()

  async function mintSession(partyId, leaseId, userId) {
    const key = keyFor(partyId, leaseId, userId)
    const prior = inFlight.get(key)
    const task = (prior || Promise.resolve()).catch(() => {}).then(async () => {
      const existing = lease.sessionsForUser(partyId, userId)
      for (const { nekoSessionId } of existing) {
        try {
          await admin.deleteSession(nekoSessionId)
        } catch {
          // ignore — best-effort cleanup of a stale prior session
        }
        lease.removeUserSession(partyId, userId, nekoSessionId)
      }

      const username = deriveUsername(partyId, leaseId, userId)
      const { sessionId, cookie, token } = await admin.loginViewer(username)
      lease.recordUserSession(partyId, leaseId, userId, sessionId)

      const controllerInfo = await controller.currentController(partyId)
      return { cookie, token, controllerUserId: controllerInfo?.userId ?? null }
    })

    inFlight.set(key, task)
    try {
      return await task
    } finally {
      if (inFlight.get(key) === task) inFlight.delete(key)
    }
  }

  return { mintSession }
}

export function registerNekoRoutes(app, io, { admin = defaultAdmin, lease = defaultLease, controller = defaultController } = {}) {
  const broker = createSessionBroker({ admin, lease, controller })

  app.post('/api/party/:id/browser/session', async (req, res) => {
    try {
      assertNekoEnabled()
    } catch {
      return res.status(404).json({ error: 'browser disabled' })
    }

    const sess = getSession(req.params.id)
    if (!sess) return res.status(404).json({ error: 'party not found' })

    const userId = req.session?.jellyfin?.userId
    if (!userId || !isMember(sess, userId)) return res.status(403).json({ error: 'not a member' })

    const activeLease = lease.getLease()
    if (!activeLease || activeLease.partyId !== sess.id || activeLease.state !== 'active') {
      return res.status(409).json({ error: 'browser not active' })
    }

    try {
      const { cookie, token, controllerUserId } = await broker.mintSession(sess.id, activeLease.leaseId, userId)
      const isSecureRequest = req.secure === true || req.headers?.['x-forwarded-proto'] === 'https'
      const scoped = scopeCookieToNeko(cookie, { secure: isSecureRequest })
      if (scoped) res.setHeader('Set-Cookie', scoped)
      res.json({ wsUrl: nekoConfig().publicWs, token, controllerUserId })
    } catch (err) {
      console.error('browser session broker', err.message)
      res.status(502).json({ error: 'could not start browser session' })
    }
  })

  io.on('connection', (socket) => registerControlEvents(socket, io, { admin, lease, controller }))
}

// C12 — Neko-enforced control socket events. Called once per connected
// socket (from registerNekoRoutes above, or directly from index.js's own
// io.on('connection') handler) so each handler closes over that socket.
export function registerControlEvents(socket, io, { admin = defaultAdmin, lease = defaultLease, controller = defaultController } = {}) {
    const userId = socket.user?.userId

    function activePartyFor(partyId) {
      const active = lease.getLease()
      return active && active.partyId === partyId && active.state === 'active' ? active : null
    }

    function requireMember() {
      return findSessionForMember(userId) || null
    }

    socket.on('browser:requestControl', async (_p, ack) => {
      const sess = requireMember()
      if (!sess) return ack?.({ error: 'not allowed' })
      const partyId = sess.id
      if (!activePartyFor(partyId)) return ack?.({ error: 'not allowed' })
      try {
        const status = await admin.controlStatus()
        if (status.hasHost) return ack?.({ error: 'held' })
        const mine = lease.sessionsForUser(partyId, userId)
        const sessionId = mine[0]?.nekoSessionId
        if (!sessionId) return ack?.({ error: 'viewer not connected' })
        await admin.giveControl(sessionId)
        io.to(partyId).emit('browser:control', { controllerUserId: userId })
        ack?.({ ok: true, controllerUserId: userId })
      } catch (err) {
        ack?.({ error: err.message })
      }
    })

    socket.on('browser:assignControl', async ({ userId: targetUserId } = {}, ack) => {
      const sess = requireMember()
      if (!sess) return ack?.({ error: 'not allowed' })
      const partyId = sess.id
      if (!activePartyFor(partyId)) return ack?.({ error: 'not allowed' })
      if (sess.hostId !== userId) return ack?.({ error: 'not allowed' })
      try {
        const targetSessions = lease.sessionsForUser(partyId, targetUserId)
        const sessionId = targetSessions[0]?.nekoSessionId
        if (!sessionId) return ack?.({ error: 'viewer not connected' })
        await admin.giveControl(sessionId)
        io.to(partyId).emit('browser:control', { controllerUserId: targetUserId })
        ack?.({ ok: true, controllerUserId: targetUserId })
      } catch (err) {
        ack?.({ error: err.message })
      }
    })

    socket.on('browser:revokeControl', async (_p, ack) => {
      const sess = requireMember()
      if (!sess) return ack?.({ error: 'not allowed' })
      const partyId = sess.id
      if (!activePartyFor(partyId)) return ack?.({ error: 'not allowed' })
      if (sess.hostId !== userId) return ack?.({ error: 'not allowed' })
      try {
        await admin.resetControl()
        io.to(partyId).emit('browser:control', { controllerUserId: null })
        ack?.({ ok: true })
      } catch (err) {
        ack?.({ error: err.message })
      }
    })

    socket.on('browser:getControl', async (_p, ack) => {
      const sess = requireMember()
      if (!sess) return ack?.({ error: 'not allowed' })
      const partyId = sess.id
      try {
        const info = await controller.currentController(partyId)
        ack?.({ controllerUserId: info?.userId ?? null })
      } catch (err) {
        ack?.({ error: err.message })
      }
    })
}
