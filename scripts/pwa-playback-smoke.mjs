// Browser regression for active PWA downloads: incremental progress, rapid
// missing-range seeks, no source reloads when chrome changes, and phone bounds.
// Uses an isolated local fixture server and a fresh browser profile; no accounts
// or external media services are needed. Requires a built client and Playwright.
// Run from the repository root:
//   ffmpeg -f lavfi -i testsrc2=size=960x540:rate=24 -t 36 -c:v libx264 \
//     -preset ultrafast -crf 18 -pix_fmt yuv420p -movflags +faststart /tmp/pwa.mp4
//   npm --prefix app/client run build
//   WP_MOVIE_FILE=/tmp/pwa.mp4 node scripts/pwa-playback-smoke.mjs
// Optional CHROMIUM=/usr/bin/chromium and PLAYWRIGHT_MODULE=/path/to/index.mjs.
// The fixture must be 36 seconds long and larger than 12 MiB.
import { createServer } from 'node:http'
import { readFileSync, existsSync, mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, extname, resolve } from 'node:path'
const movie = readFileSync(process.env.WP_MOVIE_FILE),
  dist = resolve('app/client/dist')
const fixtureStats = { ranges: [], delay: 700, pace: 0 }
const info = (id) => ({
  owner: 'alice',
  itemId: id,
  sourceId: 'source',
  revision: 'one',
  size: movie.length,
  title: `Movie ${id}`,
  series: '',
  duration: 36,
  audioIndex: 1,
  etag: '"one"',
  modified: '',
  subtitles: [{ index: 2, displayTitle: 'English', language: 'eng' }]
})
const png = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS1cAAAAASUVORK5CYII=',
  'base64'
)
const fixtureServer = createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost'),
    p = url.pathname
  const json = (value) => {
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify(value))
  }
  if (p === '/__test/state')
    return json({ ...fixtureStats, size: movie.length })
  if (p === '/__test/reset') {
    fixtureStats.ranges = []
    fixtureStats.pace = Number(url.searchParams.get('pace') ?? 0)
    fixtureStats.delay = Number(url.searchParams.get('delay') ?? 700)
    return json({ ok: true })
  }
  if (p === '/__test/fixture') {
    res.setHeader('content-type', 'video/mp4')
    return res.end(movie)
  }
  if (p === '/api/auth/me')
    return json({ userId: 'alice', name: 'Alice', isAdmin: false })
  if (p === '/api/profile') return json({ displayName: null, avatar: null })
  if (p === '/api/library/home')
    return json({
      views: [
        {
          Id: 'shows',
          Name: 'Shows',
          Type: 'CollectionFolder',
          CollectionType: 'tvshows'
        },
        {
          Id: 'movies',
          Name: 'Movies',
          Type: 'CollectionFolder',
          CollectionType: 'movies'
        }
      ]
    })
  if (p.endsWith('/children'))
    return json(
      ['Courage', 'Lanterns', 'The Mentalist', 'Over the Garden Wall'].map(
        (Name, i) => ({
          Id: 'show' + i,
          Name,
          Type: 'Series',
          ImageTags: { Primary: 'poster' }
        })
      )
    )
  if (p.startsWith('/api/library/image/')) {
    res.setHeader('content-type', 'image/png')
    return res.end(png)
  }
  if (p.includes('/subtitles/') && p.endsWith('/content')) {
    res.setHeader('content-type', 'text/vtt')
    return res.end(
      'WEBVTT\n\n00:00:01.000 --> 00:00:05.000\nA local subtitle\n'
    )
  }
  if (p.match(/^\/api\/offline\/[^/]+\/info$/))
    return json(info(p.split('/')[3]))
  if (p.match(/^\/api\/offline\/[^/]+\/media$/)) {
    const m = /bytes=(\d+)-(\d*)/.exec(req.headers.range ?? 'bytes=0-')
    const start = Number(m[1]),
      end = Math.min(movie.length - 1, m[2] ? Number(m[2]) : movie.length - 1)
    const entry = {
      item: p.split('/')[3],
      start,
      end,
      chunk: Number(url.searchParams.get('chunk')),
      sent: 0,
      aborted: false
    }
    fixtureStats.ranges.push(entry)
    res.on('close', () => {
      entry.aborted = !res.writableEnded
    })
    const send = () => {
      if (res.destroyed) return
      res.writeHead(206, {
        'content-type': 'video/mp4',
        'content-length': end - start + 1,
        'accept-ranges': 'bytes',
        'content-range': `bytes ${start}-${end}/${movie.length}`
      })
      if (!fixtureStats.pace) {
        entry.sent = end - start + 1
        res.end(movie.subarray(start, end + 1))
        return
      }
      let offset = start
      const timer = setInterval(() => {
        if (res.destroyed) {
          clearInterval(timer)
          return
        }
        const stop = Math.min(end + 1, offset + 65536)
        res.write(movie.subarray(offset, stop))
        entry.sent += stop - offset
        offset = stop
        if (offset > end) {
          clearInterval(timer)
          res.end()
        }
      }, fixtureStats.pace)
    }
    return setTimeout(send, fixtureStats.delay)
  }
  if (p.startsWith('/api/')) return json([])
  let file = join(dist, p === '/' ? 'index.html' : p)
  if (!existsSync(file)) file = join(dist, 'index.html')
  res.setHeader('Service-Worker-Allowed', '/')
  res.setHeader(
    'content-type',
    {
      '.js': 'text/javascript',
      '.css': 'text/css',
      '.html': 'text/html',
      '.webmanifest': 'application/manifest+json',
      '.svg': 'image/svg+xml',
      '.woff2': 'font/woff2'
    }[extname(file)] ?? 'application/octet-stream'
  )
  res.end(readFileSync(file))
})
await new Promise((resolve) => fixtureServer.listen(0, '127.0.0.1', resolve))
const base = `http://127.0.0.1:${fixtureServer.address().port}`
const artifacts = mkdtempSync(join(tmpdir(), 'wp-pwa-smoke-'))

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright')
import assert from 'node:assert/strict'
const chunkSize = 2 * 1024 * 1024
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM,
  args: ['--no-sandbox']
})
const context = await browser.newContext({
  viewport: { width: 390, height: 844 },
  isMobile: true,
  hasTouch: true
})
await context.addInitScript(() =>
  Object.defineProperty(
    ServiceWorkerRegistration.prototype,
    'backgroundFetch',
    { configurable: true, get: () => undefined }
  )
)
let page = await context.newPage()
const errors = []
context.on('page', (p) =>
  p.on('pageerror', (error) => errors.push(error.message))
)
page.on('pageerror', (error) => errors.push(error.message))
page.on('console', (msg) => {
  if (msg.type() === 'error') console.log('Browser:', msg.text())
})
async function until(fn, arg, timeout = 20000) {
  const end = Date.now() + timeout
  while (Date.now() < end) {
    if (await page.evaluate(fn, arg)) return
    await new Promise((r) => setTimeout(r, 100))
  }
  console.log(
    'TIMEOUT',
    await page.evaluate(() => ({
      time: window.movie?.currentTime,
      ready: window.movie?.readyState,
      seeking: window.movie?.seeking,
      error: window.movie?.error?.message,
      events: window.events,
      buffered: window.movie
        ? Array.from({ length: window.movie.buffered.length }, (_, i) => [
            window.movie.buffered.start(i),
            window.movie.buffered.end(i)
          ])
        : [],
      body: document.body.innerText
    }))
  )
  throw new Error('Condition timed out: ' + fn.toString())
}
async function records() {
  return page.evaluate(
    () =>
      new Promise((resolve, reject) => {
        const open = indexedDB.open('watchparty-media', 1)
        open.onerror = () => reject(open.error)
        open.onsuccess = () => {
          const db = open.result,
            request = db.transaction('media').objectStore('media').getAll()
          request.onsuccess = () => {
            resolve(request.result)
            db.close()
          }
        }
      })
  )
}
async function seed(id, count, retention = 'cache', paused = false) {
  return page.evaluate(
    async ({ id, count, retention, paused, chunkSize }) => {
      const info = await (await fetch(`/api/offline/${id}/info`)).json()
      const bytes = await (await fetch('/__test/fixture')).blob()
      const key = `${info.owner}:${id}:${info.sourceId}:${info.revision}`
      const received = Math.min(count * chunkSize, info.size)
      const record = {
        ...info,
        key,
        generation: crypto.randomUUID(),
        retention,
        state: received === info.size ? 'complete' : 'paused',
        received,
        accessed: Date.now(),
        resumeOnOpen: !paused && retention === 'download'
      }
      await new Promise((resolve, reject) => {
        const open = indexedDB.open('watchparty-media', 1)
        open.onsuccess = () => {
          const db = open.result,
            tx = db.transaction(['media', 'chunks'], 'readwrite')
          tx.objectStore('media').put(record)
          for (
            let index = 0;
            index < count && index * chunkSize < info.size;
            index++
          )
            tx.objectStore('chunks').put({
              media: key,
              index,
              data: bytes.slice(
                index * chunkSize,
                Math.min(info.size, (index + 1) * chunkSize)
              )
            })
          tx.oncomplete = () => {
            db.close()
            resolve()
          }
          tx.onabort = () => reject(tx.error)
        }
      })
      return key
    },
    { id, count, retention, paused, chunkSize }
  )
}
const row = (id) =>
  page.locator('.saved-card').filter({
    has: page.getByRole('heading', { name: `Movie ${id}`, exact: true })
  })
