import { requireAuth, getJellyfin } from './auth.js'
import {
  getItems, getItemChildren, buildHlsUrl, BASE,
  getViews, getResumeItems, getNextUp, getLatest, getItemDetail,
} from './jellyfin.js'

// Jellyfin item ids are 32-char hex GUIDs (dashless), though the dashed form is
// also accepted. Anything else is rejected before it reaches an internal URL.
const JELLYFIN_ID = /^[0-9a-f]{32}$/i
const JELLYFIN_GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const isJellyfinId = (v) => typeof v === 'string' && (JELLYFIN_ID.test(v) || JELLYFIN_GUID.test(v))

// Known Jellyfin image types — the only values allowed to be interpolated into
// the internal /Items/:id/Images/:type URL.
const IMAGE_TYPES = new Set([
  'Primary', 'Backdrop', 'Thumb', 'Logo', 'Banner', 'Art', 'Disc', 'Box',
  'BoxRear', 'Menu', 'Screenshot', 'Chapter', 'Profile',
])

// Remove every api_key query param from an HLS playlist body so the per-user
// token never reaches the browser. Nested URIs stay relative (and thus keep
// routing back through this proxy, which re-attaches the token server-side).
function stripApiKey(text) {
  return text
    .replace(/([?&])api_key=[^&\s"'<>]*/gi, (_m, sep) => (sep === '?' ? '?' : ''))
    .replace(/\?&/g, '?')
    .replace(/\?"/g, '"')
    .replace(/\?(\r?\n)/g, '$1')
    .replace(/\?$/g, '')
}

export function registerLibraryRoutes(app) {
  // Aggregated landing data: libraries + Continue Watching + Next Up
  app.get('/api/library/home', requireAuth, async (req, res) => {
    const { token, userId } = getJellyfin(req)
    try {
      const [views, resume, nextUp] = await Promise.all([
        getViews(token, userId).catch(() => ({ Items: [] })),
        getResumeItems(token, userId).catch(() => ({ Items: [] })),
        getNextUp(token, userId).catch(() => ({ Items: [] })),
      ])
      res.json({
        views: views.Items ?? [],
        resume: resume.Items ?? [],
        nextUp: nextUp.Items ?? [],
      })
    } catch (err) {
      console.error('library/home', err.message)
      res.status(502).json({ error: 'Failed to load home' })
    }
  })

  // Recently added, optionally scoped to a library view
  app.get('/api/library/latest', requireAuth, async (req, res) => {
    const { token, userId } = getJellyfin(req)
    try {
      const data = await getLatest(token, userId, req.query.parentId)
      res.json(Array.isArray(data) ? data : (data.Items ?? []))
    } catch (err) {
      console.error('library/latest', err.message)
      res.status(502).json({ error: 'Failed to fetch latest' })
    }
  })

  // Full item detail (overview, genres, rating) for the hero banner
  app.get('/api/library/item/:id', requireAuth, async (req, res) => {
    const { token, userId } = getJellyfin(req)
    try {
      const data = await getItemDetail(token, userId, req.params.id)
      res.json(data)
    } catch (err) {
      console.error('library/item', err.message)
      res.status(502).json({ error: 'Failed to fetch item' })
    }
  })

  app.get('/api/library/items', requireAuth, async (req, res) => {
    const { token, userId } = getJellyfin(req)
    try {
      const data = await getItems(token, userId, req.query.parentId ? { ParentId: req.query.parentId } : {})
      res.json(data.Items ?? [])
    } catch (err) {
      console.error('library/items', err.message)
      res.status(502).json({ error: 'Failed to fetch library' })
    }
  })

  app.get('/api/library/items/:id/children', requireAuth, async (req, res) => {
    const { token, userId } = getJellyfin(req)
    try {
      const data = await getItemChildren(token, userId, req.params.id)
      res.json(data.Items ?? [])
    } catch (err) {
      console.error('library/children', err.message)
      res.status(502).json({ error: 'Failed to fetch children' })
    }
  })

  // Proxy poster images so the client never needs the Jellyfin token
  app.get('/api/library/image/:id', requireAuth, async (req, res) => {
    const { token } = getJellyfin(req)
    const type = req.query.type || 'Primary'
    if (!isJellyfinId(req.params.id)) return res.status(400).end()
    if (!IMAGE_TYPES.has(type)) return res.status(400).end()
    const url = `${BASE}/Items/${encodeURIComponent(req.params.id)}/Images/${encodeURIComponent(type)}?api_key=${encodeURIComponent(token)}`
    try {
      const upstream = await fetch(url)
      if (!upstream.ok) {
        // Negative-cache misses so a missing backdrop/logo isn't re-requested in a loop
        res.set('Cache-Control', 'public, max-age=3600')
        return res.status(upstream.status).end()
      }
      const buf = Buffer.from(await upstream.arrayBuffer())
      res.set('Content-Type', upstream.headers.get('content-type') || 'image/jpeg')
      res.set('Cache-Control', 'public, max-age=86400')
      res.send(buf)
    } catch (err) {
      res.status(502).end()
    }
  })

  // Returns the HLS URL for a media item (token stays server-side).
  //   &abr=1        → adaptive multi-variant master.m3u8 (ABR ladder; hls.js
  //                   selects the rung by bandwidth). This is the default path.
  //   &maxBitrate=N → single-bitrate transcode (legacy fixed-tier / src-swap).
  app.get('/api/library/hls-url', requireAuth, (req, res) => {
    const { token } = getJellyfin(req)
    const { itemId, maxBitrate, abr } = req.query
    if (!itemId) return res.status(400).json({ error: 'itemId required' })
    if (abr === '1' || abr === 'true') {
      return res.json({ url: buildHlsUrl(itemId, { abr: true }) })
    }
    const cap = maxBitrate ? parseInt(maxBitrate, 10) : undefined
    res.json({ url: buildHlsUrl(itemId, { maxBitrate: cap }) })
  })

  // Authenticated HLS proxy. buildHlsUrl points hls.js here instead of straight
  // at Jellyfin so the per-user api_key stays server-side: we attach it to the
  // upstream request and strip it from any playlist we hand back. Playlists are
  // rewritten (token removed, URIs stay relative → they re-enter this route);
  // segments/keys are streamed through unchanged.
  app.get('/api/library/hls/*', requireAuth, async (req, res) => {
    const { token } = getJellyfin(req)
    const rest = req.params[0] || ''
    // Only ever proxy the Jellyfin video paths our own URLs produce.
    if (!/^Videos\/[A-Za-z0-9._\-/]+$/.test(rest)) return res.status(400).end()

    const search = new URLSearchParams()
    for (const [k, v] of Object.entries(req.query)) {
      if (k.toLowerCase() === 'api_key') continue   // never trust a client-supplied token
      search.set(k, Array.isArray(v) ? v[0] : v)
    }
    search.set('api_key', token)

    const target = `${BASE}/${rest}?${search}`
    try {
      const upstream = await fetch(target, {
        headers: req.headers.range ? { Range: req.headers.range } : {},
      })
      const ct = upstream.headers.get('content-type') || ''
      const isPlaylist = ct.includes('mpegurl') || /\.m3u8($|\?)/i.test(rest)

      if (isPlaylist) {
        const body = stripApiKey(await upstream.text())
        res.status(upstream.status)
        res.set('Content-Type', ct || 'application/vnd.apple.mpegurl')
        res.set('Cache-Control', 'no-store')
        return res.send(body)
      }

      // Binary segment/key: forward status + range-related headers verbatim.
      res.status(upstream.status)
      for (const h of ['content-type', 'content-length', 'accept-ranges', 'content-range', 'cache-control']) {
        const val = upstream.headers.get(h)
        if (val) res.set(h, val)
      }
      const buf = Buffer.from(await upstream.arrayBuffer())
      res.send(buf)
    } catch (err) {
      res.status(502).end()
    }
  })
}
