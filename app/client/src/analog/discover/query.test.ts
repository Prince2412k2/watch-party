// The URL round-trip, the search gate, and the copy that keeps Discover from
// being a dead end.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  DISCOVER_PATH,
  SEARCH_DEBOUNCE_MS,
  SUGGESTED_SEARCHES,
  discoverEmptyReason,
  discoverPath,
  nextDiscoverUrl,
  railCopy,
  readDiscoverParams,
  searchPath,
  searchPlan,
  unavailableCopy,
} from './query.ts'

test('the debounce is long enough to skip a keystroke and short enough to follow one', () => {
  assert.equal(SEARCH_DEBOUNCE_MS, 400)
})

// ── reading ─────────────────────────────────────────────────────────────────

test('a deep link restores both the term and the kind', () => {
  assert.deepEqual(readDiscoverParams('?q=dune&type=movie'), { kind: 'movie', term: 'dune' })
  assert.deepEqual(readDiscoverParams('?q=severance&type=series'), { kind: 'series', term: 'severance' })
})

test('an absent or malformed type lands on movies rather than on nothing', () => {
  assert.deepEqual(readDiscoverParams(''), { kind: 'movie', term: '' })
  assert.deepEqual(readDiscoverParams('?type=tv'), { kind: 'movie', term: '' })
  assert.deepEqual(readDiscoverParams('?type=SERIES'), { kind: 'movie', term: '' })
})

test('a term with spaces and punctuation survives the round trip', () => {
  const url = nextDiscoverUrl(DISCOVER_PATH, '', { kind: 'movie', term: 'the matrix & co' })
  assert.ok(url)
  const restored = readDiscoverParams(url.slice(url.indexOf('?')))
  assert.equal(restored.term, 'the matrix & co')
})

// ── writing ─────────────────────────────────────────────────────────────────

test('the kind is always written and a blank term is removed, not blanked', () => {
  assert.equal(nextDiscoverUrl(DISCOVER_PATH, '', { kind: 'series', term: '' }), '/discover?type=series')
  // `?q=` with nothing after it would deep-link back into an empty search
  // rather than into the feed.
  assert.equal(nextDiscoverUrl(DISCOVER_PATH, '?q=old&type=movie', { kind: 'movie', term: '  ' }), '/discover?type=movie')
})

test('an unchanged URL is null so replaceState is not called on every keystroke', () => {
  assert.equal(nextDiscoverUrl(DISCOVER_PATH, '?q=dune&type=movie', { kind: 'movie', term: 'dune' }), null)
  // Trailing whitespace is not a change either.
  assert.equal(nextDiscoverUrl(DISCOVER_PATH, '?q=dune&type=movie', { kind: 'movie', term: 'dune ' }), null)
})

test('another page mid-navigation is never rewritten', () => {
  assert.equal(nextDiscoverUrl('/movies', '', { kind: 'movie', term: 'dune' }), null)
  assert.equal(nextDiscoverUrl('/downloads', '?q=x', { kind: 'series', term: 'x' }), null)
})

test('an unrelated query parameter is preserved', () => {
  const url = nextDiscoverUrl(DISCOVER_PATH, '?ref=share', { kind: 'series', term: 'arcane' })
  assert.ok(url?.includes('ref=share'), url ?? 'no url')
  assert.ok(url?.includes('type=series'))
  assert.ok(url?.includes('q=arcane'))
})

// ── the search gate ─────────────────────────────────────────────────────────

test('whitespace is not a search', () => {
  assert.deepEqual(searchPlan(''), { action: 'clear' })
  assert.deepEqual(searchPlan('   '), { action: 'clear' })
  assert.deepEqual(searchPlan('\t\n'), { action: 'clear' })
})

test('a real term is trimmed before it is sent', () => {
  assert.deepEqual(searchPlan('  dune  '), { action: 'search', query: 'dune' })
})

test('a term is encoded into the search path, not concatenated into it', () => {
  assert.equal(searchPath('radarr', 'a&b=c'), '/api/servarr/radarr/search?term=a%26b%3Dc')
  assert.equal(discoverPath('sonarr'), '/api/servarr/sonarr/discover?page=1')
})

// ── the dead ends ───────────────────────────────────────────────────────────

test('an unconfigured service and an unreachable one say different things', () => {
  const never = unavailableCopy('movie', { configured: false, reachable: false })
  const down = unavailableCopy('movie', { configured: true, reachable: false })

  assert.equal(never.transient, false)
  assert.equal(down.transient, true)
  assert.notEqual(never.title, down.title)
  assert.match(down.body, /come back on their own/)
  assert.match(never.body, /Once Discover is configured/)
})

test('unavailable copy never names the underlying service', () => {
  for (const state of [undefined, { configured: true, reachable: false }, { configured: false }]) {
    for (const kind of ['movie', 'series'] as const) {
      const copy = unavailableCopy(kind, state)
      assert.doesNotMatch(`${copy.title} ${copy.body}`, /radarr|sonarr|jellyfin|qbittorrent/i)
    }
  }
})

test('each feed failure gets its own actionable reason', () => {
  const reasons = [
    discoverEmptyReason(503, 'radarr'),
    discoverEmptyReason(502, 'radarr'),
    discoverEmptyReason(200, 'radarr'),
    discoverEmptyReason(0, 'radarr'),
  ]
  assert.equal(new Set(reasons).size, 4, 'four different failures must not collapse into one sentence')
  assert.match(reasons[0], /Radarr/)
  assert.match(discoverEmptyReason(503, 'sonarr'), /Sonarr/)
  assert.match(reasons[1], /Try again/)
  assert.equal(discoverEmptyReason(504, 'radarr'), reasons[1])
})

test('there is always something to search for', () => {
  for (const kind of ['movie', 'series'] as const) {
    assert.ok(SUGGESTED_SEARCHES[kind].length >= 3)
    assert.equal(new Set(SUGGESTED_SEARCHES[kind]).size, SUGGESTED_SEARCHES[kind].length)
  }
})

// ── rail copy ───────────────────────────────────────────────────────────────

const copy = (over: Partial<Parameters<typeof railCopy>[0]> = {}) =>
  railCopy({
    kind: 'movie',
    query: '',
    searching: false,
    searched: false,
    resultCount: 0,
    feedLabel: 'Discover',
    feedReason: null,
    ...over,
  })

test('the rail heading counts results and pluralises honestly', () => {
  assert.equal(copy({ query: 'dune', searched: true, resultCount: 1 }).label, '1 result for “dune”')
  assert.equal(copy({ query: 'dune', searched: true, resultCount: 4 }).label, '4 results for “dune”')
  assert.equal(copy({ query: 'dune', searching: true }).label, 'Searching “dune”')
})

test('no matches reads as no matches, not as an empty library', () => {
  const none = copy({ query: 'zzzz', searched: true, resultCount: 0 })
  assert.match(none.emptyTitle, /No movies matched “zzzz”/)
  assert.match(none.emptyHint, /spelling/)
})

test('with no query the rail is the feed, and its failure reason is the hint', () => {
  assert.equal(copy({ feedLabel: 'Trending this week' }).label, 'Trending this week')
  assert.equal(copy({ feedReason: 'boom' }).emptyHint, 'boom')
  assert.match(copy({ kind: 'series' }).emptyHint, /series/)
})
