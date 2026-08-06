// The Shows stage's browse model.
//
// The parts worth pinning are the ones the surface it replaces got wrong or did
// not have: a season axis that has to survive a stale id off the wire, an
// episode rail that must distinguish "still arriving" from "genuinely empty",
// the season-artwork chain (which has to go through the SHARED core, not a
// second copy, and to a same-origin URL), and Back landing on the exact series
// it was left from rather than at the start of the library.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  activationFor,
  closeSeries,
  openSeries,
  resolveSeasonId,
  rootLevel,
  seasonArtwork,
  seasonEpisodes,
  seasonFromStack,
  seasonIndex,
  seasonLabel,
  seriesFromStack,
  showsSurface,
  stepSeason,
  withSeason,
  type SeasonItem,
  type ShowLevel,
} from './showBrowse.ts'
import { resolveSeasonArtwork } from './browseCore.ts'
import { artworkSrc, UNVERIFIED_TAG } from './artwork.ts'
import { planForSurface, rememberSurfaceFocus, resetSurfaceFocus, shelfSnapshot } from './surface.ts'

const ROOT = rootLevel({ Id: 'tv', Name: 'TV Shows' })

const season = (n: number, over: Partial<SeasonItem> = {}): SeasonItem => ({
  Id: `s${n}`,
  Name: `Season ${n}`,
  Type: 'Season',
  IndexNumber: n,
  SeriesId: 'show',
  ImageTags: { Primary: `season-art-${n}` },
  ...over,
})

const SEASONS = [season(1), season(2), season(3)]
const SERIES = { Id: 'show', ImageTags: { Primary: 'series-art' } }

// ── the stack ───────────────────────────────────────────────────────────────

test('a series drills in and Back pops straight back out', () => {
  const opened = openSeries([ROOT], { Id: 'show', Name: 'Sherlock', Type: 'Series' })

  assert.deepEqual(opened, [ROOT, { id: 'show', name: 'Sherlock', type: 'Series' }])
  assert.equal(seriesFromStack(opened)?.id, 'show')
  assert.deepEqual(closeSeries(opened), [ROOT])
  // Already at the root: Back has nowhere to go and must not empty the stack.
  assert.deepEqual(closeSeries([ROOT]), [ROOT])
})

test('a level the superseded Library pushed is not mistaken for a series', () => {
  // The old implementation pushes Season and Episode levels of its own. Reading
  // one as a series would ask Jellyfin for the children of an episode and render
  // an empty rail under a title that does not belong to it.
  for (const type of ['Season', 'Episode', 'Movie', 'BoxSet']) {
    assert.equal(seriesFromStack([ROOT, { id: 'x', type }]), null, type)
  }
  // A level with no type at all is still accepted — every field is optional on
  // the wire, and this surface only ever pushes series.
  assert.equal(seriesFromStack([ROOT, { id: 'x' }])?.id, 'x')
  assert.equal(seriesFromStack([ROOT]), null, 'the list level has no series')
})

test('the season rides on the stack, so a follower lands on the driver’s', () => {
  const opened = openSeries([ROOT], { Id: 'show', Name: 'Sherlock' })
  assert.equal(seasonFromStack(opened), null, 'nothing chosen yet')

  const moved = withSeason(opened, 's2')
  assert.equal(seasonFromStack(moved), 's2')
  assert.equal(moved.length, 2, 'the season is a field on the series level, not a level of its own')
  assert.equal(seriesFromStack(moved)?.id, 'show', 'and the level is still a series')

  // A season id left over on the list level must not leak back out of it.
  assert.equal(seasonFromStack([{ ...ROOT, seasonId: 's2' } as ShowLevel]), null)
  assert.deepEqual(withSeason([ROOT], 's2'), [ROOT], 'no series, no axis to move')
})

// ── the season axis ─────────────────────────────────────────────────────────

test('the season shown is the one on the stack, or the first', () => {
  assert.equal(resolveSeasonId(SEASONS, 's3'), 's3')
  // A driver on another show, or a season deleted since it was published: fall
  // to the first rather than rendering an empty rail for an id that is gone.
  assert.equal(resolveSeasonId(SEASONS, 'from-another-show'), 's1')
  assert.equal(resolveSeasonId(SEASONS, null), 's1')
  assert.equal(resolveSeasonId([], 's1'), null)
})

