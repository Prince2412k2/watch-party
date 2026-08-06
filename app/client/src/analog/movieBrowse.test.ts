// Singles ⇄ Collections, and drilling into a franchise.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  BROWSE_MODES,
  activationFor,
  closeCollection,
  collectionFromStack,
  isBrowseMode,
  modeForScrollStep,
  modeFromStack,
  moviesTab,
  openCollection,
  rootLevel,
  stageKeyIntent,
  stepBrowseMode,
  withMode,
  type MovieLevel,
} from './movieBrowse.ts'
import { surfaceId } from './surface.ts'

const view = { Id: 'view-1', Name: 'Movies', Type: 'CollectionFolder' }
const root = (mode: 'singles' | 'collections' = 'singles'): MovieLevel[] => [rootLevel(view, mode)]

test('the mode slider steps and clamps rather than wrapping', () => {
  assert.deepEqual(BROWSE_MODES, ['singles', 'collections'])
  assert.equal(stepBrowseMode('singles', 1), 'collections')
  assert.equal(stepBrowseMode('collections', -1), 'singles')
  // Held Down settles on the last position instead of flickering back to the
  // first, which is what a two-position slider that wrapped would do.
  assert.equal(stepBrowseMode('collections', 1), 'collections')
  assert.equal(stepBrowseMode('singles', -1), 'singles')
  assert.equal(stepBrowseMode('singles', 0), 'singles')
})

test('a stepped scroll outside the rail moves the same slider the arrows do', () => {
  assert.equal(modeForScrollStep('singles', 1), stepBrowseMode('singles', 1))
  assert.equal(modeForScrollStep('collections', -1), stepBrowseMode('collections', -1))
  // steppedScroll returns 0 for everything that is not a deliberate step —
  // absorbed momentum, a delta under the threshold, a burst inside the cooldown.
  assert.equal(modeForScrollStep('collections', 0), 'collections')
})

test('the four arrows are four different movements on this stage', () => {
  // NOT stageCore.focusIntentForKey, which folds Up/Down onto Left/Right: this
  // stage has a horizontal rail AND a vertical mode slider.
  assert.equal(stageKeyIntent('ArrowLeft'), 'rail-prev')
  assert.equal(stageKeyIntent('ArrowRight'), 'rail-next')
  assert.equal(stageKeyIntent('ArrowUp'), 'mode-prev')
  assert.equal(stageKeyIntent('ArrowDown'), 'mode-next')
  assert.equal(stageKeyIntent('Enter'), 'activate')
  assert.equal(stageKeyIntent(' '), 'activate')
  assert.equal(stageKeyIntent('Spacebar'), 'activate')
  assert.equal(stageKeyIntent('Escape'), 'back')
  assert.equal(stageKeyIntent('Backspace'), 'back')
  assert.equal(stageKeyIntent('a'), null)
  assert.equal(stageKeyIntent('Tab'), null)
})

test('the mode rides on the stack, so a party follower sees the one the host is on', () => {
  assert.equal(modeFromStack(root('collections')), 'collections')
  assert.equal(modeFromStack(root('singles')), 'singles')
  // A host on the superseded Library implementation publishes a stack with no
  // mode at all; a follower must land somewhere rather than crash.
  assert.equal(modeFromStack([{ id: 'view-1', name: 'Movies' }]), 'singles')
  assert.equal(modeFromStack([]), 'singles')
  assert.equal(modeFromStack([{ id: 'v', mode: 'nonsense' } as unknown as MovieLevel]), 'singles')
  assert.equal(modeFromStack([], 'collections'), 'collections')
  assert.ok(isBrowseMode('singles') && isBrowseMode('collections'))
  assert.equal(isBrowseMode('movies'), false)
})

test('switching mode leaves any franchise you were inside', () => {
  const inside = openCollection(root('collections'), { Id: 'box-1', Name: 'Alien', Type: 'BoxSet' })
  assert.equal(inside.length, 2)

  const switched = withMode(inside, 'singles')
  assert.deepEqual(switched, [{ id: 'view-1', name: 'Movies', type: 'CollectionFolder', mode: 'singles' }])
  assert.equal(collectionFromStack(switched), null)
  assert.deepEqual(withMode([], 'singles'), [])
})

