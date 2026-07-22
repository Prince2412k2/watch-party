// C11 — same-origin /neko proxy: allow-list + auth decisions.
//
// Kept dependency-injectable and framework-agnostic so the authorization
// logic (the part that matters for security) is unit-testable without a real
// HTTP server or a real upgrade socket — the actual `httpServer.on('upgrade')`
// wiring in index.js is a thin wrapper that calls `authorizeNekoUpgrade` and
// translates the verdict into a real socket write/destroy.
import { nekoConfig } from './config.js'
import { getSession as defaultGetSession, isMember as defaultIsMember } from '../session.js'
import * as defaultLease from './lease.js'

// Static assets + icons/manifest + the live-controller websocket. Allow-list
// by directory prefix, not exact hashed filenames (A0 item 8) — Neko's build
// hashes change per release.
const BOOTSTRAP_API_PATHS = new Set([
  '/neko/api/webrtc/config',
])

export function isAllowedNekoRequest(pathname, searchParams) {
  const isWs = pathname === '/neko/api/ws'
  if (searchParams) {
    // usr/pwd are the Neko-password-in-URL vector (the bundled client's own
    // auth) and are never legitimate through our proxy. `token` IS legitimate
    // on the ws endpoint only — that's our own client's scoped, revocable
    // per-user session token (server/session/auth.go getToken: cookie ->
    // Bearer -> ?token=), not the shared Neko password.
    for (const key of ['usr', 'pwd']) {
      if (searchParams.has(key)) return false
    }
    if (!isWs && searchParams.has('token')) return false
  }
  if (pathname === '/neko' || pathname === '/neko/') return true
  if (/^\/neko\/(js|css)\//.test(pathname)) return true
  if (/^\/neko\/(favicon[^/]*|apple-touch-icon[^/]*|site\.webmanifest|safari-pinned-tab\.svg)$/.test(pathname)) return true
  if (isWs) return true
  if (BOOTSTRAP_API_PATHS.has(pathname)) return true
  return false // includes /neko/metrics, /neko/api/profile, /neko/api/room/control*, legacy /neko/ws
}

function parseNekoUrl(rawUrl) {
  try {
    return new URL(rawUrl, 'http://internal')
  } catch {
    return null
  }
}

// Party-membership + active-lease check shared by the HTTP middleware and
// the WS-upgrade authorizer: the requester's session must be the party that
// currently holds the active lease.
function authorizedMember(userId, { getSession = defaultGetSession, isMember = defaultIsMember, lease = defaultLease } = {}) {
  if (!userId) return false
  const activeLease = lease.getLease()
  if (!activeLease || activeLease.state !== 'active') return false
  const sess = getSession(activeLease.partyId)
  return Boolean(sess && isMember(sess, userId))
}

// HTTP middleware chain (mounted after assertNekoEnabled-gate + requireAuth
// in index.js): membership/lease check, then the allow-list, then the real
// proxy.
export function nekoMembershipGate(deps = {}) {
  return (req, res, next) => {
    const userId = req.session?.jellyfin?.userId
    if (!authorizedMember(userId, deps)) return res.status(403).end()
    next()
  }
}

export function nekoAllowListGate(req, res, next) {
  const url = parseNekoUrl(req.originalUrl || req.url)
  if (!url || !isAllowedNekoRequest(url.pathname, url.searchParams)) return res.status(403).end()
  next()
}

// Pure decision function for the raw `httpServer.on('upgrade')` path — no
// res object exists for an upgrade, so this returns a verdict instead of
// writing anything, letting index.js's thin wrapper do the actual
// socket.write()/destroy(). Assumes `req.session` has already been populated
// by running the session middleware against the upgrade request.
export function authorizeNekoUpgrade(req, deps = {}) {
  if (!nekoConfig().enabled) return { ok: false, status: 403 }

  const userId = req.session?.jellyfin?.userId
  if (!userId) return { ok: false, status: 401 }

  if (!authorizedMember(userId, deps)) return { ok: false, status: 403 }

  const url = parseNekoUrl(req.url)
  if (!url || !isAllowedNekoRequest(url.pathname, url.searchParams)) return { ok: false, status: 403 }

  return { ok: true }
}
