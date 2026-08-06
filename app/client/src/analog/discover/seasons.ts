// The season chooser's grouping and per-season state.
//
// TV arrives in pieces over time, so a series request is monitor-and-search
// rather than grab-now: the season is flipped to monitored and a SeasonSearch is
// fired, and episodes land as they are found. That makes "what state is this
// season in" a three-way answer — what Sonarr already tracks, what this session
// has asked for, and what failed — which is exactly the kind of thing that goes
// wrong quietly, so it lives here.

import type { CatalogItem, CatalogSeason } from './catalog.ts'
import { isAdded } from './catalog.ts'

/** Season 0 is Sonarr's specials bucket. */
export const SPECIALS_SEASON = 0

export interface SeasonGroups {
  /** Seasons 1..n, in order. */
  regular: CatalogSeason[]
  /** Season 0, listed separately and last. */
  specials: CatalogSeason[]
}

/**
 * Split and order the season list.
 *
 * Specials are separated rather than sorted to the end because they are also
 * excluded from "All seasons": asking for every season of a show should not
 * quietly pull down a decade of behind-the-scenes featurettes.
 */
export function groupSeasons(item: CatalogItem): SeasonGroups {
  const seasons = Array.isArray(item.seasons) ? item.seasons : []
  return {
    regular: seasons
      .filter((season) => season.seasonNumber >= 1)
      .slice()
      .sort((a, b) => a.seasonNumber - b.seasonNumber),
    specials: seasons.filter((season) => season.seasonNumber === SPECIALS_SEASON),
  }
}

/**
 * Whether this show has seasons to choose between.
 *
 * One predicate rather than one per call site: the primary action, the Enter
 * key and the sheet all have to agree, and a show with nothing but specials is
 * exactly the case where two hand-written checks disagree.
 */
export function hasSeasonList(item: CatalogItem): boolean {
  const groups = groupSeasons(item)
  return groups.regular.length > 0 || groups.specials.length > 0
}

export type SeasonRequestState = 'requesting' | 'requested' | 'error'
export type SeasonState = 'idle' | SeasonRequestState | 'monitored'

/**
 * What one season is doing.
 *
 * `monitored` only means "already tracked in your library" when the series is
 * actually added. A not-yet-added lookup echoes TVDB's defaults, which usually
 * mark every season monitored — reading that as already-added would show a whole
 * show as tracked before anyone had asked for any of it.
 */
export function seasonState(
  season: CatalogSeason,
  requests: Readonly<Record<number, SeasonRequestState | undefined>>,
  item: CatalogItem,
): SeasonState {
  const requested = requests[season.seasonNumber]
  if (requested) return requested
  return isAdded(item) && season.monitored ? 'monitored' : 'idle'
}

/** The seasons "All seasons" asks for: every regular one, never the specials. */
export const allSeasonNumbers = (groups: SeasonGroups): number[] =>
  groups.regular.map((season) => season.seasonNumber)

/** Whether "All seasons" has nothing left to do. */
export function allSeasonsCovered(
  groups: SeasonGroups,
  requests: Readonly<Record<number, SeasonRequestState | undefined>>,
  item: CatalogItem,
): boolean {
  if (groups.regular.length === 0) return false
  return groups.regular.every((season) => {
    const state = seasonState(season, requests, item)
    return state === 'monitored' || state === 'requested'
  })
}

export const anySeasonRequesting = (
  requests: Readonly<Record<number, SeasonRequestState | undefined>>,
): boolean => Object.values(requests).some((state) => state === 'requesting')

export const seasonLabel = (season: CatalogSeason): string =>
  season.seasonNumber === SPECIALS_SEASON ? 'Specials' : `Season ${season.seasonNumber}`

/**
 * The episode count, when Sonarr has one.
 *
 * A series that is not in the library yet has no counts at all, and rendering
 * "0 episodes" against every season of a show that plainly has some reads as a
 * broken listing rather than as missing data.
 */
export function episodeCountLabel(season: CatalogSeason): string | null {
  const total = season.totalEpisodeCount ?? season.statistics?.totalEpisodeCount ?? null
  if (total == null || total <= 0) return null
  return `${total} episode${total === 1 ? '' : 's'}`
}

/** Mark a set of seasons at once, for the optimistic flip before the request lands. */
export function withSeasonState(
  requests: Readonly<Record<number, SeasonRequestState | undefined>>,
  seasons: readonly number[],
  state: SeasonRequestState,
): Record<number, SeasonRequestState | undefined> {
  const next = { ...requests }
  for (const season of seasons) next[season] = state
  return next
}