test('opening a collection pushes a level and Back pops it', () => {
  const stack = openCollection(root('collections'), { Id: 'box-1', Name: 'Alien', Type: 'BoxSet' })

  assert.deepEqual(stack, [
    { id: 'view-1', name: 'Movies', type: 'CollectionFolder', mode: 'collections' },
    { id: 'box-1', name: 'Alien', type: 'BoxSet' },
  ])
  assert.deepEqual(collectionFromStack(stack), { id: 'box-1', name: 'Alien', type: 'BoxSet' })

  const back = closeCollection(stack)
  assert.equal(back.length, 1)
  assert.equal(collectionFromStack(back), null)
  assert.equal(modeFromStack(back), 'collections', 'Back must return to the list you came from')

  // Back at the root is a no-op, not an empty stack that would leave the surface
  // with nothing to fetch.
  assert.deepEqual(closeCollection(back), back)
})

test('opening a collection from Singles switches the mode with it', () => {
  // A box set can turn up in a library listing. Following it must not leave the
  // slider pointing at Singles while the rail shows a franchise's parts.
  const stack = openCollection(root('singles'), { Id: 'box-1', Name: 'Alien' })
  assert.equal(modeFromStack(stack), 'collections')
  assert.equal(stack[1].type, 'BoxSet')
  assert.deepEqual(openCollection([], { Id: 'box-1', Name: 'Alien' }), [])
})

test('only a box set counts as a drill-in', () => {
  // The wire type allows every field to be absent, and following an unidentified
  // level would fetch nothing and render an empty rail.
  assert.equal(collectionFromStack([{ id: 'view-1' }, { name: 'Ghost' }]), null)
  assert.equal(collectionFromStack([{ id: 'view-1' }]), null)
  assert.equal(collectionFromStack([]), null)

  // A driver on the superseded Library implementation pushes a Movie level for a
  // title's detail page. Reading that as a franchise would ask the collections
  // route for a movie id and render an empty rail under the wrong heading.
  assert.equal(collectionFromStack([{ id: 'view-1' }, { id: 'm1', name: 'Alien', type: 'Movie' }]), null)
  assert.equal(collectionFromStack([{ id: 'view-1' }, { id: 's1', type: 'Season' }]), null)
  // No type at all is still followed: this surface only ever pushes box sets.
  assert.deepEqual(collectionFromStack([{ id: 'view-1' }, { id: 'box-1', name: 'Alien' }]), {
    id: 'box-1',
    name: 'Alien',
  })
})

test('Enter plays a movie and opens a collection', () => {
  assert.deepEqual(activationFor({ Id: 'm1', Name: 'Alien', Type: 'Movie' }), {
    kind: 'play',
    itemId: 'm1',
  })
  // A part inside a franchise is a movie, so it plays — "movies will act like
  // episodes", and the details are already on the stage.
  assert.deepEqual(activationFor({ Id: 'm2', Name: 'Aliens', Type: 'Movie' }), {
    kind: 'play',
    itemId: 'm2',
  })
  assert.deepEqual(activationFor({ Id: 'box-1', Name: 'Alien', Type: 'BoxSet' }), {
    kind: 'open',
    collection: { Id: 'box-1', Name: 'Alien', Type: 'BoxSet' },
  })
  assert.deepEqual(activationFor(null), { kind: 'none' })
  assert.deepEqual(activationFor({ Name: 'No id', Type: 'Movie' }), { kind: 'none' })
  assert.deepEqual(activationFor({ Id: '', Name: 'Blank', Type: 'Movie' }), { kind: 'none' })
})

test('each mode and each franchise keeps its own focus position', () => {
  // Singles and Collections are two lists of different lengths; one memory would
  // restore focus in one from an index only the other ever had.
  const singles = surfaceId(moviesTab('singles'), root('singles'))
  const collections = surfaceId(moviesTab('collections'), root('collections'))
  const inside = surfaceId(
    moviesTab('collections'),
    openCollection(root('collections'), { Id: 'box-1', Name: 'Alien' }),
  )

  assert.equal(singles, 'movies:singles/view-1')
  assert.equal(collections, 'movies:collections/view-1')
  assert.equal(inside, 'movies:collections/view-1/box-1')
  assert.equal(new Set([singles, collections, inside]).size, 3)
})
