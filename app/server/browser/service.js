// The shared browser, from the server's point of view.
//
// This module owns the lifecycle (who holds the browser, when it starts, when it
// is destroyed) and the control lease (who may drive it). The container agent
// owns the processes; app/server owns the policy — the agent trusts whatever it
// is told, so every authorisation decision has to be made here.
//
// Fault-isolation rule for the whole file: nothing here may throw into a caller.
// The socket handlers that call it are the same handlers that carry chat, joins
// and playback, and a browser that cannot start must cost a party nothing but an
// error message on one surface.
import { AccessToken } from 'livekit-server-sdk'
import * as agent from './agent.js'
import * as lease from './lease.js'
import { browserConfig } from './config.js'
import {
  clearBrowserActivity, effectiveName, getSession, isHost, isMember, publicSession,
  setBrowserActivity, updateBrowserActivity,
} from '../session.js'

let io = null
let monitorTimer = null
const teardownsInFlight = new Map()   // partyId → Promise

export function initBrowserService(server) {
  io = server
}

function broadcast(session) {
  if (!io || !session) return
  try {
    io.to(session.id).emit('party:state', publicSession(session))
  } catch (error) {
    // A broadcast failure must not abort a lifecycle transition.
    console.warn('browser: broadcast failed:', error.message)
  }
}

function notifyError(session, message) {
  if (!io || !session) return
  try {
    io.to(session.id).emit('browser:error', { message })
  } catch { /* see broadcast */ }
}

export function browserAvailable() {
  return browserConfig().enabled
}

// ── tokens ──────────────────────────────────────────────────────────────────

/**
 * A publish-only token for the container.
 *
 * canSubscribe is false deliberately: the browser must not be able to receive
 * the party's cameras and microphones. It is a screen being shown to the room,
 * not a member of it — and a browser that could subscribe would be a way to
 * exfiltrate a party's own video to whatever page it was pointed at.
 */
async function mintPublisherToken(partyId) {
  const config = browserConfig()
  const token = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, {
    identity: config.identity,
    name: 'Shared browser',
    // A session lives minutes, not hours; a short TTL bounds the damage if the
    // token ever leaks out of the container.
    ttl: '4h',
  })
  token.addGrant({
    roomJoin: true,
    room: partyId,
    canPublish: true,
    canSubscribe: false,
    canPublishData: false,
  })
  return token.toJwt()
}

// ── lifecycle ───────────────────────────────────────────────────────────────

/**
 * Start the shared browser for a party.
 *
 * Returns as soon as the container has accepted the request; the stream is not
 * up yet. A background waiter flips the party to 'active' once the publisher
 * reports a live track, so clients render "starting…" instead of a black frame
 * they cannot explain.
 */
