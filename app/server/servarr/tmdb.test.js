import { test } from 'node:test'
import assert from 'node:assert/strict'

import { tmdbSeasonEpisodes, tmdbSeriesIdFromTvdb } from './tmdb.js'

const realFetch = globalThis.fetch

function stubFetch(payload, { ok = true, status = 200 } = {}) {
  const calls = []
  globalThis.fetch = async (url) => {
    calls.push(url.toString())
    return {
      ok,
      status,
      json: async () => payload,
      headers: new Map([['content-type', 'application/json']]),
    }
  }
  return calls
}

test.afterEach(() => { globalThis.fetch = realFetch })

test('tmdbSeasonEpisodes maps a season into the episode-row shape', async (t) => {
  process.env.TMDB_API_KEY = 'test-key'
  t.after(() => { delete process.env.TMDB_API_KEY })

  const calls = stubFetch({
    season_number: 1,
    name: 'Season 1',
    overview: 'First season.',
    poster_path: '/season1.jpg',
    episodes: [
      {
        episode_number: 1,
        name: 'Pilot',
        overview: 'It begins.',
        still_path: '/e1.jpg',
        air_date: '2013-09-17',
        runtime: 23,
        vote_average: 7.6,
      },
      { episode_number: 2, name: 'The Tagger', overview: '', still_path: null, air_date: null, runtime: null },
    ],
  })

  const season = await tmdbSeasonEpisodes(2710, 1)

  assert.equal(season.seasonNumber, 1)
  assert.equal(season.poster, 'https://image.tmdb.org/t/p/w780/season1.jpg')
  assert.equal(season.episodes.length, 2)
  assert.deepEqual(season.episodes[0], {
    episodeNumber: 1,
    name: 'Pilot',
    overview: 'It begins.',
    still: 'https://image.tmdb.org/t/p/w780/e1.jpg',
    airDate: '2013-09-17',
    runtime: 23,
    rating: 7.6,
  })
  // A missing still must be null, not a URL ending in "null".
  assert.equal(season.episodes[1].still, null)
  assert.equal(season.episodes[1].overview, null)

  // The key travels as a query param and the path is the season endpoint.
  assert.match(calls[0], /\/3\/tv\/2710\/season\/1\?/)
  assert.match(calls[0], /api_key=test-key/)
})

test('tmdbSeasonEpisodes surfaces an upstream failure instead of hanging', async (t) => {
  process.env.TMDB_API_KEY = 'test-key'
  t.after(() => { delete process.env.TMDB_API_KEY })
  stubFetch({}, { ok: false, status: 404 })

  await assert.rejects(() => tmdbSeasonEpisodes(1, 1), (err) => {
    assert.equal(err.status, 404)
    assert.equal(err.upstream, true)
    return true
  })
})

test('tmdbSeasonEpisodes reports "not configured" without a key', async () => {
  delete process.env.TMDB_API_KEY
  await assert.rejects(() => tmdbSeasonEpisodes(1, 1), (err) => {
    assert.equal(err.notConfigured, true)
    assert.equal(err.service, 'tmdb')
    return true
  })
})

test('tmdbSeriesIdFromTvdb resolves the first tv result, or null', async (t) => {
  process.env.TMDB_API_KEY = 'test-key'
  t.after(() => { delete process.env.TMDB_API_KEY })

  stubFetch({ tv_results: [{ id: 2710 }, { id: 9999 }] })
  assert.equal(await tmdbSeriesIdFromTvdb(269586), 2710)

  stubFetch({ tv_results: [] })
  assert.equal(await tmdbSeriesIdFromTvdb(1), null)

  stubFetch({})
  assert.equal(await tmdbSeriesIdFromTvdb(1), null)
})
