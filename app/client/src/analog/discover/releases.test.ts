// The picker's lifecycle rules — the ones whose failure mode is a stale entry
// left in Radarr rather than anything visible on screen.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  PICKER_CANCEL_DELAYS,
  cancelSettled,
  parseReleaseData,
  releaseCountLabel,
  releaseRow,
  releasesRequest,
  retainedToken,
  shouldCancelPicker,
} from './releases.ts'
import type { CatalogItem } from './catalog.ts'

const item = (over: Partial<CatalogItem> = {}): CatalogItem => ({ title: 'Dune', tmdbId: 1, ...over })
const options = { qualityProfileId: 4, rootFolderPath: '/movies' }

// ── backoff ─────────────────────────────────────────────────────────────────

test('the cancel backoff starts immediately and is bounded', () => {
  assert.deepEqual([...PICKER_CANCEL_DELAYS], [0, 250, 750, 1500, 3000])
  assert.equal(PICKER_CANCEL_DELAYS[0], 0, 'the first attempt must not wait')
  // Monotonic, so a retry never lands sooner than the one before it.
  for (let i = 1; i < PICKER_CANCEL_DELAYS.length; i += 1) {
    assert.ok(PICKER_CANCEL_DELAYS[i] > PICKER_CANCEL_DELAYS[i - 1])
  }
  const total = PICKER_CANCEL_DELAYS.reduce((sum, delay) => sum + delay, 0)
  assert.ok(total > 3000 && total < 10_000, `bounded window, got ${total}ms`)
})

test('only "busy" is worth retrying — every other answer is final', () => {
  assert.equal(cancelSettled(503), false)
  assert.equal(cancelSettled(200), true)
  assert.equal(cancelSettled(204), true)
  // A 404 means the entry is already gone; retrying cannot improve on that.
  assert.equal(cancelSettled(404), true)
  assert.equal(cancelSettled(500), true)
})

test('a picker with nothing of its own to remove does not call cancel at all', () => {
  const base = { movieId: 7, cancellationToken: 'tok', settled: false, cancelling: false }
  assert.equal(shouldCancelPicker(base), true)
  // No token = the entry was already in the library and is not ours to delete.
  assert.equal(shouldCancelPicker({ ...base, cancellationToken: null }), false)
  assert.equal(shouldCancelPicker({ ...base, movieId: null }), false)
  // Guards against the double-fire from close-then-unmount.
  assert.equal(shouldCancelPicker({ ...base, settled: true }), false)
  assert.equal(shouldCancelPicker({ ...base, cancelling: true }), false)
})

// ── opening ─────────────────────────────────────────────────────────────────

test('a title already in the library is searched by its own id and never added', () => {
  const request = releasesRequest({
    item: item({ id: 42 }),
    operationId: 'op',
    existingMovieId: null,
    options,
  })
  assert.equal(request?.kind, 'library')
  assert.deepEqual(request?.body, { movieId: 42, operationId: 'op' })
})

test('a title not in the library is added by the request that searches it', () => {
  const request = releasesRequest({ item: item(), operationId: 'op', existingMovieId: null, options })
  assert.equal(request?.kind, 'add')
  assert.deepEqual(request?.body, {
    movie: item(),
    qualityProfileId: 4,
    rootFolderPath: '/movies',
    operationId: 'op',
  })
})

test('a retry reuses the entry the first attempt created rather than adding twice', () => {
  const request = releasesRequest({ item: item(), operationId: 'op', existingMovieId: 99, options })
  assert.equal(request?.kind, 'existing')
  assert.deepEqual(request?.body, { movieId: 99, operationId: 'op' })
})

test('an existing entry outranks library membership, so a retry cannot fork', () => {
  const request = releasesRequest({ item: item({ id: 42 }), operationId: 'op', existingMovieId: 99, options })
  assert.deepEqual(request?.body, { movieId: 99, operationId: 'op' })
})

test('without add options there is no request to make', () => {
  assert.equal(releasesRequest({ item: item(), operationId: 'op', existingMovieId: null, options: null }), null)
})

