import httpProxy from 'http-proxy'

// Our routes use literal mounts, so no glob parser is needed. HTTP URLs are
// already stripped by Express; raw upgrade URLs still include the mount.
export function createProxyMiddleware({ target, changeOrigin = true, prefix, on = {} }) {
  const proxy = httpProxy.createProxyServer({ target, changeOrigin })
  if (on.proxyReq) proxy.on('proxyReq', on.proxyReq)
  proxy.on('error', (_error, _req, response) => {
    if (typeof response.writeHead === 'function') {
      if (!response.headersSent) response.writeHead(502)
      response.end()
    } else {
      response.destroy()
    }
  })
  // Match the previous middleware's handling of disconnected clients.
  proxy.on('proxyRes', (upstream, _req, response) => {
    response.on('close', () => {
      if (!response.writableEnded) upstream.destroy()
    })
    upstream.on('error', () => response.destroy())
  })
  const middleware = (req, res) => proxy.web(req, res)
  middleware.upgrade = (req, socket, head) => {
    if (req.url === prefix || req.url.startsWith(`${prefix}/`) || req.url.startsWith(`${prefix}?`)) {
      req.url = req.url.slice(prefix.length) || '/'
      if (req.url.startsWith('?')) req.url = `/${req.url}`
    }
    proxy.ws(req, socket, head)
  }
  return middleware
}
