// The strobe illusion, as arithmetic.
//
// Nothing sequences the "speeds up, stalls, runs backwards" cycle — it falls
// out of sampling a real angular velocity through a shutter on an eight-fold
// symmetric ring. These pin the parts that make that true, because a plausible
// -looking mistake here reads as a bug in the animation rather than as one.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  BOARD_BELOW,
  CLEAR_ABOVE,
  SEAT_STEP,
  SYNC_RATE,
  apparentRate,
  approach,
  boardingOpen,
  targetSpeed,
} from './reel.ts'

test('at sync the ring reads as frozen', () => {
  // 45° per exposure is indistinguishable from standing still on an eight-fold
  // ring. That is the whole illusion.
  assert.equal(apparentRate(SYNC_RATE), 0)
})

test('just under sync it crawls forward, just over it goes backwards', () => {
  const slow = apparentRate(SYNC_RATE - 20)
  const fast = apparentRate(SYNC_RATE + 20)
  assert.ok(slow < 0, 'below sync the seats fall behind')
  assert.ok(fast > 0, 'above sync they creep ahead')
  // ...and both by a crawl, nowhere near the real speed.
  assert.ok(Math.abs(slow) < SYNC_RATE / 4)
  assert.ok(Math.abs(fast) < SYNC_RATE / 4)
})

test('the fold always lands within half a seat', () => {
  for (let omega = 0; omega < 4000; omega += 37) {
    const apparent = apparentRate(omega)
    assert.ok(
      Math.abs(apparent * (1 / 20)) <= SEAT_STEP / 2 + 1e-9,
      `omega ${omega} folded outside a half-seat`,
    )
  }
})

test('a whole extra revolution between exposures is invisible', () => {
  // Eight seats on: the same picture, at a wildly different real speed.
  assert.ok(Math.abs(apparentRate(SYNC_RATE * 9) - apparentRate(SYNC_RATE)) < 1e-9)
})

test('the speed program straddles sync, and swells past it', () => {
  let max = -Infinity
  let min = Infinity
  let nearSync = 0
  let belowSync = 0
  const samples = 22000
  for (let i = 0; i < samples; i++) {
    const speed = targetSpeed(i * 0.005)
    max = Math.max(max, speed)
    min = Math.min(min, speed)
    if (Math.abs(speed - SYNC_RATE) <= SYNC_RATE * 0.05) nearSync++
    if (speed < SYNC_RATE) belowSync++
  }
  // The surge is real: a third again over lock, which is far too fast to follow.
  assert.ok(max > SYNC_RATE * 1.2, 'never surges')
  // It spends most of its life within a few percent of lock — that is where the
  // seats are watchable and people can board.
  assert.ok(nearSync / samples > 0.5, 'too little time near sync to look stalled')
  // And it crosses to BOTH sides, which is what makes the ring appear to run
  // backwards rather than merely slow down. A program that only ever exceeded
  // sync would play half the illusion.
  assert.ok(belowSync / samples > 0.2, 'never drops below sync, so never reverses')
  assert.ok(min > SYNC_RATE * 0.9, 'drops so far below sync that the fold breaks')
})

test('approach never overshoots and always moves', () => {
  let value = 0
  for (let i = 0; i < 200; i++) value = approach(value, 100, 1.6, 1 / 60)
  assert.ok(value > 85 && value <= 100)
  // Frame-rate independence: a big step gets closer than a small one, and
  // neither passes the target.
  assert.ok(approach(0, 100, 1.6, 1) < 100)
  assert.ok(approach(0, 100, 1.6, 1) > approach(0, 100, 1.6, 0.1))
})

test('boarding has hysteresis, not a threshold', () => {
  assert.equal(boardingOpen(0, false), true)
  assert.equal(boardingOpen(200, true), false)
  // Between the gates nothing changes: one number here would have people
  // boarding and leaving several times a second while the rate sat on it.
  const between = (BOARD_BELOW + CLEAR_ABOVE) / 2
  assert.equal(boardingOpen(between, true), true)
  assert.equal(boardingOpen(between, false), false)
  // Direction does not matter — running backwards fast is still too fast.
  assert.equal(boardingOpen(-200, true), false)
})
