// The fixed cursor, and what has to be warm before it gets there.
//
// `railWindow`/`clampRailOffset` are already covered by the shared interaction
// fixture in both languages. What is NOT covered there is the thing this surface
// actually does with them: pin the cursor to the first slot, let the row run out
// of travel at the end of the library, and warm the artwork that is about to
// arrive. Those are the cases here.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  prefetchTargets,
  railCursor,
  railMetrics,
  railRendered,
  railStepPx,
  railTranslatePx,
  stepRailSelection,
} from './movieRail.ts'
import { railWindow } from './browseCore.ts'
import { UNVERIFIED_TAG } from './artwork.ts'

const items = (count: number) =>
  Array.from({ length: count }, (_, index) => ({ Id: `m${index}`, Name: `Movie ${index}`, Type: 'Movie' }))

test('the cursor stays in the first slot and the row moves underneath it', () => {
  for (let selection = 0; selection <= 14; selection += 1) {
    const cursor = railCursor({ total: 20, selection, slots: 6 })
    assert.equal(cursor.cursorSlot, 0, `selection ${selection} moved the cursor instead of the row`)
    assert.equal(cursor.start, selection)
    assert.equal(cursor.visible[0], selection, 'the selected item must be the one under the cursor')
    assert.equal(cursor.visible.length, 6)
  }
})

test('the cursor walks the last page once the row has no travel left', () => {
  // total 20, slots 6 -> the row stops at start 14. Selecting 15..19 has to move
  // the cursor, because the alternative is five titles you can see and never
  // reach.
  const tail = [15, 16, 17, 18, 19].map((selection) => railCursor({ total: 20, selection, slots: 6 }))

  assert.deepEqual(tail.map((cursor) => cursor.start), [14, 14, 14, 14, 14])
  assert.deepEqual(tail.map((cursor) => cursor.cursorSlot), [1, 2, 3, 4, 5])
  for (const [offset, cursor] of tail.entries()) {
    assert.equal(cursor.visible[cursor.cursorSlot], 15 + offset)
  }
})

test('a rail shorter than the row never moves at all', () => {
  const cursor = railCursor({ total: 3, selection: 2, slots: 6 })
  assert.equal(cursor.start, 0)
  assert.equal(cursor.cursorSlot, 2)
  assert.deepEqual(cursor.visible, [0, 1, 2])
  assert.deepEqual(cursor.prefetch, [])
})

test('an out-of-range selection is clamped rather than emptying the window', () => {
  assert.deepEqual(railCursor({ total: 5, selection: 99, slots: 3 }), {
    start: 2,
    cursorSlot: 2,
    visible: [2, 3, 4],
    prefetch: [0, 1],
  })
  assert.deepEqual(railCursor({ total: 5, selection: -4, slots: 3 }).visible, [0, 1, 2])
  assert.deepEqual(railCursor({ total: 0, selection: 0, slots: 6 }), {
    start: 0,
    cursorSlot: 0,
    visible: [],
    prefetch: [],
  })
})

test('the cursor derives its window from the shared core, not a second copy', () => {
  // If this stops agreeing, the rail has grown its own geometry and the Flutter
  // port is no longer showing the same items.
  for (const selection of [0, 1, 7, 13, 14, 19]) {
    const cursor = railCursor({ total: 20, selection, slots: 6 })
    const shared = railWindow({ total: 20, offset: selection, slots: 6 })
    assert.deepEqual({ visible: cursor.visible, prefetch: cursor.prefetch }, shared)
  }
})

test('stepping is clamped at both ends', () => {
  assert.equal(stepRailSelection(0, 20, -1), 0)
  assert.equal(stepRailSelection(0, 20, 1), 1)
  assert.equal(stepRailSelection(19, 20, 1), 19)
  assert.equal(stepRailSelection(19, 20, -1), 18)
  // One item per step whatever the caller passes, so a burst of wheel deltas
  // cannot be laundered into a jump.
  assert.equal(stepRailSelection(5, 20, 6), 6)
  assert.equal(stepRailSelection(5, 20, -6), 4)
  assert.equal(stepRailSelection(3, 0, 1), 0)
})

test('the track translates by whole slots', () => {
  assert.equal(railStepPx(118, 14), 132)
  assert.equal(railTranslatePx(0, 118, 14), 0)
  assert.equal(railTranslatePx(5, 118, 14), -660)
  // Never positive: a positive translate would drag the row away from the
  // cursor and leave the first slot empty.
  assert.ok(railTranslatePx(14, 118, 14) < 0)
})

