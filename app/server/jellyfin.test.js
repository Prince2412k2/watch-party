import test from 'node:test'
import assert from 'node:assert/strict'

import {
  buildHlsUrl, getTrickplayProfile, normalizePlaybackInfo, selectTrickplayProfile,
} from './jellyfin.js'

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

const trickplayItem = {
  MediaSources: [{ Id: 'source-a' }, { Id: 'source-b' }],
  Trickplay: {
    'source-a': {
      160: { Width: 160, Height: 90, TileWidth: 10, TileHeight: 10, ThumbnailCount: 201, Interval: 10000 },
      320: { Width: 320, Height: 180, TileWidth: 5, TileHeight: 5, ThumbnailCount: 201, Interval: 10000 },
      640: { Width: 640, Height: 360, TileWidth: 5, TileHeight: 5, ThumbnailCount: 201, Interval: 10000 },
    },
  },
}

test('selectTrickplayProfile normalizes the profile nearest 320 pixels', () => {
  assert.deepEqual(selectTrickplayProfile(trickplayItem, 'source-a'), {
    mediaSourceId: 'source-a',
    width: 320,
    height: 180,
    tileWidth: 5,
    tileHeight: 5,
    thumbnailCount: 201,
    intervalMs: 10000,
    sheetCount: 9,
  })
})

test('selectTrickplayProfile resolves the first source with trickplay when omitted', () => {
  assert.equal(selectTrickplayProfile(trickplayItem)?.mediaSourceId, 'source-a')
})

test('trickplay profiles must belong to a media source on the requested item', () => {
  assert.equal(selectTrickplayProfile(trickplayItem, 'source-b'), null)
  assert.equal(selectTrickplayProfile(trickplayItem, 'source-missing'), null)
  assert.equal(getTrickplayProfile(trickplayItem, 'source-a', 321), null)
})

test('invalid trickplay profile values are rejected', () => {
  const item = structuredClone(trickplayItem)
  item.Trickplay['source-a'][320].TileWidth = 0
  assert.equal(getTrickplayProfile(item, 'source-a', 320), null)

  item.Trickplay['source-a'][320].TileWidth = 5
  item.Trickplay['source-a'][320].Width = 640
  assert.equal(getTrickplayProfile(item, 'source-a', 320), null)
})
