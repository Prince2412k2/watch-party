// UI-free playback-sync decision core.
//
// This is the pure math extracted verbatim from the useSyncPlay control loop.
// It knows nothing about React or the DOM: given the current schedule, clock,
// and player state, it returns an *intent* object describing what the caller
// should do to the media element. The browser hook and the headless CLI client
// both drive the exact same function, so a headless guest tracks the shared
// timeline identically to a real browser guest.

export const TICKS = 10_000_000          // Jellyfin ticks per second

// ── Correction-loop tuning ──────────────────────────────────────────────────
// These are fixed constants, not adaptive to network/media conditions (RTT
// jitter, HLS segment duration, buffer health). That's a known simplification,
// not an oversight — see the per-constant notes below for the reasoning behind
// each value and what "tunable" would mean if this ever needs to react to
// conditions instead of using one number for every guest:
//
//   CONTROL_MS           — how often the correction loop re-evaluates drift.
//                           200ms is fast enough to feel responsive without
//                           spamming currentTime/rate writes or drift telemetry.
//   HARD_SEEK_SEC        — guest drift beyond this is treated as "lost sync",
//                           not "running slightly hot/cold": a rate nudge would
//                           take too long to close a gap this size, so we jump
//                           straight to the buffer-aware hard-seek path instead.
//                           1.0s is a guess at "clearly desynced" for typical
//                           home-network jitter; a high-latency/high-jitter link
//                           would benefit from widening this (fewer, bigger
//                           corrections) but that requires a jitter estimate we
//                           don't currently compute (see clock-quality gap).
//   HOST_DRAG_SEEK_SEC   — a dragging host only obeys the shared timeline for
//                           gross drift (e.g. it stalled and fell behind the
//                           room), not routine jitter — hence a looser bound
//                           than HARD_SEEK_SEC.
//   SOFT_SEC             — below HARD_SEEK_SEC but above this, drift is closed
//                           with a bounded rate nudge instead of a seek (seeks
//                           are disruptive; nudges are not). 80ms is roughly
//                           the smallest drift a viewer reliably perceives as
//                           audio/video desync.
//   RATE_GAIN / MAX_RATE_ADJ — how aggressively the nudge closes drift, and how
//                           far playbackRate is allowed to move from 1.0 while
//                           doing it. MAX_RATE_ADJ=0.08 (i.e. 0.92x–1.08x) is
//                           chosen to stay under the point most viewers notice
//                           a pitch/speed change; RATE_GAIN=0.12 sets how much
//                           of the current error is corrected per tick.
//   HOLD_TOLERANCE       — slack around the frozen position while paused so a
//                           guest already sitting on the right frame doesn't
//                           re-seek on every tick from float/measurement noise.
//   HARD_SEEK_COOLDOWN_MS — see suppressHardSeek below: a debounce, not a
//                           network-aware value, so it doesn't need tuning per
//                           connection quality, only per "how long does one
//                           hard-seek+buffer round trip take".
//
// None of this reacts to measured jitter, RTT, or HLS segment length today —
// that would need the clock/quality signals described in the sync audit
// (clock uncertainty, recent drift variance) to decide, live, where these
// thresholds should sit per guest. Out of scope here; documenting the
// reasoning so a future change knows what each constant is actually trading
// off before moving it.
export const CONTROL_MS = 200
export const HARD_SEEK_SEC = 1.0         // guest drift beyond this → jump to live
export const HOST_DRAG_SEEK_SEC = 2.0    // dragging host only corrects gross drift
export const SOFT_SEC = 0.08             // drift beyond this → speed nudge begins (enter threshold)
// Exit threshold for the soft-correction nudge, deliberately lower than SOFT_SEC.
// Without a separate exit point, drift hovering right around SOFT_SEC flips the
// nudge on/off every CONTROL_MS tick (audible rate flutter). Once correcting,
// stay correcting until drift falls under this tighter bound instead. See
// `correctionState` on decideSyncAction.
export const SOFT_EXIT_SEC = 0.04
export const RATE_GAIN = 0.12
export const MAX_RATE_ADJ = 0.08
export const HOLD_TOLERANCE = 0.4
// Debounce after a hard seek: suppresses re-triggering another hard seek for
// this long so the buffer-aware catch-up (which takes real wall time) isn't
// re-entered mid-flight from a stale drift reading. This is the hysteresis for
// the HARD_SEEK_SEC boundary — see `suppressHardSeek` below.
export const HARD_SEEK_COOLDOWN_MS = 2500

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
 * @param {object}   [a.correctionState]  optional, caller-owned mutable object
 *   (e.g. a ref persisted across ticks for this one guest/player) used only to
 *   add hysteresis to the soft-correction band: `{ correcting: boolean }`.
 *   When provided, once a nudge starts it keeps correcting until drift falls
 *   under SOFT_EXIT_SEC rather than immediately stopping at SOFT_SEC, so drift
 *   hovering near the boundary doesn't flip playbackRate on/off every tick.
 *   Omitting it (the default) reproduces the original single-threshold
 *   behavior exactly — this parameter is opt-in and changes nothing for a
 *   caller that doesn't pass it.
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
  suppressHardSeek = false, correctionState = null,
}: any = {}): any {
  if (!s) return null
  // A hopping host plays natively and never runs the correction loop.
  if (isHost && mode !== 'dragging') return null
  if (userSeeking) return null

  const P0 = s.positionTicks / TICKS

  // paused OR stalled → everyone holds at the frozen position
  if (s.phase !== 'playing') {
    const intent: any = { rate: 1 }
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
    const drift = expected - currentTime
    const intent: any = { seekTo: expected, rate: 1, play: true, drift }
    // A paused hopping guest is commonly a late joiner. Large initial drift
    // needs the same buffered rendezvous as a playing guest's hard correction;
    // seek+play directly into unbuffered HLS creates a stall/re-seek loop.
    if (!isHost && mode === 'hopping' && Math.abs(drift) > HARD_SEEK_SEC) intent.hardSeek = true
    return intent
  }

  const err = expected - currentTime
  const ae = Math.abs(err)

  if (isHost) {
    // dragging host: obey the timeline, correct only gross drift, no nudge
    const intent: any = { rate: 1, drift: err }
    if (ae > HOST_DRAG_SEEK_SEC) intent.seekTo = expected
    return intent
  }

  if (ae > HARD_SEEK_SEC && !suppressHardSeek) {
    if (correctionState) correctionState.correcting = false
    return { seekTo: expected, rate: 1, hardSeek: true, drift: err }
  }

  // Hysteresis around the soft-correction band (see correctionState doc above):
  // once already nudging, require drift to fall under the lower SOFT_EXIT_SEC
  // bound before stopping, instead of the higher SOFT_SEC enter bound. With no
  // correctionState supplied, wasCorrecting is always false, so threshold is
  // always SOFT_SEC — identical to the original single-threshold check.
  const wasCorrecting = correctionState ? !!correctionState.correcting : false
  const softThreshold = wasCorrecting ? SOFT_EXIT_SEC : SOFT_SEC
  const shouldCorrect = ae > softThreshold
  if (correctionState) correctionState.correcting = shouldCorrect

  if (shouldCorrect) {
    return { rate: 1 + clamp(err * RATE_GAIN, -MAX_RATE_ADJ, MAX_RATE_ADJ), drift: err }
  }
  return { rate: 1, drift: err }
}
