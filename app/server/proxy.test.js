import test from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import express from 'express'
import { createProxyMiddleware } from './proxy.js'

const listen = server => new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server)))
const origin = server => `http://127.0.0.1:${server.address().port}`

test('literal proxy preserves mount-stripped paths, query, body and server token', async t => {
  const upstream = await listen(http.createServer(async (req, res) => {
    let body = ''
    for await (const chunk of req) body += chunk
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify({ url: req.url, body, token: req.headers['x-emby-token'] }))
  }))
  t.after(() => upstream.close())
  const app = express()
  app.use('/jellyfin', createProxyMiddleware({
    target: origin(upstream), prefix: '/jellyfin',
    on: { proxyReq: req => req.setHeader('X-Emby-Token', 'server-token') },
  }))
  const server = await listen(http.createServer(app))
  t.after(() => server.close())
  const response = await fetch(`${origin(server)}/jellyfin/Items/a?Fields=Path`, {
    method: 'POST', body: 'payload', headers: { 'X-Emby-Token': 'client-token' },
  })
  assert.deepEqual(await response.json(), {
    url: '/Items/a?Fields=Path', body: 'payload', token: 'server-token',
  })
  assert.equal(server.listenerCount('upgrade'), 0)
})

test('unavailable proxy target returns 502', async t => {
  const upstream = await listen(http.createServer())
  const target = origin(upstream)
  await new Promise(resolve => upstream.close(resolve))
  const app = express()
  app.use('/jellyfin', createProxyMiddleware({ target, prefix: '/jellyfin' }))
  const server = await listen(http.createServer(app))
  t.after(() => server.close())
  assert.equal((await fetch(`${origin(server)}/jellyfin/Items`)).status, 502)
})
