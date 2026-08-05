import test from 'node:test'
import assert from 'node:assert/strict'

import { enrichTorrents, posterUrlFromImage, remoteImageFetch, shapeImages } from './arr.js'

const realFetch = globalThis.fetch

function stubFetch(handler) {
  const calls = []
  globalThis.fetch = async (url, opts) => {
    calls.push({ url: url.toString(), opts })
    return handler(url.toString(), opts)
  }
  return calls
}

function bodyStream(chunks) {
  return new ReadableStream({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(chunk)
      controller.close()
    },
  })
}

async function readStream(stream) {
  const chunks = []
  for await (const chunk of stream) chunks.push(chunk)
  return Buffer.concat(chunks)
}

test.afterEach(() => { globalThis.fetch = realFetch })

test('posterUrlFromImage proxies an allow-listed remoteUrl, never the CDN URL', () => {
  assert.equal(
    posterUrlFromImage('radarr', { remoteUrl: 'https://image.tmdb.org/t/p/w500/x.jpg' }),
    `/api/servarr/remote-image?url=${encodeURIComponent('https://image.tmdb.org/t/p/w500/x.jpg')}`,
  )
  assert.equal(
    posterUrlFromImage('sonarr', { remoteUrl: 'https://artworks.thetvdb.com/banners/x.jpg' }),
    `/api/servarr/remote-image?url=${encodeURIComponent('https://artworks.thetvdb.com/banners/x.jpg')}`,
  )
  assert.equal(
    posterUrlFromImage('sonarr', { remoteUrl: 'https://assets.fanart.tv/fanart/x.jpg' }),
    `/api/servarr/remote-image?url=${encodeURIComponent('https://assets.fanart.tv/fanart/x.jpg')}`,
  )
})

test('posterUrlFromImage falls back to the key-adding local proxy when remoteUrl is not allow-listed', () => {
  assert.equal(
    posterUrlFromImage('radarr', { remoteUrl: 'https://evil.example.com/x.jpg', url: '/MediaCover/1/poster.jpg' }),
    '/api/servarr/image?service=radarr&path=%2FMediaCover%2F1%2Fposter.jpg',
  )
  // Nothing usable at all → placeholder, never the untrusted URL.
  assert.equal(posterUrlFromImage('radarr', { remoteUrl: 'https://evil.example.com/x.jpg' }), null)
})

test('shapeImages strips raw remoteUrl/url and keeps only coverType + proxied art', () => {
  const images = [
    { coverType: 'poster', remoteUrl: 'https://image.tmdb.org/t/p/w500/p.jpg', url: '/MediaCover/1/poster.jpg' },
    { coverType: 'fanart', remoteUrl: 'https://evil.example.com/f.jpg' },
    { coverType: 'banner' }, // no art at all
  ]
  const shaped = shapeImages('radarr', images)
  assert.deepEqual(shaped, [
    { coverType: 'poster', remoteUrl: `/api/servarr/remote-image?url=${encodeURIComponent('https://image.tmdb.org/t/p/w500/p.jpg')}` },
    { coverType: 'fanart', remoteUrl: null },
    { coverType: 'banner', remoteUrl: null },
  ])
  for (const i of shaped) assert.equal('url' in i, false)
})

test('enriched downloads proxy embedded queue artwork', () => {
  const remoteUrl = 'https://image.tmdb.org/t/p/w500/p.jpg'
  const [torrent] = enrichTorrents(
    [{ hash: 'ABC', name: 'Movie.2026' }],
    { radarr: [{ downloadId: 'abc', movie: { title: 'Movie', images: [{ coverType: 'poster', remoteUrl }] } }] },
  )
  assert.equal(torrent.posterUrl, `/api/servarr/remote-image?url=${encodeURIComponent(remoteUrl)}`)
  assert.notEqual(torrent.posterUrl, remoteUrl)
})

test('remoteImageFetch rejects a host that is not on the artwork allow-list, without ever calling fetch', async () => {
  const calls = stubFetch(() => { throw new Error('must not be called') })
  await assert.rejects(() => remoteImageFetch('https://evil.example.com/x.jpg'), (err) => {
    assert.equal(err.status, 400)
    return true
  })
  assert.equal(calls.length, 0)
})

test('remoteImageFetch requires https', async () => {
  const calls = stubFetch(() => { throw new Error('must not be called') })
  await assert.rejects(() => remoteImageFetch('http://image.tmdb.org/t/p/w500/x.jpg'), (err) => {
    assert.equal(err.status, 400)
    return true
  })
  assert.equal(calls.length, 0)
})

test('remoteImageFetch rejects an IP-literal host and embedded credentials', async () => {
  const calls = stubFetch(() => { throw new Error('must not be called') })
  for (const bad of [
    'https://127.0.0.1/x.jpg',
    'https://[::1]/x.jpg',
    'https://user:pass@image.tmdb.org/x.jpg',
    'https://image.tmdb.org:8443/x.jpg',
    'https://image.tmdb.org.evil.com/x.jpg', // host confusion via a lookalike subdomain
  ]) {
    await assert.rejects(() => remoteImageFetch(bad), (err) => {
      assert.equal(err.status, 400)
      return true
    })
  }
  assert.equal(calls.length, 0)
})

test('remoteImageFetch passes bytes + content-type through for an allow-listed host', async () => {
  const calls = stubFetch((url) => {
    assert.equal(url, 'https://image.tmdb.org/t/p/w500/x.jpg')
    return {
      ok: true,
      status: 200,
      headers: new Map([['content-type', 'image/jpeg']]),
      body: bodyStream([new TextEncoder().encode('JPEGBYTES')]),
    }
  })
  const out = await remoteImageFetch('https://image.tmdb.org/t/p/w500/x.jpg')
  assert.equal(out.contentType, 'image/jpeg')
  assert.equal((await readStream(out.stream)).toString(), 'JPEGBYTES')
  // fetch() follows redirects by default — this proxy must ask for manual
  // redirect handling instead, or the allow-list check below is worthless.
  assert.equal(calls[0].opts.redirect, 'manual')
})

test('remoteImageFetch does not follow a redirect to a disallowed host', async () => {
  stubFetch(() => ({
    ok: false,
    status: 302,
    headers: new Map([['location', 'https://evil.example.com/x.jpg']]),
    body: bodyStream([]),
  }))
  await assert.rejects(() => remoteImageFetch('https://image.tmdb.org/t/p/w500/x.jpg'), (err) => {
    assert.equal(err.upstream, true)
    assert.notEqual(err.status, 200)
    return true
  })
})

test('remoteImageFetch rejects a response over the size cap', async () => {
  const chunk = new Uint8Array(7 * 1024 * 1024)
  stubFetch(() => ({
    ok: true,
    status: 200,
    headers: new Map([['content-type', 'image/jpeg']]),
    body: bodyStream([chunk, chunk]),
  }))
  const { stream } = await remoteImageFetch('https://image.tmdb.org/t/p/w500/x.jpg')
  await assert.rejects(() => readStream(stream), (err) => {
    assert.equal(err.upstream, true)
    return true
  })
})
