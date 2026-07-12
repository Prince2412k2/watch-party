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
import FileStoreFactory from 'session-file-store'
import { existsSync, mkdirSync } from 'fs'
import { join } from 'path'
import { createProxyMiddleware } from 'http-proxy-middleware'
import { login, me, logout, testLogin, requireAuth } from './auth.js'
import { registerLibraryRoutes } from './library.js'
import { registerNativeRoutes } from './native.js'
import { registerSubtitleRoutes } from './subtitles.js'
import { registerLiveKitRoutes } from './livekit.js'
import { registerServarrRoutes } from './servarr/index.js'
import { refreshPlayback } from './playback.js'
import {
  createSession, getSession, deleteSession,
  findSessionBySocket, findSessionForMember, findSessionByHost,
  addToWaiting, approveGuest, admitGuest, rejectGuest, removeGuest,
  transferHost, pushMessage, isHost, isMember, publicSession, allSessions,
  validateSyncCommand, authorizeSyncCommand, beginMediaGeneration, applyStallReport,
} from './session.js'
import { getItems } from './jellyfin.js'

// Fail fast: never run in production with a missing or default session secret.
if (process.env.NODE_ENV === 'production' &&
    (!process.env.SESSION_SECRET || process.env.SESSION_SECRET === 'changeme')) {
  console.error('FATAL: SESSION_SECRET must be set to a strong, non-default value in production')
  process.exit(1)
}

const app = express()
// Behind the Tailscale Funnel (a reverse proxy) — trust the first proxy hop so
// req.ip and secure-cookie detection reflect the real client, not the proxy.
app.set('trust proxy', 1)
const httpServer = createServer(app)

// Allowed browser origins. Same-origin (the server now serves the built client)
// needs none of these, but keep dev (Vite) + the tailnet reachable, and let
// deployments add their own public origin(s) via PUBLIC_ORIGIN (comma-separated).
const EXTRA_ORIGINS = (process.env.PUBLIC_ORIGIN || '')
  .split(',').map((s) => s.trim()).filter(Boolean)
// The dev/tailnet origin is env-driven with a default so current local/tailnet
// dev keeps working, but a deployment can override it (or set it empty).
const DEV_TAILNET_ORIGIN = process.env.DEV_TAILNET_ORIGIN ?? 'https://dsk-4161.tail0a3558.ts.net'
const ALLOWED_ORIGINS = [
  'http://localhost:5173', 'http://localhost:5174',
  ...(DEV_TAILNET_ORIGIN ? [DEV_TAILNET_ORIGIN] : []),
  ...EXTRA_ORIGINS,
]

const io = new Server(httpServer, {
  cors: { origin: ALLOWED_ORIGINS, credentials: true },
})

// Sessions persist to disk so a redeploy (container restart) doesn't silently
// log everyone out — express-session's default MemoryStore is wiped on every
// restart. SESSION_STORE_DIR should be a bind-mounted volume in production
// (see docker-compose.yml) so it survives a container recreate, not just a
// process restart. Test mode uses a private tmp dir per run so parallel
// scratch-server tests never share or pollute session state.
const FileStore = FileStoreFactory(session)
const sessionStoreDir = process.env.SESSION_STORE_DIR
  || (process.env.WP_TEST_MODE === '1'
    ? join('/tmp', `wp-test-sessions-${process.pid}-${Date.now()}`)
    : join(__dirname, '../../data/sessions'))
mkdirSync(sessionStoreDir, { recursive: true })

const sessionMiddleware = session({
  store: new FileStore({
    path: sessionStoreDir,
    ttl: 7 * 24 * 60 * 60,                    // seconds — matches cookie maxAge below
    reapInterval: 60 * 60,                    // purge expired session files hourly
    logFn: () => {},                          // quiet — the store logs routine housekeeping otherwise
  }),
  secret: process.env.SESSION_SECRET || 'changeme',
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    domain: process.env.SESSION_COOKIE_DOMAIN || undefined,
    maxAge: 7 * 24 * 60 * 60 * 1000,          // 7 days
    secure: process.env.NODE_ENV === 'production',
  },
})

