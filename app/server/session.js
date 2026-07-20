import { randomUUID } from 'crypto'
import { loadParties, removeParty, saveParty } from './party-store.js'

const sessions = new Map() // partyId → Session

export const DEFAULT_SUBTITLE_PREFERENCES = Object.freeze({
  delayMs: 0,
  fontScalePercent: 100,
  verticalPosition: 'bottom',
  fontFamily: 'sans',
  textColor: '#FFFFFF',
  backgroundOpacityPercent: 65,
})

export function validateSubtitlePreferences(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return { error: 'invalid subtitlePreferences' }
  const keys = Object.keys(DEFAULT_SUBTITLE_PREFERENCES)
  if (Object.keys(value).length !== keys.length || keys.some(key => !(key in value))) return { error: 'invalid subtitlePreferences' }
  if (!Number.isInteger(value.delayMs) || value.delayMs < -10_000 || value.delayMs > 10_000) return { error: 'invalid delayMs' }
  if (!Number.isInteger(value.fontScalePercent) || value.fontScalePercent < 60 || value.fontScalePercent > 200) return { error: 'invalid fontScalePercent' }
  if (!['top', 'middle', 'bottom'].includes(value.verticalPosition)) return { error: 'invalid verticalPosition' }
  if (!['sans', 'serif', 'mono'].includes(value.fontFamily)) return { error: 'invalid fontFamily' }
  if (typeof value.textColor !== 'string' || !/^#[0-9A-Fa-f]{6}$/.test(value.textColor)) return { error: 'invalid textColor' }
  if (!Number.isInteger(value.backgroundOpacityPercent) || value.backgroundOpacityPercent < 0 || value.backgroundOpacityPercent > 100) return { error: 'invalid backgroundOpacityPercent' }
  return { value: { ...value, textColor: value.textColor.toUpperCase() } }
}

function durableState(session) {
  const durableGuest = ({ userId, name, token, deviceId, joinedAt }) => ({
    userId, name, token, deviceId, joinedAt,
  })

  return {
    id: session.id,
    originalHostId: session.originalHostId,
    hostId: session.hostId,
    hostName: session.hostName,
    hostToken: session.hostToken,
    hostDeviceId: session.hostDeviceId,
    mediaItemId: session.mediaItemId,
    mediaSourceId: session.mediaSourceId,
    playback: session.playback,
    subtitlePreferences: session.subtitlePreferences,
    stage: session.stage,
    browse: session.browse,
    guests: session.guests.map(durableGuest),
    approved: [...session.approved],
    messages: session.messages,
    collaborativeControl: session.collaborativeControl,
    mediaGeneration: session.mediaGeneration,
    schedule: session.schedule,
    syncMode: session.syncMode,
    intent: session.intent,
    pos: session.pos,
    playT0: session.playT0,
    effPlaying: session.effPlaying,
  }
}

function runtimeState(saved) {
  const mediaGeneration = saved.mediaGeneration ?? 0
  return {
    id: saved.id,
    originalHostId: saved.originalHostId ?? saved.hostId,
    hostId: saved.hostId,
    hostName: saved.hostName,
    hostToken: saved.hostToken,
    hostDeviceId: saved.hostDeviceId,
    hostSocketId: null,
    mediaItemId: saved.mediaItemId ?? null,
    mediaSourceId: saved.mediaSourceId ?? null,
    playback: saved.playback ?? null,
    subtitlePreferences: validateSubtitlePreferences(saved.subtitlePreferences).value ?? { ...DEFAULT_SUBTITLE_PREFERENCES },
    stage: saved.stage ?? (saved.mediaItemId ? 'watching' : 'lobby'),
    browse: saved.browse ?? { stack: [] },
    guests: (saved.guests ?? []).map(guest => ({ ...guest, socketId: null })),
    waiting: [],
    approved: new Set(saved.approved ?? [saved.hostId]),
    messages: saved.messages ?? [],
    collaborativeControl: saved.collaborativeControl ?? false,
    hostDisconnectTimer: null,
    mediaGeneration,
    syncMode: saved.syncMode ?? 'hopping',
    stalled: new Set(),
    stallFallback: new Set(),
    seenCommandIds: new Set(),
    reports: new Map(),
    intent: saved.intent ?? { playing: false },
    schedule: saved.schedule ?? { positionTicks: 0, t0: 0, rate: 0, paused: true, phase: 'paused', version: 0, mediaGeneration },
    pos: saved.pos ?? 0,
    playT0: saved.playT0 ?? 0,
    effPlaying: saved.effPlaying ?? false,
  }
}

const restoreGraceMs = Number(process.env.PARTY_RESTORE_GRACE_MS) || 60_000
for (const saved of loadParties()) {
  const session = runtimeState(saved)
  session.hostDisconnectTimer = setTimeout(() => deleteSession(session.id), restoreGraceMs)
  session.hostDisconnectTimer.unref()
  sessions.set(saved.id, session)
}

export function persistSession(session) {
  saveParty(durableState(session))
}

export function createSession({ hostId, hostToken, hostDeviceId, hostName, hostSocketId, mediaItemId = null, mediaSourceId = null }) {
  const id = randomUUID().slice(0, 8).toUpperCase()
  const session = {
    id,
    originalHostId: hostId,
    hostId,
    hostName,         // display name of the current host
    hostToken,        // never sent to client
    hostDeviceId,     // Jellyfin deviceId
    hostSocketId,
    mediaItemId,      // null until a title is chosen in the lobby
    mediaSourceId,
    playback: null,   // normalized PlaybackInfo for the current title
    subtitlePreferences: { ...DEFAULT_SUBTITLE_PREFERENCES },
    // 'lobby'    = everyone's in, browsing the library together, no title yet
    // 'watching' = a title is selected, playback sync engine is live
    stage: mediaItemId ? 'watching' : 'lobby',
    // Host-authority browse state, mirrored to guests (the "shared screen").
    // stack = drill path: [] = home, else [{ id, name, type }, …]
    browse: { stack: [] },
    guests: [],       // [{ userId, name, socketId, joinedAt }]
    waiting: [],      // [{ userId, name, socketId }]
    approved: new Set([hostId]),  // userIds allowed to re-enter without asking (until kicked)
    messages: [],     // capped 200
    collaborativeControl: false,
    hostDisconnectTimer: null,
    mediaGeneration: mediaItemId ? 1 : 0,
    // Shared playback timeline. position = positionTicks + rate*(now - t0).
    schedule: { positionTicks: 0, t0: 0, rate: 0, paused: true, phase: 'paused', version: 0, mediaGeneration: mediaItemId ? 1 : 0 },
    // 'hopping' = host-authority, guests catch up, host never waits.
    // 'dragging' = group waits for the slowest; any stall freezes everyone.
    syncMode: 'hopping',
    stalled: new Set(),   // members currently buffering (dragging mode)
    stallFallback: new Set(), // timed-out members temporarily treated as hopping
    seenCommandIds: new Set(),
    intent: { playing: false },  // host's play/pause intent (independent of stalls)
    pos: 0,               // frozen media position (ticks) when not effectively playing
    playT0: 0,            // server ms when the current play segment started
    effPlaying: false,    // is playback effectively running right now
    reports: new Map(),   // userId → { position, drift, rate, at } (debug telemetry)
  }
  sessions.set(id, session)
  persistSession(session)
  return session
}

export function getSession(id) {
  return sessions.get(id) ?? null
}

export function deleteSession(id) {
  sessions.delete(id)
  removeParty(id)
}

export function findSessionByUser(userId) {
  for (const s of sessions.values()) {
    if (s.hostId === userId) return s
    if (s.guests.some(g => g.userId === userId)) return s
    if (s.waiting.some(w => w.userId === userId)) return s
  }
  return null
}

export function findSessionBySocket(socketId) {
  for (const s of sessions.values()) {
    if (s.hostSocketId === socketId) return s
    if (s.guests.some(g => g.socketId === socketId)) return s
    if (s.waiting.some(w => w.socketId === socketId)) return s
  }
  return null
}

export function addToWaiting(session, user) {
  const existing = session.waiting.find(w => w.userId === user.userId)
  if (existing) {
    // Already waiting — just refresh the connection details, don't duplicate
    Object.assign(existing, user)
    return false
  }
  session.waiting.push(user)
  return true
}

export function approveGuest(session, userId) {
  const idx = session.waiting.findIndex(w => w.userId === userId)
  if (idx === -1) return null
  const [guest] = session.waiting.splice(idx, 1)
  guest.joinedAt = Date.now()
  session.guests.push(guest)
  session.approved.add(userId)   // remembered — can re-enter freely from now on
  return guest
}

// Directly admit a returning, already-approved user (skips the waiting room)
export function admitGuest(session, user) {
  const existing = session.guests.find(g => g.userId === user.userId)
  if (existing) { Object.assign(existing, user); return existing }
  const guest = { ...user, joinedAt: Date.now() }
  session.guests.push(guest)
  return guest
}

export function rejectGuest(session, userId) {
  const idx = session.waiting.findIndex(w => w.userId === userId)
  if (idx === -1) return null
  const [w] = session.waiting.splice(idx, 1)
  return w
}

export function removeGuest(session, userId) {
  const idx = session.guests.findIndex(g => g.userId === userId)
  if (idx === -1) return null
  const [g] = session.guests.splice(idx, 1)
  return g
}

export function randomConnectedGuest(session, isConnected, random = Math.random) {
  const connected = session.guests.filter(guest => isConnected(guest.socketId))
  return connected[Math.floor(random() * connected.length)] ?? null
}

export function transferHost(session, newHostUserId, newHostSocketId, newHostToken) {
  const guest = session.guests.find(g => g.userId === newHostUserId)
  if (!guest) return false
  const previousHost = {
    userId: session.hostId,
    name: session.hostName,
    socketId: session.hostSocketId,
    token: session.hostToken,
    deviceId: session.hostDeviceId,
    joinedAt: Date.now(),
  }
  session.hostId = newHostUserId
  session.hostName = guest.name
  session.hostSocketId = newHostSocketId
  session.hostToken = newHostToken
  session.hostDeviceId = guest.deviceId
  session.guests = session.guests.filter(g => g.userId !== newHostUserId)
  session.guests.push(previousHost)
  persistSession(session)
  return true
}

export function reclaimOriginalHost(session, { socketId, token, deviceId, name }) {
  if (session.hostId === session.originalHostId) return false
  const currentHost = {
    userId: session.hostId,
    name: session.hostName,
    socketId: session.hostSocketId,
    token: session.hostToken,
    deviceId: session.hostDeviceId,
    joinedAt: Date.now(),
  }
  session.guests = session.guests.filter(guest => guest.userId !== session.originalHostId)
  session.guests.push(currentHost)
  session.hostId = session.originalHostId
  session.hostName = name
  session.hostSocketId = socketId
  session.hostToken = token
  session.hostDeviceId = deviceId
  persistSession(session)
  return true
}

export function pushMessage(session, msg) {
  session.messages.push(msg)
  if (session.messages.length > 200) session.messages.shift()
  persistSession(session)
}

export function isHost(session, userId) {
  return session.hostId === userId
}

export function isMember(session, userId) {
  return session.hostId === userId || session.guests.some(g => g.userId === userId)
}

export function publicSession(session) {
  return {
    id: session.id,
    hostId: session.hostId,
    hostName: session.hostName,
    stage: session.stage,
    activity: session.activity ?? 'none',
    mediaItemId: session.mediaItemId,
    mediaSourceId: session.mediaSourceId,
    playback: session.playback,
    subtitlePreferences: session.subtitlePreferences,
    collaborativeControl: session.collaborativeControl,
    syncMode: session.syncMode,
    browse: session.browse,
    schedule: session.schedule,
    mediaGeneration: session.mediaGeneration,
    guests: session.guests.map(({ userId, name }) => ({ userId, name })),
    waiting: session.waiting.map(({ userId, name }) => ({ userId, name })),
    stallFallback: [...session.stallFallback],
  }
}

// Capability-aware wrapper around publicSession(). Modern clients (those that
// announced `caps.remoteBrowser` on connect) get the full DTO including
// `activity`. Legacy clients get the DTO with `activity` stripped, and — when
// the party is actually in `remote-browser` — `stage` is presented as `lobby`
// so an old client shows the library harmlessly instead of a stage it can't
// render.
export function publicSessionFor(session, { caps } = {}) {
  const pub = publicSession(session)
  if (caps?.remoteBrowser === true) return pub
  const { activity, ...legacy } = pub
  if (activity === 'remote-browser') legacy.stage = 'lobby'
  return legacy
}

// Centralized room broadcast: sends every socket currently in the party's
// room its own capability-appropriate snapshot, so a legacy client can never
// receive modern state (e.g. `activity`) through a broadcast. `except` skips
// a socket id (mirrors the `socket.to(id).emit` self-exclusion pattern).
export function emitPartyState(io, session, { except } = {}) {
  const room = io.sockets.adapter.rooms.get(session.id)
  if (!room) return
  for (const socketId of room) {
    if (except && socketId === except) continue
    const target = io.sockets.sockets.get(socketId)
    if (!target) continue
    io.to(socketId).emit('party:state', publicSessionFor(session, { caps: target.caps }))
  }
}

export function validateSyncCommand(payload = {}) {
  const positionTicks = payload.positionTicks ?? 0
  if (!Number.isFinite(positionTicks) || positionTicks < 0) return { error: 'invalid positionTicks' }
  if (payload.baseVersion !== undefined && (!Number.isSafeInteger(payload.baseVersion) || payload.baseVersion < 0)) {
    return { error: 'invalid baseVersion' }
  }
  if (payload.commandId !== undefined &&
      (typeof payload.commandId !== 'string' || payload.commandId.length < 1 || payload.commandId.length > 128)) {
    return { error: 'invalid commandId' }
  }
  const value = { positionTicks }
  if (payload.baseVersion !== undefined) value.baseVersion = payload.baseVersion
  if (payload.commandId !== undefined) value.commandId = payload.commandId
  return { value }
}

export function authorizeSyncCommand(session, command) {
  if (command.baseVersion !== undefined && command.baseVersion !== session.schedule.version) {
    return { error: 'stale schedule', version: session.schedule.version }
  }
  if (command.commandId && session.seenCommandIds.has(command.commandId)) return { error: 'duplicate command' }
  if (command.commandId) {
    session.seenCommandIds.add(command.commandId)
    if (session.seenCommandIds.size > 512) session.seenCommandIds.delete(session.seenCommandIds.values().next().value)
  }
  return { ok: true }
}

export function beginMediaGeneration(session) {
  session.mediaGeneration++
  session.stalled.clear()
  session.stallFallback.clear()
  session.seenCommandIds.clear()
  return session.mediaGeneration
}

export function applyStallReport(session, userId, { stalled = false, mediaGeneration } = {}) {
  if (mediaGeneration !== undefined && mediaGeneration !== session.mediaGeneration) return false
  if (!stalled) {
    const changed = session.stalled.delete(userId) || session.stallFallback.delete(userId)
    return changed
  }
  if (session.stallFallback.has(userId)) return false
  const before = session.stalled.size
  session.stalled.add(userId)
  return session.stalled.size !== before
}

export function allSessions() {
  return sessions.values()
}

export function findSessionForMember(userId) {
  for (const s of sessions.values()) {
    if (s.hostId === userId || s.guests.some(g => g.userId === userId)) return s
  }
  return null
}

export function findSessionByHost(hostId) {
  for (const s of sessions.values()) {
    if (s.hostId === hostId) return s
  }
  return null
}