test('the season axis is clamped at both ends, never wrapping', () => {
  assert.equal(stepSeason(SEASONS, 's1', -1), 's1', 'Up at the top holds')
  assert.equal(stepSeason(SEASONS, 's1', 1), 's2')
  assert.equal(stepSeason(SEASONS, 's3', 1), 's3', 'Down at the bottom holds')
  assert.equal(stepSeason(SEASONS, 's3', -1), 's2')
  // A stale id resolves before it steps, so the first press moves off season 1
  // rather than doing nothing visible.
  assert.equal(stepSeason(SEASONS, 'gone', 1), 's2')
  assert.equal(stepSeason([], 's1', 1), null)
  assert.equal(seasonIndex(SEASONS, 's2'), 1)
  assert.equal(seasonIndex(SEASONS, 'gone'), -1)
  assert.equal(seasonIndex(SEASONS, null), -1)
})

test('a season names itself even when the scan gave it nothing', () => {
  assert.equal(seasonLabel(season(2), 1), 'Season 2')
  assert.equal(seasonLabel(season(0, { Name: 'Specials' }), 0), 'Specials')
  // Unnamed: the season NUMBER wins over the display position, because season 0
  // is Specials and calling it "Season 1" would be a lie.
  assert.equal(seasonLabel(season(0, { Name: undefined }), 0), 'Season 0')
  assert.equal(seasonLabel(season(4, { Name: undefined }), 2), 'Season 4')
  assert.equal(seasonLabel({ Id: 's', Name: undefined, IndexNumber: null }, 2), 'Season 3')
})

test('the episode rail follows the season, and says which kind of empty it is', () => {
  const episodes = { s1: [{ Id: 'e1' }, { Id: 'e2' }], s2: [{ Id: 'e3' }] }

  assert.deepEqual(seasonEpisodes(episodes, SEASONS, 's1'), episodes.s1)
  assert.deepEqual(seasonEpisodes(episodes, SEASONS, 's2'), episodes.s2, 'the axis drives the rail')

  // Seasons still in flight -> skeleton. Seasons arrived and there are none, or
  // there is no season to select -> the empty state. Season selected but its
  // episodes still in flight -> skeleton again. Conflating any two of these is
  // how a show Sonarr has not populated sits under a shimmer forever.
  assert.equal(seasonEpisodes(episodes, null, 's1'), null)
  assert.deepEqual(seasonEpisodes(episodes, [], null), [])
  assert.deepEqual(seasonEpisodes(episodes, SEASONS, null), [])
  assert.equal(seasonEpisodes(episodes, SEASONS, 's3'), null)
})

// ── season artwork ──────────────────────────────────────────────────────────

test('season artwork falls through season -> series -> fixed placeholder', () => {
  assert.deepEqual(seasonArtwork(season(1), SERIES), {
    kind: 'season',
    itemId: 's1',
    imageTag: 'season-art-1',
    label: null,
  })

  // No art of its own: the show's poster, NOT a placeholder.
  assert.deepEqual(seasonArtwork(season(2, { ImageTags: { Primary: null } }), SERIES), {
    kind: 'series',
    itemId: 'show',
    imageTag: 'series-art',
    label: null,
  })

  // Neither: a fixed-size placeholder labelled with the season number, so
  // layout and focus do not move when artwork is missing.
  assert.deepEqual(
    seasonArtwork(season(3, { ImageTags: { Primary: null } }), { Id: 'show', ImageTags: { Primary: null } }),
    { kind: 'placeholder', itemId: null, imageTag: null, label: 'S3' },
  )

  // A season whose image 404'd once falls to the show rather than retrying.
  assert.equal(seasonArtwork(season(1), SERIES, ['s1']).itemId, 'show')
  assert.equal(seasonArtwork(season(1), SERIES, ['s1', 'show']).kind, 'placeholder')
})

test('season artwork is the shared core, not a second copy of it', () => {
  // If these stop agreeing, Shows has grown its own fallback chain and the
  // Flutter port is showing different artwork from the same library.
  for (const [item, series] of [
    [season(1), SERIES],
    [season(2, { ImageTags: { Primary: null } }), SERIES],
    [season(3, { ImageTags: { Primary: null } }), { Id: 'show', ImageTags: { Primary: null } }],
  ] as const) {
    assert.deepEqual(
      seasonArtwork(item, series),
      resolveSeasonArtwork({
        seasonId: item.Id,
        seasonNumber: item.IndexNumber ?? null,
        seasonImageTag: item.ImageTags?.Primary ?? null,
        seriesId: 'show',
        seriesImageTag: series.ImageTags?.Primary ?? null,
      }),
      `season ${item.IndexNumber}`,
    )
  }
})