export async function startBrowser({ partyId, userId, url, onActivityEnter }) {
  const config = browserConfig()
  if (!config.enabled) return { error: 'The shared browser is not available on this server' }

  const session = getSession(partyId)
  if (!session) return { error: 'party not found' }
  if (!isHost(session, userId)) return { error: 'not host' }

  if (lease.isHeldBy(partyId) && session.browser) return { ok: true, alreadyRunning: true }

  const acquired = lease.acquireLease(partyId)
  if (!acquired.ok) {
    // Says only that it is in use. Naming the occupying party — or its host —
    // would tell a stranger who is watching together.
    return { error: 'The shared browser is in use right now. Try again in a few minutes.' }
  }

  // Only now that the browser is genuinely ours does the party leave its current
  // activity — a refused start must not have stopped anybody's movie.
  if (onActivityEnter) {
    try {
      onActivityEnter(session)
    } catch (error) {
      console.error('browser: leaving the previous activity failed:', error?.message)
    }
  }

  const target = normalizeUrl(url) || config.homeUrl
  setBrowserActivity(session, {
    state: 'starting',
    url: target,
    driverUserId: userId,      // the host drives by default
    requests: [],
    error: null,
    // Present from the very first broadcast. A client needs this to map a click
    // onto the remote screen, and one that never receives it cannot drive at all
    // — so it is never left to a later code path to fill in.
    screen: config.screen,
  })
  broadcast(session)

  let token
  try {
    token = await mintPublisherToken(partyId)
  } catch (error) {
    console.error('browser: could not mint publisher token:', error.message)
    await teardownBrowser(partyId, 'token-failed')
    return { error: 'Could not start the shared browser' }
  }

  const started = await agent.startSession({
    url: target,
    token,
    lkUrl: process.env.LIVEKIT_URL || 'ws://livekit:7880',
    kbps: config.maxBitrateKbps,
    fps: config.fps,
  })

  if (!started.ok) {
    console.warn(`browser: agent refused start (${started.error})`)
    await teardownBrowser(partyId, `start-failed:${started.error}`)
    return {
      error: started.status === 0
        ? 'The shared browser is not running on this server'
        : 'Could not start the shared browser',
    }
  }

  lease.markActive(partyId)
  void waitForStream(partyId).catch(error => {
    // Belt and braces — waitForStream already swallows its own failures.
    console.error('browser: waitForStream escaped:', error?.message)
  })
  startMonitor()
  return { ok: true }
}

async function waitForStream(partyId) {
  const config = browserConfig()
  const deadline = Date.now() + config.startTimeoutMs
  while (Date.now() < deadline) {
    await sleep(400)
    if (!lease.isHeldBy(partyId)) return          // stopped while we waited
    const remote = await agent.status()
    if (!remote.ok) continue                      // a blip is not a failure yet
    const body = remote.body ?? {}
    if (body.publishing) {
      const session = getSession(partyId)
      if (!session?.browser) return
      // Refine the screen size with what the container actually came up at — the
      // configured value is a good default but the agent is the authority. Only
      // ever narrowed, never cleared: clients depend on this being set.
      const screen = (Number.isFinite(body.screen?.w) && Number.isFinite(body.screen?.h))
        ? { w: body.screen.w, h: body.screen.h }
        : null
      updateBrowserActivity(session, { state: 'active', error: null, ...(screen ? { screen } : {}) })
      broadcast(session)
      return
    }
    if (body.lastError || body.exited) {
      await failBrowser(partyId, body.lastError || 'The shared browser stopped unexpectedly')
      return
    }
  }
  await failBrowser(partyId, 'The shared browser took too long to start')
}

/**
 * Report a failure on the browser surface and return the party to the lobby.
 *
 * The party itself is untouched: cameras, chat, joins and Jellyfin all keep
 * working, and the host can start playback immediately afterwards.
 */
async function failBrowser(partyId, message) {
  const session = getSession(partyId)
  if (session?.browser) {
    updateBrowserActivity(session, { state: 'error', error: message })
    broadcast(session)
    notifyError(session, message)
  }
  await teardownBrowser(partyId, 'failed')
  const after = getSession(partyId)
  if (after) broadcast(after)
}

/**
 * Destroy the browser session held by a party.
 *
 * Idempotent, concurrency-safe, and it never rejects: teardown sits on the path
 * of a party ending, and a container that will not answer must not be able to
 * stop a party from ending.
 */