test('the retry keeps the ORIGINAL cancellation token', () => {
  // The retry response carries none; overwriting with it would strand the entry
  // the first request created.
  assert.equal(retainedToken('existing', 'first-token', undefined), 'first-token')
  assert.equal(retainedToken('existing', 'first-token', 'second-token'), 'first-token')
  // A library entry is never ours, whatever the server echoes.
  assert.equal(retainedToken('library', 'first-token', 'echo'), null)
  // A fresh add takes the token it was just issued.
  assert.equal(retainedToken('add', null, 'fresh'), 'fresh')
  assert.equal(retainedToken('add', null, undefined), null)
})

// ── parsing ─────────────────────────────────────────────────────────────────

test('a response without a movie id is not a release list', () => {
  assert.deepEqual(parseReleaseData(null), { movieId: 0, releases: [] })
  assert.deepEqual(parseReleaseData({ releases: [{ guid: 'a' }] }), { movieId: 0, releases: [] })
})

test('release parsing drops entries with no guid and keeps the flags', () => {
  const data = parseReleaseData({
    movieId: 5,
    createdByPicker: true,
    cancellationToken: 'tok',
    searchFailed: false,
    releases: [{ guid: 'a' }, { title: 'no guid' }],
  })
  assert.equal(data.movieId, 5)
  assert.equal(data.createdByPicker, true)
  assert.equal(data.cancellationToken, 'tok')
  assert.equal(data.searchFailed, false)
  assert.deepEqual(data.releases, [{ guid: 'a' }])
})

// ── rows ────────────────────────────────────────────────────────────────────

test('a zero-seed release is toned apart from a healthy one', () => {
  assert.equal(releaseRow({ guid: 'a', seeders: 0 }).seedTone, 'none')
  assert.equal(releaseRow({ guid: 'a', seeders: 12 }).seedTone, 'some')
  // Unknown is not zero: an indexer that does not report seeders must not make
  // every one of its releases look dead.
  assert.equal(releaseRow({ guid: 'a' }).seedTone, 'unknown')
  assert.equal(releaseRow({ guid: 'a' }).seedLabel, '— seeds')
  assert.equal(releaseRow({ guid: 'a', seeders: 1 }).seedLabel, '1 seed')
  assert.equal(releaseRow({ guid: 'a', seeders: 0 }).seedLabel, '0 seeds')
})

test('a rejected release is greyed, un-grabbable and says why', () => {
  const row = releaseRow({ guid: 'a', rejected: true, rejections: ['Not a preferred word', 'Too big'] })
  assert.equal(row.rejected, true)
  assert.equal(row.grabbable, false)
  assert.equal(row.reason, 'Not a preferred word')
  assert.deepEqual(row.reasons, ['Not a preferred word', 'Too big'])
})

test('a rejection with no reason still explains itself', () => {
  assert.equal(releaseRow({ guid: 'a', rejected: true }).reason, 'Skipped by the quality profile')
  assert.equal(releaseRow({ guid: 'a' }).reason, null)
  assert.equal(releaseRow({ guid: 'a' }).grabbable, true)
})

test('a row always has something to render as its title', () => {
  assert.equal(releaseRow({ guid: 'abc' }).title, 'abc')
  assert.equal(releaseRow({ guid: 'abc', title: 'Dune.2021.1080p' }).title, 'Dune.2021.1080p')
})

test('size, peers and indexer degrade rather than render undefined', () => {
  const row = releaseRow({ guid: 'a' })
  assert.equal(row.sizeLabel, '—')
  assert.equal(row.peerLabel, '— peers')
  assert.equal(row.indexer, null)
  assert.equal(row.quality, null)
  assert.equal(releaseRow({ guid: 'a', size: 1536 }).sizeLabel, '1.5 KB')
})

test('the picker counts what it found', () => {
  assert.equal(releaseCountLabel(0), '0 sources')
  assert.equal(releaseCountLabel(1), '1 source')
  assert.equal(releaseCountLabel(9), '9 sources')
})
