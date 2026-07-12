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
// STATUS: contract, signing/verification, AND the Jellyfin byte-range proxy
// are all real (agent N3). Streams straight through without buffering so many
// concurrent Range requests against the same token (the multi-part
// downloader) each get their own independent upstream connection.
import crypto from 'crypto'
import { Readable } from 'stream'
import { requireAuth, getJellyfin } from './auth.js'

// TTLs per §0.5 / §4.3: playback tokens are short-lived (rotated as the app
// keeps watching); download tokens are long enough to cover a full-file grab,
// and the downloader re-mints via `stream-url` on a 401/403 if one still expires.
const TTL_MS = { stream: 6 * 60 * 60 * 1000, download: 48 * 60 * 60 * 1000 }

function sign(payload, secret) {
  const body = JSON.stringify(payload)
  const b64 = Buffer.from(body).toString('base64url')
  const mac = crypto.createHmac('sha256', secret).update(b64).digest('base64url')
  return `${b64}.${mac}`
}

function verify(token, secret) {
  if (typeof token !== 'string' || !token.includes('.')) return null
  const [b64, mac] = token.split('.')
  const expected = crypto.createHmac('sha256', secret).update(b64).digest('base64url')
  // timing-safe compare
  const a = Buffer.from(mac)
  const b = Buffer.from(expected)
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null
  const payload = JSON.parse(Buffer.from(b64, 'base64url').toString('utf8'))
  if (typeof payload.exp !== 'number' || Date.now() > payload.exp) return null
  return payload
}

// Headers we pass straight through from Jellyfin's response to the client,
// verbatim, whether it's a 200 (full body) or a 206 (ranged).
const PASSTHROUGH_HEADERS = ['content-type', 'content-length', 'content-range', 'accept-ranges']

export function registerNativeRoutes(app) {
  // Read at registration time. This supports local `.env` loading in index.js,
  // whose assignments run after ESM dependencies have been evaluated.
  const secret = process.env.NATIVE_STREAM_SECRET
  if (!secret) {
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
    const token = sign({ itemId, purpose, userId, jellyfinToken, baseUrl, exp }, secret)
    const url = `${req.protocol}://${req.get('host')}/api/library/native/file?token=${encodeURIComponent(token)}`
    res.json({ url, expiresAt: exp })
  })

  // No requireAuth here on purpose — the signed token IS the auth. mpv and the
  // Rust downloader call this directly, outside the browser's cookie jar.
  // Each call opens its own independent upstream fetch, so N concurrent Range
  // requests for the same token (the multi-part downloader) proxy to N
  // independent Jellyfin connections — nothing here is shared/serialized.
  app.get('/api/library/native/file', async (req, res) => {
    const payload = verify(req.query.token, secret)
    if (!payload) return res.status(401).json({ error: 'invalid or expired token' })

    const { itemId, jellyfinToken, baseUrl } = payload
    const target = `${baseUrl}/Videos/${encodeURIComponent(itemId)}/stream?static=true&mediaSourceId=${encodeURIComponent(itemId)}&api_key=${encodeURIComponent(jellyfinToken)}`

    try {
      const upstream = await fetch(target, {
        headers: req.headers.range ? { Range: req.headers.range } : {},
      })

      if (!upstream.ok && upstream.status !== 206) {
        res.status(upstream.status).end()
        return
      }

      res.status(upstream.status)
      for (const h of PASSTHROUGH_HEADERS) {
        const val = upstream.headers.get(h)
        if (val) res.set(h, val)
      }
      if (!res.get('content-type')) res.set('Content-Type', 'video/mp4')

      // Stream straight through — never buffer the whole file in memory, so
      // this scales to many concurrent (large) Range GETs against one token.
      if (!upstream.body) return res.end()
      const nodeStream = Readable.fromWeb(upstream.body)
      nodeStream.on('error', () => res.destroy())
      req.on('close', () => nodeStream.destroy())
      nodeStream.pipe(res)
    } catch (err) {
      console.error('native/file', err.message)
      if (!res.headersSent) res.status(502).end()
      else res.destroy()
    }
  })
}
