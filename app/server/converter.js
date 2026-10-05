import { requireAuth, requireAdmin } from './auth.js'

// Browser requests use the app session. The private converter API never receives
// browser cookies, and its service credential never reaches the client.
export function registerConverterRoutes(app, {
  base = process.env.MEDIA_CONVERTER_URL || 'http://media-converter:8090',
  key = process.env.MEDIA_CONVERTER_API_KEY || process.env.SESSION_SECRET || '',
} = {}) {
  const proxy = async (req, res) => {
    const path = req.path.replace(/^\/api\/converter/, '')
    const valid = req.method === 'GET' ? path === '/state'
      : /^\/(scan|pause|resume)$/.test(path) || /^\/jobs\/[1-9]\d*\/(next|up|down|retry|cancel)$/.test(path)
    if (!valid) return res.status(404).json({ error: 'Unknown converter action' })
    if (!key) return res.status(503).json({ error: 'Converter service authentication is not configured' })
    try {
      const upstream = await fetch(`${base}/api${path}`, {
        method: req.method,
        headers: { Authorization: `Bearer ${key}` },
        signal: AbortSignal.timeout(path === '/scan' ? 120_000 : 10_000),
      })
      res.set('Cache-Control', 'no-store')
      res.status(upstream.status).json(await upstream.json())
    } catch {
      res.status(503).json({ error: 'Converter service is unavailable. Check that the worker is running.' })
    }
  }
  app.get('/api/converter/state', requireAuth, requireAdmin, proxy)
  app.post('/api/converter/*', requireAuth, requireAdmin, proxy)
}
