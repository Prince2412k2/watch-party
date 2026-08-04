// Socket wiring for the shared browser.
//
// Input rides the existing Socket.IO connection rather than an endpoint of its
// own: that connection is already authenticated, already knows which party a
// socket belongs to, and already knows who the host is. The spike's open HTTP
// endpoint was expedient and is not what ships.
import { browserConfig } from './config.js'
import * as service from './service.js'

const EVENTS = [
  'browser:start',
  'browser:stop',
  'browser:navigate',
  'browser:input',
  'browser:requestControl',
  'browser:grantControl',
  'browser:denyControl',
  'browser:reclaimControl',
]

/**
 * Register the browser's socket events for one connection.
 *
 * With the feature off, the handlers are replaced by a single refusal. Nothing
 * is created, no container is contacted and no state is touched, so a
 * hand-crafted event gets an explicit "not available" rather than a silent
 * timeout — the feature is absent, not merely hidden behind a missing button.
 *
 * @param {import('socket.io').Socket} socket
 * @param {object} deps
 * @param {() => object | null} deps.findSession  the caller's current party
 * @param {(session: object) => void} deps.leaveCurrentActivity  stop Jellyfin playback
 */
export function registerBrowserEvents(socket, { findSession, leaveCurrentActivity }) {
  const { userId, name } = socket.user

  if (!browserConfig().enabled) {
    for (const event of EVENTS) {
      socket.on(event, (_payload, ack) => ack?.({ error: 'not available' }))
    }
    return
  }

  // Every handler resolves its own errors into an ack. An exception escaping one
  // of these would land in Socket.IO's error path and could take down the
  // connection that also carries chat and playback.
  const guard = (handler) => async (payload = {}, ack) => {
    try {
      const result = await handler(payload ?? {})
      ack?.(result ?? { ok: true })
    } catch (error) {
      console.error('browser: socket handler failed:', error?.message)
      ack?.({ error: 'The shared browser hit an error' })
    }
  }

  socket.on('browser:start', guard(async ({ url }) => {
    const session = findSession()
    if (!session) return { error: 'not in a party' }
    return service.startBrowser({
      partyId: session.id,
      userId,
      url,
      onActivityEnter: leaveCurrentActivity,
    })
  }))

  socket.on('browser:stop', guard(async () => {
    const session = findSession()
    if (!session) return { error: 'not in a party' }
    return service.stopBrowser({ partyId: session.id, userId })
  }))

  socket.on('browser:navigate', guard(async ({ url }) => {
    const session = findSession()
    if (!session) return { error: 'not in a party' }
    return service.navigateBrowser({ partyId: session.id, userId, url })
  }))

  socket.on('browser:input', guard(async ({ events }) => {
    const session = findSession()
    if (!session) return { error: 'not in a party' }
    return service.forwardInput({ partyId: session.id, userId, events })
  }))

  socket.on('browser:requestControl', guard(async () => {
    const session = findSession()
    if (!session) return { error: 'not in a party' }
    return service.requestControl({ partyId: session.id, userId, name })
  }))

  socket.on('browser:grantControl', guard(async ({ userId: targetUserId }) => {
    const session = findSession()
    if (!session) return { error: 'not in a party' }
    return service.grantControl({ partyId: session.id, hostUserId: userId, targetUserId })
  }))

  socket.on('browser:denyControl', guard(async ({ userId: targetUserId }) => {
    const session = findSession()
    if (!session) return { error: 'not in a party' }
    return service.denyControl({ partyId: session.id, hostUserId: userId, targetUserId })
  }))

  socket.on('browser:reclaimControl', guard(async () => {
    const session = findSession()
    if (!session) return { error: 'not in a party' }
    return service.reclaimControl({ partyId: session.id, hostUserId: userId })
  }))
}
