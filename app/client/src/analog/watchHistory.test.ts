// The rules a web playback session follows when it tells the server what was
// watched.
//
// These exist because the web client reported NOTHING before them: every
// surface that shows watch progress — Continue Watching, Next Up, the "Resume
// 1h 30m" label, the poster progress bars — was fed only by the desktop app.
// The numbers below are deliberately the same ones the Flutter reporter uses;
// two clients disagreeing about when a title counts as watched would be a bug
// with no owner.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  PENDING_LIMIT,
  RESUME_REWIND_SECONDS,
  TICKS_PER_SECOND,
  mergePending,
  newSessionId,
  parsePending,
  resumeStartSeconds,
  secondsOf,
  shouldReportProgress,
  ticksOf,
  type PlaybackReport,
} from './watchHistory.ts'

const report = (itemId: string, positionTicks: number): PlaybackReport =>
  ({ itemId, positionTicks })

test('seconds and ticks round-trip', () => {
  // A factor-of-ten slip here lands the resume point in the wrong scene rather
  // than throwing anything, which is why it is pinned rather than assumed.
  assert.equal(ticksOf(1), TICKS_PER_SECOND)
  assert.equal(ticksOf(90 * 60), 90 * 60 * TICKS_PER_SECOND)
  assert.equal(secondsOf(ticksOf(2745)), 2745)
})

test('a nonsense position is zero, not NaN', () => {
  // A media element reports NaN for currentTime until it has metadata, and JSON
  // has no NaN — it would reach the server as null, be read as 0, and wipe a
  // real resume point.
  assert.equal(ticksOf(Number.NaN), 0)
  assert.equal(ticksOf(-5), 0)
  assert.equal(ticksOf(Infinity), 0)
  assert.equal(secondsOf(Number.NaN), 0)
})

test('resuming starts a few seconds before the mark, never before zero', () => {
  assert.equal(resumeStartSeconds(ticksOf(2745)), 2745 - RESUME_REWIND_SECONDS)
  // Inside the run-up: a negative seek is a position that does not exist.
  assert.equal(resumeStartSeconds(ticksOf(2)), 0)
  assert.equal(resumeStartSeconds(0), 0)
})

test('a tick is only worth sending when something changed', () => {
  // A paused player ticking every ten seconds would otherwise report the same
  // number forever.
  assert.equal(shouldReportProgress(100, 100, false), false)
  assert.equal(shouldReportProgress(200, 100, false), true)
  // ...but the pause edge itself is the most valuable report there is: it is
  // where someone stops for the night.
  assert.equal(shouldReportProgress(100, 100, true), true)
  assert.equal(shouldReportProgress(0, null, false), true)
})

test('a session id is unique and hex', () => {
  const a = newSessionId()
  const b = newSessionId()
  assert.match(a, /^[0-9a-f]{32}$/)
  assert.notEqual(a, b)
})

test('one pending report per title, newest wins', () => {
  let queue = mergePending([], report('a', 10))
  queue = mergePending(queue, report('b', 20))
  queue = mergePending(queue, report('a', 30))

  // Replaying both positions for 'a' would move its resume point backwards
  // depending on which request landed last.
  assert.deepEqual(queue, [report('b', 20), report('a', 30)])
})

test('the queue is bounded, oldest out first', () => {
  let queue: PlaybackReport[] = []
  for (let i = 0; i < PENDING_LIMIT + 5; i++) queue = mergePending(queue, report(`i${i}`, i))

  assert.equal(queue.length, PENDING_LIMIT)
  // The five oldest are the ones dropped.
  assert.equal(queue[0].itemId, 'i5')
  assert.equal(queue[queue.length - 1].itemId, `i${PENDING_LIMIT + 4}`)
})

test('a corrupt stored queue reads as empty rather than throwing', () => {
  // localStorage is shared with everything else on the origin and survives
  // upgrades; a parse failure here must not take playback down with it.
  assert.deepEqual(parsePending(null), [])
  assert.deepEqual(parsePending('not json'), [])
  assert.deepEqual(parsePending('{"itemId":"a"}'), [])
  assert.deepEqual(parsePending('[{"nope":1},{"itemId":"a","positionTicks":5}]'), [
    report('a', 5),
  ])
})
