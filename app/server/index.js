import { readFileSync } from 'fs'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
for (const file of ['.env', '.env.local']) {
  try {
    const env = readFileSync(resolve(__dirname, '../../', file), 'utf8')
    for (const line of env.split('\n')) {
      const m = line.match(/^([^#=]+)=(.*)$/)
      if (m) process.env[m[1].trim()] = m[2].trim()
    }
  } catch {}
}

import express from 'express'
import { createServer } from 'http'
import { Server } from 'socket.io'
import cookieParser from 'cookie-parser'
import session from 'express-session'
import { login, me, logout } from './auth.js'
import { registerLibraryRoutes } from './library.js'
import { registerLiveKitRoutes } from './livekit.js'
import {
  createSession, getSession, deleteSession,
  findSessionBySocket, findSessionForMember, findSessionByHost,
  addToWaiting, approveGuest, rejectGuest, removeGuest,
  transferHost, pushMessage, isHost, isMember, publicSession,
} from './session.js'
import { getItems } from './jellyfin.js'

const app = express()
const httpServer = createServer(app)
const io = new Server(httpServer, {
  cors: {
    origin: [
      'http://localhost:5173', 'http://localhost:5174',
      'https://dsk-4161.tail0a3558.ts.net',
    ],
    credentials: true,
  },
})

const sessionMiddleware = session({
  secret: process.env.SESSION_SECRET || 'changeme',
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax' },
})

app.use(express.json())
app.use(cookieParser())
app.use(sessionMiddleware)
io.engine.use(sessionMiddleware)

app.get('/api/health', (_req, res) => res.json({ ok: true }))
app.post('/api/auth/login', login)
app.get('/api/auth/me', me)
app.post('/api/auth/logout', logout)
registerLibraryRoutes(app)
registerLiveKitRoutes(app)

// ── Socket.io auth middleware ─────────────────────────────────────────────

io.use((socket, next) => {
  const jf = socket.request.session?.jellyfin
  if (!jf) return next(new Error('unauthenticated'))
  socket.user = { userId: jf.userId, name: jf.name, token: jf.accessToken, deviceId: jf.deviceId }
  next()
})

// ── Connection ────────────────────────────────────────────────────────────

io.on('connection', (socket) => {
  const { userId, name, token, deviceId } = socket.user

  // party:create ────────────────────────────────────────────────────────────
  socket.on('party:create', async ({ mediaItemId } = {}, ack) => {
    try {
      const data = await getItems(token, userId, { Ids: mediaItemId, Fields: 'MediaSources' })
      const item = data.Items?.[0]
      if (!item) return ack?.({ error: 'item not found' })
      const mediaSourceId = item.MediaSources?.[0]?.Id ?? mediaItemId

      const sess = createSession({
        hostId: userId, hostToken: token, hostDeviceId: deviceId, hostName: name,
        hostSocketId: socket.id, mediaItemId, mediaSourceId,
      })

      socket.join(sess.id)
      ack?.({ partyId: sess.id, session: publicSession(sess) })
    } catch (err) {
      console.error('party:create', err.message)
      ack?.({ error: err.message })
    }
  })

  // party:join ──────────────────────────────────────────────────────────────
  socket.on('party:join', ({ partyId } = {}, ack) => {
    const sess = getSession(partyId)
    if (!sess) return ack?.({ error: 'party not found' })

    if (sess.hostId === userId) {
      // Host reconnecting after disconnect
      if (sess.hostDisconnectTimer) {
        clearTimeout(sess.hostDisconnectTimer)
        sess.hostDisconnectTimer = null
      }
      sess.hostSocketId = socket.id
      socket.join(partyId)
      return ack?.({ status: 'joined', session: publicSession(sess) })
    }

    if (isMember(sess, userId)) {
      const guest = sess.guests.find(g => g.userId === userId)
      if (guest) guest.socketId = socket.id
      socket.join(partyId)
      return ack?.({ status: 'joined', session: publicSession(sess) })
    }

    const added = addToWaiting(sess, { userId, name, socketId: socket.id, token, deviceId })
    socket.join(partyId)
    ack?.({ status: 'waiting' })
    // Only notify the host on a genuinely new request (avoids duplicate prompts)
    if (added) io.to(sess.hostSocketId).emit('party:waiting', { userId, name })
  })

  // party:approve ───────────────────────────────────────────────────────────
  socket.on('party:approve', async ({ userId: targetId } = {}, ack) => {
    const sess = findSessionByHost(userId)
    if (!sess) return ack?.({ error: 'not host' })

    const guest = approveGuest(sess, targetId)
    if (!guest) return ack?.({ error: 'user not waiting' })

    io.to(guest.socketId).emit('party:approved', { session: publicSession(sess) })
    // Hand the joiner the current timeline so it locks straight onto the schedule
    io.to(guest.socketId).emit('sync:schedule', sess.schedule)
    io.to(sess.id).emit('user:joined', { userId: guest.userId, name: guest.name })
    // Position sync is handled by the per-second drift heartbeat + buffer-ahead
    // rendezvous on the client (no immediate Unpause that would stall the guest).
    ack?.({ ok: true })
  })

  // party:reject ────────────────────────────────────────────────────────────
  socket.on('party:reject', ({ userId: targetId } = {}, ack) => {
    const sess = findSessionByHost(userId)
    if (!sess) return ack?.({ error: 'not host' })
    const w = rejectGuest(sess, targetId)
    if (!w) return ack?.({ error: 'not waiting' })
    io.to(w.socketId).emit('party:rejected', {})
    ack?.({ ok: true })
  })

  // party:kick ──────────────────────────────────────────────────────────────
  socket.on('party:kick', ({ userId: targetId } = {}, ack) => {
    const sess = findSessionByHost(userId)
    if (!sess) return ack?.({ error: 'not host' })
    const g = removeGuest(sess, targetId)
    if (!g) return ack?.({ error: 'user not found' })
    io.to(g.socketId).emit('party:kicked', { userId: targetId })
    io.to(sess.id).emit('user:left', { userId: targetId, name: g.name })
    ack?.({ ok: true })
  })

  // party:transferHost ──────────────────────────────────────────────────────
  socket.on('party:transferHost', ({ userId: targetId } = {}, ack) => {
    const sess = findSessionByHost(userId)
    if (!sess) return ack?.({ error: 'not host' })
    const targetGuest = sess.guests.find(g => g.userId === targetId)
    if (!targetGuest) return ack?.({ error: 'user not found' })
    const targetSocket = io.sockets.sockets.get(targetGuest.socketId)
    const targetToken = targetSocket?.user?.token ?? token
    transferHost(sess, targetId, targetGuest.socketId, targetToken)
    io.to(sess.id).emit('host:changed', { hostId: targetId })
    ack?.({ ok: true })
  })

  // party:setCollaborative ──────────────────────────────────────────────────
  socket.on('party:setCollaborative', ({ enabled } = {}, ack) => {
    const sess = findSessionByHost(userId)
    if (!sess) return ack?.({ error: 'not host' })
    sess.collaborativeControl = !!enabled
    io.to(sess.id).emit('party:state', publicSession(sess))
    ack?.({ ok: true })
  })

  // clock:ping — NTP-lite; client computes its offset from server time ───────
  socket.on('clock:ping', (_t1, ack) => ack?.(Date.now()))

  const canDrive = (sess) => isHost(sess, userId) || sess.collaborativeControl

  // sync:hello — client asks for the current timeline once it's listening
  // (avoids the race where a pushed schedule arrives before the guest mounts)
  socket.on('sync:hello', () => {
    const sess = findSessionForMember(userId)
    if (sess) io.to(socket.id).emit('sync:schedule', sess.schedule)
  })

  // The controller (host, or a collaborative guest) authors the timeline; it
  // plays natively and never waits. Guests reconcile to the schedule locally.
  // t0 is the controller's own server-synced timestamp, so guests align precisely.
  socket.on('sync:play', ({ positionTicks = 0, t0 } = {}) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return
    setSchedule(sess, { positionTicks, t0: t0 || Date.now(), rate: 1, paused: false, phase: 'playing' })
  })

  socket.on('sync:pause', ({ positionTicks = 0 } = {}) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return
    setSchedule(sess, { positionTicks, t0: 0, rate: 0, paused: true, phase: 'paused' })
  })

  socket.on('sync:seek', ({ positionTicks = 0, t0 } = {}) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return
    const wasPlaying = sess.schedule.phase === 'playing'
    setSchedule(sess, wasPlaying
      ? { positionTicks, t0: t0 || Date.now(), rate: 1, paused: false, phase: 'playing' }
      : { positionTicks, t0: 0, rate: 0, paused: true, phase: 'paused' })
  })

  // chat:message ────────────────────────────────────────────────────────────
  socket.on('chat:message', ({ text } = {}, ack) => {
    const sess = findSessionForMember(userId)
    if (!sess || !text?.trim()) return
    const msg = { userId, name, text: text.trim(), timestamp: Date.now() }
    pushMessage(sess, msg)
    io.to(sess.id).emit('chat:message', msg)
    ack?.({ ok: true })
  })

  // camera:remove ───────────────────────────────────────────────────────────
  socket.on('camera:remove', ({ userId: targetId } = {}, ack) => {
    const sess = findSessionByHost(userId)
    if (!sess) return ack?.({ error: 'not host' })
    io.to(sess.id).emit('camera:removed', { userId: targetId })
    ack?.({ ok: true })
  })

  // disconnect ──────────────────────────────────────────────────────────────
  socket.on('disconnect', () => {
    const sess = findSessionBySocket(socket.id)
    if (!sess) return

    if (sess.hostId === userId) {
      handleHostDisconnect(sess)
    } else {
      const g = removeGuest(sess, userId)
      if (g) io.to(sess.id).emit('user:left', { userId, name })
    }
  })
})

