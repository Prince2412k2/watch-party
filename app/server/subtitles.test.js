import test from 'node:test'
import assert from 'node:assert/strict'

import {
  findExternalSubtitleStream,
  resolveJellyfinDeliveryUrl,
  srtToVtt,
  subtitleMutationError,
} from './subtitles.js'

test('srtToVtt removes sequence numbers and converts comma timestamps', () => {
  const result = srtToVtt('\uFEFF1\r\n00:00:01,250 --> 00:00:03,500\r\nHello!\r\n\r\n2\r\n00:01:02,000 --> 00:01:05,125\r\nAgain')
  assert.equal(result, 'WEBVTT\n\n00:00:01.250 --> 00:00:03.500\nHello!\n\n00:01:02.000 --> 00:01:05.125\nAgain\n')
})

test('findExternalSubtitleStream requires an exact external stream index with a delivery URL', () => {
  const playback = { MediaSources: [{ MediaStreams: [
    { Type: 'Subtitle', Index: 4, IsExternal: false, DeliveryUrl: '/Videos/a/Subtitles/4/Stream.vtt' },
    { Type: 'Subtitle', Index: 7, IsExternal: true, DeliveryUrl: '/Videos/a/Subtitles/7/Stream.vtt' },
    { Type: 'Audio', Index: 7, IsExternal: true, DeliveryUrl: '/audio' },
  ] }] }

  assert.equal(findExternalSubtitleStream(playback, 7)?.Index, 7)
  assert.equal(findExternalSubtitleStream(playback, 4), null)
  assert.equal(findExternalSubtitleStream(playback, 8), null)
})

test('resolveJellyfinDeliveryUrl accepts only URLs under the configured Jellyfin base', () => {
  const relative = resolveJellyfinDeliveryUrl('/jellyfin/Videos/a/Subtitles/7/Stream.vtt?api_key=client', 'server-token', 'https://media.test/jellyfin')
  assert.equal(relative?.href, 'https://media.test/jellyfin/Videos/a/Subtitles/7/Stream.vtt?api_key=server-token')

  assert.equal(resolveJellyfinDeliveryUrl('https://evil.test/subtitle.vtt', 'token', 'https://media.test/jellyfin'), null)
  assert.equal(resolveJellyfinDeliveryUrl('/outside/subtitle.vtt', 'token', 'https://media.test/jellyfin'), null)
  assert.equal(resolveJellyfinDeliveryUrl('/jellyfin/../outside/subtitle.vtt', 'token', 'https://media.test/jellyfin'), null)
})

test('subtitleMutationError maps Jellyfin client and server failures safely', () => {
  assert.deepEqual(subtitleMutationError(400), { status: 422, error: 'Jellyfin rejected the subtitle file' })
  assert.equal(subtitleMutationError(403).status, 403)
  assert.equal(subtitleMutationError(404).status, 404)
  assert.equal(subtitleMutationError(500).status, 502)
  assert.equal(subtitleMutationError(undefined).status, 502)
})
