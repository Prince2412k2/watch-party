// Per-member Neko detachment (finding #2 of the neko-collab-browser plan).
//
// Distinct from teardownBrowser (teardown.js): this severs ONE departing
// user's Neko session(s) without touching the party's browser lease — used
// when a member leaves/disconnects/is kicked while the browser stays live
// for everyone else.
//
// Transactional order to avoid orphans: controller status is read BEFORE any
// mapping is dropped (so a failed delete still lets us know whether to reset
// control), and a mapping is only dropped after its Neko delete succeeds (or
// 404s, meaning it's already gone). A failed delete leaves the mapping
// recorded so a later detach/teardown can retry it.
import * as defaultAdmin from './admin.js'
import * as defaultLease from './lease.js'
import * as defaultController from './controller.js'

function isNotFound(error) {
  return /\b404\b/.test(error?.message || '')
}

export async function detachMember(partyId, userId, { deps: overrides = {} } = {}) {
  const deps = {
    admin: overrides.admin || defaultAdmin,
    lease: overrides.lease || defaultLease,
    controller: overrides.controller || defaultController,
    broadcast: overrides.broadcast,
  }

  const lease = deps.lease.getLease()
  if (!lease || lease.partyId !== partyId || lease.state !== 'active') return

  // (1) Controller status FIRST — the mapping used to resolve it must still
  // be intact when we ask.
  const wasController = await deps.controller.isController(partyId, userId)

  // (2) Read (not drop) this user's mapped Neko sessions for this lease.
  const sessions = deps.lease.sessionsForUser(partyId, userId)
  if (sessions.length === 0 && !wasController) return

  // (3) Delete each mapped session; only drop the mapping once Neko confirms
  // it's gone (success or 404). A genuine failure leaves it for retry.
  for (const { nekoSessionId } of sessions) {
    try {
      await deps.admin.deleteSession(nekoSessionId)
      deps.lease.removeUserSession(partyId, userId, nekoSessionId)
    } catch (error) {
      if (isNotFound(error)) {
        deps.lease.removeUserSession(partyId, userId, nekoSessionId)
      }
      // else: leave the mapping recorded for retry — no orphan-drop.
    }
  }

  // (4) If they held control, release it at Neko and tell the room.
  if (wasController) {
    await deps.admin.resetControl()
    if (deps.broadcast) deps.broadcast({ controllerUserId: null })
  }
}
