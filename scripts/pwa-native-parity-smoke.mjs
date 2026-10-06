// Native-player parity regression with two real Socket.IO/LiveKit clients.
// Requires built app/client, installed app dependencies, Playwright, Chromium,
// and a local LiveKit dev server (livekit-server --dev --bind 127.0.0.1).
// Use the 36-second >12 MiB H.264/AAC fixture from pwa-playback-smoke.mjs:
//   WP_MOVIE_FILE=/tmp/pwa.mp4 node scripts/pwa-native-parity-smoke.mjs
// WP_PARTIAL=1 repeats the flow using an incomplete download.
// Optional: CHROMIUM, PLAYWRIGHT_MODULE, LIVEKIT_URL/KEY/SECRET.
// All accounts, app data and upstream media are isolated local fixtures.
import assert from 'node:assert/strict'
import { createServer } from 'node:http'
import { createServer as createNetServer } from 'node:net'
import { readFileSync, mkdtempSync, createWriteStream } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { createRequire } from 'node:module'
import { spawn } from 'node:child_process'
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright')
const { io } = createRequire(resolve('app/package.json'))('socket.io-client')
const artifacts = mkdtempSync(join(tmpdir(), 'wp-native-parity-'))
console.log('Artifacts:', artifacts)
const movieId = '11111111111111111111111111111111',
  sourceId = '22222222222222222222222222222222'
