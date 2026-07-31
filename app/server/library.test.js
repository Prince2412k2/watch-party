import test from 'node:test'
import assert from 'node:assert/strict'

import { isJellyfinId, isSafeHlsPath } from './library.js'

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
