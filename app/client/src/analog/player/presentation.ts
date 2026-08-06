// Accessibility-preference branches for the player chrome.
//
// Two requirements from the references, both of which change what is painted
// rather than merely how fast:
//
//   "Reduced-motion mode removes spatial transitions while preserving placement
//    previews and state feedback."
//   "Reduced-transparency mode uses an opaque surface with equivalent contrast."
//
// Pure and token-driven so both branches are testable, and so "equivalent
// contrast" is a fact about the values rather than a claim in a comment.

import { analogTokens, ease } from '../../design/analogTokens.ts'

export interface DisplayPreferences {
  reducedMotion: boolean
  reducedTransparency: boolean
}

export const defaultDisplayPreferences: DisplayPreferences = {
  reducedMotion: false,
  reducedTransparency: false,
}

export interface SurfaceStyle {
  background: string
  border: string
  boxShadow: string
}

/**
 * The toast surface.
 *
 * Translucent by default (`backdropScrim` is the warm ground at 85%); opaque
 * under reduced transparency. Both are drawn from the neutral ramp and both
 * carry `--an-color-ink` text, so the contrast the reader gets does not depend
 * on which branch they are in — the opaque colour is if anything darker than
 * the translucent one composited over a bright frame.
 */
export function toastSurface(prefs: DisplayPreferences): SurfaceStyle {
  return {
    background: prefs.reducedTransparency
      ? 'var(--an-color-stage-ground)'
      : 'var(--an-color-backdrop-scrim)',
    border: '1px solid var(--an-color-line-strong)',
    boxShadow: prefs.reducedTransparency ? 'none' : '0 8px 24px var(--an-color-shadow-cast)',
  }
}

/** The settings stack sits over the frame and follows the same rule. */
export function panelSurface(prefs: DisplayPreferences): SurfaceStyle {
  return {
    background: prefs.reducedTransparency
      ? 'var(--an-color-stage-ground)'
      : 'var(--an-color-stage-surface)',
    border: '1px solid var(--an-color-line)',
    boxShadow: prefs.reducedTransparency ? 'none' : '0 18px 46px var(--an-color-shadow-cast-strong)',
  }
}

export const motionDurationMs = (prefs: DisplayPreferences, ms: number): number =>
  prefs.reducedMotion ? 0 : ms

/**
 * A CSS transition string, or `'none'`.
 *
 * Reduced motion removes the transition outright rather than shortening it: the
 * end state — a thicker line, a visible handle, a revealed stack — is the state
 * feedback the reference says to preserve, and it is preserved by arriving
 * instantly.
 */
export function chromeTransition(
  prefs: DisplayPreferences,
  properties: string[],
  ms: number = analogTokens.motion.chromeFadeMs,
): string {
  if (prefs.reducedMotion || properties.length === 0) return 'none'
  const curve = ease(analogTokens.motion.chromeFadeEase)
  return properties.map((property) => `${property} ${ms}ms ${curve}`).join(', ')
}

/**
 * Entrance for a surface that expands upward (`up` is the existing
 * translateY(10px) -> none keyframe in styles.css). Reduced motion gets no
 * animation at all — the stack is simply there.
 */
export function riseAnimation(prefs: DisplayPreferences, ms = analogTokens.motion.drawerMs): string {
  if (prefs.reducedMotion) return 'none'
  return `up ${ms}ms ${ease(analogTokens.motion.drawerEase)} both`
}
