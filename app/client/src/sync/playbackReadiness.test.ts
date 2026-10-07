import test from 'node:test'
import assert from 'node:assert/strict'
import { isPlaybackReady } from './playbackReadiness.ts'

function video(ranges: number[][] = []) {
  return {
    currentTime: 60, duration: 120, readyState: 3, seeking: false, ended: false,
    buffered: { length: ranges.length, start: (i: number) => ranges[i][0], end: (i: number) => ranges[i][1] },
  }
}

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
