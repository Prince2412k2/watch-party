// Browsing interaction core — the parts of the analog stage model that must
// behave identically in React and Flutter.
//
// Ported verbatim to flutter_app/lib/analog/browse_core.dart. Both ports are
// driven by app/shared/design/interaction.json, so a change to one that isn't
// mirrored in the other fails the other language's suite.
//
// Everything here is pure: no DOM, no timers, no framework. Callers own the
// clock and feed `atMs` in.

// ── stepped scroll ──────────────────────────────────────────────────────────
//
// "Each deliberate gesture moves one item; momentum is absorbed so focus never
// coasts past the intended item." (analog-interface-reference.md)
//
// Wheel and trackpad hardware emit wildly different event streams: a notched
// mouse wheel sends a few large deltas, a trackpad flick sends dozens of small
// decaying ones. Mapping raw delta to focus movement makes the trackpad
// unusable, so deltas are accumulated to a threshold and the inertia tail is
// discarded.

export interface SteppedScrollConfig {
  /** Accumulated delta needed to move focus one item. */
  stepThresholdPx: number
  /** Silence long enough to count as the end of a gesture. */
  gestureIdleMs: number
  /** Floor for the minimum wall time between two steps. */
  stepCooldownMs: number
  /** Deltas at or below this, after a step, are the momentum tail. */
  inertiaFloorPx: number
}

export const STEPPED_SCROLL_DEFAULTS: SteppedScrollConfig = {
  stepThresholdPx: 48,
  gestureIdleMs: 140,
  stepCooldownMs: 110,
  inertiaFloorPx: 8,
}

export interface SteppedScrollState {
  accumPx: number
  lastEventAtMs: number | null
  lastStepAtMs: number | null
  /** Sign of the gesture in progress: -1, 0 or 1. */
  direction: number
}

export const newSteppedScrollState = (): SteppedScrollState => ({
  accumPx: 0,
  lastEventAtMs: null,
  lastStepAtMs: null,
  direction: 0,
})

/**
 * Feed one wheel/trackpad event. Returns the focus movement it produces:
 * `-1`, `0` or `+1` — never more than one item per event, which is what stops
 * a fast flick from coasting.
 *
 * Mutates `state` in place; the Dart port does the same so the fixture scripts
 * read identically in both languages.
 */
export function steppedScroll(
  state: SteppedScrollState,
  deltaPx: number,
  atMs: number,
  config: SteppedScrollConfig = STEPPED_SCROLL_DEFAULTS,
): number {
  // A gap in the event stream ends the gesture: nothing carries over.
  if (state.lastEventAtMs !== null && atMs - state.lastEventAtMs >= config.gestureIdleMs) {
    state.accumPx = 0
    state.direction = 0
  }
  state.lastEventAtMs = atMs

  if (deltaPx === 0) return 0

  const sign = deltaPx > 0 ? 1 : -1
  // A deliberate reverse restarts accumulation rather than cancelling out
  // against travel already spent in the other direction.
  if (state.direction !== 0 && sign !== state.direction) state.accumPx = 0
  state.direction = sign

  // The decaying tail of a flick, after the gesture has already scored a step.
  if (Math.abs(deltaPx) <= config.inertiaFloorPx && state.lastStepAtMs !== null) return 0

  state.accumPx += deltaPx
  if (Math.abs(state.accumPx) < config.stepThresholdPx) return 0

  // Threshold reached but the previous step is too recent: hold at the line
  // instead of banking the excess, so a burst can't discharge as a run of steps.
  if (state.lastStepAtMs !== null && atMs - state.lastStepAtMs < config.stepCooldownMs) {
    state.accumPx = sign * config.stepThresholdPx
    return 0
  }

  state.accumPx = 0
  state.lastStepAtMs = atMs
  return sign
}

// ── focus restoration ───────────────────────────────────────────────────────
//
// "Back returns to the exact browsing position and focused item."
//
// The interesting cases are the ones where "exact" is no longer available: the
// item was removed from the shelf, or the shelf itself is gone. Both happen
// routinely here — Continue Watching reorders as you watch, and Downloads
// empties. Focus has to land somewhere sensible and deterministic.

