// The release picker's arithmetic and lifecycle rules.
//
// The picker is the one part of Discover that mutates the catalog just by being
// opened: asking Radarr for live releases requires the movie to exist in Radarr,
// so opening the picker on a title that is not in the library ADDS it (monitored,
// no search) and closing it has to take that back. Every branch of that is a
// place a stale entry can be left behind, which is why the decisions live here
// rather than inside an effect.

import { isRecord, arrayOf } from '../../types/guards.ts'
import { fmtSize } from '../../lib/format.ts'
import { isAdded, type CatalogItem } from './catalog.ts'

// ── the wire ────────────────────────────────────────────────────────────────

export interface Release {
  guid: string
  title?: string
  indexer?: string
  size?: number
  age?: number
  ageHours?: number
  seeders?: number
  leechers?: number
  protocol?: string
  quality?: string
  indexerId?: number
  rejected?: boolean
  rejections?: string[]
  downloadAllowed?: boolean
}

export interface ReleaseData {
  movieId: number
  createdByPicker?: boolean
  cancellationToken?: string
  searchFailed?: boolean
  releases: Release[]
}

export const isRelease = (value: unknown): value is Release =>
  isRecord(value) && typeof value.guid === 'string'

export function parseReleaseData(value: unknown): ReleaseData {
  if (!isRecord(value) || typeof value.movieId !== 'number') return { movieId: 0, releases: [] }
  return {
    movieId: value.movieId,
    createdByPicker: typeof value.createdByPicker === 'boolean' ? value.createdByPicker : undefined,
    cancellationToken: typeof value.cancellationToken === 'string' ? value.cancellationToken : undefined,
    searchFailed: typeof value.searchFailed === 'boolean' ? value.searchFailed : undefined,
    releases: arrayOf(value.releases, isRelease),
  }
}

// ── cancel-with-backoff ─────────────────────────────────────────────────────

/**
 * Delays before each cancel attempt, in ms.
 *
 * The first attempt is immediate; the rest back off because the only failure
 * worth retrying is a 503 — Radarr busy finishing the very search this picker
 * started. Bounded rather than open-ended: five attempts spread over five and a
 * half seconds is long enough to outlast a search wrapping up, and short enough
 * that a genuinely dead instance does not leave a promise running for the rest
 * of the session.
 */
export const PICKER_CANCEL_DELAYS: readonly number[] = [0, 250, 750, 1500, 3000]

/**
 * Whether a cancel response settles the matter.
 *
 * ANY response other than 503 is terminal, including a 4xx: if the server says
 * the entry is gone, or was never ours to remove, retrying cannot improve on
 * that. Only "temporarily unavailable" earns another go.
 */
export const cancelSettled = (status: number): boolean => status !== 503

/**
 * Whether there is anything to cancel.
 *
 * A picker opened on a title already in the library did not create the entry and
 * must not remove it — the server issues a `cancellationToken` only for an entry
 * it created for this picker, so its absence IS the answer.
 */
export function shouldCancelPicker(life: {
  movieId: number | null
  cancellationToken: string | null
  settled: boolean
  cancelling: boolean
}): boolean {
  if (life.settled || life.cancelling) return false
  return life.cancellationToken != null && life.movieId != null
}

// ── opening the picker ──────────────────────────────────────────────────────

export type ReleasesRequest =
  /** A retry, or a second open: reuse the entry we already have. */
  | { kind: 'existing'; body: { movieId: number; operationId: string } }
  /** The title is already in the library — its own id, and nothing to clean up. */
  | { kind: 'library'; body: { movieId: number; operationId: string } }
  /** Not in the library: the server adds it monitored+no-search, then searches. */
  | { kind: 'add'; body: Record<string, unknown> }

/**
 * The body for `POST /api/servarr/radarr/releases`, and which of the three cases
 * it is.
 *
 * The distinction matters after the response, not before it: only the `add` case
 * can produce an entry this picker is responsible for removing, and a retry must
 * reuse the id it already has or it would add the title a second time and lose
 * the `createdByPicker` flag that authorises the cleanup.
 */
export function releasesRequest(input: {
  item: CatalogItem
  operationId: string
  existingMovieId: number | null
  options: { qualityProfileId: number; rootFolderPath: string } | null
}): ReleasesRequest | null {
  const { item, operationId, existingMovieId, options } = input
  if (existingMovieId != null) {
    return { kind: 'existing', body: { movieId: existingMovieId, operationId } }
  }
  if (isAdded(item) && item.id != null) {
    return { kind: 'library', body: { movieId: item.id, operationId } }
  }
  if (!options) return null
  return {
    kind: 'add',
    body: {
      movie: item,
      qualityProfileId: options.qualityProfileId,
      rootFolderPath: options.rootFolderPath,
      operationId,
    },
  }
}

/**
 * The cancellation token to keep after a response.
 *
 * A retry runs against the entry the FIRST request created, so the token that
 * authorises removing it is the original one — the retry's response carries none,
 * and overwriting with it would strand the entry.
 */
export function retainedToken(
  kind: ReleasesRequest['kind'],
  previous: string | null,
  fromResponse: string | null | undefined,
): string | null {
  if (kind === 'existing') return previous
  if (kind === 'library') return null
  return fromResponse ?? null
}

// ── one row ─────────────────────────────────────────────────────────────────

export type SeedTone = 'none' | 'some' | 'unknown'

export interface ReleaseRow {
  guid: string
  title: string
  quality: string | null
  seeds: number | null
  seedLabel: string
  /** 'none' at zero seeders — a release nobody is sharing will never finish. */
  seedTone: SeedTone
  peerLabel: string
  sizeLabel: string
  indexer: string | null
  rejected: boolean
  /** Why the auto-picker skipped it. Null unless rejected. */
  reason: string | null
  /** Every rejection, for the row's title attribute. */
  reasons: string[]
  grabbable: boolean
}

/**
 * One source row.
 *
 * Seeders lead because they are the only field that predicts whether the
 * download will finish; a zero-seed release is worse than a smaller or older
 * one and the tone says so without relying on the number being read.
 */
export function releaseRow(release: Release): ReleaseRow {
  const seeds = typeof release.seeders === 'number' ? release.seeders : null
  const rejected = Boolean(release.rejected)
  const reasons = release.rejections ?? []
  return {
    guid: release.guid,
    title: release.title || release.guid,
    quality: release.quality || null,
    seeds,
    seedLabel: `${seeds == null ? '—' : seeds} seed${seeds === 1 ? '' : 's'}`,
    seedTone: seeds == null ? 'unknown' : seeds > 0 ? 'some' : 'none',
    peerLabel: `${typeof release.leechers === 'number' ? release.leechers : '—'} peers`,
    sizeLabel: fmtSize(release.size),
    indexer: release.indexer || null,
    rejected,
    reason: rejected ? (reasons[0] || 'Skipped by the quality profile') : null,
    reasons,
    grabbable: !rejected,
  }
}

/** How the picker's own heading counts what it found. */
export const releaseCountLabel = (count: number): string =>
  `${count} source${count === 1 ? '' : 's'}`
