// The catalog derivations, and the two that leak if they are wrong: artwork that
// bypasses the same-origin proxy, and a title matched to somebody else's
// download.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  backdropUrl,
  defaultAddOptions,
  eyebrowParts,
  feedLabel,
  isAdded,
  keyOf,
  matchTorrent,
  metaLine,
  normTitle,
  parseDiscoverFeed,
  posterUrl,
  ratingLabel,
  ratingOf,
  removePath,
  requestBody,
  serviceFor,
  stepKind,
  type CatalogItem,
} from './catalog.ts'

const movie = (over: Partial<CatalogItem> = {}): CatalogItem => ({ title: 'Dune', ...over })

test('the two services are named from the kind, not guessed at each call site', () => {
  assert.equal(serviceFor('movie'), 'radarr')
  assert.equal(serviceFor('series'), 'sonarr')
})

test('the kind slider clamps rather than wrapping', () => {
  assert.equal(stepKind('movie', -1), 'movie')
  assert.equal(stepKind('movie', 1), 'series')
  assert.equal(stepKind('series', 1), 'series')
  assert.equal(stepKind('series', -1), 'movie')
  // Holding a direction has to settle, not oscillate.
  assert.equal(stepKind(stepKind(stepKind('movie', 1), 1), 1), 'series')
  assert.equal(stepKind('movie', 0), 'movie')
})

// ── artwork ─────────────────────────────────────────────────────────────────

test('poster art comes from the proxied remoteUrl, never the *arr-local url', () => {
  const proxied = '/api/servarr/remote-image?url=https%3A%2F%2Fimage.tmdb.org%2Fp.jpg'
  const url = posterUrl([
    { coverType: 'fanart', remoteUrl: '/api/servarr/remote-image?url=fan' },
    { coverType: 'poster', remoteUrl: proxied, url: 'http://radarr.internal/MediaCover/1/poster.jpg' },
  ])
  assert.equal(url, proxied)
})

test('a poster with no remoteUrl falls back to url rather than to nothing', () => {
  assert.equal(posterUrl([{ coverType: 'poster', url: '/api/servarr/image?x=1' }]), '/api/servarr/image?x=1')
})

test('no images at all is null, not an empty string that renders a broken img', () => {
  assert.equal(posterUrl(), null)
  assert.equal(posterUrl([]), null)
  assert.equal(backdropUrl(), null)
})

test('the backdrop prefers wide art and falls back to the poster', () => {
  const images = [
    { coverType: 'poster', remoteUrl: '/proxy/poster' },
    { coverType: 'fanart', remoteUrl: '/proxy/fanart' },
  ]
  assert.equal(backdropUrl(images), '/proxy/fanart')
  assert.equal(backdropUrl([{ coverType: 'banner', remoteUrl: '/proxy/banner' }]), '/proxy/banner')
  // A title with only a poster still gets a backdrop rather than a black stage.
  assert.equal(backdropUrl([{ coverType: 'poster', remoteUrl: '/proxy/poster' }]), '/proxy/poster')
})

// ── identity ────────────────────────────────────────────────────────────────

test('items are keyed per kind so a movie and a series cannot share request state', () => {
  assert.equal(keyOf('movie', movie({ tmdbId: 438631 })), 'm:438631')
  assert.equal(keyOf('series', movie({ tvdbId: 121361 })), 's:121361')
  assert.notEqual(keyOf('movie', movie({ tmdbId: 7 })), keyOf('series', movie({ tvdbId: 7 })))
})

test('a title with no provider id still gets its own key', () => {
  // Otherwise every id-less result shares "m:undefined" and one request flips
  // all of them.
  assert.equal(keyOf('movie', movie({ titleSlug: 'dune-2021' })), 'm:dune-2021')
  assert.equal(keyOf('movie', movie({ title: 'Dune' })), 'm:Dune')
  assert.notEqual(keyOf('movie', movie({ title: 'A' })), keyOf('movie', movie({ title: 'B' })))
})

test('in-library is the echoed numeric id and nothing else', () => {
  assert.equal(isAdded(movie()), false)
  assert.equal(isAdded(movie({ id: 12 })), true)
  // Zero is a real id; `monitored` is not evidence of membership.
  assert.equal(isAdded(movie({ id: 0 })), true)
  assert.equal(isAdded(movie({ monitored: true })), false)
})

// ── ratings ─────────────────────────────────────────────────────────────────

test('a rating is read out of whichever of the three shapes arrived', () => {
  assert.equal(ratingOf(movie({ ratings: { value: 7.8 } })), 7.8)
  assert.equal(ratingOf(movie({ ratings: { imdb: { value: 8.1 } } })), 8.1)
  assert.equal(ratingOf(movie({ ratings: { tmdb: { value: 6.4 } } })), 6.4)
  // A flat value wins over the per-provider ones when both are present.
  assert.equal(ratingOf(movie({ ratings: { value: 9, imdb: { value: 3 } } })), 9)
})

test('an unrated title is null rather than a confident zero', () => {
  assert.equal(ratingOf(movie()), null)
  assert.equal(ratingOf(movie({ ratings: {} })), null)
  assert.equal(ratingOf(movie({ ratings: { value: 0 } })), null)
  assert.equal(ratingLabel(movie({ ratings: { value: 0 } })), null)
  assert.equal(ratingLabel(movie({ ratings: { value: 7 } })), '★ 7.0')
})

