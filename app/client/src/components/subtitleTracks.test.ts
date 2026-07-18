import test from 'node:test'
import assert from 'node:assert/strict'

import { hlsIndexForJellyfin, jellyfinStreamIndex, subtitleContentUrl } from './subtitleTracks.ts'

test('maps Jellyfin subtitle indices from rendition URLs or playback order', () => {
  const tracks = [{ url: '/sub.vtt?SubtitleStreamIndex=7' }, { url: '/other.vtt' }]
  assert.equal(jellyfinStreamIndex(tracks[0].url, 'SubtitleStreamIndex'), 7)
  assert.equal(hlsIndexForJellyfin(tracks, 7, 'SubtitleStreamIndex'), 0)
  assert.equal(hlsIndexForJellyfin(tracks, 9, 'SubtitleStreamIndex', [{ index: 7 }, { index: 9 }]), 1)
})

test('builds an authenticated app subtitle-content URL', () => {
  assert.equal(subtitleContentUrl('movie/id', 4, 'source id'), '/api/library/items/movie%2Fid/subtitles/4/content?mediaSourceId=source%20id')
})
