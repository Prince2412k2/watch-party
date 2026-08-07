// The catalog shapes Discover browses, and the derivations the stage reads off
// them.
//
// Discover's rail is not the Jellyfin library: it is whatever Radarr/Sonarr say
// exists in the world, which is a different item shape with different identity
// (tmdbId/tvdbId, not a Jellyfin Id), different artwork (a remote CDN, proxied
// same-origin by the server) and a different notion of "have it" (the catalog
// echoes back a numeric `id` only for titles it already tracks).
//
// Pure on purpose. There are no DOM tests in this repo, and these are the
// derivations that actually went wrong in the surface this replaces: a rating
// read off the wrong one of three shapes, a poster hotlinked past the proxy, a
// title matched to the wrong torrent.

import { isRecord, arrayOf } from '../../types/guards.ts'

// ── identity ────────────────────────────────────────────────────────────────

export type Kind = 'movie' | 'series'
export type Service = 'radarr' | 'sonarr'

export const serviceFor = (kind: Kind): Service => (kind === 'movie' ? 'radarr' : 'sonarr')

export const KIND_LABELS: Record<Kind, string> = { movie: 'Movies', series: 'Shows' }

/** Slider order, top to bottom. Up moves towards the first, Down the last. */
export const KINDS: readonly Kind[] = ['movie', 'series']

/**
 * One step of the Movies/Series slider.
 *
 * Clamped rather than wrapping, exactly like `stepBrowseMode` on the Movies
 * stage: holding Down must settle on Shows rather than flickering, and the same
 * function serves the arrow keys and a stepped scroll so the two input routes
 * cannot drift.
 */
export function stepKind(kind: Kind, direction: number): Kind {
  const index = KINDS.indexOf(kind)
  const next = index + Math.sign(direction)
  return KINDS[Math.max(0, Math.min(next, KINDS.length - 1))]
}

// ── the wire shapes ─────────────────────────────────────────────────────────

export interface CatalogImage {
  coverType?: string
  /** Already rewritten server-side to the same-origin `/api/servarr/remote-image` proxy. */
  remoteUrl?: string
  url?: string
}

export interface CatalogRating {
  value?: number
  imdb?: { value?: number }
  tmdb?: { value?: number }
}

export interface CatalogSeason {
  seasonNumber: number
  monitored?: boolean
  totalEpisodeCount?: number
  statistics?: { episodeCount?: number; totalEpisodeCount?: number; percentOfEpisodes?: number }
}

export interface CatalogItem {
  /** Present ONLY when the catalog already tracks this title. */
  id?: number
  tmdbId?: number
  tvdbId?: number
  titleSlug?: string
  title: string
  originalTitle?: string
  year?: number
  network?: string
  status?: string
  overview?: string
  images?: CatalogImage[]
  ratings?: CatalogRating
  runtime?: number
  genres?: string[]
  certification?: string
  seasonCount?: number
  seasons?: CatalogSeason[]
  monitored?: boolean
  qualityProfileId?: number
  rootFolderPath?: string
  languageProfileId?: number
}

export interface QualityProfile {
  id: number
  name?: string
}

export interface RootFolder {
  id?: number
  path: string
  freeSpace?: number
}

export interface CatalogMetadata {
  profiles: QualityProfile[]
  rootFolders: RootFolder[]
  langProfiles: QualityProfile[]
}

export const isCatalogItem = (value: unknown): value is CatalogItem =>
  isRecord(value) && typeof value.title === 'string'

export const isQualityProfile = (value: unknown): value is QualityProfile =>
  isRecord(value) && typeof value.id === 'number'

export const isRootFolder = (value: unknown): value is RootFolder =>
  isRecord(value) && typeof value.path === 'string'

export const outcomeOf = (value: unknown): string | undefined =>
  isRecord(value) && typeof value.outcome === 'string' ? value.outcome : undefined

export interface DiscoverFeed {
  source: string
  items: CatalogItem[]
}

