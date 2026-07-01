import { requireAuth, getJellyfin } from './auth.js'
import { getItems, getItemChildren, buildHlsUrl, BASE } from './jellyfin.js'

export function registerLibraryRoutes(app) {
  app.get('/api/library/items', requireAuth, async (req, res) => {
    const { token, userId } = getJellyfin(req)
    try {
      const data = await getItems(token, userId)
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
    const url = `${BASE}/Items/${req.params.id}/Images/${type}?api_key=${token}`
    try {
      const upstream = await fetch(url)
      if (!upstream.ok) return res.status(upstream.status).end()
      const buf = Buffer.from(await upstream.arrayBuffer())
      res.set('Content-Type', upstream.headers.get('content-type') || 'image/jpeg')
      res.set('Cache-Control', 'public, max-age=86400')
      res.send(buf)
    } catch (err) {
      res.status(502).end()
    }
  })

  // Returns the HLS URL for a media item (token stays server-side)
  app.get('/api/library/hls-url', requireAuth, (req, res) => {
    const { token } = getJellyfin(req)
    const { itemId, maxBitrate } = req.query
    if (!itemId) return res.status(400).json({ error: 'itemId required' })
    const cap = maxBitrate ? parseInt(maxBitrate, 10) : undefined
    res.json({ url: buildHlsUrl(itemId, token, { maxBitrate: cap }) })
  })
}
