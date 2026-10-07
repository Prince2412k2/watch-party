// Invoked by pwa-native-parity-smoke.mjs with WP_SYNC_ONLY=1. A real phone-sized
// PWA plays a complete OPFS movie against a Socket.IO peer issuing the native
// client's versioned commands. This does not run the Windows app or iOS Safari.
import assert from 'node:assert/strict'
import { setTimeout as delay } from 'node:timers/promises'

export async function runMixedSyncSmoke({ participant, base, sockets, io, ack, until }) {
  const host = await participant('PWA Host'), native = await participant('Native Protocol Peer')
  async function control(person) {
    const cookies = await person.context.cookies(base)
    const socket = io(base, {
      transports: ['websocket'], forceNew: true,
      extraHeaders: { Cookie: cookies.map(c => `${c.name}=${c.value}`).join('; ') },
    })
    sockets.push(socket)
    await new Promise((resolve, reject) => {
      socket.once('connect', resolve); socket.once('connect_error', reject)
    })
    return socket
  }
  const h = await control(host), n = await control(native)
  const { partyId } = await ack(h, 'party:create', { mediaItemId: '11111111111111111111111111111111' })
  assert.ok(partyId)
  await ack(n, 'party:join', { partyId })
  await ack(h, 'party:approve', { userId: native.user.userId })
  let pollingSid
  host.page.on('request', req => {
    const url = new URL(req.url())
    if (url.pathname === '/socket.io/' && url.searchParams.has('sid')) pollingSid = url.searchParams.get('sid')
  })
  await host.page.goto(`${base}/party/${partyId}`)
  await until(host.page, () => document.querySelector('.watch-video')?.readyState >= 3)
  assert.match(await host.page.evaluate(() => document.querySelector('.watch-video').currentSrc), /^blob:/)
  await host.page.evaluate(() => {
    window.movie = document.querySelector('.watch-video')
    // Model Safari's sparse range bookkeeping while the real local decoder
    // has future frames. This must not pause a fully downloaded movie's party.
    Object.defineProperty(window.movie, 'buffered', {
      configurable: true, get: () => ({ length: 0, start() {}, end() {} }),
    })
    window.dispatchEvent(new CustomEvent('watch:transport', { detail: { kind: 'play' } }))
  })
  await until(host.page, () => window.movie.currentTime > 2 && !window.movie.paused)
  assert.equal((await ack(h, 'party:resume')).session.schedule.phase, 'playing')

  // A genuine decoder stall still pauses peers. Parent renders (including
  // one-second peer telemetry) must not clear/re-add it repeatedly.
  await host.page.evaluate(() => {
    Object.defineProperty(window.movie, 'readyState', { configurable: true, get: () => 2 })
    window.movie.dispatchEvent(new Event('waiting'))
  })
  const phase = async () => (await ack(h, 'party:resume')).session.schedule
  let stalled
  for (let i = 0; i < 30; i++) {
    stalled = await phase()
    if (stalled.phase === 'stalled') break
    await delay(100)
  }
  assert.equal(stalled.phase, 'stalled')
  await until(host.page, () => window.movie.paused)
  for (let i = 0; i < 5; i++) {
    n.emit('sync:report', { position: stalled.positionTicks / 1e7, rate: 1, mediaGeneration: stalled.mediaGeneration })
    await delay(300)
    assert.equal((await phase()).version, stalled.version, 'render churn must not flip the stalled schedule')
  }
  await host.page.evaluate(() => {
    delete window.movie.readyState
    window.movie.dispatchEvent(new Event('canplay'))
  })
  // Recovery can briefly seek to the frozen group position. Wait for that
  // decoder transition rather than asserting during its in-flight frame load.
  let stable = 0
  for (let i = 0; i < 100 && stable < 3; i++) {
    const ready = await host.page.evaluate(() => !window.movie.paused && !window.movie.seeking && window.movie.readyState >= 3)
    stable = ready && (await phase()).phase === 'playing' ? stable + 1 : 0
    await delay(100)
  }
  assert.equal(stable, 3, 'a recovered local decoder must resume the group')
  assert.equal((await phase()).phase, 'playing')

  await ack(h, 'party:transferHost', { userId: native.user.userId })
  assert.equal((await ack(h, 'party:resume')).session.hostId, native.user.userId)
  // Close only the PWA Engine.IO transport, forcing the mounted client through
  // its real reconnect/rejoin path. Socket.IO's server-side control peer stays.
  assert.ok(pollingSid)
  await host.context.request.post(`${base}/socket.io/?EIO=4&transport=polling&sid=${pollingSid}`, {
    data: '1', headers: { 'content-type': 'text/plain;charset=UTF-8' },
  })
  const oldSid = pollingSid
  for (let i = 0; i < 100 && pollingSid === oldSid; i++) await delay(100)
  assert.notEqual(pollingSid, oldSid, 'PWA transport must reconnect')
  await delay(300)
  const joined = await ack(h, 'party:resume')
  assert.equal(joined.session.hostId, native.user.userId)
  assert.equal((await ack(h, 'sync:pause', { positionTicks: 0 })).error, 'not allowed')
  const nativePause = await ack(n, 'sync:pause', {
    positionTicks: 5e7, baseVersion: joined.session.schedule.version, commandId: 'native-pause',
  })
  assert.equal(nativePause.ok, true)
  await until(host.page, () => window.movie.paused && Math.abs(window.movie.currentTime - 5) < 0.3)
  await host.page.evaluate(() => window.dispatchEvent(new CustomEvent('watch:transport', { detail: { kind: 'play' } })))
  await delay(250)
  assert.notEqual((await phase()).phase, 'playing', 'demoted PWA UI must not author play commands')
  const nativePlay = await ack(n, 'sync:play', {
    positionTicks: 5e7, baseVersion: (await phase()).version, commandId: 'native-play',
  })
  assert.equal(nativePlay.ok, true)
  const resumedAt = Date.now()
  await until(host.page, () => !window.movie.paused && window.movie.currentTime > 6)
  assert.ok(Date.now() - resumedAt < 3000, 'decoded local catch-up must not wait for the 8-second network timeout')
  await ack(n, 'party:end')
  console.log('PASS mixed sync: OPFS sparse ranges, stable real stall/recovery, explicit host transfer, PWA transport reconnect, native versioned pause/play')
}