export function teardownBrowser(partyId, reason = 'stop') {
  if (!partyId) return Promise.resolve()
  const existing = teardownsInFlight.get(partyId)
  if (existing) return existing

  const run = (async () => {
    try {
      const held = lease.isHeldBy(partyId)
      if (held) lease.beginCleaning(partyId)

      if (held) {
        const stopped = await agent.stopSession(reason)
        if (!stopped.ok) {
          // Recorded for the operator, then ignored. The container's profile
          // lives on a tmpfs and the agent kills orphans on the next start, so a
          // failed stop is a cleanup problem, not a correctness one.
          console.error(`browser: agent stop failed for ${partyId} (${stopped.error}) — releasing the lease anyway`)
        }
      }

      const session = getSession(partyId)
      if (session?.browser) {
        clearBrowserActivity(session)
        broadcast(session)
      }
      // forceClear, not releaseLease: a lease stuck in an unexpected state must
      // never keep the feature locked for every other party.
      if (held) lease.forceClear()
    } catch (error) {
      console.error('browser: teardown error:', error?.message)
      try { lease.forceClear() } catch { /* nothing left to try */ }
    } finally {
      teardownsInFlight.delete(partyId)
      stopMonitorIfIdle()
    }
  })()

  teardownsInFlight.set(partyId, run)
  return run
}

/** Host explicitly closed the browser. */
export async function stopBrowser({ partyId, userId }) {
  const session = getSession(partyId)
  if (!session) return { error: 'party not found' }
  if (!isHost(session, userId)) return { error: 'not host' }
  await teardownBrowser(partyId, 'host-stopped')
  return { ok: true }
}

// ── control lease ───────────────────────────────────────────────────────────

function activeBrowserSession(partyId) {
  const session = getSession(partyId)
  if (!session?.browser) return null
  if (!lease.isHeldBy(partyId)) return null
  return session
}

export function isDriver(session, userId) {
  return Boolean(session?.browser && session.browser.driverUserId === userId)
}

/** Guest asks for the pointer; the host decides. */
export function requestControl({ partyId, userId, name }) {
  const session = activeBrowserSession(partyId)
  if (!session) return { error: 'the shared browser is not running' }
  if (!isMember(session, userId)) return { error: 'not a party member' }
  if (isDriver(session, userId)) return { ok: true }

  const requests = session.browser.requests ?? []
  if (!requests.some(request => request.userId === userId)) {
    updateBrowserActivity(session, { requests: [...requests, { userId, name }] })
  }
  broadcast(session)
  if (io) {
    // A direct nudge as well as the state broadcast: the host may be watching the
    // stream full-screen with no room for a list they have to notice changing.
    // effectiveName so the host sees the display name this person chose, matching
    // every other named broadcast (user:left, chat:message) — the stored request
    // above needs no such treatment, since publicMember resolves it on the way out.
    io.to(session.hostSocketId).emit('browser:controlRequested', {
      userId,
      name: effectiveName(userId, name),
    })
  }
  return { ok: true }
}

export function grantControl({ partyId, hostUserId, targetUserId }) {
  const session = activeBrowserSession(partyId)
  if (!session) return { error: 'the shared browser is not running' }
  if (!isHost(session, hostUserId)) return { error: 'not host' }
  if (!isMember(session, targetUserId)) return { error: 'not a party member' }

  updateBrowserActivity(session, {
    driverUserId: targetUserId,
    requests: (session.browser.requests ?? []).filter(request => request.userId !== targetUserId),
  })
  broadcast(session)
  return { ok: true }
}

export function denyControl({ partyId, hostUserId, targetUserId }) {
  const session = activeBrowserSession(partyId)
  if (!session) return { error: 'the shared browser is not running' }
  if (!isHost(session, hostUserId)) return { error: 'not host' }

  const requests = (session.browser.requests ?? []).filter(request => request.userId !== targetUserId)
  updateBrowserActivity(session, { requests })
  broadcast(session)
  if (io) {
    const guest = session.guests.find(candidate => candidate.userId === targetUserId)
    if (guest?.socketId) io.to(guest.socketId).emit('browser:controlDenied', {})
  }
  return { ok: true }
}

/** Host takes the pointer back. Always allowed, at any time. */
export function reclaimControl({ partyId, hostUserId }) {
  const session = activeBrowserSession(partyId)
  if (!session) return { error: 'the shared browser is not running' }
  if (!isHost(session, hostUserId)) return { error: 'not host' }
  updateBrowserActivity(session, { driverUserId: hostUserId })
  broadcast(session)
  return { ok: true }
}