const stats = async () => (await fetch(base + '/__test/state')).json()
try {
  await fetch(base + '/__test/reset?delay=100&pace=180')
  await page.goto(base + '/saved')
  await until(() => !!navigator.serviceWorker.controller)
  const key = await seed('streaming', 1)
  await page.getByRole('tab', { name: /Cache/ }).click()
  await row('streaming')
    .getByRole('button', { name: 'Download', exact: true })
    .click()
  await page.getByRole('tab', { name: /Downloads/ }).click()
  await row('streaming')
    .getByRole('button', { name: 'Pause', exact: true })
    .waitFor()
  const samples = []
  for (let i = 0; i < 12; i++) {
    samples.push(await row('streaming').locator('.saved-status').innerText())
    await new Promise((r) => setTimeout(r, 150))
  }
  console.log('progress', samples)
  assert.ok(
    new Set(samples).size >= 6,
    'progress should change within a storage chunk'
  )
  assert.ok(
    samples.some((s) => / [1-9][0-9]*\.[0-9] Mbps/.test(s)),
    'live Mbps'
  )
  await row('streaming')
    .getByRole('button', { name: 'Play Movie streaming', exact: true })
    .first()
    .click()
  await until(() => document.querySelector('video')?.readyState >= 2)
  assert.equal(
    (await records()).find((r) => r.key === key).state,
    'downloading'
  )
  await page.evaluate(() => {
    window.movie = document.querySelector('video')
    window.movieSrc = window.movie.currentSrc
    window.events = []
    for (const type of [
      'loadstart',
      'seeking',
      'seeked',
      'waiting',
      'stalled',
      'playing',
      'pause',
      'error',
      'emptied',
      'loadedmetadata'
    ])
      window.movie.addEventListener(type, () =>
        window.events.push({
          type,
          t: window.movie.currentTime,
          ready: window.movie.readyState,
          at: performance.now()
        })
      )
    window.positions = []
    window.movie.addEventListener('timeupdate', () =>
      window.positions.push(window.movie.currentTime)
    )
    window.movie.currentTime = 21
  })
  await new Promise((r) => setTimeout(r, 350))
  await page.evaluate(() => {
    window.movie.currentTime = 8
  })
  await new Promise((r) => setTimeout(r, 350))
  await page.evaluate(() => {
    window.positions = []
    window.movie.currentTime = 27
  })
  await until(
    () => window.movie.currentTime >= 27 && window.movie.readyState >= 2,
    undefined,
    25000
  )
  await page.evaluate(() => window.movie.play())
  await until(() => window.movie.currentTime > 30, undefined, 20000)
  const playback = await page.evaluate(() => ({
    src: window.movie.currentSrc,
    same: window.movie === document.querySelector('video'),
    positions: window.positions,
    error: window.movie.error?.message
  }))
  assert.equal(playback.same, true)
  assert.equal(playback.src, await page.evaluate(() => window.movieSrc))
  assert.equal(
    await page.evaluate(
      () =>
        window.events.filter(
          (e) => e.type === 'emptied' || e.type === 'loadstart'
        ).length
    ),
    0
  )
  assert.equal(playback.error, undefined)
  assert.ok(
    playback.positions
      .filter((n) => n >= 27)
      .every((n, i, a) => i === 0 || n >= a[i - 1] - 0.1),
    'no backwards movement after final seek'
  )
  console.log(
    'PASS active download: repeated missing-range seeks resume, stable source and monotonic playback',
    playback.positions
  )
  assert.ok(
    (await stats()).ranges.some((r) => r.aborted),
    'abandoned seek aborted upstream'
  )
  // Force chrome visible by pausing and tapping the surface if necessary.
  await page.evaluate(() => window.movie.pause())
  await page.setViewportSize({ width: 844, height: 390 })
  await page.locator('.watch-levels--volume').waitFor({ state: 'attached' })
  assert.equal(await page.getByLabel('Picture brightness', { exact: true }).count(), 0)
  assert.equal(await page.getByRole('slider', { name: 'Volume', exact: true }).count(), 0)
  await new Promise((resolve) => setTimeout(resolve, 300))
  await page.evaluate(() => {
    if (
      Number(
        getComputedStyle(document.querySelector('.watch-levels')).opacity
      ) < 0.5
    )
      document.querySelector('.watch-player').parentElement.click()
  })
  await new Promise((resolve) => setTimeout(resolve, 300))
  assert.equal(
    await page
      .locator('.watch-levels')
      .first()
      .evaluate((e) => getComputedStyle(e).opacity),
    '1'
  )
  const mute = page.locator('.watch-levels--volume button[aria-pressed]')
  const initiallyMuted = await page.locator('video').evaluate(video => video.muted)
  await mute.click()
  assert.equal(await page.locator('video').evaluate(video => video.muted), !initiallyMuted)
  await mute.click()
  assert.equal(await page.locator('video').evaluate(video => video.muted), initiallyMuted)
  await page.screenshot({ path: join(artifacts, 'player-landscape.png') })
  const geometry = await page.evaluate(() =>
    Array.from(
      document.querySelectorAll(
        '.watch-levels--volume button[aria-pressed],[aria-label="Share camera"],[aria-label="Seek"]'
      )
    ).map((e) => ({
      name: e.getAttribute('aria-label'),
      x: e.getBoundingClientRect().x,
      y: e.getBoundingClientRect().y,
      w: e.getBoundingClientRect().width,
      h: e.getBoundingClientRect().height
    }))
  )
  console.log('player geometry', geometry)
  assert.ok(
    geometry.every(
      (r) => r.x >= 0 && r.y >= 0 && r.x + r.w <= 844 && r.y + r.h <= 390
    )
  )
  await page.setViewportSize({ width: 1280, height: 800 })
  const desktopVolume = page.getByRole('slider', { name: 'Volume', exact: true })
  await desktopVolume.waitFor()
  const volumeBounds = await desktopVolume.boundingBox()
  await desktopVolume.click({ position: { x: volumeBounds.width / 2, y: volumeBounds.height / 2 } })
  assert.ok(Math.abs(await page.locator('video').evaluate(video => video.volume) - 0.5) < 0.05)
  assert.equal(await page.locator('video').evaluate(video => video.muted), false)
  assert.equal(await page.locator('video').evaluate(video => getComputedStyle(video).filter), 'none')
  console.log('PASS phone sliders absent, mute toggles playback audio, desktop volume adjusts audio, no brightness filter')
  await page.setViewportSize({ width: 844, height: 390 })
  await page.goto(base + '/series')
  await page
    .getByRole('button', { name: 'Details for Lanterns', exact: true })
    .waitFor()
  await page.setViewportSize({ width: 390, height: 844 })
  await page.screenshot({ path: join(artifacts, 'library.png') })
  assert.equal(
    await page
      .locator('.phone-catalog-nav')
      .evaluate((e) => e.getBoundingClientRect().bottom),
    844
  )
  console.log('PASS phone library and player geometry')
  assert.deepEqual(errors, [])
} finally {
  await browser.close()
  fixtureServer.closeAllConnections()
  await new Promise((resolve) => fixtureServer.close(resolve))
}
console.log('Screenshots:', artifacts)
