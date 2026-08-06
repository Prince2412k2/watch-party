// The Shows stage's browse model: the series list, the drill-in to a series,
// the season axis on the right rail, and the episode rail a season drives.
//
// Shows is where the Movies stage came from conceptually — a rail of posters
// along the bottom, the focused item's details on the stage itself, Enter plays
// — so everything genuinely shared is imported rather than restated here:
// `railWindow`/`clampRailOffset` through movieRail.ts, `restoreFocus` through
// surface.ts, `resolveSeasonArtwork` from browseCore.ts, and `StageIntent`
// itself from movieBrowse.ts, which is what lets one AnalogRail drive both
// stages instead of two rails that have to be kept in step by hand.
//
// The one axis Movies does not have is the season. It is presented and driven
// exactly like the Singles/Collections slider — right rail, Up/Down, a stepped
// scroll outside the rail — with two differences that matter: it only exists
// once a series is open, and it selects from a list whose length comes off the
// server rather than stepping between two fixed positions. So the vertical
// intents are the same two names ('mode-prev'/'mode-next'); what they move is
// what differs between the surfaces.
//
// Pure: no React, no fetching. The page is the only thing that knows a URL.

import { resolveArtwork, primaryImageTag, type ArtworkItem } from './artwork.ts'
import type { SeasonArtwork } from './browseCore.ts'
import { surfaceId, type StackLevel } from './surface.ts'

export const SERIES_TYPE = 'Series'
export const SEASON_TYPE = 'Season'
export const EPISODE_TYPE = 'Episode'

// ── the browse stack ────────────────────────────────────────────────────────
//
// The season rides on the stack rather than in component state, for the same
// reason the Movies mode does: `session.browse.stack` is what a party driver
// publishes, and a follower who received only the drill-in level would sit on
// season 1 while the driver reads season 4. `BrowseEntry` is explicitly
// open-ended on the wire (types.ts) and other surfaces already carry extra keys
// on it.

export interface ShowLevel extends StackLevel {
  /** The season selected inside a series level. Absent means "the first". */
  seasonId?: string
}

export interface ShowsView {
  Id: string
  Name: string
  Type?: string
}

/** The root of the stack: the Shows library view. */
export const rootLevel = (view: ShowsView): ShowLevel => ({
  id: view.Id,
  name: view.Name,
  type: view.Type ?? 'CollectionFolder',
})

export const rootOf = (stack: readonly ShowLevel[]): ShowLevel | null => stack[0] ?? null

/**
 * The series currently drilled into, or null at the list level.
 *
 * The type check is what keeps a follower sane when the driver is on the
 * superseded Library implementation, which pushes `Season` and `Episode` levels
 * of its own. Treating one of those as a series would ask Jellyfin for the
 * children of an episode and render an empty rail. A level with no type at all
 * is still accepted — the wire allows every field to be absent, and this
 * surface only ever pushes series.
 */
export function seriesFromStack(stack: readonly ShowLevel[]): ShowLevel | null {
  const top = stack[stack.length - 1]
  if (!top || stack.length < 2 || typeof top.id !== 'string') return null
  if (top.type !== undefined && top.type !== SERIES_TYPE) return null
  return top
}

/** The season on the stack, or null — including at the list level, where a
 *  leftover season id would otherwise leak into the surface identity. */
export function seasonFromStack(stack: readonly ShowLevel[]): string | null {
  const series = seriesFromStack(stack)
  return typeof series?.seasonId === 'string' && series.seasonId.length > 0 ? series.seasonId : null
}

/** Enter on a series: its seasons become the right rail, its episodes the bottom one. */
export function openSeries(
  stack: readonly ShowLevel[],
  series: { Id: string; Name?: string; Type?: string },
): ShowLevel[] {
  const root = rootOf(stack)
  if (!root) return [...stack]
  return [root, { id: series.Id, name: series.Name ?? '', type: SERIES_TYPE }]
}

/** Back out of a series to the list it came from. */
export function closeSeries(stack: readonly ShowLevel[]): ShowLevel[] {
  return stack.length > 1 ? stack.slice(0, -1) : [...stack]
}

/** Move the season axis. A no-op outside a series, which has no axis to move. */
export function withSeason(stack: readonly ShowLevel[], seasonId: string): ShowLevel[] {
  const series = seriesFromStack(stack)
  if (!series) return [...stack]
  const next = [...stack]
  next[next.length - 1] = { ...series, seasonId }
  return next
}

// ── the season axis ─────────────────────────────────────────────────────────

export interface SeasonItem {
  Id: string
  Name?: string
  Type?: string
  IndexNumber?: number | null
  SeriesId?: string | null
  ChildCount?: number | null
  ImageTags?: { Primary?: string | null } | null
  SeriesPrimaryImageTag?: string | null
}

/**
 * A season's label on the rail.
 *
 * Jellyfin usually names seasons ("Season 3", "Specials"), but a library that
 * was scanned without metadata gives them nothing at all, and an unlabelled
 * position on a slider is unusable. `IndexNumber` is preferred over the display
 * order because season 0 is Specials and listing it as "Season 1" would be a
 * lie.
 */
export function seasonLabel(season: SeasonItem, index: number): string {
  if (season.Name) return season.Name
  return season.IndexNumber == null ? `Season ${index + 1}` : `Season ${season.IndexNumber}`
}

export const seasonIndex = (seasons: readonly SeasonItem[], seasonId: string | null): number =>
  seasonId == null ? -1 : seasons.findIndex((season) => season.Id === seasonId)

