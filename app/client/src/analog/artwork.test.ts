// Season artwork, wired to the Jellyfin item shape the client actually gets.
//
// The chain itself (season Primary -> series Primary -> fixed placeholder) is
// pinned across languages by interactionParity.test.ts. These cases cover the
// wiring #66 calls out as missing today: desktop `PosterCardFluid` asks for a
// season's Primary with NO fallback and renders nothing on a 404, the phone
// falls back to the series *Backdrop* so every season shows the same wide art
// letterboxed into a 2:3 box, and the two trees keep separate 404 registries so
// a failure learned on one is re-requested on the other.

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import {
  UNVERIFIED_TAG,
  artworkSrc,
  backdropSrc,
  failedArtworkIds,
  initialsFor,
  noteArtworkFailure,
  primaryImageTag,
  resetArtworkFailures,
  resolveArtwork,
  seriesImageTag,
} from './artwork.ts'

const fixture = JSON.parse(
  readFileSync(new URL('../../../shared/design/interaction.json', import.meta.url), 'utf8'),
)

const season = (over: Record<string, unknown> = {}) => ({
  Id: 'season-1',
  Name: 'Season 3',
  Type: 'Season',
  IndexNumber: 3,
  SeriesId: 'series-1',
  ImageTags: { Primary: 'season-tag' },
  SeriesPrimaryImageTag: 'series-tag',
  ...over,
})

test('a season with its own art uses it', () => {
  assert.deepEqual(resolveArtwork(season()), {
    kind: 'season',
    itemId: 'season-1',
    imageTag: 'season-tag',
    label: null,
  })
})

test('a season without art falls back to the series poster, not its backdrop', () => {
  const art = resolveArtwork(season({ ImageTags: {} }))
  assert.equal(art.kind, 'series')
  assert.equal(art.itemId, 'series-1')
  // The bug this replaces: the phone requested type=Backdrop here, so every
  // season of a show rendered the same wide still squeezed into a 2:3 frame.
  assert.equal(artworkSrc(art), '/api/library/image/series-1?type=Primary')
})

test('season art that failed to load falls through to the series', () => {
  const art = resolveArtwork(season(), ['season-1'])
  assert.equal(art.kind, 'series')
  assert.equal(art.itemId, 'series-1')
})

test('both images failing yields the numbered placeholder rather than looping', () => {
  const art = resolveArtwork(season(), ['season-1', 'series-1'])
  assert.deepEqual(art, { kind: 'placeholder', itemId: null, imageTag: null, label: 'S3' })
  assert.equal(artworkSrc(art), null, 'a placeholder must not produce another request')
})

test('an unnumbered season still gets a fixed-size placeholder', () => {
  const art = resolveArtwork(season({ IndexNumber: null }), ['season-1', 'series-1'])
  assert.equal(art.kind, 'placeholder')
  assert.equal(art.label, '—')
})

test('the season chain is the shared core, not a second implementation', () => {
  // Every fixture case, driven through the item shape the client receives.
  for (const testCase of fixture.seasonArtwork.cases) {
    const input = testCase.input
    const art = resolveArtwork(
      {
        Id: input.seasonId,
        Type: 'Season',
        IndexNumber: input.seasonNumber,
        SeriesId: input.seriesId,
        ImageTags: { Primary: input.seasonImageTag },
        SeriesPrimaryImageTag: input.seriesImageTag,
      },
      input.failedIds ?? [],
    )
    assert.deepEqual(art, testCase.expect, testCase.name)
  }
})

test('a movie follows the identical three steps', () => {
  const movie = { Id: 'movie-1', Name: 'Wages Of Fear', Type: 'Movie', ImageTags: { Primary: 'tag' } }
  assert.equal(resolveArtwork(movie).itemId, 'movie-1')
  // Fixed-size placeholder for a movie too: layout and focus must not move
  // when artwork is missing, which is not a season-specific requirement.
  const missing = resolveArtwork({ ...movie, ImageTags: {} })
  assert.deepEqual(missing, { kind: 'placeholder', itemId: null, imageTag: null, label: 'WO' })
})

test('an absent ImageTags map is treated as unknown, not as "no artwork"', () => {
  // The library proxy only guarantees the fields it asks for. Reading "absent"
  // as "no art" would drop every poster on the floor; assuming art and letting
  // the 404 fall through is the chain the reference already describes.
  assert.equal(primaryImageTag({ Id: 'x' }), UNVERIFIED_TAG)
  assert.equal(primaryImageTag({ Id: 'x', ImageTags: {} }), null)
  assert.equal(primaryImageTag({ Id: 'x', ImageTags: { Primary: 'real' } }), 'real')

  assert.equal(seriesImageTag({ Id: 'x' }), null, 'no series means no series art')
  assert.equal(seriesImageTag({ Id: 'x', SeriesId: 's' }), UNVERIFIED_TAG)
  assert.equal(seriesImageTag({ Id: 'x', SeriesId: 's', SeriesPrimaryImageTag: null }), null)
})

test('placeholder initials stay to two characters', () => {
  assert.equal(initialsFor('Blade Runner 2049'), 'BR')
  assert.equal(initialsFor('Alien'), 'A')
  assert.equal(initialsFor('   '), '—')
  assert.equal(initialsFor(undefined), '—')
})

test('artwork resolves to the existing same-origin proxy route', () => {
  // No new backend route: /api/library/image/{id}?type=Primary is already
  // whitelisted server-side (app/server/library.js).
  assert.equal(artworkSrc(resolveArtwork(season())), '/api/library/image/season-1?type=Primary')
  assert.equal(backdropSrc('movie-1'), '/api/library/image/movie-1?type=Backdrop')
  assert.equal(backdropSrc(null), null)
})

test('one failure registry serves every tree', () => {
  resetArtworkFailures()
  assert.deepEqual(failedArtworkIds(), [])

  // A 404 observed anywhere is known everywhere — the two Sets this replaces
  // (pages/Library.tsx and mobile/ui/Poster.tsx) never shared a thing.
  noteArtworkFailure('season-1')
  noteArtworkFailure('season-1')
  assert.deepEqual(failedArtworkIds(), ['season-1'])
  assert.equal(resolveArtwork(season(), failedArtworkIds()).itemId, 'series-1')

  noteArtworkFailure('series-1')
  assert.equal(resolveArtwork(season(), failedArtworkIds()).kind, 'placeholder')
  resetArtworkFailures()
})