// ── Playback schedule (the shared timeline every client locks onto) ────────

const TICKS_PER_MS = 10_000

function setSchedule(sess, next) {
  sess.schedule = { ...next, version: (sess.schedule?.version ?? 0) + 1 }
  io.to(sess.id).emit('sync:schedule', sess.schedule)
}

function livePositionTicks(sess) {
  const s = sess.schedule
  if (s.paused || s.phase !== 'playing') return s.positionTicks
  return Math.max(0, s.positionTicks + (Date.now() - s.t0) * TICKS_PER_MS)
}

// ── Host disconnect grace period ──────────────────────────────────────────

const HOST_GRACE_MS = 30_000

function handleHostDisconnect(sess) {
  // Freeze the timeline where it currently is
  setSchedule(sess, { positionTicks: livePositionTicks(sess), t0: 0, rate: 0, paused: true, phase: 'paused' })
  io.to(sess.id).emit('sync:host_gone')

  sess.hostDisconnectTimer = setTimeout(() => {
    sess.hostDisconnectTimer = null
    const next = [...sess.guests].sort((a, b) => a.joinedAt - b.joinedAt)[0]
    if (!next) {
      deleteSession(sess.id)
      return
    }
    const nextSocket = io.sockets.sockets.get(next.socketId)
    const nextToken = nextSocket?.user?.token ?? sess.hostToken
    transferHost(sess, next.userId, next.socketId, nextToken)
    io.to(sess.id).emit('host:changed', { hostId: next.userId })
  }, HOST_GRACE_MS)
}

const PORT = process.env.PORT || 3001
httpServer.listen(PORT, () => console.log(`server listening on :${PORT}`))
