import test from 'node:test'
import assert from 'node:assert/strict'
import { analogTokens } from '../../design/analogTokens.ts'
import {
  clampPopupCenter,
  hairlineThicknessPx,
  handleDiameterPx,
  isHairlineActive,
  isHandleVisible,
  normalizeSpans,
  ratioFromPointer,
  seekTimeFromRatio,
  timelineLayers,
  toPercentSpans,
  trackBoxPx,
} from './timelineGeometry.ts'

test('spans are clamped, sorted and merged only where they touch', () => {
  const spans = normalizeSpans(
    [
      { start: 40, end: 55 },
      { start: -10, end: 12 },
      { start: 12, end: 18 },   // touches the one before it
      { start: 90, end: 200 },  // runs past the end
      { start: 30, end: 30 },   // empty
      { start: 70, end: 60 },   // inverted
    ],
    100,
  )
  assert.deepEqual(spans, [
    { start: 0, end: 18 },
    { start: 40, end: 55 },
    { start: 90, end: 100 },
  ])
})

test('a hole behind a forward seek stays a hole', () => {
  // The single-span renderer this replaces took buffered.end(length - 1) and
  // drew from zero, so everything before a forward seek was painted as loaded
  // when none of it was. Two ranges have to survive as two ranges.
  const layers = timelineLayers({
    durationSec: 600,
    positionSec: 300,
    buffered: [{ start: 0, end: 60 }, { start: 290, end: 360 }],
  })
  assert.equal(layers.buffered.length, 2)
  assert.deepEqual(
    layers.buffered.map((span) => [span.startPct, span.widthPct]),
    [[0, 10], [(290 / 600) * 100, (70 / 600) * 100]],
  )
  assert.equal(layers.playedPct, 50)
})

test('adjacent ranges keep a minimum visible separation', () => {
  const spans = toPercentSpans([{ start: 0, end: 10 }, { start: 10.001, end: 20 }], 100)
  assert.equal(spans[0].gapAfterPx, analogTokens.hairline.rangeGapPx)
  // Nothing follows the last span, so nothing has to be separated from it.
  assert.equal(spans[1].gapAfterPx, 0)
})

test('cached spans are their own layer, not folded into the buffer', () => {
  const layers = timelineLayers({
    durationSec: 100,
    positionSec: 0,
    buffered: [{ start: 0, end: 40 }],
    cached: [{ start: 10, end: 20 }, { start: 80, end: 95 }],
  })
  assert.equal(layers.buffered.length, 1)
  assert.deepEqual(
    layers.cached.map((span) => [span.startPct, span.widthPct]),
    [[10, 10], [80, 15]],
  )
})

test('with no cached source the layer is empty rather than guessed', () => {
  // React has no on-disk cache to read time spans from. The layer renders empty
  // — it is not silently filled with the network buffer, which would make
  // "cached" and "buffered" indistinguishable, the one thing the reference
  // says they must not be.
  const layers = timelineLayers({ durationSec: 100, positionSec: 10, buffered: [{ start: 0, end: 50 }] })
  assert.deepEqual(layers.cached, [])
  assert.equal(layers.buffered.length, 1)
})

test('a missing or zero duration produces no geometry at all', () => {
  for (const duration of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    const layers = timelineLayers({ durationSec: duration, positionSec: 5, buffered: [{ start: 0, end: 5 }] })
    assert.equal(layers.playedPct, 0)
    assert.deepEqual(layers.buffered, [])
  }
})

test('the played segment never runs past the end', () => {
  const layers = timelineLayers({ durationSec: 100, positionSec: 140 })
  assert.equal(layers.playedPct, 100)
})

test('the hit target is large, constant, and far bigger than the line', () => {
  // "Keep the visible idle line approximately 2px thick while providing a much
  // larger invisible pointer/touch target."
  assert.equal(trackBoxPx(), analogTokens.hairline.hitPx)
  assert.ok(trackBoxPx() >= 24, 'the hit target holds the 24px touch floor')
  assert.ok(hairlineThicknessPx({}) <= 2, 'the idle line stays about 2px')
  assert.ok(trackBoxPx() > hairlineThicknessPx({ hovered: true }) * 4)
  // And it does not depend on activity: growing the line cannot move the
  // controls around it, because the box it grows inside never changes size.
  assert.equal(trackBoxPx(), trackBoxPx())
})

test('the line thickens on hover, focus or scrub and only then', () => {
  assert.equal(hairlineThicknessPx({}), analogTokens.hairline.idlePx)
  for (const activity of [{ hovered: true }, { focused: true }, { dragging: true }]) {
    assert.ok(isHairlineActive(activity))
    assert.equal(hairlineThicknessPx(activity), analogTokens.hairline.activePx)
  }
})

test('the handle appears on hover, focus or drag, and focus enlarges it', () => {
  assert.equal(isHandleVisible({}), false)
  assert.equal(isHandleVisible({ hovered: true }), true)
  assert.equal(handleDiameterPx({ hovered: true }), analogTokens.hairline.handlePx)
  assert.equal(handleDiameterPx({ focused: true }), analogTokens.hairline.handleFocusPx)
  assert.ok(
    analogTokens.hairline.handleFocusPx > analogTokens.hairline.handlePx,
    'keyboard focus is obvious without permanently enlarging the handle',
  )
})

test('pointer position maps to a clamped ratio and a seek time', () => {
  const rect = { left: 100, width: 400 }
  assert.equal(ratioFromPointer(300, rect), 0.5)
  assert.equal(ratioFromPointer(0, rect), 0)
  assert.equal(ratioFromPointer(9999, rect), 1)
  assert.equal(ratioFromPointer(300, { left: 0, width: 0 }), 0)
  assert.equal(seekTimeFromRatio(0.25, 200), 50)
  assert.equal(seekTimeFromRatio(2, 200), 200)
  assert.equal(seekTimeFromRatio(0.5, 0), 0)
})

test('a hover popup stays inside the track', () => {
  assert.equal(clampPopupCenter(0, 240, 1000), 120)
  assert.equal(clampPopupCenter(1000, 240, 1000), 880)
  assert.equal(clampPopupCenter(500, 240, 1000), 500)
  // Narrower than the popup: centring wins over clamping rather than inverting.
  assert.equal(clampPopupCenter(10, 240, 100), 120)
})
