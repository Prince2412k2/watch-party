import { randomUUID } from 'crypto'

// In-memory store
const sessions = new Map() // partyId → Session

export function createSession({ hostId, hostToken, hostDeviceId, hostName, hostSocketId, mediaItemId, mediaSourceId }) {
  const id = randomUUID().slice(0, 8).toUpperCase()
  const session = {
    id,
    hostId,
    hostToken,        // never sent to client
    hostDeviceId,     // Jellyfin deviceId for SyncPlay calls
    hostSocketId,
    syncPlayGroupId: null,
    mediaItemId,
    mediaSourceId,
    guests: [],       // [{ userId, name, socketId, joinedAt }]
    waiting: [],      // [{ userId, name, socketId }]
    messages: [],     // capped 200
    collaborativeControl: false,
    hostDisconnectTimer: null,
    // Shared playback timeline. position = positionTicks + rate*(now - t0).
    schedule: { positionTicks: 0, t0: 0, rate: 0, paused: true, phase: 'paused', version: 0 },
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
  const { hostToken, hostDisconnectTimer, ...pub } = session
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
