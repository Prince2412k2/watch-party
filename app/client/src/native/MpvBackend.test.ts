import { test } from 'node:test'
import assert from 'node:assert/strict'

import { __setMockTransport } from './ipc'
import { IPC, EVENTS } from './contract.ts'
import { MpvBackend } from './MpvBackend'

// Minimal mock transport: invoke() records calls; listen() registers a
// handler per event name and returns an unlisten fn. emit() lets a test fire
// a synthetic mpv:* event as Rust would via Tauri's `emit`.
function makeMockTransport() {
  const calls = []
  const handlers = new Map() // eventName -> Set<fn>
  const invoke = async (cmd, payload) => { calls.push([cmd, payload]); return undefined }
  const listen = async (eventName, handler) => {
    if (!handlers.has(eventName)) handlers.set(eventName, new Set())
    handlers.get(eventName).add(handler)
    return () => handlers.get(eventName)?.delete(handler)
  }
  const emit = async (eventName, payload) => {
    for (const h of handlers.get(eventName) || []) h({ payload })
  }
  return { invoke, listen, calls, emit }
}

// listen() calls inside the constructor are fire-and-forget promises; give
// them a tick to resolve before a test emits, so the handler is registered.
function flush() { return new Promise((r) => setTimeout(r, 0)) }

test('mpv:seeked fires seeked and updates currentTime', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  let fired = false
  backend.addEventListener('seeked', () => { fired = true })
  await t.emit(EVENTS.MPV_SEEKED, { sec: 42.5 })

  assert.equal(fired, true)
  assert.equal(backend.currentTime, 42.5)
})

test('setting currentTime invokes MPV_SEEK with the seconds payload', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  backend.currentTime = 12.3
  await flush()

  const seekCall = t.calls.find(([cmd]) => cmd === IPC.MPV_SEEK)
  assert.ok(seekCall, 'expected an MPV_SEEK invoke call')
  assert.deepEqual(seekCall[1], { sec: 12.3 })
  assert.equal(backend.currentTime, 12.3)
})

test('play() invokes MPV_PLAY and clears paused', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  await backend.play()

  assert.ok(t.calls.some(([cmd]) => cmd === IPC.MPV_PLAY))
  assert.equal(backend.paused, false)
})

test('pause() invokes MPV_PAUSE and sets paused', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  backend.pause()
  await flush()

  assert.ok(t.calls.some(([cmd]) => cmd === IPC.MPV_PAUSE))
  assert.equal(backend.paused, true)
})

test('mpv:pause event relays to standard play/pause events', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  const seen = []
  backend.addEventListener('pause', () => seen.push('pause'))
  backend.addEventListener('play', () => seen.push('play'))

  await t.emit(EVENTS.MPV_PAUSE, { paused: true })
  await t.emit(EVENTS.MPV_PAUSE, { paused: false })

  assert.deepEqual(seen, ['pause', 'play'])
  assert.equal(backend.paused, false)
})

test('mpv:timepos relays as timeupdate and updates currentTime', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  let ticks = 0
  backend.addEventListener('timeupdate', () => { ticks += 1 })
  await t.emit(EVENTS.MPV_TIMEPOS, { sec: 7 })

  assert.equal(ticks, 1)
  assert.equal(backend.currentTime, 7)
})

test('mpv:duration and mpv:loadedmetadata relay + update duration', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  const seen = []
  backend.addEventListener('durationchange', () => seen.push('durationchange'))
  backend.addEventListener('loadedmetadata', () => seen.push('loadedmetadata'))

  await t.emit(EVENTS.MPV_DURATION, { sec: 100 })
  assert.equal(backend.duration, 100)
  await t.emit(EVENTS.MPV_LOADEDMETADATA, { durationSec: 120 })
  assert.equal(backend.duration, 120)

  assert.deepEqual(seen, ['durationchange', 'loadedmetadata'])
})

test('mpv:buffering relays as waiting/playing', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  const seen = []
  backend.addEventListener('waiting', () => seen.push('waiting'))
  backend.addEventListener('playing', () => seen.push('playing'))

  await t.emit(EVENTS.MPV_BUFFERING, { active: true })
  await t.emit(EVENTS.MPV_BUFFERING, { active: false })

  assert.deepEqual(seen, ['waiting', 'playing'])
})

test('mpv:eof relays as ended and sets paused', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  let ended = false
  backend.addEventListener('ended', () => { ended = true })
  await t.emit(EVENTS.MPV_EOF, {})

  assert.equal(ended, true)
  assert.equal(backend.paused, true)
})

test('mpv:speed relays as ratechange and updates playbackRate', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  let fired = false
  backend.addEventListener('ratechange', () => { fired = true })
  await t.emit(EVENTS.MPV_SPEED, { rate: 1.5 })

  assert.equal(fired, true)
  assert.equal(backend.playbackRate, 1.5)
})

test('setting playbackRate invokes MPV_SET_SPEED', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  backend.playbackRate = 2
  await flush()

  const call = t.calls.find(([cmd]) => cmd === IPC.MPV_SET_SPEED)
  assert.deepEqual(call[1], { rate: 2 })
})

test('buffered reflects the last mpv:cache event', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  assert.equal(backend.buffered.length, 0)

  await t.emit(EVENTS.MPV_TIMEPOS, { sec: 10 })
  await t.emit(EVENTS.MPV_CACHE, { cachedAheadSec: 30, cachedBytes: 1024 })

  assert.equal(backend.buffered.length, 1)
  assert.equal(backend.buffered.start(0), 10)
  assert.equal(backend.buffered.end(0), 40)
})

test('mpv:cache fires progress', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  let fired = false
  backend.addEventListener('progress', () => { fired = true })
  await t.emit(EVENTS.MPV_CACHE, { cachedAheadSec: 5, cachedBytes: 10 })

  assert.equal(fired, true)
})

test('load() invokes MPV_LOAD with url/startSec/paused and seeds local state', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  backend.load('https://example.test/stream', { startSec: 5, paused: true })
  await flush()

  const call = t.calls.find(([cmd]) => cmd === IPC.MPV_LOAD)
  assert.deepEqual(call[1], { url: 'https://example.test/stream', startSec: 5, paused: true })
  assert.equal(backend.currentTime, 5)
  assert.equal(backend.paused, true)
})

test('removeEventListener stops further delivery', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  let count = 0
  const cb = () => { count += 1 }
  backend.addEventListener('seeked', cb)
  await t.emit(EVENTS.MPV_SEEKED, { sec: 1 })
  backend.removeEventListener('seeked', cb)
  await t.emit(EVENTS.MPV_SEEKED, { sec: 2 })

  assert.equal(count, 1)
})

test('destroy() invokes MPV_TEARDOWN', async () => {
  const t = makeMockTransport()
  __setMockTransport(t)
  const backend = new MpvBackend()
  await flush()

  backend.destroy()
  await flush()

  assert.ok(t.calls.some(([cmd]) => cmd === IPC.MPV_TEARDOWN))
})