// ── Origin-relative reverse proxies (production parity with Vite's dev proxy) ──
// The browser keeps everything same-origin: HLS manifests/segments and poster
// images hit /jellyfin/* (server → JELLYFIN_URL), and LiveKit *signaling* can go
// through /livekit (server → LIVEKIT_URL) so an HTTPS page isn't blocked by
// mixed content. Media (UDP/ICE) still flows direct to livekit's node_ip.
// Registered before the JSON body parser so streamed bodies pass through raw.
const JELLYFIN_TARGET = process.env.JELLYFIN_URL || 'http://localhost:8096'
const LIVEKIT_TARGET = (process.env.LIVEKIT_URL || 'ws://localhost:7880').replace(/^ws/, 'http')

// Session must be available BEFORE the proxies so requireAuth can gate them —
// these expose internal services and must never be reachable unauthenticated.
app.use(cookieParser())
app.use(sessionMiddleware)
io.engine.use(sessionMiddleware)

app.use('/jellyfin', requireAuth, createProxyMiddleware({
  target: JELLYFIN_TARGET,
  changeOrigin: true,
  pathRewrite: { '^/jellyfin': '' },
  on: {
    proxyReq: (proxyReq, req) => {
      const token = req.session?.jellyfin?.accessToken
      if (token) proxyReq.setHeader('X-Emby-Token', token)
    },
  },
}))

const livekitProxy = createProxyMiddleware({
  target: LIVEKIT_TARGET,
  changeOrigin: true,
  ws: true,
  pathRewrite: { '^/livekit': '' },
})
app.use('/livekit', requireAuth, livekitProxy)
// Proxy the WebSocket upgrade for /livekit only. socket.io owns /socket.io
// upgrades on the same server; the path filter keeps the two from colliding.
httpServer.on('upgrade', (req, socket, head) => {
  if (req.url && req.url.startsWith('/livekit')) livekitProxy.upgrade(req, socket, head)
})

app.use(express.json())

// ── Login brute-force limiter (in-process, dependency-free) ────────────────
// Keyed by client IP (req.ip is accurate now that trust proxy is set) + the
// attempted username, plus a coarse global cap so a distributed spray can't
// hammer the upstream Jellyfin. Windows reset lazily on next attempt.
const LOGIN_WINDOW_MS = 5 * 60 * 1000
const LOGIN_MAX_ATTEMPTS = 10          // per IP+username per window
const LOGIN_GLOBAL_MAX = 300           // coarse cap across all keys per window
const loginAttempts = new Map()        // key -> { count, resetAt }
let loginGlobal = { count: 0, resetAt: Date.now() + LOGIN_WINDOW_MS }

function loginRateLimit(req, res, next) {
  const now = Date.now()

  // Coarse global cap
  if (now > loginGlobal.resetAt) loginGlobal = { count: 0, resetAt: now + LOGIN_WINDOW_MS }
  if (loginGlobal.count >= LOGIN_GLOBAL_MAX) {
    res.set('Retry-After', String(Math.ceil((loginGlobal.resetAt - now) / 1000)))
    return res.status(429).json({ error: 'Too many login attempts, please try again later' })
  }
  loginGlobal.count++

  const username = (req.body?.username || '').toString().toLowerCase().trim()
  const key = `${req.ip}|${username}`
  let entry = loginAttempts.get(key)
  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + LOGIN_WINDOW_MS }
    loginAttempts.set(key, entry)
  }
  if (entry.count >= LOGIN_MAX_ATTEMPTS) {
    res.set('Retry-After', String(Math.ceil((entry.resetAt - now) / 1000)))
    return res.status(429).json({ error: 'Too many login attempts, please try again later' })
  }
  entry.count++
  next()
}

// Test/debug endpoints are hard-gated: they require BOTH a non-production
// NODE_ENV and the explicit WP_TEST_MODE flag. In production they don't exist.
const TEST_ENDPOINTS_ENABLED = process.env.NODE_ENV !== 'production' && process.env.WP_TEST_MODE === '1'

