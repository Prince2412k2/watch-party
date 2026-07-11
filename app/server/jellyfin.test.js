import test from 'node:test'
import assert from 'node:assert/strict'

import { buildHlsUrl, normalizePlaybackInfo } from './jellyfin.js'

test('HLS URLs ask Jellyfin to advertise subtitle renditions', () => {
  for (const options of [{ abr: true }, { maxBitrate: 1_500_000 }, {}]) {
    const url = new URL(buildHlsUrl('media-id', options), 'http://watch-party.test')

    assert.equal(url.searchParams.get('EnableSubtitlesInManifest'), 'true')
  }
})

test('HLS URLs can carry Jellyfin stream indexes and media-source ids', () => {
  const url = new URL(buildHlsUrl('item-id', {
    mediaSourceId: 'source-id',
    audioStreamIndex: 7,
    subtitleStreamIndex: -1,
  }), 'http://watch-party.test')

  assert.equal(url.searchParams.get('MediaSourceId'), 'source-id')
  assert.equal(url.searchParams.get('AudioStreamIndex'), '7')
  assert.equal(url.searchParams.get('SubtitleStreamIndex'), '-1')
})

test('normalizePlaybackInfo preserves Jellyfin stream indices instead of array positions', () => {
  const playback = normalizePlaybackInfo({
    MediaSources: [{
      Id: 'source-id',
      MediaStreams: [
        { Type: 'Video', Index: 3 },
        { Type: 'Audio', Index: 11, DisplayTitle: 'English' },
        { Type: 'Subtitle', Index: 19, DisplayTitle: 'English SDH' },
      ],
    }],
    PlaySessionId: 'play-session-id',
  }, {
    itemId: 'item-id',
    selectedAudioIndex: 11,
    selectedSubtitleIndex: 19,
  })

  assert.deepEqual(playback.audioStreams.map(s => s.index), [11])
  assert.deepEqual(playback.subtitleStreams.map(s => s.index), [19])
  assert.equal(playback.mediaSourceId, 'source-id')
  assert.equal(playback.selectedAudioIndex, 11)
  assert.equal(playback.selectedSubtitleIndex, 19)
})
