// The join behind "delete this from the server", and the cases where there is
// nothing to delete.
//
// Jellyfin's item id means nothing to Radarr or Sonarr; the only thing the two
// sides share is the metadata provider id. Get that wrong and the delete either
// does nothing or — far worse — removes a different film.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  arrDeletePath,
  arrLibraryPath,
  deleteConfirmation,
  matchArrRecord,
  providerIdOf,
} from './libraryDelete.ts'

test('the provider id is read whatever the plugin capitalised it as', () => {
  // Tmdb / TMDB / tmdb have all been seen in the wild; matching one exactly is
  // a join that works on one server and silently fails on the next.
  assert.equal(providerIdOf({ Tmdb: '550' }, 'movie'), 550)
  assert.equal(providerIdOf({ TMDB: '550' }, 'movie'), 550)
  assert.equal(providerIdOf({ tmdb: 550 }, 'movie'), 550)
  assert.equal(providerIdOf({ Tvdb: '81189' }, 'series'), 81189)
})

test('a movie does not answer with a series id, or vice versa', () => {
  assert.equal(providerIdOf({ Tvdb: '81189' }, 'movie'), null)
  assert.equal(providerIdOf({ Tmdb: '550' }, 'series'), null)
})

test('a missing or unusable provider id is null, not a guess', () => {
  assert.equal(providerIdOf(undefined, 'movie'), null)
  assert.equal(providerIdOf(null, 'movie'), null)
  assert.equal(providerIdOf({}, 'movie'), null)
  assert.equal(providerIdOf({ Tmdb: 'not a number' }, 'movie'), null)
})

test('the matched record is the one whose provider id agrees', () => {
  const rows = [
    { id: 78, tmdbId: 999999, title: 'Something Else' },
    { id: 77, tmdbId: 550, title: 'Fight Club' },
  ]
  // 77, not 78, and not the Jellyfin id — deleting the wrong row here erases
  // somebody's film.
  assert.deepEqual(matchArrRecord(rows, 'movie', 550), { id: 77, title: 'Fight Club' })
})

test('a title the *arr never added has nothing to delete', () => {
  const rows = [{ id: 78, tmdbId: 999999, title: 'Something Else' }]
  // Hand-copied, imported by something else, or the service is not configured.
  // The caller shows no button rather than a dead one.
  assert.equal(matchArrRecord(rows, 'movie', 550), null)
  assert.equal(matchArrRecord(rows, 'movie', null), null)
  assert.equal(matchArrRecord(null, 'movie', 550), null)
  assert.equal(matchArrRecord('nope', 'movie', 550), null)
  assert.equal(matchArrRecord([{ tmdbId: 550 }], 'movie', 550), null, 'a row with no id')
})

test('the paths name the right service', () => {
  assert.equal(arrLibraryPath('movie'), 'radarr/movies')
  assert.equal(arrLibraryPath('series'), 'sonarr/series')
  assert.equal(arrDeletePath('movie', 77), 'radarr/movie/77')
  assert.equal(arrDeletePath('series', 12), 'sonarr/series/12')
})

test('the confirmation says whose copy this is', () => {
  const text = deleteConfirmation('movie', 'Fight Club')
  assert.match(text, /Fight Club/)
  // The part that matters: this is not a local tidy-up.
  assert.match(text, /everyone's copy/)
  assert.match(text, /can't be undone/)
  assert.match(deleteConfirmation('series', 'Signal'), /show is excluded/)
})
