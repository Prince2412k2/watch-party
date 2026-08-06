// Season grouping and per-season state — including the one that misleads:
// a not-yet-added lookup echoing TVDB's "everything monitored" defaults.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  allSeasonNumbers,
  allSeasonsCovered,
  anySeasonRequesting,
  episodeCountLabel,
  groupSeasons,
  hasSeasonList,
  seasonLabel,
  seasonState,
  withSeasonState,
  type SeasonRequestState,
} from './seasons.ts'
import type { CatalogItem, CatalogSeason } from './catalog.ts'

const show = (seasons: CatalogSeason[], over: Partial<CatalogItem> = {}): CatalogItem => ({
  title: 'Severance',
  seasons,
  ...over,
})

const seasons: CatalogSeason[] = [
  { seasonNumber: 2, monitored: true, totalEpisodeCount: 10 },
  { seasonNumber: 0, monitored: true, totalEpisodeCount: 3 },
  { seasonNumber: 1, monitored: true, totalEpisodeCount: 9 },
]

test('specials are split out and the rest are ordered', () => {
  const groups = groupSeasons(show(seasons))
  assert.deepEqual(groups.regular.map((season) => season.seasonNumber), [1, 2])
  assert.deepEqual(groups.specials.map((season) => season.seasonNumber), [0])
})

test('a series with no season list groups to nothing rather than throwing', () => {
  assert.deepEqual(groupSeasons(show([])), { regular: [], specials: [] })
  assert.deepEqual(groupSeasons({ title: 'x' }), { regular: [], specials: [] })
})

test('grouping does not reorder the caller’s array', () => {
  const input = seasons.slice()
  groupSeasons(show(input))
  assert.deepEqual(input.map((season) => season.seasonNumber), [2, 0, 1])
})

test('a show with only specials still has a season list to choose from', () => {
  // The primary action, the Enter key and the sheet all read this one
  // predicate, so a specials-only show cannot offer a chooser in one place and
  // a whole-series grab in another.
  assert.equal(hasSeasonList(show([{ seasonNumber: 0 }])), true)
  assert.equal(hasSeasonList(show([{ seasonNumber: 1 }])), true)
  assert.equal(hasSeasonList(show([])), false)
  assert.equal(hasSeasonList({ title: 'x' }), false)
})

test('"All seasons" never includes the specials', () => {
  // A decade of behind-the-scenes featurettes is not what "every season" means.
  assert.deepEqual(allSeasonNumbers(groupSeasons(show(seasons))), [1, 2])
})

// ── state ───────────────────────────────────────────────────────────────────

test('a lookup’s monitored flags do not read as already-added', () => {
  // TVDB defaults every season to monitored:true; before the series is in the
  // library that says nothing about what is being tracked.
  const notAdded = show(seasons)
  assert.equal(seasonState(seasons[2], {}, notAdded), 'idle')
  const added = show(seasons, { id: 4 })
  assert.equal(seasonState(seasons[2], {}, added), 'monitored')
})

test('an unmonitored season of an added series is still requestable', () => {
  const item = show([{ seasonNumber: 1, monitored: false }], { id: 4 })
  assert.equal(seasonState({ seasonNumber: 1, monitored: false }, {}, item), 'idle')
})

test('this session’s own request outranks what the catalog echoed', () => {
  const added = show(seasons, { id: 4 })
  const requests: Record<number, SeasonRequestState | undefined> = { 1: 'requesting' }
  assert.equal(seasonState(seasons[2], requests, added), 'requesting')
  assert.equal(seasonState(seasons[2], { 1: 'error' }, added), 'error')
  assert.equal(seasonState(seasons[2], { 1: 'requested' }, added), 'requested')
})

test('"All seasons" is done only when every regular season is covered', () => {
  const groups = groupSeasons(show(seasons, { id: 4 }))
  const added = show(seasons, { id: 4 })
  assert.equal(allSeasonsCovered(groups, {}, added), true, 'both already monitored')

  const notAdded = show(seasons)
  assert.equal(allSeasonsCovered(groups, {}, notAdded), false)
  assert.equal(allSeasonsCovered(groups, { 1: 'requested' }, notAdded), false, 'season 2 is still open')
  assert.equal(allSeasonsCovered(groups, { 1: 'requested', 2: 'requested' }, notAdded), true)
  // In-flight is not covered — the button must stay disabled, not become done.
  assert.equal(allSeasonsCovered(groups, { 1: 'requesting', 2: 'requesting' }, notAdded), false)
})

test('a show with no regular seasons is never "all covered"', () => {
  const groups = groupSeasons(show([{ seasonNumber: 0 }]))
  assert.equal(allSeasonsCovered(groups, {}, show([{ seasonNumber: 0 }], { id: 1 })), false)
})

test('any request in flight locks the whole chooser', () => {
  assert.equal(anySeasonRequesting({}), false)
  assert.equal(anySeasonRequesting({ 1: 'requested', 2: 'error' }), false)
  assert.equal(anySeasonRequesting({ 1: 'requested', 2: 'requesting' }), true)
})

test('a bulk request flips every season it names and leaves the rest alone', () => {
  const next = withSeasonState({ 3: 'error' }, [1, 2], 'requesting')
  assert.deepEqual(next, { 1: 'requesting', 2: 'requesting', 3: 'error' })
})

test('marking seasons does not mutate the previous map', () => {
  const before: Record<number, SeasonRequestState | undefined> = { 1: 'error' }
  withSeasonState(before, [1], 'requested')
  assert.deepEqual(before, { 1: 'error' })
})

// ── labels ──────────────────────────────────────────────────────────────────

test('season 0 is Specials everywhere it is named', () => {
  assert.equal(seasonLabel({ seasonNumber: 0 }), 'Specials')
  assert.equal(seasonLabel({ seasonNumber: 3 }), 'Season 3')
})

test('an episode count is shown only when the catalog actually has one', () => {
  assert.equal(episodeCountLabel({ seasonNumber: 1, totalEpisodeCount: 9 }), '9 episodes')
  assert.equal(episodeCountLabel({ seasonNumber: 1, totalEpisodeCount: 1 }), '1 episode')
  // A not-yet-added series has no counts; "0 episodes" reads as broken data.
  assert.equal(episodeCountLabel({ seasonNumber: 1, totalEpisodeCount: 0 }), null)
  assert.equal(episodeCountLabel({ seasonNumber: 1 }), null)
  assert.equal(episodeCountLabel({ seasonNumber: 1, statistics: { totalEpisodeCount: 6 } }), '6 episodes')
})
