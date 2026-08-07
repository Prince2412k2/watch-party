// The fixed-cursor rail.
//
// "Currently movie cursor moves around. Now we will have our cursor at the first
// position and the whole row will move. Like old video game consoles."
//
// The window geometry itself is `railWindow`/`clampRailOffset` in browseCore.ts —
// shared with Flutter and driven by app/shared/design/interaction.json. Nothing
// here re-derives it. This file is the surface-shaped layer around it: where the
// cursor actually sits once the row has run out of travel, how far the track has
// to translate to put the window's first index under it, how big the posters are
// now that they are a rail along the bottom rather than the main event, and which
// artwork to warm before it arrives.
//
// Pure on purpose. The repo has no DOM tests; every suite runs on extracted
// logic, and the rail's arithmetic is exactly the part worth pinning.

import { clampPinnedOffset, railWindow } from './browseCore.ts'
import { artworkSrc, backdropSrc, resolveArtwork, type ArtworkItem } from './artwork.ts'
import { analogTokens } from '../design/analogTokens.ts'
import type { StageSize } from './stageLayout.ts'

// ── cursor + window ─────────────────────────────────────────────────────────

export interface RailCursorInput {
  total: number
  /**
   * The selected index. In this model "which item is selected" and "how far the
   * row has scrolled" are the same number, which is what makes the visible set —
   * and therefore the prefetch set — trivially derivable.
   */
  selection: number
  /** Slots visible on screen at once. */
  slots: number
  lookahead?: number
  behind?: number
}

export interface RailCursor {
  /** Index sitting in the leftmost slot. What the track translates to. */
  start: number
  /**
   * Which slot the cursor occupies. **Always zero.**
   *
   * Kept as a field rather than dropped so the surface reads its position from
   * the model instead of hard-coding a 0, and so a regression that moves the
   * cursor shows up here rather than as a layout mystery.
   */
  cursorSlot: number
  visible: number[]
  /** Indices to warm but not render. Never overlaps `visible`. */
  prefetch: number[]
}

export function railCursor(input: RailCursorInput): RailCursor {
  const { total, slots } = input
  if (total <= 0 || slots <= 0) return { start: 0, cursorSlot: 0, visible: [], prefetch: [] }

  const start = clampPinnedOffset(input.selection, total)
  const { visible, prefetch } = railWindow({
    total,
    offset: start,
    slots,
    lookahead: input.lookahead,
    behind: input.behind,
    pinned: true,
  })

  return { start, cursorSlot: 0, visible, prefetch }
}

/**
 * One step of the cursor. Clamped rather than wrapping: there is one rail on
 * this surface, so an overflow has nowhere to go and a wrap would make the ends
 * of a long library indistinguishable from each other.
 */
export function stepRailSelection(selection: number, total: number, direction: number): number {
  if (total <= 0) return 0
  return Math.max(0, Math.min(selection + Math.sign(direction), total - 1))
}

/** Centre-to-centre distance between two slots. */
export const railStepPx = (posterWidthPx: number, gapPx: number): number => posterWidthPx + gapPx

/** How far the track is translated to put `start` under the cursor. Never positive. */
export function railTranslatePx(start: number, posterWidthPx: number, gapPx: number): number {
  const travelled = start * railStepPx(posterWidthPx, gapPx)
  // `-0` is a real value that survives into a template literal as "-0px".
  return travelled === 0 ? 0 : -travelled
}

/**
 * The contiguous index range that has to exist in the DOM.
 *
 * `visible` alone would mount an arriving poster at the instant the track starts
 * moving, which is a decode in the middle of the transition. Mounting the warmed
 * neighbours as well means the item under the cursor after a step was already
 * laid out and decoded a step ago.
 */
export function railRendered(cursor: RailCursor): number[] {
  const indices = [...cursor.visible, ...cursor.prefetch]
  if (indices.length === 0) return []
  const first = Math.min(...indices)
  const last = Math.max(...indices)
  const rendered: number[] = []
  for (let index = first; index <= last; index += 1) rendered.push(index)
  return rendered
}

// ── rail sizing ─────────────────────────────────────────────────────────────
//
// "We put the posters in movie selection bottom and make them smaller." The
// stage's main event is now the focused title's details, so the rail is a strip
// underneath them rather than the half-height shelf `stageLayout` sizes.

export interface RailMetrics {
  posterWidthPx: number
  gapPx: number
  /** Whole posters that fit across the rail at this width. */
  slots: number
}

/**
 * Target poster width per device size — roughly two thirds of the shelf's, so
 * ten titles are on screen at once on a desktop where seven used to be.
 */
const RAIL_POSTER_PX: Record<StageSize, number> = { phone: 68, tablet: 88, desktop: 104 }

/** Below this a poster is an icon rather than artwork you can recognise. */
const MIN_RAIL_POSTER_PX = 64

export function railMetrics(usableWidthPx: number, size: StageSize): RailMetrics {
  const gapPx = analogTokens.poster.gapPx
  const target = RAIL_POSTER_PX[size]
  const usable = Math.max(MIN_RAIL_POSTER_PX, usableWidthPx)

  // Fit whole posters across the usable width, then spend the remainder widening
  // them back out — so the rail always ends on a poster edge instead of a sliver
  // of the next one, at any viewport width.
  const slots = Math.max(1, Math.floor((usable + gapPx) / (target + gapPx)))
  const posterWidthPx = Math.max(MIN_RAIL_POSTER_PX, Math.floor((usable - gapPx * (slots - 1)) / slots))

  return { posterWidthPx, gapPx, slots }
}

// ── prefetch ────────────────────────────────────────────────────────────────
//
// `railWindow(...).prefetch` names the indices about to slide into view. Warming
// their artwork is the difference between a rail that steps and one that steps
// and then pops a frame later while the browser decodes.

export interface PrefetchInput {
  items: readonly ArtworkItem[]
  /** Indices to warm — `railCursor(...).prefetch`. */
  indices: readonly number[]
  /** Images already known to 404, from the shared artwork registry. */
  failedIds?: readonly string[]
}

/**
 * Artwork URLs to warm, in arrival order.
 *
 * Both the poster AND the backdrop: the backdrop IS the selection feedback on
 * this stage, so an unwarmed one means every step shows the previous title's
 * artwork until the next decode lands. Deduplicated because a title with no wide
 * art falls back to its own poster, which would otherwise be requested twice.
 */
export function prefetchTargets({ items, indices, failedIds = [] }: PrefetchInput): string[] {
  const urls: string[] = []
  const seen = new Set<string>()

  for (const index of indices) {
    const item = items[index]
    if (!item) continue
    const poster = artworkSrc(resolveArtwork(item, failedIds))
    const backdrop = backdropSrc(item.Id)
    for (const url of [poster, backdrop]) {
      if (!url || seen.has(url)) continue
      seen.add(url)
      urls.push(url)
    }
  }

  return urls
}
