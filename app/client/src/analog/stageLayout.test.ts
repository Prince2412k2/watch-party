// The responsive and reduced-motion branches.
//
// Phones keep the SAME stage and focus model as desktop — this is what changes
// instead, and it is only ever a size. If one of these cases ever has to return
// a different structure, the phone tree has grown back.

import test from 'node:test'
import assert from 'node:assert/strict'
import { analogTokens } from '../design/analogTokens.ts'
import { edgeLightOffsets, motionProfile, stageLayout } from './stageLayout.ts'

const PHONE = true
const POINTER = false

test('a phone, a tablet and a desktop differ only in size', () => {
  const phone = stageLayout(390, 844, PHONE)
  const tablet = stageLayout(900, 1200, POINTER)
  const desktop = stageLayout(1440, 900, POINTER)

  assert.equal(phone.size, 'phone')
  assert.equal(tablet.size, 'tablet')
  assert.equal(desktop.size, 'desktop')

  assert.equal(phone.gutterPx, analogTokens.space.stageGutterPhonePx)
  assert.equal(tablet.gutterPx, analogTokens.space.stageGutterPx)
  assert.equal(desktop.gutterPx, analogTokens.space.stageGutterPx)

  // Same shelf, more of it.
  assert.deepEqual([phone.visibleCount, tablet.visibleCount, desktop.visibleCount], [3, 5, 7])
  assert.ok(phone.posterWidthPx < tablet.posterWidthPx)
  assert.ok(tablet.posterWidthPx < desktop.posterWidthPx)
  for (const layout of [phone, tablet, desktop]) {
    assert.equal(layout.gapPx, analogTokens.poster.gapPx)
  }
})

test('a narrow desktop window is not a phone', () => {
  // The split is usePhone() — a coarse-pointer query — NOT the 640px
  // useIsMobile() breakpoint. A 600px browser window still has a mouse.
  const narrow = stageLayout(600, 800, POINTER)
  assert.equal(narrow.size, 'tablet')
  assert.equal(narrow.gutterPx, analogTokens.space.stageGutterPx)
})

test('a phone held sideways is still a phone, sized for the height it has', () => {
  // usePhone() fires for a short landscape phone, and 844px of width would
  // otherwise buy posters far taller than the 390px viewport.
  const portrait = stageLayout(390, 844, PHONE)
  const landscape = stageLayout(844, 390, PHONE)

  assert.equal(landscape.size, 'phone')
  assert.ok(
    landscape.posterWidthPx * (analogTokens.poster.aspectH / analogTokens.poster.aspectW) < 390,
    'artwork must fit the short axis',
  )
  assert.ok(landscape.visibleCount > portrait.visibleCount, 'the extra width shows more of the shelf')
})

test('a poster never collapses to an icon or swells past the ceiling', () => {
  const tiny = stageLayout(200, 300, POINTER)
  assert.ok(tiny.posterWidthPx >= 104)
  assert.equal(tiny.visibleCount, 1, 'at least one item is always focusable on screen')

  const huge = stageLayout(5120, 2880, POINTER)
  assert.ok(huge.posterWidthPx <= 232)
  assert.ok(huge.visibleCount > 7, 'an ultrawide shows more posters, not bigger ones')
})

test('the motion profile is the tokens, verbatim', () => {
  const motion = motionProfile(false)
  assert.equal(motion.focusStepMs, analogTokens.motion.focusStepMs)
  assert.equal(motion.backdropCrossMs, analogTokens.motion.backdropCrossMs)
  assert.equal(motion.chromeFadeMs, analogTokens.motion.chromeFadeMs)
  assert.equal(motion.drawerMs, analogTokens.motion.drawerMs)
  assert.equal(motion.focusScale, analogTokens.selection.focusScale)
  assert.equal(motion.focusLiftPx, analogTokens.selection.focusLiftPx)
  assert.equal(motion.framePx, analogTokens.poster.framePx)
  assert.equal(motion.scrollBehavior, 'smooth')
})

test('reduced motion removes every spatial effect', () => {
  const motion = motionProfile(true)
  assert.equal(motion.focusStepMs, 0)
  assert.equal(motion.backdropCrossMs, 0)
  assert.equal(motion.chromeFadeMs, 0)
  assert.equal(motion.drawerMs, 0)
  assert.equal(motion.focusLiftPx, 0, 'no forward lift')
  assert.equal(motion.focusScale, analogTokens.selection.restScale, 'focused and resting are the same size')
  assert.equal(motion.scrollBehavior, 'auto', 'the shelf jumps rather than animating')
})

test('reduced motion still says which item is focused, and not with colour', () => {
  // "Reduced-motion mode must preserve all state changes without spatial
  // effects" — take away the lift and the scale and the frame has to carry it.
  // A thicker line is a size change, not a spatial one, and it survives on a
  // monochrome display where a tint would not.
  const still = motionProfile(true)
  const moving = motionProfile(false)
  assert.ok(still.framePx > moving.framePx)
  assert.equal(still.framePx, analogTokens.poster.framePx * 3)
})

test('the scene light comes from above-left, and everything is lit the same way', () => {
  assert.equal(analogTokens.selection.sceneLightAngleDeg, 315)
  const edge = edgeLightOffsets(analogTokens.selection.sceneLightAngleDeg, 1)

  // Positive inset offsets push the highlight down and right inside the box,
  // which is what makes the TOP and LEFT edges the lit ones.
  assert.ok(edge.litX > 0 && edge.litY > 0, 'highlight on the top-left edges')
  assert.ok(edge.shadeX < 0 && edge.shadeY < 0, 'shade on the bottom-right edges')
  assert.equal(edge.litX, -edge.shadeX)
  assert.equal(edge.litY, -edge.shadeY)
  assert.equal(edge.litX, 0.71)

  // The cast shadow falls the other way from the same one light source.
  assert.ok(analogTokens.elevation.restOffsetXPx > 0 && analogTokens.elevation.restOffsetYPx > 0)
  assert.ok(analogTokens.elevation.focusOffsetYPx > analogTokens.elevation.restOffsetYPx, 'focus lifts higher')
})

test('a scene light from the other side flips the edges', () => {
  // 135deg is below-right; nothing is hard-coded to the current token.
  const flipped = edgeLightOffsets(135, 1)
  assert.ok(flipped.litX < 0 && flipped.litY < 0)
})