app.get('/api/health', (_req, res) => res.json({ ok: true }))
app.post('/api/auth/login', loginRateLimit, login)
if (TEST_ENDPOINTS_ENABLED) {
  app.post('/api/auth/test-login', testLogin)   // absent unless test mode + non-prod
}
app.get('/api/auth/me', me)
app.post('/api/auth/logout', logout)
registerLibraryRoutes(app)
registerSubtitleRoutes(app, io)
registerLiveKitRoutes(app)
registerServarrRoutes(app)
registerNativeRoutes(app)

// ── Dev-only observability (gated: 404 unless WP_TEST_MODE=1) ───────────────
// Exposes session internals for the sync test harness. MUST stay off in prod.
function debugMembers(sess) {
  const members = [{ userId: sess.hostId, name: sess.hostName, isHost: true }]
  for (const g of sess.guests) members.push({ userId: g.userId, name: g.name, isHost: false })
  return members.map(m => ({ ...m, report: sess.reports?.get(m.userId) ?? null }))
}
function debugView(sess) {
  return { id: sess.id, syncMode: sess.syncMode, schedule: sess.schedule, members: debugMembers(sess) }
}
if (TEST_ENDPOINTS_ENABLED) {
  app.get('/api/debug/sessions', (_req, res) => {
    res.json([...allSessions()].map(debugView))
  })
  app.get('/api/debug/session/:id', (req, res) => {
    const sess = getSession(req.params.id)
    if (!sess) return res.status(404).json({ error: 'not found' })
    res.json(debugView(sess))
  })
}

