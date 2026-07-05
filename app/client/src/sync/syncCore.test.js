import test from 'node:test'
import assert from 'node:assert/strict'

import { decideSyncAction } from './syncCore.js'
import { selectBufferedResumeTarget } from './bufferSeek.js'

const playing = { positionTicks: 100_000_000, t0: 1_000, phase: 'playing', version: 7 }

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

  assert.equal(intent.hardSeek, undefined)
  assert.equal(intent.seekTo, undefined)
  assert.equal(intent.rate, 1.08)
})
