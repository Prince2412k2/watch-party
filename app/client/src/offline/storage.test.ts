import test from 'node:test'
import assert from 'node:assert/strict'
import 'fake-indexeddb/auto'
import {
  CACHE_TTL,
  CHUNK_SIZE,
  chunk,
  clearCache,
  getMedia,
  listMedia,
  prepare,
  putChunk,
  putSubtitle,
  read,
  removeMedia,
  setOwner,
  type MediaInfo
} from './storage.ts'
import { byteRange, validateChunk } from './ranges.ts'
const info = (id: string, owner = 'alice'): MediaInfo => ({
  owner,
  itemId: id,
  sourceId: 'source',
  revision: 'one',
  size: CHUNK_SIZE + 3,
  title: 'Movie ' + id,
  series: '',
  duration: 120,
  audioIndex: 1,
  etag: '"one"',
  modified: '',
  subtitles: []
})
test('range requests support Safari probes, suffixes and seeking; reject malformed ranges', () => {
  assert.deepEqual(byteRange('bytes=0-1', 10), { start: 0, end: 1 })
  assert.deepEqual(byteRange('bytes=-3', 10), { start: 7, end: 9 })
  assert.deepEqual(byteRange('bytes=4-', 10), { start: 4, end: 9 })
  assert.equal(byteRange('bytes=10-', 10), null)
  assert.equal(byteRange('bytes=8-2', 10), null)
  assert.equal(byteRange('bytes=0-1,4-5', 10), null)
  assert.throws(() =>
    validateChunk(new Response('data', { status: 200 }), 0, 3, 4)
  )
  assert.throws(() =>
    validateChunk(
      new Response('data', {
        status: 206,
        headers: { 'content-range': 'bytes 0-3/5' }
      }),
      0,
      3,
      4
    )
  )
})
test('watched chunks promote to a download; clear and TTL protect partial downloads', async () => {
  await setOwner('alice')
  const cache = await prepare(info('promotion'), 'cache')
  await putChunk(cache, 0, new Blob([new Uint8Array(CHUNK_SIZE)]))
  const pin = await prepare(info('promotion'), 'download')
  assert.equal(pin.received, CHUNK_SIZE)
  assert.equal(pin.generation, cache.generation)
  await prepare(info('promotion'), 'cache')
  await clearCache('alice')
  assert.equal((await getMedia(pin.key))?.retention, 'download')
  await putChunk(pin, 1, new Blob([new Uint8Array(3)]))
  assert.equal((await getMedia(pin.key))?.state, 'complete')
  await putChunk(pin, 1, new Blob([new Uint8Array(3)]))
  assert.equal((await getMedia(pin.key))?.received, pin.size)
})
test('removal drains chunks and late writers cannot resurrect or poison a recreated file', async () => {
  const record = await prepare(info('removed'), 'download')
  await putChunk(record, 0, new Blob(['old']))
  await putSubtitle(record, 2, new Blob(['WEBVTT']))
  await removeMedia(record.key)
  assert.equal(await chunk(record.key, 0), undefined)
  assert.equal(await read('subtitles', [record.key, 2]), undefined)
  assert.equal(await putChunk(record, 1, new Blob(['late'])), false)
  assert.equal(await getMedia(record.key), undefined)
  const replacement = await prepare(info('removed'), 'download')
  assert.notEqual(replacement.generation, record.generation)
  assert.equal(await putChunk(record, 0, new Blob(['old'])), false)
  assert.equal(await chunk(record.key, 0), undefined)
  await putSubtitle(record, 2, new Blob(['late captions']))
  assert.equal(await read('subtitles', [record.key, 2]), undefined)
})
test('cache clearing is account scoped and expiry uses inactivity, preserving active reads', async () => {
  const old = await prepare(info('old'), 'cache')
  const recent = await prepare(info('recent'), 'cache')
  const bob = await prepare(info('other', 'bob'), 'cache')
  const { updateMedia } = await import('./storage.ts')
  await updateMedia(
    old.key,
    (r) => r && { ...r, accessed: Date.now() - CACHE_TTL - 1000 }
  )
  await clearCache('alice', true, new Set([old.key]))
  assert.ok(await getMedia(old.key))
  await clearCache('alice', true)
  assert.equal(await getMedia(old.key), undefined)
  assert.ok(await getMedia(recent.key))
  await clearCache('alice')
  assert.equal(await getMedia(recent.key), undefined)
  assert.ok(await getMedia(bob.key))
  assert.ok((await listMedia('alice')).every((m) => m.owner === 'alice'))
})
