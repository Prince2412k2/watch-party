// Regression for audit finding #11 (soft-correction band hysteresis).
//
// decideSyncAction's soft-correction band previously had a single threshold
// (SOFT_SEC): drift oscillating right around that boundary would flip
// playbackRate between 1.0 and a corrected rate every CONTROL_MS tick
// (audible rate flutter). The fix adds an optional `correctionState` param
// implementing enter/exit hysteresis: once a nudge starts, drift must fall
// under the tighter SOFT_EXIT_SEC bound (not just back under SOFT_SEC) before
// it stops.
//
// This calls decideSyncAction directly with synthetic drift — no server or
// guests needed — since the fix lives entirely in the pure decision function
// and is opt-in (omitting correctionState must reproduce the old behavior
// exactly, which this also asserts).

import { check } from './_helpers.js'
import { decideSyncAction, SOFT_SEC, SOFT_EXIT_SEC } from '../../client/src/sync/syncCore.js'

// Drift sequence hovering across the SOFT_SEC boundary: alternates between
// just above SOFT_SEC and just below it but still above SOFT_EXIT_SEC (i.e.
// squarely in the hysteresis band), then finally drops below SOFT_EXIT_SEC.
const ABOVE_SOFT = SOFT_SEC + 0.01
const IN_BAND = (SOFT_SEC + SOFT_EXIT_SEC) / 2   // below SOFT_SEC, above SOFT_EXIT_SEC
const BELOW_EXIT = SOFT_EXIT_SEC - 0.01
const DRIFTS = [ABOVE_SOFT, IN_BAND, ABOVE_SOFT, IN_BAND, ABOVE_SOFT, IN_BAND, ABOVE_SOFT, IN_BAND, BELOW_EXIT]

// currentTime pinned at 0, t0=0, so predictPosition(schedule, serverNowMs()) ==
// serverNowMs()/1000 == the desired err directly (expected - currentTime).
function runSequence(drifts, useHysteresis) {
  const correctionState = useHysteresis ? { correcting: false } : null
  const trace = []
  let toggles = 0
  let prev = null
  for (const drift of drifts) {
    const schedule = { positionTicks: 0, t0: 0, phase: 'playing', paused: false, version: 1 }
    const intent = decideSyncAction({
      schedule,
      serverNowMs: () => Math.round(drift * 1000),
      clockReady: () => true,
      currentTime: 0,
      paused: false,
      isHost: false,
      mode: 'hopping',
      userSeeking: false,
      correctionState,
    })
    const correcting = intent.rate !== 1
    trace.push(correcting)
    if (prev !== null && correcting !== prev) toggles++
    prev = correcting
  }
  return { trace, toggles }
}

export const softCorrectionHysteresis = {
  name: 'soft-correction-hysteresis',
  async run() {
    const without = runSequence(DRIFTS, false)
    const withH = runSequence(DRIFTS, true)

    // Sanity: both engage correction on the very first (unambiguous, above
    // SOFT_SEC) sample — hysteresis only changes what happens AFTER engaging.
    const bothEngageFirst = without.trace[0] === true && withH.trace[0] === true

    // Without correctionState: every sample in DRIFTS alternates across the
    // single SOFT_SEC threshold, so consecutive ticks must flip.
    const flapsWithoutHysteresis = without.toggles >= DRIFTS.length - 2

    // With correctionState: once engaged by the first ABOVE_SOFT sample, the
    // in-band samples (below SOFT_SEC but above SOFT_EXIT_SEC) must NOT drop
    // correction — no toggling until the sequence actually falls under
    // SOFT_EXIT_SEC at the very end.
    const noFlapWithHysteresis = withH.toggles === 1   // exactly the final drop-below-exit transition
    const staysEngagedThroughBand = withH.trace.slice(0, -1).every(c => c === true)
    const dropsBelowExit = withH.trace[withH.trace.length - 1] === false

    return { checks: [
      check('both engage on first clearly-above-threshold sample', bothEngageFirst, `without=${without.trace[0]} with=${withH.trace[0]}`),
      check('single-threshold (no correctionState) flaps in the hysteresis band', flapsWithoutHysteresis, `toggles=${without.toggles}/${DRIFTS.length - 1}`),
      check('with correctionState, stays engaged through the band (no flapping)', noFlapWithHysteresis && staysEngagedThroughBand, `toggles=${withH.toggles} trace=[${withH.trace.join(',')}]`),
      check('with correctionState, disengages once drift falls under SOFT_EXIT_SEC', dropsBelowExit, `finalDrift=${BELOW_EXIT.toFixed(3)} correcting=${withH.trace[withH.trace.length - 1]}`),
      check('omitting correctionState reproduces the exact original single-threshold behavior', without.toggles === DRIFTS.length - 2, `toggles=${without.toggles}`),
    ] }
  },
}
