// ── Native-desktop stream endpoint — see docs/native/PLAN.md §4.3 ──────────
// The Tauri app (mpv + the multi-part downloader) runs OUTSIDE the browser's
// cookie jar, so it can't hit the normal session-authenticated routes. This
// hands out a short-lived signed URL instead: `stream-url` requires the normal
// session (proves "this user is logged in right now"), then mints an HMAC
// token binding {itemId, purpose, exp}. `file` validates that token and proxies
// the ORIGINAL Jellyfin file (no transcode) with Range passthrough, using the
// server-held per-user Jellyfin token captured at mint time — never the
// client's session cookie.
//
// STATUS: contract + signing/verification are real; the actual Jellyfin
// byte-range proxy (marked TODO below) is implemented by agent N3 per the
// native redesign plan. Phase-0 ships this stubbed so N4 (MpvBackend) and N6
// (offline UI) have a real endpoint shape to build against.
import crypto from 'crypto'
import { requireAuth, getJellyfin } from './auth.js'

const SECRET = process.env.NATIVE_STREAM_SECRET

// TTLs per §0.5 / §4.3: playback tokens are short-lived (rotated as the app
// keeps watching); download tokens are long enough to cover a full-file grab,
// and the downloader re-mints via `stream-url` on a 401/403 if one still expires.
const TTL_MS = { stream: 6 * 60 * 60 * 1000, download: 48 * 60 * 60 * 1000 }

function sign(payload) {
  const body = JSON.stringify(payload)
  const b64 = Buffer.from(body).toString('base64url')
  const mac = crypto.createHmac('sha256', SECRET).update(b64).digest('base64url')
  return `${b64}.${mac}`
}

function verify(token) {
  if (typeof token !== 'string' || !token.includes('.')) return null
  const [b64, mac] = token.split('.')
  const expected = crypto.createHmac('sha256', SECRET).update(b64).digest('base64url')
  // timing-safe compare
  const a = Buffer.from(mac)
  const b = Buffer.from(expected)
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null
  const payload = JSON.parse(Buffer.from(b64, 'base64url').toString('utf8'))
  if (typeof payload.exp !== 'number' || Date.now() > payload.exp) return null
  return payload
}

export function registerNativeRoutes(app) {
  if (!SECRET) {
    // Fail closed, not open: the whole feature is unavailable rather than
    // silently unsigned. Native builds without this env var simply can't
    // stream/download — everything else in the app is unaffected.
    app.get('/api/library/native/stream-url/:itemId', (_req, res) =>
      res.status(501).json({ error: 'NATIVE_STREAM_SECRET not configured' }))
    app.get('/api/library/native/file', (_req, res) =>
      res.status(501).json({ error: 'NATIVE_STREAM_SECRET not configured' }))
    return
  }

  // Requires the normal session — this is the ONE place a cookie is checked.
  // Everything downstream (the `file` route) trusts the signed token instead.
  app.get('/api/library/native/stream-url/:itemId', requireAuth, (req, res) => {
    const { itemId } = req.params
    const purpose = req.query.purpose === 'download' ? 'download' : 'stream'
    const { baseUrl, token: jellyfinToken, userId } = getJellyfin(req)
    const exp = Date.now() + TTL_MS[purpose]
    const token = sign({ itemId, purpose, userId, jellyfinToken, baseUrl, exp })
    const url = `${req.protocol}://${req.get('host')}/api/library/native/file?token=${encodeURIComponent(token)}`
    res.json({ url, expiresAt: exp })
  })

  // No requireAuth here on purpose — the signed token IS the auth. mpv and the
  // Rust downloader call this directly, outside the browser's cookie jar.
  app.get('/api/library/native/file', async (req, res) => {
    const payload = verify(req.query.token)
    if (!payload) return res.status(401).json({ error: 'invalid or expired token' })

    // TODO (agent N3): proxy Jellyfin's original/static stream for
    // payload.itemId using payload.jellyfinToken against payload.baseUrl,
    // e.g. `${baseUrl}/Videos/${itemId}/stream?static=true&api_key=${jellyfinToken}`,
    // passing through the client's `Range` header and the upstream response's
    // status/`Content-Range`/`Content-Length`/`Accept-Ranges`/`Content-Type`
    // verbatim (206 on a ranged request), so multiple concurrent Range GETs
    // for the same token (the multi-part downloader) all work independently.
    res.status(501).json({ error: 'native file proxy not implemented yet (agent N3)', itemId: payload.itemId })
  })
}