export function parseDiscoverFeed(value: unknown): DiscoverFeed {
  const source = isRecord(value) && typeof value.source === 'string' ? value.source : 'curated'
  return { source, items: arrayOf(isRecord(value) ? value.items : null, isCatalogItem) }
}

/**
 * The feed's own heading.
 *
 * A genuine live list and the curated fallback are not the same claim, and the
 * surface this replaces said "Trending" for both.
 */
export const feedLabel = (source: string): string =>
  source === 'tmdb_trending' ? 'Trending this week' : 'Discover'

// ── identity + library membership ───────────────────────────────────────────

/**
 * A stable per-item key for request state.
 *
 * Keyed on the catalog id rather than the title, because a search and the
 * discover feed return the same title as two different objects and a request
 * made from one has to show on the other. Falls back to the slug and then the
 * title, so an item missing its provider id still gets its own state rather
 * than sharing `m:undefined` with every other one.
 */
export function keyOf(kind: Kind, item: CatalogItem): string {
  const prefix = kind === 'movie' ? 'm' : 's'
  const id = kind === 'movie' ? item.tmdbId : item.tvdbId
  if (id != null) return `${prefix}:${id}`
  return `${prefix}:${item.titleSlug || item.title}`
}

/**
 * "Already in the library" — the lookup echoes back a numeric id only for
 * titles the catalog already tracks.
 */
export const isAdded = (item: CatalogItem): boolean => item.id != null

// ── artwork ─────────────────────────────────────────────────────────────────

/**
 * Pick a poster out of a lookup's `images`.
 *
 * `remoteUrl` first: the server rewrites it to the same-origin
 * `/api/servarr/remote-image` proxy, which is the ONLY route this client may
 * take to third-party artwork — the session cookie rides on every request and
 * hotlinking a CDN would ship it to them. `url` points at the *arr instance and
 * 404s for a title that has not been added, so it is strictly the fallback.
 */
export function posterUrl(images?: CatalogImage[]): string | null {
  if (!Array.isArray(images) || images.length === 0) return null
  const poster = images.find((image) => image.coverType === 'poster') || images[0]
  return poster?.remoteUrl || poster?.url || null
}

/** Wide art for the stage backdrop; a poster is the fallback, as everywhere else. */
export function backdropUrl(images?: CatalogImage[]): string | null {
  if (!Array.isArray(images) || images.length === 0) return null
  const wide =
    images.find((image) => image.coverType === 'fanart') ||
    images.find((image) => image.coverType === 'banner')
  return wide?.remoteUrl || wide?.url || posterUrl(images)
}

// ── ratings ─────────────────────────────────────────────────────────────────

/**
 * One 0–10 rating out of the three shapes the catalog returns: newer Radarr
 * sends `{imdb:{value}, tmdb:{value}}`, older sends a flat `{value}`, and a
 * title nobody has rated sends a zero that must not render as "★ 0.0".
 */
export function ratingOf(item: CatalogItem): number | null {
  const ratings = item.ratings
  if (!ratings) return null
  const value =
    (typeof ratings.value === 'number' ? ratings.value : null) ??
    ratings.imdb?.value ??
    ratings.tmdb?.value ??
    null
  return typeof value === 'number' && value > 0 ? value : null
}

export const ratingLabel = (item: CatalogItem): string | null => {
  const value = ratingOf(item)
  return value == null ? null : `★ ${value.toFixed(1)}`
}

// ── torrent matching ────────────────────────────────────────────────────────

export interface TorrentLike {
  hash?: string
  name?: string
  title?: string
  state?: string
  progress?: number
  dlspeed?: number
  eta?: number
  numSeeds?: number
  numLeechs?: number
}

/**
 * Lowercase, non-alphanumerics to spaces, collapsed. Release names look like
 * "The.Matrix.1999.1080p.WEB-DL", so this is what makes a normalized substring
 * match a usable link between a live download and the title that spawned it.
 */