const file = readFileSync(process.env.WP_MOVIE_FILE)
const source = {
  Id: sourceId,
  Container: 'mp4',
  Path: '/fixture.mp4',
  RunTimeTicks: 360000000,
  SupportsDirectPlay: true,
  SupportsDirectStream: true,
  DefaultAudioStreamIndex: 1,
  MediaStreams: [
    {
      Index: 0,
      Type: 'Video',
      Codec: 'h264',
      BitDepth: 8,
      PixelFormat: 'yuv420p',
    },
    { Index: 1, Type: 'Audio', Codec: 'aac', Profile: 'LC', IsDefault: true },
  ],
}
const item = {
  Id: movieId,
  Name: 'Party Movie',
  Type: 'Movie',
  RunTimeTicks: 360000000,
  MediaSources: [source],
}
const fixture = createServer((req, res) => {
  const p = new URL(req.url, 'http://localhost').pathname
  const json = (value) => {
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify(value))
  }
  if (p === '/__test/fixture') {
    res.setHeader('content-type', 'video/mp4')
    return res.end(file)
  }
  if (p.endsWith('/PlaybackInfo'))
    return json({ PlaySessionId: 'fixture-play', MediaSources: [source] })
  if (p.endsWith('/Views'))
    return json({
      Items: [
        {
          Id: 'movies',
          Name: 'Movies',
          Type: 'CollectionFolder',
          CollectionType: 'movies',
        },
        {
          Id: 'shows',
          Name: 'Shows',
          Type: 'CollectionFolder',
          CollectionType: 'tvshows',
        },
      ],
      TotalRecordCount: 2,
    })
  if (p.endsWith('/Items') || p.endsWith('/Latest') || p.endsWith('/Resume'))
    return json({ Items: [], TotalRecordCount: 0 })
  if (p.includes('/Items/') && !p.includes('/Images/')) return json(item)
  if (p.includes('/Videos/') && p.endsWith('/stream.mp4')) {
    const headers = {
      'content-type': 'video/mp4',
      'accept-ranges': 'bytes',
      etag: '"fixture"',
    }
    if (req.method === 'HEAD') {
      res.writeHead(200, { ...headers, 'content-length': file.length })
      return res.end()
    }
    const range = /bytes=(\d+)-(\d*)/.exec(req.headers.range ?? 'bytes=0-'),
      start = Number(range[1]),
      end = Math.min(
        file.length - 1,
        range[2] ? Number(range[2]) : file.length - 1
      )
    res.writeHead(206, {
      ...headers,
      'content-length': end - start + 1,
      'content-range': `bytes ${start}-${end}/${file.length}`,
    })
    return res.end(file.subarray(start, end + 1))
  }
  if (p.startsWith('/Users/'))
    return json({ Policy: { IsAdministrator: false } })
  return json({})
})
await new Promise((resolve) => fixture.listen(0, '127.0.0.1', resolve))
const upstream = `http://127.0.0.1:${fixture.address().port}`
const reservation = createNetServer()
await new Promise((resolve) => reservation.listen(0, '127.0.0.1', resolve))
const port = reservation.address().port
await new Promise((resolve) => reservation.close(resolve))
const base = `http://127.0.0.1:${port}`
const app = spawn(process.execPath, ['server/index.js'], {
  cwd: resolve('app'),
  env: {
    ...process.env,
    NODE_ENV: 'test',
    WP_TEST_MODE: '1',
    SERVE_CLIENT: '1',
    PORT: String(port),
    PUBLIC_ORIGIN: base,
    JELLYFIN_URL: upstream,
    LIVEKIT_URL: process.env.LIVEKIT_URL || 'ws://127.0.0.1:7880',
    LIVEKIT_PUBLIC_URL: process.env.LIVEKIT_URL || 'ws://127.0.0.1:7880',
    LIVEKIT_API_KEY: process.env.LIVEKIT_KEY || 'devkey',
    LIVEKIT_API_SECRET: process.env.LIVEKIT_SECRET || 'secret',
    SESSION_SECRET: 'isolated-native-parity-fixture',
    SESSION_STORE_DIR: join(artifacts, 'sessions'),
    PARTY_DB_PATH: join(artifacts, 'parties.sqlite'),
  },
  stdio: ['ignore', 'pipe', 'pipe'],
})
const logs = createWriteStream(join(artifacts, 'server.log'))
app.stdout.pipe(logs)
app.stderr.pipe(logs)
async function cleanup() {
  if (app.exitCode === null) {
    app.kill('SIGTERM')
    await new Promise((resolve) => {
      app.once('exit', resolve)
      setTimeout(() => {
        app.kill('SIGKILL')
        resolve()
      }, 3000).unref()
    })
  }
  await new Promise((resolve) => fixture.close(resolve))
  logs.end()
}
try {
  let ready = false
  for (let i = 0; i < 100; i++) {
    try {
      await fetch(base + '/api/auth/me')
      ready = true
      break
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100))
    }
  }
  assert.ok(ready, 'Fixture app did not start; inspect server.log')
} catch (error) {
  await cleanup()
  throw error
}
const browser = await chromium
  .launch({
    executablePath: process.env.CHROMIUM || undefined,
    args: [
      '--no-sandbox',
      '--autoplay-policy=no-user-gesture-required',
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
    ],
  })
  .catch(async (error) => {
    await cleanup()
    throw error
  })
const contexts = [],
  sockets = []
async function until(page, fn, arg) {
  const end = Date.now() + 30000
  while (Date.now() < end) {
    if (await page.evaluate(fn, arg)) return
    await new Promise((r) => setTimeout(r, 100))
  }
  throw new Error(
    'Timed out: ' +
      fn.toString() +
      ' text=' +
      (await page.locator('body').innerText())
  )
}
const ack = (socket, event, data = {}) =>
  new Promise((resolve, reject) =>
    socket
      .timeout(5000)
      .emit(event, data, (error, value) =>
        error ? reject(error) : resolve(value)
      )
  )
