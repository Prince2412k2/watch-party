// What the stage's track menu opens on, and what it sends to the player.

import test from 'node:test'
import assert from 'node:assert/strict'
import { defaultSelection, parsePlaybackTracks, trackLabel, wireSelection } from './playbackTracks.ts'

const payload = {
  mediaSourceId: 'source-1',
  audioStreams: [
    { index: 1, displayTitle: 'English AC3', isDefault: false },
    { index: 2, language: 'jpn', isDefault: true },
    { index: 'nope' },
  ],
  subtitleStreams: [
    { index: 3, title: 'English SDH', isExternal: true },
    { index: 4, language: 'eng', isForced: true },
  ],
}

test('the payload is parsed rather than trusted', () => {
  const tracks = parsePlaybackTracks(payload)
  assert.ok(tracks)
  assert.equal(tracks.mediaSourceId, 'source-1')
  // A track with no numeric index cannot be selected or sent, so it is dropped
  // rather than rendered as a row that does nothing.
  assert.deepEqual(tracks.audioStreams.map((track) => track.index), [1, 2])
  assert.equal(tracks.subtitleStreams[0].isExternal, true)
  assert.equal(tracks.subtitleStreams[1].isForced, true)

  assert.equal(parsePlaybackTracks(null), null)
  assert.equal(parsePlaybackTracks('nope'), null)
  assert.deepEqual(parsePlaybackTracks({}), {
    mediaSourceId: null,
    audioStreams: [],
    subtitleStreams: [],
  })
})

test('a track label falls through the fields Jellyfin may leave unset', () => {
  assert.equal(trackLabel({ index: 1, displayTitle: 'English AC3', isDefault: false, isForced: false, isExternal: false }, 'Audio 1'), 'English AC3')
  assert.equal(trackLabel({ index: 1, title: 'Commentary', isDefault: false, isForced: false, isExternal: false }, 'Audio 1'), 'Commentary')
  assert.equal(trackLabel({ index: 1, language: 'jpn', isDefault: true, isForced: false, isExternal: false }, 'Audio 1'), 'jpn · Default')
  assert.equal(trackLabel({ index: 1, isDefault: true, isForced: true, isExternal: false }, 'Audio 1'), 'Audio 1 · Default · Forced')
})

test('audio opens on the default, subtitles open off unless the file insists', () => {
  const tracks = parsePlaybackTracks(payload)!
  // Index 2 is the default audio; 4 is forced, and a forced track carries
  // dialogue the viewer cannot otherwise follow.
  assert.deepEqual(defaultSelection(tracks), { audioStreamIndex: 2, subtitleStreamIndex: 4 })

  const plain = parsePlaybackTracks({
    audioStreams: [{ index: 7 }, { index: 8 }],
    subtitleStreams: [{ index: 9 }],
  })!
  // No default marked: the first audio track wins, because "no audio" is not a
  // state anyone wants — and subtitles stay off.
  assert.deepEqual(defaultSelection(plain), { audioStreamIndex: 7, subtitleStreamIndex: null })
  assert.deepEqual(defaultSelection(parsePlaybackTracks({})!), {
    audioStreamIndex: null,
    subtitleStreamIndex: null,
  })
})

test('subtitles off is spelled -1 on the wire, not null', () => {
  assert.deepEqual(wireSelection({ audioStreamIndex: 2, subtitleStreamIndex: 4 }), {
    audioStreamIndex: 2,
    subtitleStreamIndex: 4,
  })
  assert.deepEqual(wireSelection({ audioStreamIndex: 2, subtitleStreamIndex: null }), {
    audioStreamIndex: 2,
    subtitleStreamIndex: -1,
  })
  assert.deepEqual(wireSelection({}), { audioStreamIndex: null, subtitleStreamIndex: -1 })
})
