import test from 'node:test'
import assert from 'node:assert/strict'
import { trickplayFrame, type TrickplayManifest } from './trickplay.ts'

const manifest: TrickplayManifest = {
  itemId: 'movie', mediaSourceId: 'source', width: 100, height: 50,
  tileWidth: 4, tileHeight: 2, thumbnailCount: 10, intervalMs: 10_000,
  sheetCount: 2, sheetUrlTemplate: '/sheets/{sheetIndex}.jpg',
}

test('maps time to a tile and advances across sheets', () => {
  assert.deepEqual(trickplayFrame(manifest, 70), { sheetIndex: 0, x: 300, y: 50, columns: 4, rows: 2 })
  assert.deepEqual(trickplayFrame(manifest, 80), { sheetIndex: 1, x: 0, y: 0, columns: 4, rows: 2 })
})

test('clamps negative and out-of-range times to available thumbnails', () => {
  assert.deepEqual(trickplayFrame(manifest, -5), { sheetIndex: 0, x: 0, y: 0, columns: 4, rows: 2 })
  assert.deepEqual(trickplayFrame(manifest, 10_000), { sheetIndex: 1, x: 100, y: 0, columns: 4, rows: 2 })
})

test('clamps to actual sheet capacity when thumbnailCount is inconsistent', () => {
  const inconsistent = { ...manifest, thumbnailCount: 100, sheetCount: 1 }
  assert.deepEqual(trickplayFrame(inconsistent, 10_000), { sheetIndex: 0, x: 300, y: 50, columns: 4, rows: 2 })
})

test('rejects unusable sprite geometry', () => {
  assert.equal(trickplayFrame({ ...manifest, tileWidth: 0 }, 0), null)
  assert.equal(trickplayFrame({ ...manifest, intervalMs: 0 }, 0), null)
})
