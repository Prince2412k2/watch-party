import { randomUUID } from 'node:crypto'
import { loadLease, saveLease, clearLease } from '../party-store.js'

export function acquireLease({ partyId, hostName }) {
  const existing = loadLease()
  if (existing) return { ok: false, hostName: existing.hostName }
  const leaseId = randomUUID()
  saveLease({
    partyId,
    hostName,
    state: 'starting',
    leaseId,
    sessions: [],
    acquiredAt: Date.now(),
  })
  return { ok: true, leaseId }
}

export function markActive(partyId) {
  const row = loadLease()
  if (!row || row.partyId !== partyId || row.state !== 'starting') return
  saveLease({ ...row, state: 'active' })
}

export function beginCleaning(partyId) {
  const row = loadLease()
  if (!row || row.partyId !== partyId) return
  if (row.state === 'cleaning') return
  if (row.state === 'starting' || row.state === 'active') {
    saveLease({ ...row, state: 'cleaning' })
  }
}

export function releaseLease(partyId) {
  const row = loadLease()
  if (!row || row.partyId !== partyId || row.state !== 'cleaning') return
  clearLease()
}

export function getLease() {
  const row = loadLease()
  if (!row) return null
  return { partyId: row.partyId, hostName: row.hostName, state: row.state, leaseId: row.leaseId }
}

export function recordUserSession(partyId, leaseId, userId, nekoSessionId) {
  const row = loadLease()
  if (!row || row.partyId !== partyId || row.leaseId !== leaseId) return
  const sessions = row.sessions.filter(entry => !(entry.userId === userId && entry.nekoSessionId === nekoSessionId))
  sessions.push({ userId, nekoSessionId })
  saveLease({ ...row, sessions })
}

export function sessionsForUser(partyId, userId) {
  const row = loadLease()
  if (!row || row.partyId !== partyId) return []
  return row.sessions.filter(entry => entry.userId === userId).map(({ nekoSessionId }) => ({ nekoSessionId }))
}

export function removeUserSession(partyId, userId, nekoSessionId) {
  const row = loadLease()
  if (!row || row.partyId !== partyId) return
  const sessions = row.sessions.filter(entry => !(entry.userId === userId && entry.nekoSessionId === nekoSessionId))
  saveLease({ ...row, sessions })
}

export function sessionsFor(partyId) {
  const row = loadLease()
  if (!row || row.partyId !== partyId) return []
  return row.sessions.map(({ userId, nekoSessionId }) => ({ userId, nekoSessionId }))
}

export function controllerUserFor(nekoSessionId) {
  const row = loadLease()
  if (!row) return null
  const entry = row.sessions.find(session => session.nekoSessionId === nekoSessionId)
  return entry ? entry.userId : null
}

export async function reconcileLease({ listSessions, teardown, hasLiveParty } = {}) {
  const row = loadLease()
  if (!row) return null

  if (row.state === 'starting') {
    if (teardown) await teardown(row.partyId)
    clearLease()
    return null
  }

  if (hasLiveParty && !hasLiveParty(row.partyId)) {
    if (teardown) await teardown(row.partyId)
    clearLease()
    return null
  }

  if (listSessions) {
    let liveSessions
    try {
      liveSessions = await listSessions()
    } catch {
      liveSessions = null
    }
    if (liveSessions) {
      const liveIds = new Set(liveSessions.map(entry => entry.id))
      const mismatched = row.sessions.some(entry => !liveIds.has(entry.nekoSessionId))
      if (mismatched) {
        if (teardown) await teardown(row.partyId)
        clearLease()
        return null
      }
    }
  }

  if (row.state === 'active') {
    return { partyId: row.partyId, hostName: row.hostName, state: row.state, leaseId: row.leaseId }
  }

  // cleaning or any other unexpected state left over from a crash: tear down.
  if (teardown) await teardown(row.partyId)
  clearLease()
  return null
}
