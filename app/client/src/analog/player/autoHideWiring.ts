// The timer arithmetic around `playerCore`'s auto-hide state.
//
// `tickAutoHide` resolves visibility for a given instant but says nothing about
// WHEN the caller should next look. A React hook needs that: an interval that
// polls four times a second to notice a three-second timeout is both wasteful
// and imprecise, so the hook schedules a single timeout at the exact deadline.
// That scheduling is arithmetic, so it lives here and is tested here.

import { analogTokens } from '../../design/analogTokens.ts'
import { type AutoHideState } from '../playerCore.ts'

/**
 * When the chrome is due to hide, or `null` when it is not due at all.
 *
 * Held or paused means never — the hold set is what keeps the chrome up
 * mid-interaction, and "controls hide after three seconds" is scoped to
 * "during playback".
 */
export function autoHideDeadlineMs(state: AutoHideState): number | null {
  if (state.holds.length > 0 || !state.playing) return null
  return state.lastInputAtMs + analogTokens.timing.chromeAutoHideMs
}

/**
 * Milliseconds until the caller must tick again, or `null` when no tick is
 * needed. Already-hidden chrome needs no timer; an overdue deadline returns 0
 * so the caller resolves it immediately rather than scheduling into the past.
 */
export function msUntilAutoHide(state: AutoHideState, nowMs: number): number | null {
  if (!state.visible) return null
  const deadline = autoHideDeadlineMs(state)
  if (deadline == null) return null
  return Math.max(0, deadline - nowMs)
}

/**
 * Hide right now — the phone's tap-to-toggle, which must be able to dismiss the
 * chrome without waiting out the timer.
 *
 * An explicit tap may dismiss a paused player's controls too. Open menus and
 * active gestures still hold the chrome; a later input restores it normally.
 */
export function hideNow(state: AutoHideState, nowMs: number): AutoHideState {
  if (state.holds.length) return state
  return { ...state, visible: false, lastInputAtMs: nowMs }
}

/** Reasons the chrome is pinned open. Strings, so two holds cannot collide. */
export const CHROME_HOLD = {
  settings: 'settings',
  scrubbing: 'scrubbing',
  volume: 'volume',
} as const

export type ChromeHoldReason = (typeof CHROME_HOLD)[keyof typeof CHROME_HOLD]
