import test from 'node:test'
import assert from 'node:assert/strict'
import { playbackPlan, timelinePosition, type PlayerState } from './core.ts'

const schedule = { positionTicks: 10 * 10_000_000, t0: 1000, phase: 'playing', rate: 1, version: 2, mediaGeneration: 1 }
const player: PlayerState = { type: 'state', videoId: 'dQw4w9WgXcQ', title: 'Example', position: 11, duration: 300, paused: false, rate: 1, volume: 1, ready: true, seeking: false, ad: false, buffered: 20, available: true, live: false }

test('YouTube timeline follows the selected shared speed, not wall-rate only', () => {
  assert.equal(timelinePosition({ ...schedule, rate: 2 }, 3000), 14)
  assert.equal(timelinePosition({ ...schedule, phase: 'paused', rate: 0 }, 3000), 10)
})
test('an aligned player is left alone', () => {
  assert.equal(playbackPlan({ schedule, player, now: 2000, baseRate: 1 }), null)
})
test('YouTube ads and active scrubbing are never sought or rate-corrected', () => {
  for (const patch of [{ ad: true }, { seeking: true }]) assert.equal(playbackPlan({ schedule, player: { ...player, ...patch }, now: 9000, baseRate: 1, force: true }), null)
})
test('modest drift uses gentle speed correction; gross drift seeks', () => {
  const nudge = playbackPlan({ schedule, player: { ...player, position: 10 }, now: 2000, baseRate: 1 })
  assert.equal(nudge?.position, undefined)
  assert.equal(nudge?.rate, 1.05)
  assert.equal(playbackPlan({ schedule, player: { ...player, position: 2 }, now: 2000, baseRate: 1 })?.position, 11)
})
test('paused room corrects position without starting playback', () => {
  const plan = playbackPlan({ schedule: { ...schedule, phase: 'paused', rate: 0 }, player, now: 9000, baseRate: 1.5 })
  assert.equal(plan?.paused, true)
  assert.equal(plan?.position, 10)
  assert.equal(plan?.rate, 1.5)
})
test('a Lead host does not chase guest drift but obeys explicit room changes', () => {
  assert.equal(playbackPlan({ schedule, player, now: 3000, baseRate: 1, hostLead: true }), null)
  assert.equal(playbackPlan({ schedule, player, now: 3000, baseRate: 1, hostLead: true, force: true })?.position, 12)
})
test('strict synchronization seeks at the personal tolerance', () => {
  assert.equal(playbackPlan({ schedule, player, now: 2500, baseRate: 1, gentle: false, tolerance: .2 })?.position, 11.5)
})
test('a player without enough data is not repeatedly forced to play', () => {
  assert.equal(playbackPlan({ schedule, player: { ...player, ready: false }, now: 3000, baseRate: 1 }), null)
})
