// The library IS the detail view.
//
// "Backdrop will not be this dark and will show the movie's details in the
// library itself. [similar to the show screen where movies will act like
// episodes]" — so the focused title's copy, metadata and actions are derived
// here and rendered on the browse stage. There is no second screen to open, and
// therefore no drill-in for a movie at all: Enter plays it.
//
// Pure, so the derivations that actually go wrong — a runtime rendered from the
// wrong tick scale, a resolution read off an audio stream, a Resume label on a
// title nobody has started — are testable without a DOM.

import { fmtRuntimeFromTicks } from '../lib/format.ts'

export interface MediaStream {
  Type?: string
  Height?: number | null
  Width?: number | null
  VideoRange?: string | null
}

export interface MediaSource {
  Id?: string
  Size?: number | null
  MediaStreams?: MediaStream[] | null
}

/** A Jellyfin item as any of this stage's three lists delivers it. */
export interface StageItem {
  Id: string
  Name: string
  Type: string
  Overview?: string | null
  Genres?: string[] | null
  ProductionYear?: number | null
  CommunityRating?: number | null
  OfficialRating?: string | null
  RunTimeTicks?: number | null
  ChildCount?: number | null
  IndexNumber?: number | null
  SeriesId?: string | null
  ImageTags?: { Primary?: string | null } | null
  SeriesPrimaryImageTag?: string | null
  UserData?: {
    PlayedPercentage?: number | null
    PlaybackPositionTicks?: number | null
    Played?: boolean | null
  } | null
  MediaSources?: MediaSource[] | null
}

// ── metadata line ───────────────────────────────────────────────────────────

/**
 * Vertical resolution → the label the meta line shows.
 *
 * Read off the VIDEO stream specifically. `MediaStreams[0]` is not reliably the
 * video track, and an audio stream has no Height at all, so indexing blind
 * produces "?P" on exactly the files that do have a resolution to show.
 */
export function resolutionLabel(item: Pick<StageItem, 'MediaSources'>): string | null {
  const streams = item.MediaSources?.[0]?.MediaStreams ?? []
  const video = streams.find((stream) => stream.Type === 'Video')
  const height = video?.Height ?? 0
  if (!height) return null
  if (height >= 2160) return '4K'
  if (height >= 1440) return '1440P'
  if (height >= 1080) return '1080P'
  if (height >= 720) return '720P'
  return `${height}P`
}

export const ratingLabel = (item: Pick<StageItem, 'CommunityRating'>): string | null =>
  item.CommunityRating == null ? null : `★ ${item.CommunityRating.toFixed(1)}`

/**
 * The meta line: rating · runtime · year · resolution.
 *
 * Fixed order, gaps closed rather than padded — a title with no community rating
 * must not leave a leading separator, and one with no media source must not end
 * on one.
 */
export function metaLine(item: StageItem): string[] {
  return [
    ratingLabel(item),
    fmtRuntimeFromTicks(item.RunTimeTicks),
    item.ProductionYear ? String(item.ProductionYear) : null,
    resolutionLabel(item),
  ].filter((value): value is string => Boolean(value))
}

/** The line above the title: certificate, then genres. */
export function eyebrowParts(item: StageItem, context?: string | null): string[] {
  return [
    context ?? null,
    item.OfficialRating ?? null,
    ...(item.Genres ?? []).slice(0, 3),
  ].filter((value): value is string => Boolean(value))
}

// ── actions ─────────────────────────────────────────────────────────────────

/** Resume position in ticks, or null when the title has not been started. */
export function resumeTicks(item: StageItem): number | null {
  const ticks = item.UserData?.PlaybackPositionTicks
  return typeof ticks === 'number' && ticks > 0 ? ticks : null
}

/**
 * The primary action's label.
 *
 * A collection is the one item on this stage that does not play, because it is
 * the one whose details are not the whole story — its parts are.
 */
export function playActionLabel(item: StageItem | null): string {
  if (!item) return 'Play'
  if (item.Type === 'BoxSet') {
    const count = item.ChildCount ?? 0
    return count > 0 ? `Open ${count} titles` : 'Open collection'
  }
  const resume = resumeTicks(item)
  const label = resume ? fmtRuntimeFromTicks(resume) : null
  return label ? `Resume ${label}` : 'Play'
}

export interface StageActions {
  /** Whether the primary action plays (rather than opening a collection). */
  plays: boolean
  label: string
  /** Audio/subtitle selection only applies to something with media behind it. */
  tracks: boolean
  /** Offline download. Only the native shell can hold a file. */
  download: boolean
}

/**
 * Which actions the stage offers for the focused item.
 *
 * `native` is `IS_NATIVE`. The offline download UI has always been gated on it
 * (native/env.ts says so in as many words) — a browser tab has nowhere to put a
 * downloaded file, and rendering the control disabled everywhere else would
 * leave a permanently dead button on the primary surface.
 */
export function stageActions(item: StageItem | null, native: boolean): StageActions {
  if (!item) return { plays: false, label: 'Play', tracks: false, download: false }
  const playable = item.Type !== 'BoxSet'
  return {
    plays: playable,
    label: playActionLabel(item),
    tracks: playable,
    download: playable && native,
  }
}

// ── enrichment ──────────────────────────────────────────────────────────────

/**
 * Whether the focused item still needs `/api/library/item/:id` before the stage
 * can render it fully.
 *
 * Collection parts arrive from `/api/library/collections/:id/items` with the
 * full field set, so drilling into a franchise costs no extra request at all.
 * The singles list comes from `/children`, which asks Jellyfin only for
 * `MediaSources` — Overview and Genres are optional fields it does not return —
 * so those are fetched once per title and cached. Asking for it unconditionally
 * would put a request behind every step of the rail.
 */
export function needsEnrichment(item: StageItem | null | undefined): boolean {
  if (!item) return false
  if (item.Type === 'BoxSet') return false
  return item.Overview === undefined || item.Genres === undefined
}

/**
 * The enriched detail merged over the list entry.
 *
 * The list entry wins on nothing: `/api/library/item/:id` is the same item with
 * strictly more fields. Merging rather than replacing keeps the item identical
 * when the fetch has not landed yet, so the stage never blanks mid-scroll.
 */
export function mergeDetail(item: StageItem, detail: StageItem | undefined): StageItem {
  return detail ? { ...item, ...detail } : item
}