// ── Serve the built client (production) ────────────────────────────────────
// In dev the client is a separate Vite server (npm run dev). In the container
// we build client/dist and serve it here so ONE port serves the web UI, /api,
// and Socket.io. Gated on SERVE_CLIENT so `npm run dev` on the host is unaffected.
if (process.env.SERVE_CLIENT === '1') {
  const clientDist = join(__dirname, '../client/dist')
  if (existsSync(clientDist)) {
    app.use(express.static(clientDist))
    // SPA fallback — hand any non-API, non-socket, non-proxy path to index.html
    app.get('*', (req, res, next) => {
      if (req.path.startsWith('/api') || req.path.startsWith('/socket.io') ||
          req.path.startsWith('/jellyfin') || req.path.startsWith('/livekit')) return next()
      res.sendFile(join(clientDist, 'index.html'))
    })
  } else {
    console.warn(`SERVE_CLIENT=1 but ${clientDist} is missing — run "npm run build" in client/`)
  }
}

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
  socket.on('party:create', async ({ mediaItemId = null } = {}, ack) => {
    let sess = null
    try {
      // Room can start empty (lobby) — media is optional at creation.
      let mediaSourceId = null
      if (mediaItemId) {
        const src = await resolveMediaSourceSafe(token, userId, mediaItemId)
        if (!src) return ack?.({ error: 'item not found' })
        mediaSourceId = src
      }

      sess = createSession({
        hostId: userId, hostToken: token, hostDeviceId: deviceId, hostName: name,
        hostSocketId: socket.id, mediaItemId, mediaSourceId,
      })
      if (mediaItemId) {
        await refreshPlayback(sess, { token, userId, itemId: mediaItemId, mediaSourceId })
      }

      socket.join(sess.id)
      ack?.({ partyId: sess.id, session: publicSession(sess) })
    } catch (err) {
      console.error('party:create', err.message)
      if (sess) deleteSession(sess.id)
      ack?.({ error: err.message })
    }
  })

  // party:join ──────────────────────────────────────────────────────────────
  socket.on('party:join', ({ partyId } = {}, ack) => {
    const sess = getSession(partyId)
    if (!sess) return ack?.({ error: 'party not found' })

    // Rejoining uses the same Socket instance on the client but a brand-new
    // Socket.IO id on the server. Restore every room-scoped channel here, then
    // replay state that may have changed while the connection was down. In
    // particular, useSyncPlay stays mounted across a transport reconnect and
    // therefore does not emit its mount-time sync:hello again by itself.
    const restoreSocket = () => {
      socket.join(sess.id)
      io.to(socket.id).emit('chat:history', sess.messages)
      io.to(socket.id).emit('sync:schedule', sess.schedule)
    }

    if (sess.hostId === userId) {
      // Host reconnecting after disconnect
      if (sess.hostDisconnectTimer) {
        clearTimeout(sess.hostDisconnectTimer)
        sess.hostDisconnectTimer = null
      }
      sess.hostSocketId = socket.id
      restoreSocket()
      return ack?.({ status: 'joined', session: publicSession(sess) })
    }

    if (isMember(sess, userId)) {
      const guest = sess.guests.find(g => g.userId === userId)
      if (guest) guest.socketId = socket.id
      restoreSocket()
      return ack?.({ status: 'joined', session: publicSession(sess) })
    }

    // Previously approved → re-enter freely (no re-approval needed unless kicked)
    if (sess.approved.has(userId)) {
      admitGuest(sess, { userId, name, socketId: socket.id, token, deviceId })
      restoreSocket()
      // The ack's session snapshot already contains this guest. Exclude the
      // rejoining socket so its reducer cannot append itself a second time.
      socket.to(sess.id).emit('user:joined', { userId, name })
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
    sess.approved.delete(targetId)   // revoke — kicked users must re-request
    io.to(g.socketId).emit('party:kicked', { userId: targetId })
    io.to(sess.id).emit('user:left', { userId: targetId, name: g.name })
    ack?.({ ok: true })
  })

  // party:end — host's explicit "End Party" action. Unlike a host disconnect
  // (handleHostDisconnect below), this is instant and final: no grace period,
  // no promoting a guest to host. The session is torn down immediately and
  // everyone still connected is told to leave.
  socket.on('party:end', (_p, ack) => {
    const sess = findSessionByHost(userId)
    if (!sess) return ack?.({ error: 'not host' })
    clearTimeout(sess.hostDisconnectTimer)
    clearTimeout(sess._stallTimer)
    socket.to(sess.id).emit('party:ended', {})
    deleteSession(sess.id)
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

  // browse:navigate — the driver moved through the library; mirror to everyone
  // else in the room (the driver already applied it optimistically).
  socket.on('browse:navigate', ({ stack = [] } = {}) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return
    sess.browse = { stack: Array.isArray(stack) ? stack.slice(0, 8) : [] }
    socket.to(sess.id).emit('browse:state', sess.browse)
  })

  // browse:pointer — the driver's live scroll + cursor, mirrored to the room so
  // guests see exactly where the host is looking. Ephemeral (never persisted):
  // high-frequency, only meaningful in the moment. Relay-only, driver-gated.
  socket.on('browse:pointer', ({ scroll, x, y } = {}) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return
    socket.to(sess.id).emit('browse:pointer', { scroll, x, y })
  })

  // party:selectMedia — a title was chosen in the lobby → enter watching stage
  socket.on('party:selectMedia', async ({ mediaItemId } = {}, ack) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return ack?.({ error: 'not allowed' })
    try {
      const src = await resolveMediaSourceSafe(token, userId, mediaItemId)
      if (!src) return ack?.({ error: 'item not found' })
      await refreshPlayback(sess, { token, userId, itemId: mediaItemId, mediaSourceId: src })
      sess.mediaItemId = mediaItemId
      sess.mediaSourceId = src
      sess.stage = 'watching'
      beginMediaGeneration(sess)
      // Autoplay from the top: the picker's click is a user gesture (host),
      // and guests are muted so synced play() isn't blocked by autoplay policy.
      sess.pos = 0
      sess.stalled.clear()
      clearTimeout(sess._stallTimer)
      sess.intent.playing = true
      startSegment(sess, Date.now())
      io.to(sess.id).emit('party:state', publicSession(sess))
      ack?.({ ok: true })
    } catch (err) {
      console.error('party:selectMedia', err.message)
      ack?.({ error: err.message })
    }
  })

  // party:backToLobby — stop the movie, return everyone to shared browsing
  socket.on('party:backToLobby', (_p, ack) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return ack?.({ error: 'not allowed' })
    sess.mediaItemId = null
    sess.mediaSourceId = null
    sess.playback = null
    sess.stage = 'lobby'
    beginMediaGeneration(sess)
    resetTimeline(sess)
    io.to(sess.id).emit('party:state', publicSession(sess))
    ack?.({ ok: true })
  })

  socket.on('party:setPlaybackTracks', async ({ audioStreamIndex = null, subtitleStreamIndex = null } = {}, ack) => {
    const sess = findSessionForMember(userId)
    if (!sess || sess.hostId !== userId || !sess.mediaItemId) return ack?.({ error: 'not allowed' })
    try {
      const playback = await refreshPlayback(sess, {
        token,
        userId,
        itemId: sess.mediaItemId,
        mediaSourceId: sess.mediaSourceId,
        audioStreamIndex: Number.isInteger(audioStreamIndex) ? audioStreamIndex : null,
        subtitleStreamIndex: Number.isInteger(subtitleStreamIndex) ? subtitleStreamIndex : null,
      })
      io.to(sess.id).emit('party:state', publicSession(sess))
      ack?.({ ok: true, playback })
    } catch (err) {
      console.error('party:setPlaybackTracks', err.message)
      ack?.({ error: err.message })
    }
  })

  // sync:hello — client asks for the current timeline once it's listening
  // (avoids the race where a pushed schedule arrives before the guest mounts)
  socket.on('sync:hello', () => {
    const sess = findSessionForMember(userId)
    if (sess) io.to(socket.id).emit('sync:schedule', sess.schedule)
  })

  // The controller authors intent (play/pause/seek). The effective schedule is
  // intent gated by readiness — in dragging mode a stall freezes the group.
  //
  // Conflict policy for collaborative control (multiple concurrent controllers):
  // commands are otherwise applied in server arrival order — last writer wins,
  // with no merging or rejection based on who issued the previous command. A
  // controller MAY opt into optimistic concurrency by sending baseVersion; that
  // command is rejected with 'stale schedule' if sess.schedule.version has moved
  // on since the controller last observed it. baseVersion is optional and
  // omitting it (older/legacy clients) falls back to plain last-writer-wins, so
  // this stays backward-compatible without a protocol bump.
  function acceptSyncCommand(sess, payload, ack) {
    const parsed = validateSyncCommand(payload)
    if (parsed.error) { ack?.({ error: parsed.error }); return null }
    const authorized = authorizeSyncCommand(sess, parsed.value)
    if (authorized.error) { ack?.(authorized); return null }
    const now = Date.now()
    socket._syncCommandTimes = (socket._syncCommandTimes || []).filter(t => now - t < 3000)
    if (socket._syncCommandTimes.length >= 30) { ack?.({ error: 'rate limited' }); return null }
    socket._syncCommandTimes.push(now)
    return parsed.value
  }

  socket.on('sync:play', (payload = {}, ack) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return ack?.({ error: 'not allowed' })
    const command = acceptSyncCommand(sess, payload, ack)
    if (!command) return
    sess.intent.playing = true
    sess.pos = command.positionTicks
    startSegment(sess, Date.now())
    ack?.({ ok: true, version: sess.schedule.version })
  })

  socket.on('sync:pause', (payload = {}, ack) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return ack?.({ error: 'not allowed' })
    const command = acceptSyncCommand(sess, payload, ack)
    if (!command) return
    sess.intent.playing = false
    sess.pos = command.positionTicks
    sess.effPlaying = false
    setSchedule(sess, { positionTicks: sess.pos, t0: 0, rate: 0, paused: true, phase: 'paused' })
    ack?.({ ok: true, version: sess.schedule.version })
  })

  socket.on('sync:seek', (payload = {}, ack) => {
    const sess = findSessionForMember(userId)
    if (!sess || !canDrive(sess)) return ack?.({ error: 'not allowed' })
    const command = acceptSyncCommand(sess, payload, ack)
    if (!command) return
    sess.pos = command.positionTicks
    // Preserve intent: scrubbing while paused must not start the room playing.
    if (sess.intent.playing) {
      startSegment(sess, Date.now())
    } else {
      sess.effPlaying = false
      setSchedule(sess, { positionTicks: sess.pos, t0: 0, rate: 0, paused: true, phase: 'paused' })
    }
    ack?.({ ok: true, version: sess.schedule.version })
  })

  // sync:report — a member's live drift telemetry (debug/observability only)
  socket.on('sync:report', ({ position, drift, rate } = {}) => {
    const sess = findSessionForMember(userId)
    if (!sess) return
    sess.reports.set(userId, { position, drift, rate, at: Date.now() })
  })

  // sync:stall — a member's buffering state changed (drives dragging mode)
  socket.on('sync:stall', (payload = {}) => {
    const sess = findSessionForMember(userId)
    if (!sess) return
    if (applyStallReport(sess, userId, payload)) reconcile(sess)
  })

  // party:setSyncMode — host switches hopping ↔ dragging
  socket.on('party:setSyncMode', ({ mode } = {}, ack) => {
    const sess = findSessionByHost(userId)
    if (!sess) return ack?.({ error: 'not host' })
    sess.syncMode = mode === 'dragging' ? 'dragging' : 'hopping'
    if (sess.syncMode === 'hopping') {
      sess.stalled.clear()
      sess.stallFallback.clear()
    }
    io.to(sess.id).emit('party:state', publicSession(sess))
    reconcile(sess)
    ack?.({ ok: true })
  })

  // chat:message ────────────────────────────────────────────────────────────
  const CHAT_MAX_LEN = 2000
  const CHAT_RATE_WINDOW_MS = 3000
  const CHAT_RATE_MAX = 5
  socket.on('chat:message', ({ text } = {}, ack) => {
    const sess = findSessionForMember(userId)
    if (!sess || !text?.trim()) return
    // Light per-socket rate limit
    const now = Date.now()
    socket._chatTimes = (socket._chatTimes || []).filter(t => now - t < CHAT_RATE_WINDOW_MS)
    if (socket._chatTimes.length >= CHAT_RATE_MAX) return ack?.({ error: 'rate limited' })
    socket._chatTimes.push(now)
    // Server-side length cap (truncate) so a client can't flood the room log
    const clean = text.trim().slice(0, CHAT_MAX_LEN)
    const msg = { userId, name, text: clean, timestamp: now }
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
      // A departing member must not keep the group frozen in dragging mode
      const stallChanged = sess.stalled.delete(userId) || sess.stallFallback.delete(userId)
      if (stallChanged) reconcile(sess)
    }
  })
})