// ── torrent matching ────────────────────────────────────────────────────────

test('a release name normalises down to the title it carries', () => {
  assert.equal(normTitle('The.Matrix.1999.1080p.WEB-DL'), 'the matrix 1999 1080p web dl')
  assert.equal(normTitle(undefined), '')
  assert.equal(normTitle('   '), '')
})

test('a live download is matched by name on either of the two record shapes', () => {
  const qbit = { name: 'Dune.Part.Two.2024.2160p.WEB-DL' }
  const arr = { title: 'Dune.Part.Two.2024.1080p' }
  assert.equal(matchTorrent('Dune Part Two', [qbit]), qbit)
  assert.equal(matchTorrent('Dune Part Two', [arr]), arr)
  assert.equal(matchTorrent('Arrival', [qbit, arr]), null)
})

test('a one-character title does not claim every download in the queue', () => {
  assert.equal(matchTorrent('M', [{ name: 'Dune.2021' }]), null)
  assert.equal(matchTorrent('', [{ name: 'Dune.2021' }]), null)
  assert.equal(matchTorrent('Dune', null), null)
  assert.equal(matchTorrent('Dune', undefined), null)
})

// ── copy ────────────────────────────────────────────────────────────────────

test('the meta line closes its gaps instead of padding them', () => {
  assert.deepEqual(metaLine(movie({ ratings: { value: 8 }, year: 2021 }), 'movie', '2h 35m'), [
    '★ 8.0',
    '2h 35m',
    '2021',
  ])
  // Nothing known at all is an empty line, not a row of separators.
  assert.deepEqual(metaLine(movie(), 'movie', null), [])
})

test('series metadata only appears on a series', () => {
  const show = movie({ title: 'Severance', seasonCount: 2, network: 'Apple TV+', status: 'continuing' })
  assert.deepEqual(metaLine(show, 'series', null), ['2 seasons', 'Apple TV+', 'continuing'])
  assert.deepEqual(metaLine(show, 'movie', null), [])
  assert.deepEqual(metaLine(movie({ seasonCount: 1 }), 'series', null), ['1 season'])
})

test('the eyebrow names the kind, the certificate and at most three genres', () => {
  assert.deepEqual(
    eyebrowParts(movie({ certification: 'PG-13', genres: ['Sci-Fi', 'Adventure', 'Drama', 'Epic'] }), 'movie'),
    ['Movie', 'PG-13', 'Sci-Fi', 'Adventure', 'Drama'],
  )
  assert.deepEqual(eyebrowParts(movie(), 'series'), ['Series'])
})

// ── requests ────────────────────────────────────────────────────────────────

test('the one-tap path is unavailable without both a profile and a folder', () => {
  assert.equal(defaultAddOptions({ profiles: [], rootFolders: [{ path: '/m' }], langProfiles: [] }), null)
  assert.equal(defaultAddOptions({ profiles: [{ id: 1 }], rootFolders: [], langProfiles: [] }), null)
  assert.deepEqual(defaultAddOptions({ profiles: [{ id: 4 }], rootFolders: [{ path: '/m' }], langProfiles: [] }), {
    qualityProfileId: 4,
    rootFolderPath: '/m',
  })
})

test('a language profile is only carried when the instance has one', () => {
  const meta = { profiles: [{ id: 4 }], rootFolders: [{ path: '/tv' }], langProfiles: [{ id: 2 }] }
  assert.deepEqual(defaultAddOptions(meta), { qualityProfileId: 4, rootFolderPath: '/tv', languageProfileId: 2 })
})

test('a movie request carries no monitor/search toggles and a series does', () => {
  const options = { qualityProfileId: 4, rootFolderPath: '/m', languageProfileId: 2 }
  const item = movie({ tmdbId: 1 })

  const asMovie = requestBody('movie', item, options)
  assert.deepEqual(asMovie, { movie: item, qualityProfileId: 4, rootFolderPath: '/m' })
  assert.equal('monitor' in asMovie, false, 'a movie request is a single grab-or-remove')
  assert.equal('languageProfileId' in asMovie, false)

  assert.deepEqual(requestBody('series', item, options, { monitor: false, searchNow: true }), {
    series: item,
    qualityProfileId: 4,
    languageProfileId: 2,
    rootFolderPath: '/m',
    monitor: false,
    searchNow: true,
  })
})

test('remove targets the right service and always deletes the files', () => {
  assert.equal(removePath('movie', 12), '/api/servarr/radarr/movie/12?deleteFiles=true')
  assert.equal(removePath('series', 12), '/api/servarr/sonarr/series/12?deleteFiles=true')
})

// ── feed ────────────────────────────────────────────────────────────────────

test('the feed heading tells the truth about where the list came from', () => {
  assert.equal(feedLabel('tmdb_trending'), 'Trending this week')
  assert.equal(feedLabel('curated'), 'Discover')
  assert.equal(feedLabel('import_list'), 'Discover')
})

test('a malformed feed response degrades to an empty curated list', () => {
  assert.deepEqual(parseDiscoverFeed(null), { source: 'curated', items: [] })
  assert.deepEqual(parseDiscoverFeed({ items: 'nope' }), { source: 'curated', items: [] })
  assert.deepEqual(parseDiscoverFeed({ source: 'tmdb_trending', items: [{ title: 'Dune' }, { nope: 1 }] }), {
    source: 'tmdb_trending',
    items: [{ title: 'Dune' }],
  })
})