async function participant(name) {
  const context = await browser.newContext({
    viewport: { width: 844, height: 390 },
    isMobile: true,
    hasTouch: true,
    permissions: ['camera', 'microphone'],
  })
  contexts.push(context)
  const login = await context.request.post(base + '/api/auth/test-login', {
      data: { name },
    }),
    user = await login.json()
  assert.equal(login.status(), 200)
  const page = await context.newPage()
  page.on('console', (m) => {
    if (m.type() === 'error') console.log('browser', m.text())
  })
  await page.goto(base + '/saved')
  await until(page, () => !!navigator.serviceWorker.controller)
  const info = await (
    await context.request.get(
      `${base}/api/offline/${movieId}/info?source=${sourceId}`
    )
  ).json()
  assert.equal(info.owner, user.userId)
  assert.ok(info.size > 0)
  const bytes = await (await fetch(upstream + '/__test/fixture')).arrayBuffer()
  const partial = !!process.env.WP_PARTIAL && name.startsWith('Camera Host')
  const key = await page.evaluate(
    async ({ info, encoded, partial }) => {
      const bytes = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0)),
        key = `${info.owner}:${info.itemId}:${info.sourceId}:${info.revision}`,
        chunk = 2 * 1024 * 1024
      await new Promise((resolve, reject) => {
        const open = indexedDB.open('watchparty-media')
        open.onsuccess = () => {
          const db = open.result,
            tx = db.transaction(['media', 'chunks'], 'readwrite')
          tx.objectStore('media').put({
            ...info,
            key,
            generation: crypto.randomUUID(),
            retention: 'download',
            state: partial ? 'paused' : 'complete',
            received: partial ? chunk : info.size,
            accessed: Date.now(),
            resumeOnOpen: false,
          })
          for (
            let index = 0;
            index * chunk < (partial ? chunk : info.size);
            index++
          )
            tx.objectStore('chunks').put({
              media: key,
              index,
              data: new Blob([
                bytes.slice(
                  index * chunk,
                  Math.min(info.size, (index + 1) * chunk)
                ),
              ]),
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
    { info, encoded: Buffer.from(bytes).toString('base64'), partial }
  )
  await page.reload()
  await until(
    page,
    (key) =>
      new Promise((resolve) => {
        const open = indexedDB.open('watchparty-media')
        open.onsuccess = () => {
          const db = open.result,
            r = db.transaction('media').objectStore('media').get(key)
          r.onsuccess = () => {
            resolve(r.result?.fileChunks?.length >= 1)
            db.close()
          }
        }
      }),
    key
  )
  return { page, user, context, key }
}
try {
  const host = await participant('Camera Host ' + Date.now()),
    guest = await participant('Camera Guest ' + Date.now())
  await host.page.goto(`${base}/saved/watch/${encodeURIComponent(host.key)}`)
  await until(
    host.page,
    () => document.querySelector('.watch-video')?.readyState >= 2
  )
  await host.page.evaluate(() => {
    window.movie = document.querySelector('.watch-video')
    window.movie.pause()
    window.movie.currentTime = 15
    window.originalSource = window.movie.currentSrc
  })
  await until(host.page, () => !window.movie.seeking)
  // A paused movie can have its chrome hidden from the previous playing state.
  await host.page
    .getByRole('button', { name: 'Share camera', exact: true })
    .evaluate((button) => button.click())
  await host.page
    .getByRole('button', { name: 'Turn camera off', exact: true })
    .waitFor({ timeout: 30000 })
  const state = await host.page.evaluate(() => ({
    same: window.movie === document.querySelector('.watch-video'),
    src: window.movie.currentSrc,
    original: window.originalSource,
    t: window.movie.currentTime,
    paused: window.movie.paused,
    url: location.pathname,
    videos: document.querySelectorAll('video').length,
  }))
  console.log('camera handoff', state)
  assert.equal(state.same, true)
  assert.equal(state.src, state.original)
  assert.equal(state.paused, true)
  assert.ok(Math.abs(state.t - 15) < 0.1)
  assert.match(state.url, /saved\/watch/)
  assert.ok(state.videos > 1)
  const cookies = await host.context.cookies(base)
  const control = io(base, {
    transports: ['websocket'],
    extraHeaders: {
      Cookie: cookies.map((c) => `${c.name}=${c.value}`).join('; '),
    },
    forceNew: true,
  })
  sockets.push(control)
  await new Promise((resolve, reject) => {
    control.once('connect', resolve)
    control.once('connect_error', reject)
  })
  const room = await ack(control, 'party:resume')
  assert.ok(room.session?.id)
  await guest.page.goto(`${base}/party/${room.session.id}`)
  for (let i = 0; i < 100; i++) {
    const state = await ack(control, 'party:resume')
    if (state.session?.waiting?.some((w) => w.userId === guest.user.userId))
      break
    await new Promise((r) => setTimeout(r, 100))
  }
  assert.equal(
    (await ack(control, 'party:approve', { userId: guest.user.userId })).ok,
    true
  )
  await until(
    guest.page,
    () => document.querySelector('.watch-video')?.readyState >= 2
  )
  await until(guest.page, () => document.querySelectorAll('video').length > 1)
  await host.page.evaluate(() =>
    window.dispatchEvent(
      new CustomEvent('watch:transport', { detail: { kind: 'play' } })
    )
  )
  await Promise.all(
    [host, guest].map((p) =>
      until(
        p.page,
        () =>
          document.querySelector('.watch-video')?.currentTime > 16 &&
          !document.querySelector('.watch-video')?.paused
      )
    )
  )
  await host.page
    .getByRole('button', { name: 'Turn camera off', exact: true })
    .evaluate((button) => button.click())
  await until(
    host.page,
    () =>
      !document.querySelector(
        '.native-device-rail button[aria-label="Share microphone"]'
      )?.disabled
  )
  await host.page
    .getByRole('button', { name: 'Share microphone', exact: true })
    .evaluate((button) => button.click())
  await host.page
    .getByRole('button', { name: 'Mute microphone', exact: true })
    .waitFor({ state: 'attached', timeout: 20000 })
  const after = await host.page.evaluate(() => ({
    same: window.movie === document.querySelector('.watch-video'),
    src: window.movie.currentSrc,
    original: window.originalSource,
    t: window.movie.currentTime,
    paused: window.movie.paused,
  }))
  assert.equal(after.same, true)
  assert.equal(after.src, after.original)
  assert.equal(after.paused, false)
  assert.ok(after.t > 16)
  console.log(
    'PASS real LiveKit camera and microphone: same video/URL, paused position preserved, guest receives camera and synchronized local playback'
  )
  await host.page.evaluate(() =>
    window.dispatchEvent(
      new CustomEvent('watch:transport', { detail: { kind: 'pause' } })
    )
  )
  await until(host.page, () => window.movie.paused)
  await host.page.evaluate(() => {
    window.loads = 0
    window.movie.addEventListener('loadstart', () => window.loads++)
  })
  const stable = async () => {
    assert.equal(
      await host.page.evaluate(
        () => window.movie === document.querySelector('.watch-video')
      ),
      true
    )
    assert.equal(
      await host.page.evaluate(
        () => window.movie.currentSrc === window.originalSource
      ),
      true
    )
    assert.equal(await host.page.evaluate(() => window.loads), 0)
  }
  await host.page
    .getByRole('button', { name: 'Minimize movie', exact: true })
    .click()
  await host.page.locator('.player-host-frame.is-floating').waitFor()
  await stable()
  assert.ok((await ack(control, 'party:resume')).session.id)
  await host.page.getByRole('button', { name: 'Shows', exact: true }).click()
  await host.page
    .getByRole('searchbox', { name: 'Search Shows', exact: true })
    .waitFor()
  assert.equal(new URL(host.page.url()).pathname, '/series')
  await stable()
  await ack(control, 'party:setCollaborative', { enabled: true })
  await new Promise((r) => setTimeout(r, 300))
  assert.equal(new URL(host.page.url()).pathname, '/series')
  const beforeFloat = await host.page
    .locator('.player-host-frame')
    .boundingBox()
  assert.ok(beforeFloat.width <= 300 && beforeFloat.height < 220)
  // Dragging snaps to a corner without expanding/reloading the video.
  await host.page.mouse.move(beforeFloat.x + 24, beforeFloat.y + 20)
  await host.page.mouse.down()
  await host.page.mouse.move(36, 50, { steps: 12 })
  await host.page.mouse.up()
  const moved = await host.page.locator('.player-host-frame').boundingBox()
  assert.equal(Math.round(moved.x), 12)
  await stable()
  // Simulate notch/home-indicator insets independently of Chromium's zeros.
  await host.page.evaluate(() => {
    document.documentElement.style.setProperty('--sa-t', '47px')
    document.documentElement.style.setProperty('--sa-b', '34px')
  })
  await until(
    host.page,
    () =>
      document.querySelector('.player-host-frame').getBoundingClientRect()
        .top >= 59
  )
  await host.page.evaluate(() => {
    document.documentElement.style.removeProperty('--sa-t')
    document.documentElement.style.removeProperty('--sa-b')
  })
  await host.page
    .getByRole('button', { name: 'Expand movie', exact: true })
    .click()
  await host.page
    .locator('.player-host-frame.is-floating')
    .waitFor({ state: 'detached' })
  await stable()
  const beforeChat = await host.page.locator('.watch-video').boundingBox()
  await host.page.getByRole('button', { name: 'Chat', exact: true }).click()
  await host.page.getByRole('textbox', { name: 'Message the room' }).waitFor()
  assert.equal(
    await host.page
      .getByRole('textbox', { name: 'Message the room' })
      .evaluate((e) => e === document.activeElement),
    true
  )
  assert.deepEqual(
    await host.page.locator('.watch-video').boundingBox(),
    beforeChat
  )
  await host.page
    .getByRole('textbox', { name: 'Message the room' })
    .fill('Parity chat message')
  await host.page
    .getByRole('textbox', { name: 'Message the room' })
    .press('Enter')
  await host.page
    .locator('.native-chat-message')
    .filter({ hasText: 'Parity chat message' })
    .waitFor()
  await guest.page.getByText('Parity chat message', { exact: true }).waitFor()
  assert.equal(await guest.page.locator('.native-chat').count(), 0)
  await host.page.screenshot({ path: join(artifacts, 'chat-landscape.png') })
  await host.page
    .getByRole('button', { name: 'Close chat', exact: true })
    .click()
  await host.page.locator('.native-chat').waitFor({ state: 'detached' })
  await stable()
  // Camera-off participants still have audible remote audio independent of tiles.
  await until(guest.page, () =>
    Array.from(document.querySelectorAll('audio')).some((a) =>
      a.srcObject?.getAudioTracks().some((t) => t.readyState === 'live')
    )
  )
  assert.equal(await guest.page.locator('.native-camera').count(), 0)
  await host.page
    .getByRole('button', { name: 'Share camera', exact: true })
    .click()
  await host.page
    .getByRole('button', { name: 'Turn camera off', exact: true })
    .waitFor()
  await host.page.locator('.native-camera').waitFor()
  await host.page.getByRole('button', { name: 'Chat', exact: true }).click()
  await new Promise((r) => setTimeout(r, 400))
  const camera = await host.page.locator('.native-camera').boundingBox(),
    chat = await host.page.locator('.native-chat').boundingBox()
  assert.ok(camera.x + camera.width <= chat.x)
  await host.page
    .getByRole('button', { name: 'Close chat', exact: true })
    .click()
  await host.page.locator('.native-chat').waitFor({ state: 'detached' })
  await host.page.locator('.native-camera-collapse').click()
  assert.equal(
    Math.round((await host.page.locator('.native-camera').boundingBox()).width),
    60
  )
  await host.page.locator('.native-camera-expand').click()
  assert.ok(
    (await host.page.locator('.native-camera').boundingBox()).width >= 112
  )
  await host.page
    .getByRole('button', { name: 'Hide my tile', exact: true })
    .click()
  assert.equal(await host.page.locator('.native-camera').count(), 0)
  await until(
    guest.page,
    () => document.querySelector('.native-camera video')?.readyState >= 2
  )
  await host.page
    .getByRole('button', { name: 'Show my tile', exact: true })
    .click()
  await host.page.locator('.native-camera').waitFor()
  await host.page
    .getByRole('button', { name: 'Mute microphone', exact: true })
    .click()
  await host.page
    .getByRole('button', { name: 'Share microphone', exact: true })
    .waitFor()
  await host.page.keyboard.down('t')
  await host.page
    .getByRole('button', { name: 'Mute microphone', exact: true })
    .waitFor()
  await host.page.keyboard.up('t')
  await host.page
    .getByRole('button', { name: 'Share microphone', exact: true })
    .waitFor()
  await stable()
  await host.page
    .getByRole('button', { name: 'Watch party', exact: true })
    .click()
  await host.page
    .getByRole('button', { name: 'Watch party controls', exact: true })
    .click()
  await host.page
    .getByRole('dialog', { name: 'Watch party controls', exact: true })
    .waitFor()
  await host.page.evaluate(
    () =>
      (window.previousCamera = document.querySelector('.native-camera video'))
  )
  await host.page
    .getByRole('button', { name: 'Reconnect my video and audio', exact: true })
    .click()
  await until(
    host.page,
    () =>
      document.querySelector('.native-camera video') !== window.previousCamera
  )
  await until(
    host.page,
    () => document.querySelector('.native-camera video')?.readyState >= 2
  )
  await stable()
  await host.page
    .getByRole('button', { name: 'Close party controls', exact: true })
    .click()
  await host.page.screenshot({ path: join(artifacts, 'player-landscape.png') })
  await host.page.setViewportSize({ width: 390, height: 844 })
  await host.page.getByRole('button', { name: 'Chat', exact: true }).click()
  await new Promise((r) => setTimeout(r, 400))
  const portraitCamera = await host.page
      .locator('.native-camera')
      .boundingBox(),
    portraitChat = await host.page.locator('.native-chat').boundingBox()
  assert.ok(portraitChat.x >= 0 && portraitChat.x + portraitChat.width <= 390)
  assert.ok(portraitCamera.x + portraitCamera.width <= portraitChat.x)
  await host.page.screenshot({ path: join(artifacts, 'chat-portrait.png') })
  await host.page
    .getByRole('button', { name: 'Close chat', exact: true })
    .click()
  await guest.page.evaluate(() =>
    document.querySelector('.watch-player').parentElement.click()
  )
  await guest.page
    .getByRole('button', { name: 'Watch party', exact: true })
    .evaluate((e) => e.click())
  await guest.page
    .getByRole('button', { name: 'Leave party', exact: true })
    .click()
  await until(guest.page, () => !document.querySelector('.watch-video'))
  const remaining = await ack(control, 'party:resume')
  assert.equal(remaining.session.id, room.session.id)
  assert.equal(remaining.session.guests.length, 0)
  await stable()
  const cameraTrack = await host.page.evaluate(
    () =>
      document
        .querySelector('.native-camera video')
        .srcObject.getVideoTracks()[0].id
  )
  await host.page
    .getByRole('button', { name: 'Minimize movie', exact: true })
    .click()
  await host.page
    .getByRole('button', { name: 'Stop watching', exact: true })
    .click()
  await until(host.page, () => !document.querySelector('.watch-video'))
  await until(
    host.page,
    () => document.querySelector('.native-camera video')?.readyState >= 2
  )
  assert.equal(
    await host.page.evaluate(
      () =>
        document
          .querySelector('.native-camera video')
          .srcObject.getVideoTracks()[0].id
    ),
    cameraTrack
  )
  assert.equal((await ack(control, 'party:resume')).session.stage, 'lobby')
  console.log(
    'PASS native parity: minimize/browse/expand preserve video and room; chat overlays without resizing/focus stealing; independent camera collapse/hide and audio; reconnect preserves movie; portrait bounds; guest leave retains host'
  )
} catch (err) {
  console.log(
    'camera failed',
    await Promise.all(
      contexts.map((c) => c.pages()[0].locator('body').innerText())
    )
  )
  throw err
} finally {
  for (const socket of sockets) socket.disconnect()
  await browser.close()
  await cleanup()
}