export const normTitle = (value?: string): string =>
  (value || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()

/**
 * The live download for a title, if one is running.
 *
 * Reads `.name` (qBittorrent) and `.title` (*arr queue records) because both
 * carry the release name and both reach this surface through the same hub. The
 * two-character floor keeps a one-letter title from matching every download in
 * the queue.
 */
export function matchTorrent<T extends TorrentLike>(
  title: string,
  torrents?: readonly T[] | null,
): T | null {
  const needle = normTitle(title)
  if (!needle || needle.length < 2 || !Array.isArray(torrents)) return null
  return torrents.find((torrent) => normTitle(torrent.name || torrent.title).includes(needle)) || null
}

// ── the stage's copy ────────────────────────────────────────────────────────

/**
 * The line above the title: kind, certificate, then genres — the same shape
 * `eyebrowParts` gives the Movies stage, so the two surfaces read as one app.
 */
export function eyebrowParts(item: CatalogItem, kind: Kind): string[] {
  return [
    kind === 'movie' ? 'Movie' : 'Series',
    item.certification ?? null,
    ...(item.genres ?? []).slice(0, 3),
  ].filter((value): value is string => Boolean(value))
}

/**
 * Rating · runtime · year · (series: seasons, network, status).
 *
 * Gaps are closed rather than padded, so a title with no rating does not open
 * on a separator and one with no network does not end on one.
 */
export function metaLine(item: CatalogItem, kind: Kind, runtime: string | null): string[] {
  const seasons =
    kind === 'series' && item.seasonCount != null
      ? `${item.seasonCount} season${item.seasonCount === 1 ? '' : 's'}`
      : null
  return [
    ratingLabel(item),
    runtime,
    item.year != null ? String(item.year) : null,
    seasons,
    kind === 'series' ? (item.network ?? null) : null,
    kind === 'series' ? (item.status ?? null) : null,
  ].filter((value): value is string => Boolean(value))
}

/**
 * Default add options from the cached metadata.
 *
 * Returns null when the instance has no quality profile or no root folder —
 * a request built without either is rejected by the *arr API, so this is the
 * one place that decides "the one-tap path is not available right now".
 */
export function defaultAddOptions(
  meta: CatalogMetadata,
): { qualityProfileId: number; rootFolderPath: string; languageProfileId?: number } | null {
  const qualityProfileId = meta.profiles[0]?.id
  const rootFolderPath = meta.rootFolders[0]?.path
  if (qualityProfileId == null || !rootFolderPath) return null
  const languageProfileId = meta.langProfiles[0]?.id
  return languageProfileId == null
    ? { qualityProfileId, rootFolderPath }
    : { qualityProfileId, rootFolderPath, languageProfileId }
}

/**
 * The body for `POST /api/servarr/{svc}/request`.
 *
 * Movies are a single deterministic grab-or-remove and carry no toggles; series
 * monitor and search over time, so they do. Building both here keeps the
 * one-tap path and the options dialog from drifting into two different requests
 * for the same button.
 */
export function requestBody(
  kind: Kind,
  item: CatalogItem,
  options: { qualityProfileId: number; rootFolderPath: string; languageProfileId?: number },
  series: { monitor: boolean; searchNow: boolean } = { monitor: true, searchNow: true },
): Record<string, unknown> {
  if (kind === 'movie') {
    return {
      movie: item,
      qualityProfileId: options.qualityProfileId,
      rootFolderPath: options.rootFolderPath,
    }
  }
  return {
    series: item,
    qualityProfileId: options.qualityProfileId,
    languageProfileId: options.languageProfileId,
    rootFolderPath: options.rootFolderPath,
    monitor: series.monitor,
    searchNow: series.searchNow,
  }
}

/** The DELETE path that removes a title and its files from the library. */
export const removePath = (kind: Kind, id: number): string =>
  kind === 'movie'
    ? `/api/servarr/radarr/movie/${id}?deleteFiles=true`
    : `/api/servarr/sonarr/series/${id}?deleteFiles=true`
