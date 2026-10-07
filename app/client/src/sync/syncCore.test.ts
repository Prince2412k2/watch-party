import test from 'node:test'
import assert from 'node:assert/strict'

import { acceptsSchedule, decideSyncAction } from './syncCore.ts'
import { selectBufferedResumeTarget } from './bufferSeek.ts'

const playing = { positionTicks: 100_000_000, t0: 1_000, phase: 'playing', version: 7 }

test('decoder recovery resumes without seeking even when the frozen position moved', () => {
  for (const isHost of [true, false]) {
    for (const phase of ['playing', 'stalled', 'paused']) {
      const intent = decideSyncAction({
        schedule: { ...playing, phase }, serverNowMs: () => 2_000,
        clockReady: () => true, currentTime: 5, paused: true,
        isHost, mode: 'dragging', suppressHardSeek: true,
      })
      assert.equal(intent?.seekTo, undefined)
      assert.equal(intent?.play === true, phase === 'playing')
    }
  }
})

test('the Follow host honors the same recovery cooldown as its guests', () => {
  const intent = decideSyncAction({
    schedule: playing, serverNowMs: () => 2_000, clockReady: () => true,
    currentTime: 5, paused: false, isHost: true, mode: 'dragging',
    suppressHardSeek: true,
  })
  assert.equal(intent?.seekTo, undefined)
})

test('an aligned player resumes without seeking and triggering another Follow stall', () => {
  for (const isHost of [true, false]) {
    for (const drift of [-0.39, 0, 0.39]) {
      const intent = decideSyncAction({
        schedule: playing, serverNowMs: () => 2_000, clockReady: () => true,
        currentTime: 11 - drift, paused: true, isHost, mode: 'dragging',
      })
      assert.equal(intent?.play, true)
      assert.equal(intent?.seekTo, undefined)
    }
  }
})

test('a paused Follow player still seeks when it needs to catch up', () => {
  const intent = decideSyncAction({
    schedule: playing, serverNowMs: () => 2_000, clockReady: () => true,
    currentTime: 10, paused: true, isHost: false, mode: 'dragging',
  })
  assert.equal(intent?.play, true)
  assert.equal(intent?.seekTo, 11)
})

test('schedule ordering rejects a delayed older media generation', () => {
  assert.equal(acceptsSchedule(2, 10, { ...playing, mediaGeneration: 1, version: 11 }), false)
  assert.equal(acceptsSchedule(2, 10, { ...playing, mediaGeneration: 2, version: 10 }), false)
  assert.equal(acceptsSchedule(2, 10, { ...playing, mediaGeneration: 3, version: 1 }), true)
})

test('paused hopping guest with material drift requests buffer-aware catch-up', () => {
  const intent = decideSyncAction({
    schedule: playing,
    serverNowMs: () => 2_000,
    clockReady: () => true,
    currentTime: 0,
    paused: true,
    isHost: false,
    mode: 'hopping',
    userSeeking: false,
  })

  assert.ok(intent)
  assert.equal(intent.hardSeek, true)
  assert.equal(intent.seekTo, 11)
  assert.equal(intent.play, true)
})

test('resume target is clamped inside the confirmed buffered range', () => {
  const media = {
    buffered: { length: 1, start: () => 10, end: () => 14 },
  }

  assert.equal(selectBufferedResumeTarget(media, 10, 20, 0.5), 13.5)
})

test('hard-seek cooldown keeps a playing guest on bounded rate correction', () => {
  const intent = decideSyncAction({
    schedule: playing,
    serverNowMs: () => 2_000,
    clockReady: () => true,
    currentTime: 8,
    paused: false,
    isHost: false,
    mode: 'hopping',
    userSeeking: false,
    suppressHardSeek: true,
  })

  assert.ok(intent)
  assert.equal(intent.hardSeek, undefined)
  assert.equal(intent.seekTo, undefined)
  // Clamped at MAX_RATE_ADJ, which is 0.10 now: the catch-up is announced to
  // the viewer, so it no longer has to stay under the threshold of notice.
  assert.equal(intent.rate, 1.1)
})

test('drift at HARD_SEEK_SEC stays on bounded rate correction', () => {
  const intent = decideSyncAction({
    schedule: playing,
    serverNowMs: () => 2_000,
    clockReady: () => true,
    currentTime: 6,
    paused: false,
    isHost: false,
    mode: 'hopping',
    userSeeking: false,
  })

  assert.ok(intent)
  assert.equal(intent.hardSeek, undefined)
  assert.equal(intent.seekTo, undefined)
  assert.equal(intent.rate, 1.1)
})
