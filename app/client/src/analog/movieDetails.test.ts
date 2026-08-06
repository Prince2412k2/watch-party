// The detail block that now lives on the browse stage itself.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  eyebrowParts,
  mergeDetail,
  metaLine,
  needsEnrichment,
  playActionLabel,
  resolutionLabel,
  resumeTicks,
  stageActions,
  type StageItem,
} from './movieDetails.ts'

const MINUTE = 600_000_000

const movie = (patch: Partial<StageItem> = {}): StageItem => ({
  Id: 'm1',
  Name: 'Blade Runner 2049',
  Type: 'Movie',
  Overview: 'A young blade runner uncovers a secret.',
  Genres: ['Science Fiction', 'Drama', 'Thriller', 'Mystery'],
  ProductionYear: 2017,
  CommunityRating: 7.9,
  OfficialRating: 'R',
  RunTimeTicks: 164 * MINUTE,
  MediaSources: [{ MediaStreams: [{ Type: 'Audio' }, { Type: 'Video', Height: 1080 }] }],
  ...patch,
})

test('resolution comes off the video stream, not the first stream', () => {
  // MediaStreams[0] is routinely the audio track; indexing blind gives "?P" on
  // exactly the files that do have a resolution.
  assert.equal(resolutionLabel(movie()), '1080P')
  assert.equal(resolutionLabel({ MediaSources: [{ MediaStreams: [{ Type: 'Video', Height: 2160 }] }] }), '4K')
  assert.equal(resolutionLabel({ MediaSources: [{ MediaStreams: [{ Type: 'Video', Height: 1440 }] }] }), '1440P')
  assert.equal(resolutionLabel({ MediaSources: [{ MediaStreams: [{ Type: 'Video', Height: 720 }] }] }), '720P')
  assert.equal(resolutionLabel({ MediaSources: [{ MediaStreams: [{ Type: 'Video', Height: 480 }] }] }), '480P')
  assert.equal(resolutionLabel({ MediaSources: [{ MediaStreams: [{ Type: 'Audio' }] }] }), null)
  assert.equal(resolutionLabel({ MediaSources: [] }), null)
  assert.equal(resolutionLabel({}), null)
})

test('the meta line is rating, runtime, year, resolution — and closes its own gaps', () => {
  assert.deepEqual(metaLine(movie()), ['★ 7.9', '2h 44m', '2017', '1080P'])

  // A title with no rating must not leave a leading separator, and one with no
  // media source must not end on a trailing one.
  assert.deepEqual(metaLine(movie({ CommunityRating: null })), ['2h 44m', '2017', '1080P'])
  assert.deepEqual(metaLine(movie({ MediaSources: null })), ['★ 7.9', '2h 44m', '2017'])
  assert.deepEqual(
    metaLine(movie({ CommunityRating: null, RunTimeTicks: null, ProductionYear: null, MediaSources: null })),
    [],
  )
  // A whole rating renders with its decimal rather than collapsing to "8".
  assert.deepEqual(metaLine(movie({ CommunityRating: 8 }))[0], '★ 8.0')
})

test('the eyebrow carries the context, the certificate and at most three genres', () => {
  assert.deepEqual(eyebrowParts(movie()), ['R', 'Science Fiction', 'Drama', 'Thriller'])
  assert.deepEqual(eyebrowParts(movie(), 'Alien · 3 of 4'), [
    'Alien · 3 of 4',
    'R',
    'Science Fiction',
    'Drama',
    'Thriller',
  ])
  assert.deepEqual(eyebrowParts(movie({ OfficialRating: null, Genres: null })), [])
})

test('Resume appears only for a title that was actually started', () => {
  assert.equal(resumeTicks(movie()), null)
  assert.equal(resumeTicks(movie({ UserData: { PlaybackPositionTicks: 0 } })), null)
  assert.equal(resumeTicks(movie({ UserData: { PlaybackPositionTicks: 12 * MINUTE } })), 12 * MINUTE)

  assert.equal(playActionLabel(movie()), 'Play')
  assert.equal(playActionLabel(movie({ UserData: { PlaybackPositionTicks: 12 * MINUTE } })), 'Resume 12m')
  assert.equal(playActionLabel(null), 'Play')
})

test('a collection opens instead of playing', () => {
  const boxSet: StageItem = { Id: 'box-1', Name: 'Alien', Type: 'BoxSet', ChildCount: 4 }
  assert.equal(playActionLabel(boxSet), 'Open 4 titles')
  assert.equal(playActionLabel({ ...boxSet, ChildCount: null }), 'Open collection')

  const actions = stageActions(boxSet, true)
  assert.equal(actions.plays, false)
  // Neither track selection nor an offline download means anything for a
  // franchise — there is no media source behind it.
  assert.equal(actions.tracks, false)
  assert.equal(actions.download, false)
})

test('the offline download is offered only where a file can land', () => {
  // native/env.ts: "Every native-only code path (MpvBackend, the Player.jsx
  // native branch, the offline/download UI) is gated on this."
  assert.equal(stageActions(movie(), true).download, true)
  assert.equal(stageActions(movie(), false).download, false)
  assert.equal(stageActions(movie(), false).tracks, true)
  assert.deepEqual(stageActions(null, true), { plays: false, label: 'Play', tracks: false, download: false })
})

test('only the lists that arrive without the full field set pay for a detail fetch', () => {
  // /api/library/collections/:id/items asks for Overview, Genres and the rest,
  // so a franchise's parts render with no second request at all.
  assert.equal(needsEnrichment(movie()), false)
  // /api/library/items/:id/children asks Jellyfin only for MediaSources.
  assert.equal(needsEnrichment({ Id: 'm1', Name: 'Alien', Type: 'Movie' }), true)
  assert.equal(needsEnrichment({ Id: 'm1', Name: 'Alien', Type: 'Movie', Overview: null, Genres: [] }), false)
  // A collection's own overview comes from the collections route.
  assert.equal(needsEnrichment({ Id: 'b', Name: 'Alien', Type: 'BoxSet' }), false)
  assert.equal(needsEnrichment(null), false)
})

test('an enriched detail is merged over the list entry, never swapped for it', () => {
  const listEntry: StageItem = { Id: 'm1', Name: 'Alien', Type: 'Movie', UserData: { PlaybackPositionTicks: 5 } }
  const detail: StageItem = { Id: 'm1', Name: 'Alien', Type: 'Movie', Overview: 'In space.', Genres: ['Horror'] }

  assert.deepEqual(mergeDetail(listEntry, detail), {
    Id: 'm1',
    Name: 'Alien',
    Type: 'Movie',
    UserData: { PlaybackPositionTicks: 5 },
    Overview: 'In space.',
    Genres: ['Horror'],
  })
  // Until the fetch lands the item is unchanged, so the stage never blanks
  // mid-scroll.
  assert.equal(mergeDetail(listEntry, undefined), listEntry)
})