/**
 * A member left, disconnected or was kicked.
 *
 * Control must never be stranded with someone who is gone, so it falls back to
 * the host — who is, by definition, still there or being replaced.
 */
export function handleMemberGone(partyId, userId) {
  const session = getSession(partyId)
  if (!session?.browser) return
  const requests = (session.browser.requests ?? []).filter(request => request.userId !== userId)
  const strandedDriver = session.browser.driverUserId === userId
  if (!strandedDriver && requests.length === (session.browser.requests ?? []).length) return
  updateBrowserActivity(session, {
    requests,
    ...(strandedDriver ? { driverUserId: session.hostId } : {}),
  })
  broadcast(session)
}

/** The host changed (transfer, or promotion after a disconnect). */
export function handleHostChanged(partyId, newHostId, previousHostId) {
  const session = getSession(partyId)
  if (!session?.browser) return
  if (session.browser.driverUserId !== previousHostId) return
  updateBrowserActivity(session, { driverUserId: newHostId })
  broadcast(session)
}

// ── driving ─────────────────────────────────────────────────────────────────

/**
 * Forward input to the container.
 *
 * The driver check happens here, on the server, because that is the only place a
 * client cannot bypass: a non-driver who hand-crafts the socket event still gets
 * nothing through, and the container will accept anything app/server sends it.
 */
export async function forwardInput({ partyId, userId, events }) {
  const session = activeBrowserSession(partyId)
  if (!session) return { error: 'the shared browser is not running' }
  if (!isDriver(session, userId)) return { error: 'not driving' }
  if (session.browser.state !== 'active') return { error: 'the shared browser is still starting' }
  if (!Array.isArray(events) || events.length === 0) return { error: 'no events' }

  const clean = sanitizeEvents(events)
  if (clean.length === 0) return { error: 'no usable events' }

  // focus on the first batch of a session: the window may not have been mapped
  // when the browser started, and focusing nothing succeeds silently, leaving
  // every later keystroke going nowhere.
  const needsFocus = !session.browser.focused
  const result = await agent.sendInput(clean, { focus: needsFocus })
  if (needsFocus && result.ok) updateBrowserActivity(session, { focused: true })
  if (!result.ok) return { error: 'the shared browser is not responding' }
  return { ok: true }
}

export async function navigateBrowser({ partyId, userId, url }) {
  const session = activeBrowserSession(partyId)
  if (!session) return { error: 'the shared browser is not running' }
  if (!isDriver(session, userId)) return { error: 'not driving' }
  const target = normalizeUrl(url)
  if (!target) return { error: 'invalid url' }
  const result = await agent.navigate(target)
  if (!result.ok) return { error: 'the shared browser is not responding' }
  updateBrowserActivity(session, { url: target })
  broadcast(session)
  return { ok: true }
}

// ── health monitor ──────────────────────────────────────────────────────────

/**
 * Watch the container while a party is using it.
 *
 * The browser can die without anyone asking it to — a crash, an OOM kill, the
 * driver closing the last tab — and the party has to be told rather than left
 * staring at a frozen frame.
 */
export function startMonitor({ intervalMs = 4_000 } = {}) {
  if (monitorTimer) return monitorTimer
  monitorTimer = setInterval(() => {
    void tick().catch(error => console.error('browser: monitor tick failed:', error?.message))
  }, intervalMs)
  if (monitorTimer.unref) monitorTimer.unref()
  return monitorTimer
}

export function stopMonitor() {
  if (monitorTimer) clearInterval(monitorTimer)
  monitorTimer = null
}

function stopMonitorIfIdle() {
  if (!lease.getLease()) stopMonitor()
}

