// Focus survives a surface change.
//
// "Back returns to the exact browsing position and focused item." browseCore's
// `restoreFocus` decides which item that is; these cases cover the layer that
// makes it usable from a surface — naming surfaces so two levels do not share
// one memory, holding the memory across the unmount that a drill-in causes, and
// turning the core's id answer back into the index a shelf renders from.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  EMPTY_FOCUS_PLAN,
  focusPlan,
  planForSurface,
  rememberSurfaceFocus,
  resetSurfaceFocus,
  shelfSnapshot,
  surfaceId,
} from './surface.ts'
import { rememberFocus } from './browseCore.ts'

const items = (...ids: string[]) => ids.map((Id) => ({ Id }))

test('a surface is named by its tab and its drill-down path', () => {
  assert.equal(surfaceId('movies'), 'movies')
  assert.equal(surfaceId('movies', [{ id: 'view-1', name: 'Movies' }]), 'movies/view-1')
  assert.equal(surfaceId('movies', [{ id: 'view-1' }, { id: 'coll-9' }]), 'movies/view-1/coll-9')
  // A level the server could not identify must not silently collapse two
  // different surfaces onto one memory slot.
  assert.equal(surfaceId('movies', [{ name: 'unnamed' }]), 'movies')
})

test('a plan turns the core answer into shelf indices', () => {
  const shelves = [shelfSnapshot('movies', items('a', 'b', 'c'))]
  const memory = rememberFocus({}, 'movies/view', { shelfId: 'movies', itemId: 'c' })
  assert.deepEqual(focusPlan(memory, 'movies/view', shelves, 2), { kind: 'exact', shelfIndex: 0, itemIndex: 2 })
})

test('nothing remembered lands on the first focusable item', () => {
  const shelves = [shelfSnapshot('empty', []), shelfSnapshot('movies', items('a', 'b'))]
  assert.deepEqual(focusPlan({}, 'movies/view', shelves, 0), { kind: 'default', shelfIndex: 1, itemIndex: 0 })
})

test('a surface with nothing focusable reports empty rather than index zero', () => {
  assert.deepEqual(focusPlan({}, 'movies/view', [shelfSnapshot('movies', [])], 0), EMPTY_FOCUS_PLAN)
  assert.deepEqual(focusPlan({}, 'movies/view', [], 0), EMPTY_FOCUS_PLAN)
})

test('drilling into a title and coming back restores the exact item', () => {
  resetSurfaceFocus()
  const shelves = [shelfSnapshot('movies', items('a', 'b', 'c', 'd'))]
  const surface = surfaceId('movies', [{ id: 'view-1' }])

  rememberSurfaceFocus(surface, 'movies', 'c', 2)
  // The surface unmounts entirely while the detail stage is open, which is
  // exactly why the memory cannot live in component state.
  const plan = planForSurface(surface, shelves)
  assert.deepEqual(plan, { kind: 'exact', shelfIndex: 0, itemIndex: 2 })
})

test('two levels of the same tab keep separate focus', () => {
  resetSurfaceFocus()
  const top = surfaceId('movies', [{ id: 'view-1' }])
  const inner = surfaceId('movies', [{ id: 'view-1' }, { id: 'coll-9' }])
  const topShelf = [shelfSnapshot('movies', items('a', 'b', 'c'))]
  const innerShelf = [shelfSnapshot('movies', items('x', 'y', 'z'))]

  rememberSurfaceFocus(top, 'movies', 'c', 2)
  rememberSurfaceFocus(inner, 'movies', 'x', 0)

  assert.equal(planForSurface(top, topShelf).itemIndex, 2, 'the deeper level must not overwrite the shallower one')
  assert.equal(planForSurface(inner, innerShelf).itemIndex, 0)
})

test('a title removed while you were away holds its index', () => {
  resetSurfaceFocus()
  const surface = surfaceId('movies', [{ id: 'view-1' }])
  rememberSurfaceFocus(surface, 'movies', 'c', 2)

  // 'c' was deleted from the library; focus lands where the attention was.
  const plan = planForSurface(surface, [shelfSnapshot('movies', items('a', 'b', 'd', 'e'))])
  assert.deepEqual(plan, { kind: 'nearest', shelfIndex: 0, itemIndex: 2 })
})

test('the held index clamps into a shelf that shrank past it', () => {
  resetSurfaceFocus()
  const surface = surfaceId('movies', [{ id: 'view-1' }])
  rememberSurfaceFocus(surface, 'movies', 'f', 5)

  const plan = planForSurface(surface, [shelfSnapshot('movies', items('a', 'b'))])
  assert.deepEqual(plan, { kind: 'nearest', shelfIndex: 0, itemIndex: 1 })
})

test('a shelf that emptied falls back rather than restoring into nothing', () => {
  resetSurfaceFocus()
  const surface = surfaceId('movies', [{ id: 'view-1' }])
  rememberSurfaceFocus(surface, 'movies', 'c', 2)

  assert.deepEqual(planForSurface(surface, [shelfSnapshot('movies', [])]), EMPTY_FOCUS_PLAN)
  assert.deepEqual(
    planForSurface(surface, [shelfSnapshot('movies', []), shelfSnapshot('recent', items('r1'))]),
    { kind: 'default', shelfIndex: 1, itemIndex: 0 },
  )
})

test('a surface never visited falls back to the default without crashing', () => {
  resetSurfaceFocus()
  const plan = planForSurface(surfaceId('movies', [{ id: 'brand-new' }]), [
    shelfSnapshot('movies', items('a', 'b')),
  ])
  assert.deepEqual(plan, { kind: 'default', shelfIndex: 0, itemIndex: 0 })
})
