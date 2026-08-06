// Responsive and reduced-motion branches for the analog stage, derived from the
// generated tokens rather than hand-picked numbers.
//
// Phones keep the same stage and focus model as desktop — full-screen backdrop,
// one tactile shelf owning focus, bottom modes — so this returns *sizes*, never
// a different layout. The only thing that changes across the breakpoints is how
// much of the shelf is visible at once.

import { analogTokens } from '../design/analogTokens.ts'

export type StageSize = 'phone' | 'tablet' | 'desktop'

export interface StageLayout {
  size: StageSize
  /** Inset from the viewport edge to the stage content. */
  gutterPx: number
  posterWidthPx: number
  gapPx: number
  /** Whole posters that fit across the shelf at this width. */
  visibleCount: number
}

/** Posters we aim to show across the shelf, per size. */
const TARGET_ACROSS: Record<StageSize, number> = { phone: 3, tablet: 5, desktop: 7 }

/**
 * Below this a poster stops being readable artwork and becomes an icon; above
 * it the shelf reads as a wall of few enormous tiles rather than a collection.
 */
const MIN_POSTER_PX = 104
const MAX_POSTER_PX = 232

const clamp = (value: number, low: number, high: number) => Math.max(low, Math.min(high, value))

/** Share of the stage height the shelf may take, artwork plus caption. */
const SHELF_HEIGHT_SHARE = 0.46

/**
 * `coarsePointer` is `usePhone()`, which is already "phone-class device in ANY
 * orientation" — coarse pointer AND (narrow OR short). That is the right signal
 * and the 640px `useIsMobile()` breakpoint is not: a narrow *desktop* window is
 * still a desktop (mouse, hover, keyboard) and giving it the phone's three-
 * across shelf would make it worse, not smaller.
 *
 * Height matters as much as width because the stage is the whole viewport. A
 * phone held sideways is 844px wide and 390px tall — wide enough for big
 * posters that would not come close to fitting.
 */
export function stageLayout(
  viewportWidthPx: number,
  viewportHeightPx: number,
  coarsePointer: boolean,
): StageLayout {
  const { tabletMaxPx } = analogTokens.breakpoint
  const size: StageSize = coarsePointer ? 'phone' : viewportWidthPx <= tabletMaxPx ? 'tablet' : 'desktop'

  const gutterPx = size === 'phone' ? analogTokens.space.stageGutterPhonePx : analogTokens.space.stageGutterPx
  const gapPx = analogTokens.poster.gapPx
  const across = TARGET_ACROSS[size]
  const usable = Math.max(MIN_POSTER_PX, viewportWidthPx - gutterPx * 2)

  const byWidth = Math.floor((usable - gapPx * (across - 1)) / across)
  const byHeight = Math.floor(
    (viewportHeightPx * SHELF_HEIGHT_SHARE * analogTokens.poster.aspectW) / analogTokens.poster.aspectH,
  )
  const posterWidthPx = clamp(Math.min(byWidth, byHeight), MIN_POSTER_PX, MAX_POSTER_PX)
  const visibleCount = Math.max(1, Math.floor((usable + gapPx) / (posterWidthPx + gapPx)))

  return { size, gutterPx, posterWidthPx, gapPx, visibleCount }
}

// ── reduced motion ──────────────────────────────────────────────────────────

export interface MotionProfile {
  focusStepMs: number
  backdropCrossMs: number
  chromeFadeMs: number
  drawerMs: number
  focusScale: number
  focusLiftPx: number
  /** Frame around the artwork. Thicker when motion is off — see below. */
  framePx: number
  scrollBehavior: 'smooth' | 'auto'
}

/**
 * "Reduced-motion mode must preserve all state changes without spatial
 * effects." So every duration collapses, the forward lift and the focus scale
 * go away, and the backdrop still changes — it just cuts instead of crossing.
 *
 * That removes two of the four things focus is built from, and "selection must
 * not rely on color alone" rules out replacing them with a tint. The frame
 * around the focused poster therefore thickens instead: a size change, not a
 * spatial one, and it survives on a monochrome display.
 */
export function motionProfile(reducedMotion: boolean): MotionProfile {
  const { motion, selection, poster } = analogTokens
  if (reducedMotion) {
    return {
      focusStepMs: 0,
      backdropCrossMs: 0,
      chromeFadeMs: 0,
      drawerMs: 0,
      focusScale: selection.restScale,
      focusLiftPx: 0,
      framePx: poster.framePx * 3,
      scrollBehavior: 'auto',
    }
  }
  return {
    focusStepMs: motion.focusStepMs,
    backdropCrossMs: motion.backdropCrossMs,
    chromeFadeMs: motion.chromeFadeMs,
    drawerMs: motion.drawerMs,
    focusScale: selection.focusScale,
    focusLiftPx: selection.focusLiftPx,
    framePx: poster.framePx,
    scrollBehavior: 'smooth',
  }
}

// ── scene light ─────────────────────────────────────────────────────────────

export interface EdgeLightOffsets {
  /** Inset offsets for the lit edge, in px. */
  litX: number
  litY: number
  /** Inset offsets for the shaded edge, in px. */
  shadeX: number
  shadeY: number
}

/**
 * `selection.sceneLightAngleDeg` (315 = above-left) → the inset box-shadow
 * offsets that put the highlight on the edges facing the light and the shade on
 * the ones facing away.
 *
 * CSS angle convention: 0deg points up, increasing clockwise. The unit vector
 * *towards* the light is therefore (sin a, -cos a); an inset shadow offset by
 * the negative of that lands on the lit edge.
 */
export function edgeLightOffsets(angleDeg: number, weightPx: number): EdgeLightOffsets {
  const radians = (angleDeg * Math.PI) / 180
  const towardsX = Math.sin(radians)
  const towardsY = -Math.cos(radians)
  const round = (value: number) => Math.round(value * weightPx * 100) / 100
  return {
    litX: round(-towardsX),
    litY: round(-towardsY),
    shadeX: round(towardsX),
    shadeY: round(towardsY),
  }
}