// ── Playback schedule (the shared timeline every client locks onto) ────────

const TICKS_PER_MS = 10_000

const STALL_MAX_MS = 30_000     // dragging: don't let one dead client freeze forever

function setSchedule(sess, next) {
  sess.schedule = {
    ...next,
    version: (sess.schedule?.version ?? 0) + 1,
    mediaGeneration: sess.mediaGeneration,
  }
  io.to(sess.id).emit('sync:schedule', sess.schedule)
}

// Resolve a media item's primary MediaSource id (used at create + select time)
async function resolveMediaSource(token, userId, mediaItemId) {
  const data = await getItems(token, userId, { Ids: mediaItemId, Fields: 'MediaSources' })
  const item = data.Items?.[0]
  if (!item) return null
  return item.MediaSources?.[0]?.Id ?? mediaItemId
}

// Same, but under WP_TEST_MODE a fake Jellyfin token can't reach the real API,
// so fall back to the given id (or a dummy) — the timeline engine only needs an
// id to run; the harness never fetches real video. Only reachable in test mode.
async function resolveMediaSourceSafe(token, userId, mediaItemId) {
  try {
    const src = await resolveMediaSource(token, userId, mediaItemId)
    if (src) return src
  } catch (err) {
    if (process.env.WP_TEST_MODE !== '1') throw err
  }
  if (process.env.WP_TEST_MODE === '1') return mediaItemId || 'test-media'
  return null
}

