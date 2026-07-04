import { randomUUID } from 'crypto'

// In-memory store
const sessions = new Map() // partyId → Session

export function createSession({ hostId, hostToken, hostDeviceId, hostName, hostSocketId, mediaItemId = null, mediaSourceId = null }) {
  const id = randomUUID().slice(0, 8).toUpperCase()
  const session = {
    id,
    hostId,
    hostName,         // display name of the current host
    hostToken,        // never sent to client
    hostDeviceId,     // Jellyfin deviceId
    hostSocketId,
    mediaItemId,      // null until a title is chosen in the lobby
    mediaSourceId,
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
    // Shared playback timeline. position = positionTicks + rate*(now - t0).
    schedule: { positionTicks: 0, t0: 0, rate: 0, paused: true, phase: 'paused', version: 0 },
    // 'hopping' = host-authority, guests catch up, host never waits.
    // 'dragging' = group waits for the slowest; any stall freezes everyone.
    syncMode: 'hopping',
    stalled: new Set(),   // members currently buffering (dragging mode)
    intent: { playing: false },  // host's play/pause intent (independent of stalls)
    pos: 0,               // frozen media position (ticks) when not effectively playing
    playT0: 0,            // server ms when the current play segment started
    effPlaying: false,    // is playback effectively running right now
    reports: new Map(),   // userId → { position, drift, rate, at } (debug telemetry)
  }
  sessions.set(id, session)
  return session
}

export function getSession(id) {
  return sessions.get(id) ?? null
}

export function deleteSession(id) {
  sessions.delete(id)
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

export function transferHost(session, newHostUserId, newHostSocketId, newHostToken) {
  const guest = session.guests.find(g => g.userId === newHostUserId)
  if (!guest) return false
  session.hostId = newHostUserId
  session.hostName = guest.name
  session.hostSocketId = newHostSocketId
  session.hostToken = newHostToken
  session.guests = session.guests.filter(g => g.userId !== newHostUserId)
  return true
}

export function pushMessage(session, msg) {
  session.messages.push(msg)
  if (session.messages.length > 200) session.messages.shift()
}

export function isHost(session, userId) {
  return session.hostId === userId
}

export function isMember(session, userId) {
  return session.hostId === userId || session.guests.some(g => g.userId === userId)
}

export function publicSession(session) {
  const {
    hostToken, hostDisconnectTimer, approved,
    stalled, intent, pos, playT0, effPlaying, _stallTimer, reports,
    ...pub
  } = session
  return pub
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