/**
 * The season actually being shown.
 *
 * Derived rather than defaulted into the stack on arrival: writing the first
 * season back the moment the list lands would make a follower's client publish
 * over its driver, and would put a state write inside a render path that runs
 * again every time the seasons refetch. Both clients derive the same answer
 * from the same list, so they agree without either of them writing.
 */
export function resolveSeasonId(
  seasons: readonly SeasonItem[],
  seasonId: string | null,
): string | null {
  if (seasons.length === 0) return null
  if (seasonId != null && seasons.some((season) => season.Id === seasonId)) return seasonId
  return seasons[0].Id
}

/**
 * One step of the season axis. Clamped rather than wrapping, exactly like the
 * mode slider: holding Down must settle on the last season instead of cycling
 * back to the first, which on a twelve-season series is indistinguishable from
 * the control being broken.
 */
export function stepSeason(
  seasons: readonly SeasonItem[],
  seasonId: string | null,
  direction: number,
): string | null {
  if (seasons.length === 0) return null
  const current = Math.max(0, seasonIndex(seasons, resolveSeasonId(seasons, seasonId)))
  const next = Math.max(0, Math.min(current + Math.sign(direction), seasons.length - 1))
  return seasons[next].Id
}

/**
 * The bottom rail's contents inside a series.
 *
 * `null` means "still arriving" and renders a skeleton; `[]` means "there is
 * genuinely nothing here" and renders the empty state. Keeping those two apart
 * is the difference between a show Sonarr has not populated yet saying so and
 * sitting under a shimmer forever.
 */
export function seasonEpisodes<T>(
  episodes: Readonly<Record<string, readonly T[]>>,
  seasons: readonly SeasonItem[] | null,
  seasonId: string | null,
): readonly T[] | null {
  if (seasons === null) return null
  if (seasons.length === 0 || seasonId === null) return []
  return episodes[seasonId] ?? null
}

// ── season artwork ──────────────────────────────────────────────────────────
//
// "season poster -> series poster -> fixed neutral season placeholder", through
// `resolveSeasonArtwork` in browseCore.ts — the shared, cross-language core —
// and never through a second copy. The request goes to
// `/api/library/image/{seasonId}?type=Primary`: same-origin and whitelisted
// server-side. The Sonarr image path is not used at all; it is cross-origin and
// broken.

export interface SeriesLike {
  Id: string
  ImageTags?: { Primary?: string | null } | null
}

/**
 * The season, shaped so `resolveArtwork` runs the shared chain over it.
 *
 * A season fetched from `/api/library/items/:seriesId/children` does not
 * reliably carry its parent's poster tag — the proxy only guarantees the fields
 * it asks for — so the series the user drilled into is folded in here. Without
 * that, a season with no art of its own would drop straight to the placeholder
 * and skip the series poster the reference calls for.
 */
export function seasonArtworkItem(season: SeasonItem, series: SeriesLike | null): ArtworkItem {
  const seriesId = season.SeriesId ?? series?.Id ?? null
  return {
    Id: season.Id,
    Name: season.Name,
    Type: SEASON_TYPE,
    IndexNumber: season.IndexNumber ?? null,
    SeriesId: seriesId,
    ImageTags: season.ImageTags,
    SeriesPrimaryImageTag: series ? primaryImageTag(series) : season.SeriesPrimaryImageTag,
  }
}

/** The resolved chain for a season. One definition, shared with the poster. */
export const seasonArtwork = (
  season: SeasonItem,
  series: SeriesLike | null,
  failedIds: readonly string[] = [],
): SeasonArtwork => resolveArtwork(seasonArtworkItem(season, series), failedIds)

// ── activation ──────────────────────────────────────────────────────────────

export type ShowActivation =
  /** A series is a container: Enter opens it, the way a franchise opens on Movies. */
  | { kind: 'open'; series: { Id: string; Name?: string; Type?: string } }
  /** An episode's details are already on the stage, so Enter plays it. */
  | { kind: 'play'; itemId: string }
  | { kind: 'none' }

const NONE: ShowActivation = { kind: 'none' }

/**
 * What Enter/click does to the focused item.
 *
 * Driven by the item's type rather than by which rail it came from, so a series
 * opens wherever it is encountered and everything else plays. One rule instead
 * of two that have to agree.
 */
export function activationFor(
  item: { Id?: string; Name?: string; Type?: string } | null | undefined,
): ShowActivation {
  if (!item || typeof item.Id !== 'string' || item.Id.length === 0) return NONE
  if (item.Type === SERIES_TYPE) {
    return { kind: 'open', series: { Id: item.Id, Name: item.Name, Type: item.Type } }
  }
  return { kind: 'play', itemId: item.Id }
}

// ── surfaces ────────────────────────────────────────────────────────────────

export const SHOWS_TAB = 'shows'

/**
 * The focus-memory key for where the user is.
 *
 * The season is part of the identity because two seasons are two different
 * lists of two different lengths; sharing one memory would restore focus in one
 * from a position only the other ever had. The series list keeps its own key, so
 * Back lands on the exact series that was left from rather than at the start of
 * the library.
 */
export function showsSurface(stack: readonly ShowLevel[], seasonId: string | null): string {
  const path: StackLevel[] = [...stack]
  if (seriesFromStack(stack) && seasonId) path.push({ id: seasonId })
  return surfaceId(SHOWS_TAB, path)
}
