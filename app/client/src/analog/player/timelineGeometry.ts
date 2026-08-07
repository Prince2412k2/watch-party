// Timeline layer geometry — the arithmetic behind the precision hairline.
//
// "Played progress is the strongest line segment. Loaded/buffered ranges use
// quieter tonal segments behind played progress, including visible gaps when the
// playback engine exposes separate ranges. Unloaded duration remains a
// low-contrast hairline. Cached/offline spans remain distinguishable from
// transient network buffer when both are available."
//   — docs/watchparty-design/player-interface-reference.md
//
// Pure so the layering can be tested without a renderer: the React client has no
// DOM tests, every suite here drives extracted logic.

import { analogTokens } from '../../design/analogTokens.ts'

/** A half-open span of media time, in seconds. */
export interface TimeSpan {
  start: number
  end: number
}

/** A span resolved against the track's width. */
export interface PercentSpan {
  startPct: number
  widthPct: number
  /**
   * Minimum separation to hold after this span so two nearly-adjacent ranges
   * cannot read as one continuous bar. Zero on the last span — nothing follows
   * it to separate from.
   */
  gapAfterPx: number
}

export interface TimelineInput {
  durationSec: number
  positionSec: number
  /** Real `HTMLMediaElement.buffered` ranges, not a single "furthest end". */
  buffered?: readonly TimeSpan[]
  /** On-disk / offline spans. React has no source for these yet; see below. */
  cached?: readonly TimeSpan[]
}

export interface TimelineLayers {
  playedPct: number
  buffered: PercentSpan[]
  cached: PercentSpan[]
}

const finite = (value: number) => typeof value === 'number' && Number.isFinite(value)

/**
 * Clamp spans into `0..durationSec`, drop the empty and the nonsensical, sort,
 * and merge only the ones that actually touch.
 *
 * Merging is deliberately limited to `next.start <= current.end`: a genuine hole
 * in the buffer (everything behind a forward seek, most obviously) has to
 * survive as a hole, because painting over it is exactly the lie the old
 * single-span renderer told.
 */
export function normalizeSpans(
  spans: readonly TimeSpan[] | undefined,
  durationSec: number,
): TimeSpan[] {
  if (!spans || !finite(durationSec) || durationSec <= 0) return []
  const clamped: TimeSpan[] = []
  for (const span of spans) {
    if (!span || !finite(span.start) || !finite(span.end)) continue
    const start = Math.max(0, Math.min(durationSec, span.start))
    const end = Math.max(0, Math.min(durationSec, span.end))
    if (end <= start) continue
    clamped.push({ start, end })
  }
  clamped.sort((a, b) => a.start - b.start || a.end - b.end)

  const merged: TimeSpan[] = []
  for (const span of clamped) {
    const last = merged[merged.length - 1]
    if (last && span.start <= last.end) {
      if (span.end > last.end) last.end = span.end
      continue
    }
    merged.push({ ...span })
  }
  return merged
}

/** Normalized spans -> track percentages, carrying the minimum visual gap. */
export function toPercentSpans(spans: readonly TimeSpan[], durationSec: number): PercentSpan[] {
  if (!finite(durationSec) || durationSec <= 0) return []
  return spans.map((span, index) => ({
    startPct: (span.start / durationSec) * 100,
    widthPct: ((span.end - span.start) / durationSec) * 100,
    gapAfterPx: index === spans.length - 1 ? 0 : analogTokens.hairline.rangeGapPx,
  }))
}

/** Every layer of the hairline, weakest to strongest, in one pass. */
export function timelineLayers({
  durationSec,
  positionSec,
  buffered,
  cached,
}: TimelineInput): TimelineLayers {
  const duration = finite(durationSec) && durationSec > 0 ? durationSec : 0
  const position = finite(positionSec) ? Math.max(0, Math.min(duration, positionSec)) : 0
  return {
    playedPct: duration > 0 ? (position / duration) * 100 : 0,
    buffered: toPercentSpans(normalizeSpans(buffered, duration), duration),
    cached: toPercentSpans(normalizeSpans(cached, duration), duration),
  }
}

// ── geometry that must not move the surrounding controls ────────────────────
//
// "Keep the visible idle line approximately 2px thick while providing a much
// larger invisible pointer/touch target. During hover, focus, or scrubbing, the
// visible line expands slightly to about 4px WITHOUT MOVING SURROUNDING
// CONTROLS."
//
// That is what `trackBoxPx` is for: the interactive box is a constant `hitPx`
// tall no matter how thick the line inside it is, so growing the line changes
// nothing about the layout around it.

export interface HairlineActivity {
  hovered?: boolean
  focused?: boolean
  dragging?: boolean
}

export const isHairlineActive = (activity: HairlineActivity): boolean =>
  Boolean(activity.hovered || activity.focused || activity.dragging)

export const hairlineThicknessPx = (activity: HairlineActivity): number =>
  isHairlineActive(activity) ? analogTokens.hairline.activePx : analogTokens.hairline.idlePx

/** Constant. The hit target never shrinks when the visible line is at rest. */
export const trackBoxPx = (): number => analogTokens.hairline.hitPx

/** The handle shows on hover, focus or drag — never permanently. */
export const isHandleVisible = (activity: HairlineActivity): boolean => isHairlineActive(activity)

/**
 * Keyboard/remote focus has to be obvious "without permanently enlarging" the
 * handle, so focus gets the larger diameter and pointer hover keeps the small
 * one.
 */
export const handleDiameterPx = (activity: HairlineActivity): number =>
  activity.focused ? analogTokens.hairline.handleFocusPx : analogTokens.hairline.handlePx

// ── pointer -> time ─────────────────────────────────────────────────────────

export interface TrackRect {
  left: number
  width: number
}

export function ratioFromPointer(clientX: number, rect: TrackRect): number {
  if (!rect || !finite(rect.width) || rect.width <= 0) return 0
  return Math.min(1, Math.max(0, (clientX - rect.left) / rect.width))
}

export const seekTimeFromRatio = (ratio: number, durationSec: number): number =>
  !finite(durationSec) || durationSec <= 0 ? 0 : Math.min(1, Math.max(0, ratio)) * durationSec

/** Keep a hover popup (trickplay frame or bare time chip) inside the track. */
export function clampPopupCenter(x: number, popupWidth: number, trackWidth: number): number {
  const half = popupWidth / 2
  return Math.min(Math.max(x, half), Math.max(half, trackWidth - half))
}
