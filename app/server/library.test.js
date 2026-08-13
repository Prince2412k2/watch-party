import test from 'node:test'
import assert from 'node:assert/strict'

import { isJellyfinId, isSafeHlsPath, orderByRecentlyWatched } from './library.js'

const REAL_ID = '0123456789abcdef0123456789abcdef'
const REAL_GUID = '01234567-89ab-cdef-0123-456789abcdef'

test('isJellyfinId accepts dashless and dashed GUIDs, rejects everything else', () => {
  assert.equal(isJellyfinId(REAL_ID), true)
  assert.equal(isJellyfinId(REAL_GUID), true)
  assert.equal(isJellyfinId(`${REAL_ID}&IncludeItemTypes=Movie`), false)
  assert.equal(isJellyfinId('not-an-id'), false)
  assert.equal(isJellyfinId(''), false)
  assert.equal(isJellyfinId(undefined), false)
  assert.equal(isJellyfinId([REAL_ID]), false)
})

test('isSafeHlsPath rejects dot-segment traversal even though the characters are individually allowed', () => {
  // The character-class-only guard this replaces let "." and ".." straight
  // through, and fetch()'s URL parsing then collapsed them — this is the
  // exact payload that reached Jellyfin's /System/Info in the old code.
  assert.equal(isSafeHlsPath('Videos/../../System/Info'), false)
  assert.equal(isSafeHlsPath('Videos/./x'), false)
})

test('isSafeHlsPath accepts the shapes our own HLS URLs produce', () => {
  assert.equal(isSafeHlsPath(`Videos/${REAL_ID}/master.m3u8`), true)
  assert.equal(isSafeHlsPath(`Videos/${REAL_ID}/hls1/main/0.ts`), true)
})

test('isSafeHlsPath rejects paths whose item id is not a real Jellyfin id', () => {
  assert.equal(isSafeHlsPath('Videos/not-an-id/master.m3u8'), false)
  assert.equal(isSafeHlsPath(`Videos/${REAL_ID}&api_key=x/master.m3u8`), false)
  assert.equal(isSafeHlsPath('Videos'), false)
  assert.equal(isSafeHlsPath(''), false)
  assert.equal(isSafeHlsPath(null), false)
})

// ── Recently-watched ordering ────────────────────────────────────────────────

test('recently watched leads the rail; the untouched tail keeps its order', () => {
  const items = [
    { Name: 'Alien' },
    { Name: 'Arrival', UserData: { LastPlayedDate: '2026-08-12T20:00:00Z' } },
    { Name: 'Blade Runner' },
    { Name: 'Dune', UserData: { LastPlayedDate: '2026-08-13T09:00:00Z' } },
    { Name: 'Heat', UserData: { LastPlayedDate: '2026-08-06T21:00:00Z' } },
  ]

  assert.deepEqual(
    orderByRecentlyWatched(items).map((i) => i.Name),
    // Played first, newest first. Then the never-played ones exactly as the
    // query returned them — alphabetical — so the rest of the library is still
    // something you can scan.
    ['Dune', 'Arrival', 'Heat', 'Alien', 'Blade Runner'],
  )
})

test('an unplayable date is treated as never played, not as the epoch', () => {
  const items = [
    { Name: 'Alien' },
    { Name: 'Broken', UserData: { LastPlayedDate: 'not a date' } },
    { Name: 'Dune', UserData: { LastPlayedDate: '2026-08-13T09:00:00Z' } },
  ]
  // `Date.parse` yields NaN, and a NaN comparison sorts unpredictably — it must
  // fall to the tail rather than land somewhere arbitrary among real dates.
  assert.deepEqual(
    orderByRecentlyWatched(items).map((i) => i.Name),
    ['Dune', 'Alien', 'Broken'],
  )
})

test('ordering survives a library with nothing watched, and a junk payload', () => {
  const untouched = [{ Name: 'Alien' }, { Name: 'Blade Runner' }]
  assert.deepEqual(
    orderByRecentlyWatched(untouched).map((i) => i.Name),
    ['Alien', 'Blade Runner'],
  )
  assert.deepEqual(orderByRecentlyWatched(null), [])
  assert.deepEqual(orderByRecentlyWatched(undefined), [])
})
