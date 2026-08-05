import test from 'node:test'
import assert from 'node:assert/strict'
import { browseStackFromSheet, sheetStackFromBrowse, tabForMobilePath, viewPatchForSheet } from './sharedBrowse.ts'
import type { MobileItem } from './types.ts'
import type { PartyBrowse } from '../types.ts'

const series: MobileItem = { Id: 'series-1', Name: 'Severance', Type: 'Series' }
const season: MobileItem = { Id: 'season-1', Name: 'Season 1', Type: 'Season', SeriesId: 'series-1', SeriesName: 'Severance' }
const episode: MobileItem = { Id: 'ep-1', Name: 'Good News About Hell', Type: 'Episode', SeriesId: 'series-1', SeriesName: 'Severance' }

test('every phone route publishes a canonical browse tab', () => {
  assert.equal(tabForMobilePath('/discover'), 'discover')
  assert.equal(tabForMobilePath('/downloads'), 'downloads')
  // Home is the phone stand-in for both desktop library tabs, so it publishes
  // whichever one it is standing in for rather than inventing a fifth tab.
  assert.equal(tabForMobilePath('/library'), 'movies')
  assert.equal(tabForMobilePath('/'), 'movies')
  assert.equal(tabForMobilePath(undefined), 'movies')
  assert.equal(tabForMobilePath('/library', 'series'), 'series')
  // A host pushed onto an explicit desktop tab must keep publishing that tab,
  // or the room would flip back and forth between /movies and /series.
  assert.equal(tabForMobilePath('/movies'), 'movies')
  assert.equal(tabForMobilePath('/series'), 'series')
  // Nothing to share from the sign-in screen or an unknown path.
  assert.equal(tabForMobilePath('/login'), null)
  assert.equal(tabForMobilePath('/profile'), null)
})

test('a follower rebuilds the drill-in sheet from the shared stack', () => {
  const browse: PartyBrowse = {
    stack: [
      { id: 'series-1', name: 'Severance', type: 'Series' },
      { id: 'season-1', name: 'Season 1', type: 'Season', seriesId: 'series-1', seriesName: 'Severance' },
    ],
  }
  assert.deepEqual(sheetStackFromBrowse(browse), [
    { Id: 'series-1', Name: 'Severance', Type: 'Series', SeriesId: undefined, SeriesName: undefined },
    { Id: 'season-1', Name: 'Season 1', Type: 'Season', SeriesId: 'series-1', SeriesName: 'Severance' },
  ])
  // No shared position yet, or a member who is not in a party at all.
  assert.deepEqual(sheetStackFromBrowse(undefined), [])
  assert.deepEqual(sheetStackFromBrowse({}), [])
  assert.deepEqual(sheetStackFromBrowse({ stack: [] }), [])
})

test('unidentifiable stack entries are dropped, not rendered as a blank sheet', () => {
  // The wire type allows every field to be absent; an entry with no id cannot be
  // fetched, so following it would open an empty sheet over the follower's rails.
  const stack = sheetStackFromBrowse({ stack: [{ name: 'Ghost' }, { id: 'ok', name: 'Real', type: 'Movie' }] })
  assert.deepEqual(stack.map(item => item.Id), ['ok'])
  // A stack entry with an id but no type still resolves to something fetchable.
  assert.deepEqual(sheetStackFromBrowse({ stack: [{ id: 'x' }] }), [
    { Id: 'x', Name: '', Type: 'Folder', SeriesId: undefined, SeriesName: undefined },
  ])
})

test('a phone driver publishes a stack the desktop Library can follow', () => {
  assert.deepEqual(browseStackFromSheet([series, season]), [
    { id: 'series-1', name: 'Severance', type: 'Series' },
    { id: 'season-1', name: 'Season 1', type: 'Season', seriesId: 'series-1', seriesName: 'Severance' },
  ])
})

test('publish then follow round-trips to the same position', () => {
  const published = browseStackFromSheet([series, season, episode])
  assert.deepEqual(
    sheetStackFromBrowse({ stack: published }).map(item => item.Id),
    ['series-1', 'season-1', 'ep-1'],
  )
})

test('the view patch names the root title and the episode drilled into', () => {
  assert.deepEqual(viewPatchForSheet([series, season, episode]), {
    screen: 'detail', mediaId: 'series-1', episodeId: 'ep-1',
  })
  // A single-entry stack is the title itself, so there is no episode to name —
  // null (not undefined) so the server's patch whitelist actually clears it.
  assert.deepEqual(viewPatchForSheet([series]), {
    screen: 'detail', mediaId: 'series-1', episodeId: null,
  })
  // Closing the sheet returns the room to the rails and clears both ids.
  assert.deepEqual(viewPatchForSheet([]), {
    screen: 'grid', mediaId: null, episodeId: null,
  })
})
