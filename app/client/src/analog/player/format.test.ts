import test from 'node:test'
import assert from 'node:assert/strict'
import { formatClock, spokenClock } from './format.ts'

test('the clock drops the hour below an hour and pads once past it', () => {
  assert.equal(formatClock(0), '0:00')
  assert.equal(formatClock(9), '0:09')
  assert.equal(formatClock(605), '10:05')
  assert.equal(formatClock(3600), '1:00:00')
  assert.equal(formatClock(3725), '1:02:05')
})

test('a missing or nonsensical time reads as zero, never as NaN', () => {
  // Duration is NaN until loadedmetadata, and the label is on screen before it.
  assert.equal(formatClock(Number.NaN), '0:00')
  assert.equal(formatClock(-30), '0:00')
  assert.equal(formatClock(Number.POSITIVE_INFINITY), '0:00')
})

test('aria-valuetext is spoken as a duration, not as digits', () => {
  assert.equal(spokenClock(0), '0 seconds')
  assert.equal(spokenClock(61), '1 minute 1 second')
  assert.equal(spokenClock(3725), '1 hour 2 minutes 5 seconds')
  assert.equal(spokenClock(Number.NaN), '0 seconds')
})
