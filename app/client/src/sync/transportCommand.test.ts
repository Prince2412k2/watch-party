import test from 'node:test'
import assert from 'node:assert/strict'
import { clampSeekTarget, createLocalTransport, mayAuthor } from './transportCommand.ts'
import type { CommandTarget } from './transportCommand.ts'

// A player that behaves like the real one in the way that matters here: writing
// currentTime fires 'seeked', and play()/pause() fire 'play'/'pause'. Those
// events are what SyncBridge turns into 'media-event' requests, so a fake that
// fires them is what makes "exactly one seek per gesture" testable.
function fakePlayer({ duration = 600, paused = true, at = 100 } = {}) {
  const events: string[] = []
  const target = {
    duration,
    paused,
    _t: at,
    get currentTime() { return this._t },
    set currentTime(value: number) { this._t = value; events.push('seeked') },
    play() { this.paused = false; events.push('play'); return Promise.resolve() },
    pause() { this.paused = true; events.push('pause') },
  }
  return { target: target as unknown as CommandTarget, events }
}

// Harness that wires the authoring guard, the local command sequencer and the
// media-event authoring rule together the way SyncBridge does.
function harness({ canControl = true, guardMs = 250 } = {}) {
  const emitted: { kind: string; ticks: number }[] = []
  const timers: { fn: () => void; ms: number }[] = []
  let applying = 0
  const state = { blocked: false }
  const transport = createLocalTransport({
    ticksPerSecond: 10_000_000,
    guardMs,
    blocked: () => state.blocked,
    hold: () => { applying += 1 },
    release: () => { applying = Math.max(0, applying - 1) },
    emitPlay: ticks => { if (mayAuthor({ origin: 'local', suppressed: applying > 0, canControl })) emitted.push({ kind: 'play', ticks }) },
    emitPause: ticks => { if (mayAuthor({ origin: 'local', suppressed: applying > 0, canControl })) emitted.push({ kind: 'pause', ticks }) },
    emitSeek: ticks => { if (mayAuthor({ origin: 'local', suppressed: applying > 0, canControl })) emitted.push({ kind: 'seek', ticks }) },
    schedule: (fn, ms) => { timers.push({ fn, ms }) },
  })
  return {
    transport, emitted, state,
    get applying() { return applying },
    /** What SyncBridge's onSeeked/onPlay/onPause do with an observed event. */
    observeEvent(kind: string, ticks: number) {
      if (mayAuthor({ origin: 'media-event', suppressed: applying > 0, canControl })) emitted.push({ kind, ticks })
    },
    /** Fire the pending guard releases, as the real setTimeout eventually does. */
    settle() { for (const t of timers.splice(0)) t.fn() },
  }
}

const SEC = 10_000_000   // ticks per second, matching syncCore's TICKS

test('an imperative seek authors exactly one shared seek', () => {
  // Regression: the bridge used to hold the authoring guard BEFORE calling
  // requestSeek, and requestSeek refused to emit while the guard was held — so
  // a double-tap seek moved this player and told the room nothing at all.
  const h = harness()
  const { target, events } = fakePlayer({ at: 100 })

  h.transport.seekBy(target, 10)

  assert.deepEqual(h.emitted, [{ kind: 'seek', ticks: 110 * SEC }])
  assert.equal(target.currentTime, 110)
  // The local write happened under the guard, so the 'seeked' it fired is an
  // observation that must not author a second seek.
  assert.deepEqual(events, ['seeked'])
  h.observeEvent('seek', 110 * SEC)
  assert.equal(h.emitted.length, 1)
})

test('a second seek inside the previous guard window still reaches the room', () => {
  // Two double-taps land ~280ms apart, inside the 250ms guard. The room used to
  // hear only the first, leaving every guest 10s behind the controller.
  const h = harness()
  const { target } = fakePlayer({ at: 100 })

  h.transport.seekBy(target, 10)
  h.transport.seekBy(target, 10)

  assert.deepEqual(h.emitted, [
    { kind: 'seek', ticks: 110 * SEC },
    { kind: 'seek', ticks: 120 * SEC },
  ])
  assert.equal(target.currentTime, 120)
})

