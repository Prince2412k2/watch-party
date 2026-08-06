// The wiring between browser input and the shared browse cores.
//
// interactionParity.test.ts already proves `steppedScroll` itself matches the
// cross-language fixture. What is untested there — and what every previous
// wheel implementation in this repo got wrong — is the layer in front of it:
// deltaMode normalisation, which axis wins, and whether the shelf distorts the
// deltas on the way in. So these cases replay the SAME fixture through the
// wiring and assert the answers are unchanged.

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { newSteppedScrollState, steppedScroll, type SteppedScrollConfig } from './browseCore.ts'
import {
  centreScrollDelta,
  focusIntentForKey,
  rovingTabIndex,
  shouldCentre,
  stepFocus,
  touchDeltaPx,
  wheelDeltaPx,
} from './stageCore.ts'

const fixture = JSON.parse(
  readFileSync(new URL('../../../shared/design/interaction.json', import.meta.url), 'utf8'),
)
const config = fixture.steppedScroll.config as SteppedScrollConfig

test('routing a pixel wheel through the shelf reproduces every shared case', () => {
  for (const testCase of fixture.steppedScroll.cases) {
    const state = newSteppedScrollState()
    testCase.events.forEach((event: { deltaPx: number; atMs: number; expect: number }, index: number) => {
      const delta = wheelDeltaPx({ deltaX: 0, deltaY: event.deltaPx, deltaMode: 0 })
      const steps = steppedScroll(state, delta, event.atMs, config)
      assert.equal(steps, event.expect, `${testCase.name}: event ${index}`)
    })
  }
})

test('a horizontal trackpad swipe reproduces every shared case too', () => {
  // A shelf has to answer the same way whether the gesture arrives on deltaX or
  // deltaY; hard-coding one axis is what makes a trackpad useless on a rail.
  for (const testCase of fixture.steppedScroll.cases) {
    const state = newSteppedScrollState()
    testCase.events.forEach((event: { deltaPx: number; atMs: number; expect: number }, index: number) => {
      const delta = wheelDeltaPx({ deltaX: event.deltaPx, deltaY: 0, deltaMode: 0 })
      assert.equal(steppedScroll(state, delta, event.atMs, config), event.expect, `${testCase.name}: event ${index}`)
    })
  }
})

test('the dominant axis wins when a gesture carries both', () => {
  assert.equal(wheelDeltaPx({ deltaX: -30, deltaY: 4 }), -30)
  assert.equal(wheelDeltaPx({ deltaX: 4, deltaY: -30 }), -30)
  // Exactly equal magnitudes resolve to the horizontal one: a shelf is a
  // horizontal control, so a diagonal gesture reads as sideways.
  assert.equal(wheelDeltaPx({ deltaX: 12, deltaY: -12 }), 12)
})

test('a line-mode notch is one step, not one sixteenth of one', () => {
  // Firefox reports a notch as deltaY 3 in DOM_DELTA_LINE. Fed raw into a 48px
  // threshold that is sixteen notches per item.
  const state = newSteppedScrollState()
  const delta = wheelDeltaPx({ deltaX: 0, deltaY: 3, deltaMode: 1 })
  assert.equal(delta, 48, 'three lines is one step threshold')
  assert.equal(steppedScroll(state, delta, 0, config), 1)
})

test('page-mode deltas are normalised rather than treated as pixels', () => {
  assert.equal(wheelDeltaPx({ deltaX: 0, deltaY: 1, deltaMode: 2 }), 400)
  assert.equal(wheelDeltaPx({ deltaX: 0, deltaY: 1, deltaMode: 0 }), 1)
})

test('a touch drag steps exactly like a wheel, in the direction the content moves', () => {
  // Dragging the poster wall leftwards reveals what is to the right, which is
  // forward travel — so the sign is inverted relative to the finger.
  assert.equal(touchDeltaPx(300, 240), 60)
  assert.equal(touchDeltaPx(240, 300), -60)

  const state = newSteppedScrollState()
  assert.equal(steppedScroll(state, touchDeltaPx(300, 240), 0, config), 1, 'one deliberate swipe, one item')
})

test('a flick is one step, not a run of them', () => {
  // The whole point of routing touch through steppedScroll rather than writing
  // a swipe handler: a decaying tail cannot coast focus past the target.
  const state = newSteppedScrollState()
  let x = 400
  let steps = 0
  for (const move of [26, 24, 18, 12, 8, 5, 3, 2, 1]) {
    const next = x - move
    steps += steppedScroll(state, touchDeltaPx(x, next), 0, config)
    x = next
  }
  assert.equal(steps, 1)
})

test('keys and remote directions land on the same four intents', () => {
  assert.equal(focusIntentForKey('ArrowLeft'), 'prev')
  assert.equal(focusIntentForKey('ArrowUp'), 'prev')
  assert.equal(focusIntentForKey('ArrowRight'), 'next')
  assert.equal(focusIntentForKey('ArrowDown'), 'next')
  assert.equal(focusIntentForKey('Enter'), 'activate')
  assert.equal(focusIntentForKey(' '), 'activate')
  assert.equal(focusIntentForKey('Escape'), 'back')
  assert.equal(focusIntentForKey('Backspace'), 'back')
  assert.equal(focusIntentForKey('a'), null, 'typing must fall through')
  assert.equal(focusIntentForKey('Tab'), null, 'Tab still leaves the shelf')
})

test('focus stepping clamps at the ends and reports the overflow', () => {
  assert.deepEqual(stepFocus(0, 5, 1), { index: 1, overflow: 0 })
  assert.deepEqual(stepFocus(4, 5, 1), { index: 4, overflow: 1 })
  assert.deepEqual(stepFocus(0, 5, -1), { index: 0, overflow: -1 })
  assert.deepEqual(stepFocus(3, 0, 1), { index: 0, overflow: 0 }, 'an empty shelf has nowhere to go')
})

test('centring moves the track by the difference of the two midpoints', () => {
  // Track 0..1000 (midpoint 500), item at 700..900 (midpoint 800): 300 right.
  assert.equal(centreScrollDelta({ left: 0, width: 1000 }, { left: 700, width: 200 }), 300)
  assert.equal(centreScrollDelta({ left: 0, width: 1000 }, { left: 100, width: 200 }), -300)
  assert.equal(centreScrollDelta({ left: 0, width: 1000 }, { left: 400, width: 200 }), 0)
})

test('sub-pixel drift never triggers a scroll animation', () => {
  assert.equal(shouldCentre(0.4), false)
  assert.equal(shouldCentre(-1), false)
  assert.equal(shouldCentre(1.5), true)
})

test('exactly one option in a shelf holds the tab stop', () => {
  const count = 4
  const tabbable = (focusedIndex: number) =>
    Array.from({ length: count }, (_, index) => rovingTabIndex(index, focusedIndex)).filter((value) => value === 0)

  assert.equal(tabbable(2).length, 1)
  assert.equal(rovingTabIndex(2, 2), 0)
  assert.equal(rovingTabIndex(1, 2), -1)
  // Nothing focused yet: the shelf must still be reachable by Tab, so the tab
  // stop parks on the first option rather than vanishing.
  assert.equal(tabbable(-1).length, 1)
  assert.equal(rovingTabIndex(0, -1), 0)
})
