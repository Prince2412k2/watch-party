import test from 'node:test'
import assert from 'node:assert/strict'
import { createPlaybackStallGate, isPlaybackReady } from './playbackReadiness.ts'
import { waitForBuffer } from './bufferSeek.ts'

function video(ranges: number[][] = []) {
  return {
    currentTime: 60, duration: 120, readyState: 3, seeking: false, ended: false,
    buffered: { length: ranges.length, start: (i: number) => ranges[i][0], end: (i: number) => ranges[i][1] },
  }
}

test('short local decoder seeks do not repeatedly freeze the party', () => {
  const stalled = createPlaybackStallGate(true)
  assert.equal(stalled(false, 0), false)
  assert.equal(stalled(false, 250), false)
  assert.equal(stalled(true, 500), false)
  assert.equal(stalled(false, 900), false)
  assert.equal(stalled(true, 1200), false)
  assert.equal(stalled(false, 1500), false)
  assert.equal(stalled(false, 2499), false)
  assert.equal(stalled(false, 2500), true)
  assert.equal(stalled(true, 2750), false)
  assert.equal(stalled(false, 3000), false)
})

test('streaming readiness still reports missing network runway immediately', () => {
  const stalled = createPlaybackStallGate(false)
  assert.equal(stalled(false, 0), true)
  assert.equal(stalled(true, 10), false)
})

test('a decoded local file does not freeze a party because buffered ranges are sparse', () => {
  const media = video([[60, 61]])
  assert.equal(isPlaybackReady(media, true), true)
  assert.equal(isPlaybackReady(media, false), false)
  media.readyState = 2
  assert.equal(isPlaybackReady(media, true), false)
  media.readyState = 3
  assert.equal(isPlaybackReady(media, true), true)
})

test('local file seeks wait for the new frame and ended playback never freezes peers', () => {
  const media = video()
  media.seeking = true
  assert.equal(isPlaybackReady(media, true), false)
  media.seeking = false
  assert.equal(isPlaybackReady(media, true), true)
  media.ended = true
  media.readyState = 2
  assert.equal(isPlaybackReady(media, true), true)
  assert.equal(isPlaybackReady(media, false), true)
})

test('streaming can finish the final seconds without impossible runway past EOF', () => {
  const media = video([[115, 120]])
  media.currentTime = 118
  assert.equal(isPlaybackReady(media, false), true)
})

test('separate buffered ranges cannot hide a missing segment', () => {
  assert.equal(isPlaybackReady(video([[60, 61], [63, 66]]), false), false)
  assert.equal(isPlaybackReady(video([[60, 64]]), false), true)
})

test('local paused catch-up finishes on a decoded target without a network buffer timeout', async () => {
  const media = { ...video(), readyState: 2, currentSrc: 'blob:complete-opfs-movie' }
  assert.equal(await waitForBuffer(media, 60, 4, 20), 'ready')
  media.currentTime = 10
  assert.equal(await waitForBuffer(media, 60, 4, 20), 'timeout')
  media.currentTime = 60
  media.seeking = true
  assert.equal(await waitForBuffer(media, 60, 4, 20), 'timeout')
})