test('media events author again once the guard releases', () => {
  const h = harness()
  const { target } = fakePlayer({ at: 100 })

  h.transport.seekBy(target, 5)
  h.observeEvent('seek', 105 * SEC)      // suppressed: still applying
  assert.equal(h.emitted.length, 1)

  h.settle()
  assert.equal(h.applying, 0)
  h.observeEvent('seek', 105 * SEC)      // a genuine user scrub afterwards
  assert.equal(h.emitted.length, 2)
})

test('play and pause author one command each and suppress their own event', () => {
  const h = harness()
  const { target, events } = fakePlayer({ at: 42, paused: true })

  h.transport.play(target)
  h.observeEvent('play', 42 * SEC)
  h.settle()
  h.transport.pause(target)
  h.observeEvent('pause', 42 * SEC)

  assert.deepEqual(h.emitted, [
    { kind: 'play', ticks: 42 * SEC },
    { kind: 'pause', ticks: 42 * SEC },
  ])
  assert.deepEqual(events, ['play', 'pause'])
})

test('a guest without control authors nothing, local or observed', () => {
  const h = harness({ canControl: false })
  const { target } = fakePlayer({ at: 10 })

  h.transport.seekBy(target, 10)
  h.observeEvent('seek', 20 * SEC)

  assert.deepEqual(h.emitted, [])
})

test('the guard releases exactly once per command', () => {
  const h = harness()
  const { target } = fakePlayer()

  h.transport.seekBy(target, 10)
  h.transport.seekBy(target, 10)
  assert.equal(h.applying, 2)
  h.settle()
  assert.equal(h.applying, 0)
})

test('seek targets are clamped into the playable range', () => {
  assert.equal(clampSeekTarget(-5, 600), 0)
  assert.equal(clampSeekTarget(700, 600), 599.5)
  assert.equal(clampSeekTarget(300, 600), 300)
  // A live/unknown duration must not clamp to 0 — that would restart the movie.
  assert.equal(clampSeekTarget(300, NaN), 300)
  assert.equal(clampSeekTarget(300, Infinity), 300)
  assert.equal(clampSeekTarget(300, undefined), 300)
  assert.equal(clampSeekTarget(NaN, 600), 0)
})

test('a relative seek past the end clamps instead of overshooting', () => {
  const h = harness()
  const { target } = fakePlayer({ duration: 100, at: 95 })

  const landed = h.transport.seekBy(target, 10)

  assert.equal(landed, 99.5)
  assert.deepEqual(h.emitted, [{ kind: 'seek', ticks: 99.5 * SEC }])
})

test('commands are dropped while the local position means nothing', () => {
  // A source swap (quality change) rebuilds the element from 0, and a
  // buffer-aware catch-up drives it to a transient position. Authoring the room
  // off either would teleport everybody — including to 0.
  const h = harness()
  const { target, events } = fakePlayer({ at: 0 })
  h.state.blocked = true

  assert.equal(h.transport.seekBy(target, 10), null)
  h.transport.play(target)
  h.transport.pause(target)

  assert.deepEqual(h.emitted, [])
  assert.deepEqual(events, [], 'and the local player is left alone too')
  assert.equal(h.applying, 0, 'no guard is taken for a command that never ran')

  h.state.blocked = false
  h.transport.seekBy(target, 10)
  assert.deepEqual(h.emitted, [{ kind: 'seek', ticks: 10 * SEC }])
})

test('mayAuthor separates deliberate commands from observed events', () => {
  assert.equal(mayAuthor({ origin: 'local', suppressed: true, canControl: true }), true)
  assert.equal(mayAuthor({ origin: 'media-event', suppressed: true, canControl: true }), false)
  assert.equal(mayAuthor({ origin: 'media-event', suppressed: false, canControl: true }), true)
  assert.equal(mayAuthor({ origin: 'local', suppressed: false, canControl: false }), false)
})
