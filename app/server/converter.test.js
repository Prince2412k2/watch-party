import test from 'node:test'
import assert from 'node:assert/strict'
import express from 'express'
import { registerConverterRoutes } from './converter.js'

test('converter is admin-only and proxies only fixed actions with a private credential', async t => {
  const received = []
  const upstream = express()
  upstream.all('/api/*', (req, res) => { received.push({ path: req.path, auth: req.get('authorization'), cookie: req.get('cookie') }); res.json({ ok: true }) })
  const worker = await new Promise(resolve => { const server = upstream.listen(0, '127.0.0.1', () => resolve(server)) })
  t.after(() => worker.close())
  const app = express()
  app.use((req, _res, next) => {
    req.session = req.get('x-test-auth') === 'none' ? {} : { jellyfin: { userId: 'test', isAdmin: req.get('x-test-auth') === 'admin', adminCheckedAt: Date.now() } }
    next()
  })
  registerConverterRoutes(app, { base: `http://127.0.0.1:${worker.address().port}`, key: 'worker-private-key' })
  const server = await new Promise(resolve => { const server = app.listen(0, '127.0.0.1', () => resolve(server)) })
  t.after(() => server.close())
  const origin = `http://127.0.0.1:${server.address().port}`
  for (const [role, status] of [['none', 401], ['member', 403], ['admin', 200]]) {
    const response = await fetch(`${origin}/api/converter/state`, { headers: { 'x-test-auth': role, cookie: 'browser-cookie=private' } })
    assert.equal(response.status, status)
  }
  assert.equal(received.length, 1)
  assert.equal(received[0].auth, 'Bearer worker-private-key')
  assert.equal(received[0].cookie, undefined)
  assert.equal((await fetch(`${origin}/api/converter/jobs/15/next`, { method: 'POST', headers: { 'x-test-auth': 'admin' } })).status, 200)
  assert.equal(received[1].path, '/api/jobs/15/next')
  assert.equal((await fetch(`${origin}/api/converter/jobs/15/delete-file`, { method: 'POST', headers: { 'x-test-auth': 'admin' } })).status, 404)
  assert.equal(received.length, 2)
})