export interface FocusPosition {
  shelfId: string
  itemId: string
}

/** The shelves currently on screen, in display order. */
export interface ShelfSnapshot {
  shelfId: string
  itemIds: readonly string[]
}

export type FocusMemory = Record<string, FocusPosition>

export const rememberFocus = (
  memory: FocusMemory,
  surfaceId: string,
  position: FocusPosition,
): FocusMemory => ({ ...memory, [surfaceId]: { ...position } })

export const forgetFocus = (memory: FocusMemory, surfaceId: string): FocusMemory => {
  const next = { ...memory }
  delete next[surfaceId]
  return next
}

export type FocusRestoreKind =
  /** The remembered shelf and item both still exist. */
  | 'exact'
  /** The shelf survived but the item did not; focus lands by index. */
  | 'nearest'
  /** The shelf is gone (or nothing was remembered); focus lands on the default. */
  | 'default'
  /** Nothing focusable exists at all. */
  | 'empty'

export interface FocusRestoreResult {
  kind: FocusRestoreKind
  position: FocusPosition | null
}

/**
 * Resolve where focus should land when returning to a surface.
 *
 * `rememberedIndex` is the index the item held when it was remembered; it is
 * what makes the "item removed" case land next to where the user was rather
 * than at the start of the shelf.
 */
export function restoreFocus(
  memory: FocusMemory,
  surfaceId: string,
  shelves: readonly ShelfSnapshot[],
  rememberedIndex = 0,
): FocusRestoreResult {
  const firstFocusable = shelves.find((shelf) => shelf.itemIds.length > 0)
  const fallback: FocusRestoreResult = firstFocusable
    ? { kind: 'default', position: { shelfId: firstFocusable.shelfId, itemId: firstFocusable.itemIds[0] } }
    : { kind: 'empty', position: null }

  const remembered = memory[surfaceId]
  if (!remembered) return fallback

  const shelf = shelves.find((candidate) => candidate.shelfId === remembered.shelfId)
  if (!shelf || shelf.itemIds.length === 0) return fallback

  if (shelf.itemIds.includes(remembered.itemId)) {
    return { kind: 'exact', position: { shelfId: shelf.shelfId, itemId: remembered.itemId } }
  }

  // The item went away. Hold the index — clamped into the shortened shelf — so
  // focus stays where the user's attention was.
  const index = Math.max(0, Math.min(rememberedIndex, shelf.itemIds.length - 1))
  return { kind: 'nearest', position: { shelfId: shelf.shelfId, itemId: shelf.itemIds[index] } }
}

// ── season artwork fallback ─────────────────────────────────────────────────
//
// "season poster -> series poster -> fixed neutral season placeholder"
//
// React and Flutter must derive this from the same Jellyfin season item
// contract rather than each maintaining its own metadata-provider behaviour.
// The placeholder is fixed-size on purpose: layout and focus must not move
// when artwork is missing.

export interface SeasonArtworkInput {
  seasonId: string
  seasonNumber: number | null
  /** Jellyfin `ImageTags.Primary` on the season item, when it has its own art. */
  seasonImageTag: string | null
  seriesId: string
  seriesImageTag: string | null
  /** Image ids already known to have failed to load, so a retry can't loop. */
  failedIds?: readonly string[]
}

export type SeasonArtworkKind = 'season' | 'series' | 'placeholder'

export interface SeasonArtwork {
  kind: SeasonArtworkKind
  /** Jellyfin item id to request Primary art for; null for the placeholder. */
  itemId: string | null
  imageTag: string | null
  /** Text the placeholder shows, e.g. "S3". Null unless kind is 'placeholder'. */
  label: string | null
}

