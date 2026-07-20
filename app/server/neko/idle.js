// Process-level idle monitor (finding #10 of the neko-collab-browser plan).
//
// ONE loop for the whole process — not per-party — because there is at most
// one active browser lease at a time (single-global-instance). Started once
// at server startup (after reconciliation) and kept running for whichever
// lease happens to be active, including one restored by reconciliation.
import * as defaultAdmin from './admin.js'
import * as defaultLease from './lease.js'
import { teardownBrowser as defaultTeardownBrowser } from './teardown.js'
import { nekoConfig } from './config.js'

export function startIdleMonitor({ intervalMs = 5_000, now = Date.now, deps: overrides = {} } = {}) {
  const deps = {
    admin: overrides.admin || defaultAdmin,
    lease: overrides.lease || defaultLease,
    teardownBrowser: overrides.teardownBrowser || defaultTeardownBrowser,
    idleTimeoutMs: overrides.idleTimeoutMs ?? nekoConfig().idleTimeoutMs,
  }

  let lastLeaseId = null
  let idleSince = null
  let tearingDown = false

  async function tick() {
    if (tearingDown) return

    const lease = deps.lease.getLease()
    if (!lease || lease.state !== 'active') {
      lastLeaseId = null
      idleSince = null
      return
    }

    if (lease.leaseId !== lastLeaseId) {
      lastLeaseId = lease.leaseId
      idleSince = null
    }

    const recorded = new Set(deps.lease.sessionsFor(lease.partyId).map(entry => entry.nekoSessionId))

    let liveSessions
    try {
      liveSessions = await deps.admin.listSessions()
    } catch (error) {
      console.warn(`neko idle monitor: listSessions failed, skipping tick: ${error.message}`)
      return // never count a listSessions failure as idle
    }

    const viewerCount = liveSessions.filter(
      session => recorded.has(session.id) && (session.isConnected || session.isWatching)
    ).length

    if (viewerCount > 0) {
      idleSince = null
      return
    }

    const nowMs = now()
    if (idleSince === null) {
      idleSince = nowMs
      return
    }

    if (nowMs - idleSince >= deps.idleTimeoutMs) {
      tearingDown = true
      try {
        await deps.teardownBrowser(lease.partyId, { reason: 'idle' })
      } finally {
        idleSince = null
        lastLeaseId = null
        tearingDown = false
      }
    }
  }

  const timer = setInterval(() => {
    tick().catch(error => console.error('neko idle monitor: tick failed', error))
  }, intervalMs)
  if (timer.unref) timer.unref()

  return { timer, tick }
}

export function stopIdleMonitor(handle) {
  if (handle?.timer) clearInterval(handle.timer)
}