// Reset the shared timeline to a fresh, paused-at-start state (new title / lobby)
function resetTimeline(sess) {
  sess.intent.playing = false
  sess.pos = 0
  sess.effPlaying = false
  sess.stalled.clear()
  clearTimeout(sess._stallTimer)
  setSchedule(sess, { positionTicks: 0, t0: 0, rate: 0, paused: true, phase: 'paused' })
}

function livePositionTicks(sess) {
  const s = sess.schedule
  if (s.paused || s.phase !== 'playing') return s.positionTicks
  return Math.max(0, s.positionTicks + (Date.now() - s.t0) * TICKS_PER_MS)
}

function gated(sess) {
  return sess.syncMode === 'dragging' && sess.stalled.size > 0
}

// Begin (or restart) a play segment from sess.pos, unless readiness gates it.
function startSegment(sess, t0) {
  if (gated(sess)) {
    sess.effPlaying = false
    setSchedule(sess, { positionTicks: sess.pos, t0: 0, rate: 0, paused: true, phase: 'stalled' })
    return
  }
  sess.effPlaying = true
  sess.playT0 = t0
  setSchedule(sess, { positionTicks: sess.pos, t0, rate: 1, paused: false, phase: 'playing' })
}

// Re-evaluate the effective schedule against intent + readiness (stall changes).
function reconcile(sess) {
  const g = gated(sess)
  const shouldPlay = sess.intent.playing && !g

  if (shouldPlay && !sess.effPlaying) {
    startSegment(sess, Date.now())              // all clear → resume from frozen pos
  } else if (!shouldPlay && sess.effPlaying) {
    // freeze where we are (media didn't advance while we wait)
    sess.pos = Math.max(0, sess.pos + (Date.now() - sess.playT0) * TICKS_PER_MS)
    sess.effPlaying = false
    setSchedule(sess, { positionTicks: sess.pos, t0: 0, rate: 0, paused: true, phase: g ? 'stalled' : 'paused' })
  } else if (!sess.effPlaying) {
    // stay paused, but reflect whether it's a user-pause or a stall-freeze
    const phase = g ? 'stalled' : (sess.intent.playing ? 'stalled' : 'paused')
    if (sess.schedule.phase !== phase) {
      setSchedule(sess, { positionTicks: sess.pos, t0: 0, rate: 0, paused: true, phase })
    }
  }

  // Safety: if we've been frozen on a stall too long, force-resume (fall back to
  // hopping for the laggard) so a dead client can't hold everyone hostage.
  clearTimeout(sess._stallTimer)
  if (g && sess.intent.playing) {
    sess._stallTimer = setTimeout(() => {
      for (const memberId of sess.stalled) sess.stallFallback.add(memberId)
      sess.stalled.clear()
      io.to(sess.id).emit('sync:stall_fallback', {
        memberIds: [...sess.stallFallback],
        mediaGeneration: sess.mediaGeneration,
      })
      reconcile(sess)
    }, STALL_MAX_MS)
  }
}