export function resolveSeasonArtwork(input: SeasonArtworkInput): SeasonArtwork {
  const failed = new Set(input.failedIds ?? [])

  if (input.seasonImageTag && !failed.has(input.seasonId)) {
    return { kind: 'season', itemId: input.seasonId, imageTag: input.seasonImageTag, label: null }
  }
  if (input.seriesImageTag && !failed.has(input.seriesId)) {
    return { kind: 'series', itemId: input.seriesId, imageTag: input.seriesImageTag, label: null }
  }
  return {
    kind: 'placeholder',
    itemId: null,
    imageTag: null,
    label: input.seasonNumber === null ? '—' : `S${input.seasonNumber}`,
  }
}

// ── fixed-cursor rail window ────────────────────────────────────────────────
//
// The rail does not move a highlight along a stationary row. The cursor is
// pinned to the first slot and the ROW translates underneath it, the way an
// old console menu works. So "which item is selected" and "how far the row has
// scrolled" are the same number: `offset`.
//
// That makes the visible set trivially derivable, which is what prefetch needs:
// the native client can warm artwork for the items about to slide into view
// instead of decoding them on arrival. Both clients compute the same window
// from the same inputs, so "snappy" is a contract rather than each client
// guessing its own lookahead.

export interface RailWindowInput {
  /** Items in the rail. */
  total: number
  /** Index rendered in the pinned first slot. */
  offset: number
  /** Slots visible on screen at once. */
  slots: number
  /** Items past the last visible slot to warm ahead of arrival. */
  lookahead?: number
  /** Items before the cursor to keep warm, so scrolling back is not a stall. */
  behind?: number
  /**
   * Whether the cursor is *pinned* to the first slot.
   *
   * A shelf's cursor moves within it, so its row stops at the last full page
   * rather than trailing empty space — that is `pinned` false, the default.
   *
   * The Movies/Shows rail is the other model: "selected movie/show should
   * always be first, so when I scroll, the whole thing scrolls to put the movie
   * on the first spot." There the row must keep travelling past the last full
   * page, and the tail of the rail simply runs out of items to the right of the
   * selection. Trailing space is the price of the selection never moving.
   */
  pinned?: boolean
}

export interface RailWindow {
  /** Indices currently on screen, left to right. */
  visible: number[]
  /** Indices to warm but not render. Never overlaps `visible`. */
  prefetch: number[]
}

export const RAIL_LOOKAHEAD = 6
export const RAIL_BEHIND = 2

export function railWindow(input: RailWindowInput): RailWindow {
  const { total, slots } = input
  const lookahead = input.lookahead ?? RAIL_LOOKAHEAD
  const behind = input.behind ?? RAIL_BEHIND
  if (total <= 0 || slots <= 0) return { visible: [], prefetch: [] }

  // Pinned: the selection is always the first slot, so the only clamp is
  // against the ends of the list. Unpinned: a shelf scrolled to its end still
  // fills its slots rather than trailing empty space, so the offset is clamped
  // against the last full page.
  const maxOffset = input.pinned ? total - 1 : Math.max(0, total - slots)
  const start = Math.max(0, Math.min(input.offset, maxOffset))
  const end = Math.min(total, start + slots)

  const visible: number[] = []
  for (let index = start; index < end; index += 1) visible.push(index)

  const prefetch: number[] = []
  for (let index = Math.max(0, start - behind); index < start; index += 1) prefetch.push(index)
  for (let index = end; index < Math.min(total, end + lookahead); index += 1) prefetch.push(index)

  return { visible, prefetch }
}

/**
 * Clamp an offset the way `railWindow` does, for callers stepping a shelf.
 *
 * For a *pinned* rail use `clampPinnedOffset`: the selection is the offset, so
 * clamping it against the last full page would stop the row short and strand
 * the final items away from the first slot.
 */
export const clampRailOffset = (offset: number, total: number, slots: number): number =>
  Math.max(0, Math.min(offset, Math.max(0, total - slots)))

/** Clamp an offset for a rail whose cursor is pinned to the first slot. */
export const clampPinnedOffset = (offset: number, total: number): number =>
  total <= 0 ? 0 : Math.max(0, Math.min(offset, total - 1))
