import test from 'node:test'
import assert from 'node:assert/strict'
import { analogTokens } from '../../design/analogTokens.ts'
import {
  chromeTransition,
  defaultDisplayPreferences,
  motionDurationMs,
  panelSurface,
  riseAnimation,
  toastSurface,
} from './presentation.ts'

const REDUCED = { reducedMotion: true, reducedTransparency: true }
const NEITHER = defaultDisplayPreferences

test('the default is the translucent, animated branch', () => {
  assert.deepEqual(NEITHER, { reducedMotion: false, reducedTransparency: false })
})

test('reduced transparency swaps to an opaque surface', () => {
  const translucent = toastSurface(NEITHER)
  const opaque = toastSurface({ reducedMotion: false, reducedTransparency: true })
  // The translucent branch carries an alpha channel; the opaque one must not.
  assert.match(translucent.background, /backdrop-scrim/)
  assert.match(opaque.background, /stage-ground/)
  assert.equal(opaque.boxShadow, 'none', 'no cast shadow to fake depth on a flat surface')
  // Both keep a visible edge, so the toast still has a boundary either way.
  assert.ok(translucent.border.length > 0 && opaque.border.length > 0)
})

test('the opaque colour is a real neutral, not a transparent one', () => {
  // "Reduced-transparency mode uses an opaque surface with equivalent contrast."
  // The translucent surface is the warm ground at 85%; the opaque one is that
  // same ground at full strength, so ink over it can only get MORE contrast,
  // never less — which is what "equivalent" has to mean in practice.
  assert.equal(analogTokens.color.backdropScrim.slice(0, 7).toUpperCase(), analogTokens.color.stageGround.toUpperCase())
  assert.equal(analogTokens.color.backdropScrim.length, 9, 'the translucent token carries an alpha pair')
  assert.equal(analogTokens.color.stageGround.length, 7, 'the opaque token does not')
})

test('the settings stack follows the same rule', () => {
  assert.match(panelSurface(NEITHER).background, /stage-surface/)
  assert.match(panelSurface(REDUCED).background, /stage-ground/)
  assert.equal(panelSurface(REDUCED).boxShadow, 'none')
})

test('reduced motion removes transitions rather than shortening them', () => {
  // The end state is the state feedback the reference says to preserve, and it
  // is preserved by arriving instantly.
  assert.equal(chromeTransition(REDUCED, ['height', 'opacity']), 'none')
  assert.equal(riseAnimation(REDUCED), 'none')
  assert.equal(motionDurationMs(REDUCED, 260), 0)
})

test('the animated branch is driven by the shared motion tokens', () => {
  const transition = chromeTransition(NEITHER, ['opacity'])
  assert.ok(transition.includes(`${analogTokens.motion.chromeFadeMs}ms`))
  assert.ok(transition.includes('cubic-bezier('))
  assert.equal(chromeTransition(NEITHER, ['height'], 90), `height 90ms ${transitionCurve()}`)
  assert.equal(chromeTransition(NEITHER, []), 'none')
  assert.ok(riseAnimation(NEITHER).startsWith(`up ${analogTokens.motion.drawerMs}ms`))
  assert.equal(motionDurationMs(NEITHER, 260), 260)
})

test('two properties become two comma-separated transitions', () => {
  assert.equal(
    chromeTransition(NEITHER, ['height', 'opacity'], 90),
    `height 90ms ${transitionCurve()}, opacity 90ms ${transitionCurve()}`,
  )
})

function transitionCurve() {
  return `cubic-bezier(${analogTokens.motion.chromeFadeEase.join(', ')})`
}
