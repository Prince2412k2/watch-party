// UI-free playback-sync decision core.
//
// This is the pure math extracted verbatim from the useSyncPlay control loop.
// It knows nothing about React or the DOM: given the current schedule, clock,
// and player state, it returns an *intent* object describing what the caller
// should do to the media element. The browser hook and the headless CLI client
// both drive the exact same function, so a headless guest tracks the shared
// timeline identically to a real browser guest.

export const TICKS = 10_000_000          // Jellyfin ticks per second

export const CONTROL_MS = 200
export const HARD_SEEK_SEC = 1.0         // guest drift beyond this → jump to live
export const HOST_DRAG_SEEK_SEC = 2.0    // dragging host only corrects gross drift
export const SOFT_SEC = 0.08             // drift beyond this → speed nudge
export const RATE_GAIN = 0.12
export const MAX_RATE_ADJ = 0.08
export const HOLD_TOLERANCE = 0.4

// ── Phase 12: HLS buffer-aware hard-seek tuning ─────────────────────────────
// On HLS every hard-seek is expensive: hls.js must fetch and demux fresh
// segments before the new position can render, so a naive "jump to live and
// keep playing" stalls, falls behind, and re-seeks — the buffering chase loop.
// These constants tune the buffer-aware catch-up used by the guest hopping
// hard-seek path (orchestrated in useSyncPlay / the headless client, not here).
//
//   BUFFER_AHEAD_SEC  — after seeking to the predicted position, wait until at
//                       least this many seconds are buffered *ahead* of it
//                       before resuming. Must comfortably exceed the wall-clock
//                       a seek+buffer takes, so that when we re-read the (now
//                       advanced) live position it still lands inside the freshly
//                       buffered window — otherwise we'd immediately re-stall and
//                       reopen the loop. 4s ≈ a couple of HLS segments of runway.
//   SEEK_TIMEOUT_MS   — max wait for the 'seeked' event; HLS seeks are slow, so
//                       this is generous. On timeout we proceed anyway.
//   BUFFER_TIMEOUT_MS — max wait for the buffered-ahead target; on a genuinely
//                       starved link we give up waiting and resume rather than
//                       hang the guest forever.
export const BUFFER_AHEAD_SEC = 4.0
export const SEEK_TIMEOUT_MS = 5000
export const BUFFER_TIMEOUT_MS = 8000

// Runway (seconds ahead of the target) a PAUSED guest waits for before it is
// considered "ready to resume in sync". Smaller than BUFFER_AHEAD_SEC because a
// paused guest isn't racing an advancing live clock — it only needs the target
// frame decoded plus a little runway so resume is instant. The buffer-ensure
// that uses this never calls play(); it just fetches + renders the frozen frame.
export const PAUSED_BUFFER_AHEAD_SEC = 2.0

export const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))

/**
 * Predicted shared-timeline position (seconds) at a given server time. Pure.
 * When playing, position advances from P0 at wall-rate since t0; otherwise the
 * timeline is frozen at P0. Reused by decideSyncAction and by the buffer-aware
 * hard-seek so both compute "where the host is now" identically.
 *
 * @param {object} s            schedule { positionTicks, t0, phase, ... }
 * @param {number} serverNowMs  server-aligned now in ms (a value, not a fn)
 */
export function predictPosition(s, serverNowMs) {
  if (!s) return 0
  const P0 = s.positionTicks / TICKS
  if (s.phase !== 'playing') return P0
  return P0 + (serverNowMs - s.t0) / 1000
}

/**
 * Decide the sync action for one control tick. Pure — no side effects.
 *
 * @param {object}   a
 * @param {object}   a.schedule     shared timeline { positionTicks, t0, rate, paused, phase, version }
 * @param {function} a.serverNowMs  () => server-aligned now in ms
 * @param {function} a.clockReady   () => boolean, is the NTP-lite clock trustworthy
 * @param {number}   a.currentTime  player currentTime (seconds)
 * @param {boolean}  a.paused       player.paused
 * @param {boolean}  a.isHost
 * @param {string}   a.mode         'hopping' | 'dragging'
 * @param {boolean}  a.userSeeking  is the local user actively scrubbing
 * @returns {object|null} intent, or null when the tick is a no-op:
 *   { seekTo?, rate?, play?, pause?, drift }
 *   - seekTo  : seconds to set currentTime to (a hard correction)
 *   - rate    : playbackRate to set
 *   - play    : true → call play()
 *   - pause   : true → call pause()
 *   - drift   : expected - currentTime (seconds), for telemetry (may be undefined)
 */
export function decideSyncAction({
  schedule: s, serverNowMs, clockReady, currentTime, paused, isHost, mode, userSeeking,
}) {
  if (!s) return null
  // A hopping host plays natively and never runs the correction loop.
  if (isHost && mode !== 'dragging') return null
  if (userSeeking) return null

  const P0 = s.positionTicks / TICKS

  // paused OR stalled → everyone holds at the frozen position
  if (s.phase !== 'playing') {
    const intent = { rate: 1 }
    if (!paused) intent.pause = true
    // A guest that isn't already at the frozen position must jump there AND make
    // hls.js actually fetch/decode/render the frame while staying paused (a bare
    // seek while paused doesn't reliably load the segment on HLS — the loader is
    // never kicked by a play()). pausedSeek routes this through the buffer-aware
    // paused-seek in the caller instead of a bare currentTime write.
    if (Math.abs(currentTime - P0) > HOLD_TOLERANCE) { intent.seekTo = P0; intent.pausedSeek = true }
    return intent
  }

  if (!clockReady()) return null
  const expected = predictPosition(s, serverNowMs())   // === P0 + (now - t0)/1000 while playing
  if (expected < 0) return null

  if (paused) {
    return { seekTo: expected, rate: 1, play: true, drift: expected - currentTime }
  }

  const err = expected - currentTime
  const ae = Math.abs(err)

  if (isHost) {
    // dragging host: obey the timeline, correct only gross drift, no nudge
    const intent = { rate: 1, drift: err }
    if (ae > HOST_DRAG_SEEK_SEC) intent.seekTo = expected
    return intent
  }

  if (ae > HARD_SEEK_SEC) {
    return { seekTo: expected, rate: 1, hardSeek: true, drift: err }
  } else if (ae > SOFT_SEC) {
    return { rate: 1 + clamp(err * RATE_GAIN, -MAX_RATE_ADJ, MAX_RATE_ADJ), drift: err }
  } else {
    return { rate: 1, drift: err }
  }
}