test('season artwork is requested same-origin, from the season’s own item', () => {
  const url = artworkSrc(seasonArtwork(season(1), SERIES))
  // The Jellyfin season item's own Primary, through the whitelisted proxy — NOT
  // the Sonarr path, which is cross-origin and broken.
  assert.equal(url, '/api/library/image/s1?type=Primary')
  assert.equal(artworkSrc(seasonArtwork(season(2, { ImageTags: { Primary: null } }), SERIES)), '/api/library/image/show?type=Primary')
  // The placeholder is drawn, never fetched.
  assert.equal(
    artworkSrc(seasonArtwork(season(3, { ImageTags: { Primary: null } }), { Id: 'show', ImageTags: { Primary: null } })),
    null,
  )
})

test('a season payload with no ImageTags map still asks for its own poster', () => {
  // `/children` only guarantees the fields it asks Jellyfin for, so an absent
  // map is "unknown", not "no artwork". Assuming none would drop every season on
  // the surface to a placeholder without a single request being made.
  const bare: SeasonItem = { Id: 's9', Name: 'Season 9', Type: 'Season', IndexNumber: 9, SeriesId: 'show' }
  assert.deepEqual(seasonArtwork(bare, null), {
    kind: 'season',
    itemId: 's9',
    imageTag: UNVERIFIED_TAG,
    label: null,
  })
})

// ── activation ──────────────────────────────────────────────────────────────

test('Enter opens a series and plays anything else', () => {
  assert.deepEqual(activationFor({ Id: 'show', Name: 'Sherlock', Type: 'Series' }), {
    kind: 'open',
    series: { Id: 'show', Name: 'Sherlock', Type: 'Series' },
  })
  assert.deepEqual(activationFor({ Id: 'e1', Name: 'A Study in Pink', Type: 'Episode' }), {
    kind: 'play',
    itemId: 'e1',
  })
  assert.deepEqual(activationFor(null), { kind: 'none' })
  assert.deepEqual(activationFor({ Id: '', Type: 'Episode' }), { kind: 'none' })
})

// ── focus ───────────────────────────────────────────────────────────────────

test('two seasons of one show do not share a focus memory', () => {
  const opened = withSeason(openSeries([ROOT], { Id: 'show', Name: 'Sherlock' }), 's1')

  assert.equal(showsSurface([ROOT], null), 'shows/tv')
  assert.equal(showsSurface(opened, 's1'), 'shows/tv/show/s1')
  assert.notEqual(showsSurface(opened, 's2'), showsSurface(opened, 's1'))
  // A leftover season id at the list level must not change that surface's key,
  // or Back would restore from a memory the list never wrote.
  assert.equal(showsSurface([ROOT], 's2'), 'shows/tv')
})

test('Back lands on the exact series it was left from', () => {
  resetSurfaceFocus()

  const shows = [{ Id: 'a' }, { Id: 'b' }, { Id: 'c' }, { Id: 'd' }]
  const list = showsSurface([ROOT], null)

  // Browse to the third show and open it.
  rememberSurfaceFocus(list, 'shows', 'c', 2)
  const opened = withSeason(openSeries([ROOT], { Id: 'c', Name: 'Show C' }), 's1')
  rememberSurfaceFocus(showsSurface(opened, 's1'), 'shows', 'e4', 3)

  // Back.
  const back = planForSurface(showsSurface(closeSeries(opened), null), [shelfSnapshot('shows', shows)])
  assert.deepEqual(back, { kind: 'exact', shelfIndex: 0, itemIndex: 2 })

  // The show was removed from the library while it was open: focus holds the
  // index rather than jumping to the top of a library of hundreds.
  const shortened = [{ Id: 'a' }, { Id: 'b' }, { Id: 'd' }]
  const nearest = planForSurface(list, [shelfSnapshot('shows', shortened)])
  assert.deepEqual(nearest, { kind: 'nearest', shelfIndex: 0, itemIndex: 2 })

  // A different show's episode surface is a different memory entirely.
  const other = withSeason(openSeries([ROOT], { Id: 'a', Name: 'Show A' }), 's1')
  assert.equal(
    planForSurface(showsSurface(other, 's1'), [shelfSnapshot('shows', [{ Id: 'z' }])]).kind,
    'default',
  )

  resetSurfaceFocus()
})