// ── Host disconnect grace period ──────────────────────────────────────────

// 30s in production; a test harness may shorten it via WP_HOST_GRACE_MS to
// exercise host-migration end-to-end without a 30s wait (test mode only).
const HOST_GRACE_MS = (process.env.WP_TEST_MODE === '1' && Number(process.env.WP_HOST_GRACE_MS) > 0)
  ? Number(process.env.WP_HOST_GRACE_MS)
  : 30_000

function handleHostDisconnect(sess) {
  // Freeze the timeline where it currently is, and normalize the derived state
  // so a reconcile() during the grace window (e.g. a stall change) can't act on
  // stale effPlaying/intent/playT0/pos values.
  //
  // Product rule (explicit, not incidental): losing the host always pauses the
  // room, and playback does NOT auto-resume when a new host is promoted below.
  // The promoted host inherits a paused, frozen-in-place timeline and must
  // press Play again. This avoids surprising an unattended room into playing
  // on with nobody driving, and gives the new host a deliberate moment to take
  // over. If this policy ever changes, update the hostMigration harness
  // scenario (app/harness/scenarios/advanced.js) to assert the new behavior.
  const frozenPos = livePositionTicks(sess)
  sess.pos = frozenPos
  sess.effPlaying = false
  sess.intent.playing = false
  sess.playT0 = 0
  setSchedule(sess, { positionTicks: frozenPos, t0: 0, rate: 0, paused: true, phase: 'paused' })
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

// ── Process-level error handling ───────────────────────────────────────────
// Log loudly but stay alive: a single rejected promise or a stray throw from a
// socket handler must not take the whole watch party down.
process.on('unhandledRejection', (reason) => {
  console.error('unhandledRejection:', reason)
})
process.on('uncaughtException', (err) => {
  console.error('uncaughtException:', err)
})

const PORT = process.env.PORT || 3001
httpServer.listen(PORT, () => console.log(`server listening on :${PORT}`))