export async function tick() {
  const current = lease.getLease()
  if (!current) {
    stopMonitor()
    return
  }
  if (current.state !== 'active') return          // a start or a teardown is mid-flight

  const session = getSession(current.partyId)
  if (!session) {
    // The party is gone and never told us — a crash between deleteSession and
    // teardown. Reclaim the browser.
    await teardownBrowser(current.partyId, 'party-gone')
    return
  }

  const remote = await agent.status()
  if (!remote.ok) {
    // One failed poll is a blip; treat a run of them as a dead container.
    session._browserMisses = (session._browserMisses ?? 0) + 1
    if (session._browserMisses >= 3) {
      session._browserMisses = 0
      await failBrowser(current.partyId, 'Lost contact with the shared browser')
    }
    return
  }
  session._browserMisses = 0

  const body = remote.body ?? {}
  if (!body.running) {
    await failBrowser(current.partyId, 'The shared browser closed unexpectedly')
  }
}

/** Bring stored state in line with the container at startup. */
export async function reconcileBrowser({ partyExists }) {
  if (!browserConfig().enabled) {
    // The feature was turned off while a lease was held. Release it, and let any
    // party that was on the browser activity fall back to the lobby (runtimeState
    // has already done that for the restored sessions).
    const stale = lease.getLease()
    if (stale) {
      lease.forceClear()
      console.log('browser: feature disabled — cleared a stale lease')
    }
    return null
  }
  try {
    const survivor = await lease.reconcile({
      partyExists,
      agentStatus: () => agent.status(),
      stopSession: reason => agent.stopSession(reason),
    })
    if (!survivor) return null
    const session = getSession(survivor.partyId)
    if (session?.browser) {
      updateBrowserActivity(session, { driverUserId: session.hostId, requests: [], focused: false })
    }
    startMonitor()
    return survivor
  } catch (error) {
    console.error('browser: reconcile failed:', error?.message)
    return null
  }
}

// ── input validation ────────────────────────────────────────────────────────

// Modifiers then exactly one keysym. Four is the cap because there are four
// modifier keys — and it has to match the agent's own pattern, or an event would
// pass validation here and be silently dropped one layer down.
const KEY_PATTERN = /^(?:(?:ctrl|alt|shift|super)\+){0,4}[A-Za-z0-9_]{1,20}$/
const MAX_EVENTS = 64
const MAX_TEXT = 256

/**
 * Reduce a client's batch to events the agent will accept.
 *
 * The agent validates too — but it trusts app/server, so this is the layer that
 * has to assume the batch came from a hostile client.
 */
export function sanitizeEvents(events) {
  const clean = []
  for (const event of events.slice(0, MAX_EVENTS)) {
    if (!event || typeof event !== 'object') continue
    const type = event.type
    if (type === 'move' || type === 'down' || type === 'up' || type === 'click') {
      if (!Number.isFinite(event.x) || !Number.isFinite(event.y)) continue
      const button = Number.isInteger(event.button) ? Math.min(5, Math.max(1, event.button)) : 1
      clean.push({ type, x: Math.round(event.x), y: Math.round(event.y), button })
    } else if (type === 'scroll') {
      if (!Number.isFinite(event.dy)) continue
      clean.push({ type, dy: Math.max(-2000, Math.min(2000, event.dy)) })
    } else if (type === 'key') {
      if (typeof event.key !== 'string' || !KEY_PATTERN.test(event.key)) continue
      clean.push({ type, key: event.key })
    } else if (type === 'text') {
      if (typeof event.text !== 'string' || event.text.length === 0) continue
      clean.push({ type, text: event.text.slice(0, MAX_TEXT) })
    }
  }
  return clean
}

/** http(s) only, and never longer than a real URL. */
export function normalizeUrl(value) {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (!trimmed || trimmed.length > 2048) return null
  const candidate = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(trimmed) ? trimmed : `https://${trimmed}`
  let parsed
  try {
    parsed = new URL(candidate)
  } catch {
    return null
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return null
  if (!parsed.hostname) return null
  return parsed.toString()
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}
