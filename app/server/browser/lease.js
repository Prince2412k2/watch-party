// Who currently holds the shared browser.
//
// There is exactly one browser for the whole deployment (the measured cost is 4
// of 8 shared vCPUs, which does not permit a second container), so this is one
// persisted row rather than per-party state. Adapted from the unmerged
// feature/neko-collab-browser branch, minus everything that was about Neko's own
// session API.
//
// The state machine exists so a crash cannot leave the browser permanently
// "busy":
//
//   (none) --acquire--> starting --markActive--> active
//                          |                       |
//                          +-----beginCleaning-----+
//                                     |
//                                   release --> (none)
//
// A lease found in `starting` or `cleaning` at startup is the fingerprint of a
// crash mid-transition and is always torn down (see reconcile).
import { randomUUID } from 'node:crypto'
import { clearLease, loadLease, saveLease } from '../party-store.js'

export function acquireLease(partyId) {
  const existing = loadLease()
  // Refused without naming the occupant: telling a stranger which party is using
  // the browser would tell them who is watching together.
  if (existing) return { ok: false, error: 'busy' }
  const leaseId = randomUUID()
  saveLease({ partyId, leaseId, state: 'starting', acquiredAt: Date.now() })
  return { ok: true, leaseId }
}

export function markActive(partyId) {
  const lease = loadLease()
  if (!lease || lease.partyId !== partyId || lease.state !== 'starting') return false
  saveLease({ ...lease, state: 'active' })
  return true
}

export function beginCleaning(partyId) {
  const lease = loadLease()
  if (!lease || lease.partyId !== partyId) return false
  if (lease.state === 'cleaning') return true
  saveLease({ ...lease, state: 'cleaning' })
  return true
}

export function releaseLease(partyId) {
  const lease = loadLease()
  if (!lease || lease.partyId !== partyId) return false
  clearLease()
  return true
}

// Unconditional — for reconciliation and for a teardown that must not be blocked
// by whatever odd state the lease is in.
export function forceClear() {
  clearLease()
}

export function getLease() {
  return loadLease()
}

export function holderOf() {
  return loadLease()?.partyId ?? null
}

export function isHeldBy(partyId) {
  const lease = loadLease()
  return Boolean(lease && lease.partyId === partyId)
}

/**
 * Bring the lease back in line with reality at startup.
 *
 * Three ways a stored lease can be wrong after a restart: the party it names is
 * gone, the container is not actually running a session, or the lease was caught
 * mid-transition. All three resolve to "tear down and clear" — the browser is
 * cheap to start again and a stuck lease locks the feature for everyone.
 *
 * @param {object} deps
 * @param {(partyId: string) => boolean} deps.partyExists
 * @param {() => Promise<{ ok: boolean, body?: { running?: boolean } }>} deps.agentStatus
 * @param {(reason: string) => Promise<unknown>} deps.stopSession
 * @returns {Promise<{ partyId: string } | null>} the surviving lease, if any
 */
export async function reconcile({ partyExists, agentStatus, stopSession }) {
  const lease = loadLease()
  const remote = await agentStatus()

  if (!lease) {
    // No lease but a live session means an orphan — a restart that lost the row,
    // or a lease cleared while the stop was in flight. Reclaim the container.
    if (remote.ok && remote.body?.running) await stopSession('orphan')
    return null
  }

  const salvageable = lease.state === 'active'
    && partyExists(lease.partyId)
    && remote.ok
    && remote.body?.running === true

  if (!salvageable) {
    await stopSession('reconcile')
    clearLease()
    return null
  }
  return { partyId: lease.partyId, leaseId: lease.leaseId }
}