test('the rendered range is contiguous and covers the warmed neighbours', () => {
  const cursor = railCursor({ total: 40, selection: 10, slots: 6 })
  const rendered = railRendered(cursor)

  assert.deepEqual(rendered, [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21])
  for (const index of [...cursor.visible, ...cursor.prefetch]) {
    assert.ok(rendered.includes(index), `${index} was warmed but never mounted`)
  }
  // Bounded: a 40-title library must not put 40 posters in the DOM.
  assert.ok(rendered.length < 20)
  assert.deepEqual(railRendered({ start: 0, cursorSlot: 0, visible: [], prefetch: [] }), [])
})

test('the prefetch set is the artwork about to arrive, posters and backdrops', () => {
  const list = items(40)
  const cursor = railCursor({ total: list.length, selection: 0, slots: 6 })

  // Nothing behind index 0, so this is the lookahead only.
  assert.deepEqual(cursor.prefetch, [6, 7, 8, 9, 10, 11])

  const urls = prefetchTargets({ items: list, indices: cursor.prefetch })
  assert.deepEqual(urls.slice(0, 4), [
    '/api/library/image/m6?type=Primary',
    '/api/library/image/m6?type=Backdrop',
    '/api/library/image/m7?type=Primary',
    '/api/library/image/m7?type=Backdrop',
  ])
  assert.equal(urls.length, cursor.prefetch.length * 2)
  // Never the item under the cursor: it is already on screen, and re-requesting
  // it is exactly the wasted fetch prefetching is supposed to avoid.
  assert.ok(!urls.some((url) => url.includes('/m0?')))
})

test('prefetch skips artwork that is missing or already known to 404', () => {
  const list = [
    { Id: 'a', Name: 'Art', Type: 'Movie', ImageTags: { Primary: 'tag' } },
    { Id: 'b', Name: 'Bare', Type: 'Movie', ImageTags: {} },
    { Id: 'c', Name: 'Broken', Type: 'Movie', ImageTags: { Primary: 'tag' } },
  ]

  const urls = prefetchTargets({ items: list, indices: [0, 1, 2, 9], failedIds: ['c'] })

  // 'b' has no poster and 'c' already failed, so neither contributes a Primary —
  // but both still have a backdrop worth warming, and index 9 does not exist.
  assert.deepEqual(urls, [
    '/api/library/image/a?type=Primary',
    '/api/library/image/a?type=Backdrop',
    '/api/library/image/b?type=Backdrop',
    '/api/library/image/c?type=Backdrop',
  ])
})

test('prefetch never emits the same URL twice', () => {
  const list = items(4)
  const urls = prefetchTargets({ items: list, indices: [1, 1, 2] })
  assert.equal(new Set(urls).size, urls.length)
  assert.equal(urls.length, 4)
})

test('an item with no ImageTags map is assumed to have artwork', () => {
  // The library proxy only guarantees the fields it asks for, and "absent" must
  // not be read as "no artwork" — that would drop every poster to a placeholder.
  const urls = prefetchTargets({ items: [{ Id: 'z', Name: 'Zed', Type: 'Movie' }], indices: [0] })
  assert.ok(urls.includes('/api/library/image/z?type=Primary'))
  assert.equal(UNVERIFIED_TAG, 'unverified')
})

test('the rail is sized smaller than the shelf it replaces, and ends on a poster edge', () => {
  // stageLayout's shelf puts 7 across a 1280px desktop at ~166px each. The rail
  // is a strip under the details, so it has to be visibly smaller than that.
  const desktop = railMetrics(1280 - 96, 'desktop')
  assert.ok(desktop.posterWidthPx < 120, 'the rail is a strip, not the main event')
  assert.ok(desktop.slots >= 9, 'a small poster should show far more of the library at once')
  // Whole posters plus the gaps between them fill the width exactly, so the rail
  // never ends on a sliver of the next one.
  assert.ok(
    desktop.posterWidthPx * desktop.slots + desktop.gapPx * (desktop.slots - 1) <= 1280 - 96,
    'the computed row overflows its usable width',
  )

  const phone = railMetrics(390 - 40, 'phone')
  assert.ok(phone.posterWidthPx < desktop.posterWidthPx)
  assert.ok(phone.slots >= 3, 'a phone keeps the same rail, just fewer slots')

  // A viewport narrower than one poster still yields a usable rail rather than
  // zero slots and a division by zero downstream.
  const sliver = railMetrics(30, 'phone')
  assert.equal(sliver.slots, 1)
  assert.ok(sliver.posterWidthPx > 0)
})
