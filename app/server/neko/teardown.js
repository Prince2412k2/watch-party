import * as defaultAdmin from './admin.js'
import * as defaultContainer from './container.js'
import * as defaultLease from './lease.js'
import { getSession as defaultGetSession, setBrowserActivity as defaultSetBrowserActivity, persistSession as defaultPersistSession } from '../session.js'

const inFlight = new Map() // partyId → Promise

const MAX_RETRIES = 3

async function retry(fn) {
  let lastError
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      return await fn()
    } catch (error) {
      lastError = error
      if (attempt === MAX_RETRIES) throw lastError
    }
  }
  throw lastError
}

async function deleteSessions(partyId, deps) {
  const sessions = deps.lease.sessionsFor(partyId)
  for (const { userId, nekoSessionId } of sessions) {
    try {
      await deps.admin.deleteSession(nekoSessionId)
    } catch (error) {
      // 404/other delete failures are logged and ignored — the container
      // recreate below wipes the Neko state regardless.
      console.warn(`neko teardown: failed to delete session ${nekoSessionId} for user ${userId}: ${error.message}`)
    }
    deps.lease.removeUserSession(partyId, userId, nekoSessionId)
  }
}

async function runTeardown(partyId, reason, deps) {
  deps.lease.beginCleaning(partyId)

  await retry(() => deleteSessions(partyId, deps))
  await retry(() => deps.admin.resetControl())
  await retry(async () => {
    await deps.container.recreateContainer()
    await deps.container.waitForHealthy()
  })

  const session = deps.getSession(partyId)
  if (session) {
    deps.setBrowserActivity(session, false)
    session.stage = 'lobby'
    deps.persistSession(session)
  }

  if (deps.emitState) {
    await deps.emitState(partyId, session)
  }

  deps.lease.releaseLease(partyId)
}

export async function teardownBrowser(partyId, { reason = 'unknown', deps: overrides = {} } = {}) {
  if (inFlight.has(partyId)) return inFlight.get(partyId)

  const deps = {
    admin: overrides.admin || defaultAdmin,
    container: overrides.container || defaultContainer,
    lease: overrides.lease || defaultLease,
    getSession: overrides.getSession || defaultGetSession,
    setBrowserActivity: overrides.setBrowserActivity || defaultSetBrowserActivity,
    persistSession: overrides.persistSession || defaultPersistSession,
    emitState: overrides.emitState,
  }

  const current = deps.lease.getLease()
  if (!current || current.partyId !== partyId) return

  const promise = runTeardown(partyId, reason, deps).finally(() => {
    inFlight.delete(partyId)
  })
  inFlight.set(partyId, promise)
  return promise
}
