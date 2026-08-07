// Guards the three generated token surfaces against drift.
//
// app/shared/design/analog-tokens.json is the only place a token value may be
// edited. The generator emits a TypeScript module, a CSS custom-property block
// and a Dart constant surface from it, and all three are checked in so the
// clients can import them without a build step.
//
// That convenience is exactly what makes them rot: a hand-edit to any one file,
// or a JSON change without a regenerate, leaves three "sources of truth" that
// disagree. This test re-runs the generator in memory and compares byte for
// byte, so either mistake fails the suite instead of shipping.
//
// The Dart file is covered here too — Dart cannot run the Node generator, so
// this is the only check that the checked-in Dart matches the JSON. The Flutter
// side asserts the *semantics* of the transform separately, in
// flutter_app/test/ui/analog_tokens_parity_test.dart.

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { renderAll, readTokens } from '../../../shared/design/generate.mjs'
import { analogTokens } from './analogTokens.ts'

const repoRoot = new URL('../../../../', import.meta.url)
const readRepo = (relative: string) =>
  readFileSync(fileURLToPath(new URL(relative, repoRoot)), 'utf8')

test('the generated token files match the canonical JSON', () => {
  for (const [relative, expected] of Object.entries(renderAll())) {
    assert.equal(
      readRepo(relative),
      expected,
      `${relative} is stale or hand-edited — run \`node app/shared/design/generate.mjs\``,
    )
  }
})

test('poster artwork is square at every size', () => {
  // "Every poster has square, unrounded artwork, including skeletons,
  // placeholders, seasons, and selected states." A non-zero value here would
  // let rounded corners back in through the token surface itself, so it is
  // pinned rather than merely documented.
  assert.equal(analogTokens.poster.radiusPx, 0)
})

test('the neutral ramp is warm — never pure black or pure white', () => {
  // "Warm blacks and softly tinted neutrals instead of pure black." A warm
  // neutral has R >= G >= B with a real spread; a cool or neutral grey does not.
  const neutrals = [
    'stageVoid',
    'stageGround',
    'stageSurface',
    'stageSurface2',
    'stageSurface3',
    'ink',
  ] as const

  for (const name of neutrals) {
    const hex = analogTokens.color[name]
    const [r, g, b] = [1, 3, 5].map((at) => parseInt(hex.slice(at, at + 2), 16))

    assert.ok(r >= g && g >= b, `${name} (${hex}) is not warm: expected r >= g >= b`)
    assert.ok(r - b >= 2, `${name} (${hex}) is too neutral: expected a visible warm bias`)
    assert.notEqual(hex.slice(0, 7).toUpperCase(), '#000000', `${name} is pure black`)
    assert.notEqual(hex.slice(0, 7).toUpperCase(), '#FFFFFF', `${name} is pure white`)
  }
})

/// Curves allowed to carry a control point above 1 on the y axis — i.e. to
/// overshoot. Exactly one, and it is the rail's settle.
///
/// This test used to forbid overshoot outright, which was correct while the
/// tokens said "no elastic overshoot anywhere". That rule was replaced: things
/// with MASS overshoot, chrome does not. A row of posters being flung has
/// momentum and settles past its mark; a button does not.
///
/// The allowlist is the point. Dropping the assertion would have been the easy
/// way to make this pass and would have left nothing stopping a bouncy button
/// from landing next week. Adding a curve here has to be a deliberate edit
/// with a reason, which is what the old blanket ban was really buying.
const OVERSHOOT_ALLOWED = new Set(['settleEase'])

test('easing curves are four-point cubics, and only the settle overshoots', () => {
  const curves = Object.entries(analogTokens.motion).filter(([key]) => key.endsWith('Ease'))
  assert.ok(curves.length > 0, 'expected at least one easing curve')

  let sawOvershoot = false
  for (const [name, curve] of curves) {
    assert.equal((curve as readonly number[]).length, 4, `${name} is not a cubic bezier`)
    const [x1, y1, x2, y2] = curve as readonly number[]
    // x is time and must stay in 0..1 for EVERY curve, allowlist or not: a
    // control point outside it reverses the clock rather than the position.
    for (const [axis, value] of [['x1', x1], ['x2', x2]] as const) {
      assert.ok(value >= 0 && value <= 1, `${name} ${axis} (${value}) must stay within 0..1`)
    }
    const overshoots = [y1, y2].some((v) => v < 0 || v > 1)
    if (overshoots) {
      sawOvershoot = true
      assert.ok(
        OVERSHOOT_ALLOWED.has(name),
        `${name} overshoots and is not on the allowlist — chrome does not overshoot`,
      )
    }
  }

  // Guards the allowlist against rot: if settleEase is ever flattened, this
  // fails and the entry gets removed rather than sitting here forever granting
  // permission nothing uses.
  assert.ok(sawOvershoot, 'nothing overshoots — OVERSHOOT_ALLOWED is now stale')
})

test('the hairline treatment keeps a large hit target', () => {
  // "Keep the visible idle line approximately 2px thick while providing a much
  // larger invisible pointer/touch target."
  const { idlePx, activePx, hitPx } = analogTokens.hairline

  assert.ok(activePx > idlePx, 'the active line must be thicker than the idle line')
  assert.ok(hitPx >= 24, `hit target ${hitPx}px is below the 24px touch floor`)
  assert.ok(hitPx > activePx * 4, 'the hit target must be far larger than the visible line')
})

test('the JSON carries no token the generator would silently drop', () => {
  // A value nested one level deeper than the generator walks would appear in the
  // JSON, be reviewed, and never reach either client.
  const tokens = readTokens()
  for (const [groupName, group] of Object.entries(tokens)) {
    if (groupName.startsWith('$')) continue
    for (const [key, value] of Object.entries(group as Record<string, unknown>)) {
      if (key.startsWith('$')) continue
      const isCurve = key.endsWith('Ease') && Array.isArray(value)
      assert.ok(
        isCurve || value === null || typeof value !== 'object',
        `${groupName}.${key} is nested too deeply for the generator to emit`,
      )
    }
  }
})
