import test from 'node:test'
import assert from 'node:assert/strict'
import express from 'express'
import { browserSource, registerOfflineRoutes } from './offline.js'
const itemId = 'a'.repeat(32),
  sourceId = 'b'.repeat(32)
const item = {
  Name: 'A movie',
  MediaSources: [
    {
      Id: sourceId,
      Container: 'mp4',
      MediaStreams: [
        { Type: 'Video', Codec: 'h264', BitDepth: 8, PixelFormat: 'yuv420p' },
        { Type: 'Audio', Codec: 'aac', Index: 1, IsDefault: true }
      ]
    }
  ]
}
test('only browser-compatible sources can be saved; a requested source cannot fall back', () => {
  assert.equal(browserSource(item, sourceId).source.Id, sourceId)
  assert.throws(() => browserSource(item, 'c'.repeat(32)), /not found/)
  for (const change of [
    { Container: 'mkv' },
    { MediaStreams: [{ Type: 'Video', Codec: 'hevc' }] },
    { MediaStreams: [{ Type: 'Video', Codec: 'h264', BitDepth: 10 }] },
    {
      MediaStreams: [
        { Type: 'Video', Codec: 'h264' },
        { Type: 'Audio', Codec: 'ac3' }
      ]
    }
  ]) {
    assert.throws(
      () =>
        browserSource({
          MediaSources: [{ ...item.MediaSources[0], ...change }]
        }),
      /needs conversion/
    )
  }
})
test('authenticated range proxy pins source version and rejects changes before mixing bytes', async (t) => {
  const app = express()
  app.use((req, _res, next) => {
    req.session = req.get('x-test-anonymous')
      ? {}
      : {
          jellyfin: {
            accessToken: req.get('x-test-token') || 'server-token',
            userId: req.get('x-test-account') || 'alice'
          }
        }
    next()
  })
  let etag = '"one"',
    modified = '',
    responseModified = null,
    seen = []
  registerOfflineRoutes(app, {
    detail: async () => item,
    upstreamFetch: async (url, options) => {
      seen.push({ url: String(url), options })
      return options.method === 'HEAD'
        ? new Response(null, {
            headers: { 'content-length': '8', etag, 'last-modified': modified }
          })
        : new Response('0123', {
            status: 206,
            headers: {
              'content-range': 'bytes 0-3/8',
              'content-length': '4',
              etag,
              'last-modified': responseModified ?? modified
            }
          })
    }
  })
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s))
  })
  t.after(() => server.close())
  const base = `http://127.0.0.1:${server.address().port}/api/offline/${itemId}`
  assert.equal(
    (await fetch(`${base}/info`, { headers: { 'x-test-anonymous': '1' } }))
      .status,
    401
  )
  assert.equal(
    (
      await fetch(`${base}/media`, {
        headers: { 'x-test-anonymous': '1', Range: 'bytes=0-3' }
      })
    ).status,
    401
  )
  const response = await fetch(`${base}/info`),
    info = await response.json()
  assert.equal(info.owner, 'alice')
  assert.equal(info.audioIndex, 1)
  assert.ok(!JSON.stringify(info).includes('server-token'))
  const query = new URLSearchParams({
    source: sourceId,
    revision: info.revision
  })
  const media = await fetch(`${base}/media?${query}`, {
    headers: { Range: 'bytes=0-3' }
  })
  assert.equal(media.status, 206)
  assert.equal(await media.text(), '0123')
  const upstream = seen.find((x) => x.options.headers.Range)
  assert.equal(upstream.options.headers['X-Emby-Token'], 'server-token')
  assert.equal(upstream.options.headers['If-Range'], '"one"')
  const probesBefore = seen.filter((x) => x.options.method === 'HEAD').length
  const concurrent = await Promise.all(
    Array.from({ length: 6 }, () =>
      fetch(`${base}/media?${query}`, { headers: { Range: 'bytes=0-3' } })
    )
  )
  assert.ok(concurrent.every((response) => response.status === 206))
  assert.equal(
    seen.filter((x) => x.options.method === 'HEAD').length,
    probesBefore,
    'range requests reuse the authenticated source snapshot'
  )
  assert.equal(
    (
      await fetch(`${base}/media?${query}`, {
        headers: {
          Range: 'bytes=0-3',
          'x-test-account': 'bob',
          'x-test-token': 'other-token'
        }
      })
    ).status,
    206
  )
  assert.equal(
    seen.filter((x) => x.options.method === 'HEAD').length,
    probesBefore + 1,
    'other credentials must inspect their own source'
  )
  assert.equal(seen.at(-1).options.headers['X-Emby-Token'], 'other-token')
  etag = '"replacement-same-size"'
  assert.equal(
    (await fetch(`${base}/media?${query}`, { headers: { Range: 'bytes=0-3' } }))
      .status,
    409
  )
  assert.equal((await fetch(`${base}/info?source=invalid`)).status, 400)
  etag = 'W/"weak"'
  assert.equal((await fetch(`${base}/info`)).status, 409)
  modified = 'Mon, 05 Oct 2026 00:00:00 GMT'
  const weakInfo = await fetch(`${base}/info`).then((r) => r.json())
  const weakQuery = new URLSearchParams({
    source: sourceId,
    revision: weakInfo.revision
  })
  assert.equal(
    (
      await fetch(`${base}/media?${weakQuery}`, {
        headers: { Range: 'bytes=0-3' }
      })
    ).status,
    206
  )
  assert.equal(seen.at(-1).options.headers['If-Range'], modified)
  responseModified = 'Mon, 05 Oct 2026 00:00:01 GMT'
  assert.equal(
    (
      await fetch(`${base}/media?${weakQuery}`, {
        headers: { Range: 'bytes=0-3' }
      })
    ).status,
    409
  )
})
