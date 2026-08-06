// Poster artwork resolution for the analog stage.
//
// The season chain (season Primary -> series Primary -> fixed placeholder) is
// `resolveSeasonArtwork` in browseCore.ts, driven by the shared interaction
// fixture and mirrored in Dart. This file wires that core to the Jellyfin item
// shape the client actually receives, gives non-season items the same three-step
// chain, and owns the one registry of images already known to 404.
//
// Before this there were TWO failure registries — pages/Library.tsx:113 and
// mobile/ui/Poster.tsx:13 — that never shared state, so a 404 learned on the
// desktop tree was requested all over again on the phone tree.

import { resolveSeasonArtwork, type SeasonArtwork } from './browseCore.ts'

export interface ArtworkItem {
  Id: string
  Name?: string
  Type?: string
  /** Season/episode number. Season cards label their placeholder with it. */
  IndexNumber?: number | null
  SeriesId?: string | null
  ImageTags?: { Primary?: string | null } | null
  SeriesPrimaryImageTag?: string | null
}

/**
 * Stands in for a real `ImageTags.Primary` when the payload carries no
 * `ImageTags` map at all.
 *
 * Jellyfin sends the map by default, but the library proxy only *guarantees*
 * the fields it asks for (`Fields=MediaSources`), and "absent" would otherwise
 * be indistinguishable from "no artwork" — every poster would drop straight to
 * a placeholder. Assuming art exists and letting the 404 fall through is the
 * chain the reference already describes: "if season artwork is absent OR fails
 * to load, use the series Primary poster".
 */
export const UNVERIFIED_TAG = 'unverified'

const tagOf = (value: string | null | undefined): string | null => (value ? value : null)

export function primaryImageTag(item: ArtworkItem): string | null {
  if (item.ImageTags === undefined) return UNVERIFIED_TAG
  return tagOf(item.ImageTags?.Primary)
}

export function seriesImageTag(item: ArtworkItem): string | null {
  if (!item.SeriesId) return null
  if (item.SeriesPrimaryImageTag !== undefined) return tagOf(item.SeriesPrimaryImageTag)
  // Same reasoning as primaryImageTag: unknown, so try it.
  return UNVERIFIED_TAG
}

/** Up to two initials, for the placeholder a non-season item falls back to. */
export function initialsFor(name: string | undefined): string {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '—'
  return parts.slice(0, 2).map((part) => part[0]!.toUpperCase()).join('')
}

/**
 * Artwork for any library item.
 *
 * Seasons go through the shared core verbatim so React and Flutter cannot drift.
 * Everything else follows the identical three steps — own Primary, series
 * Primary, fixed-size placeholder — because the reason the placeholder is fixed
 * size (layout and focus must not move when artwork is missing) is not specific
 * to seasons.
 */
export function resolveArtwork(item: ArtworkItem, failedIds: readonly string[] = []): SeasonArtwork {
  if (item.Type === 'Season') {
    return resolveSeasonArtwork({
      seasonId: item.Id,
      seasonNumber: item.IndexNumber ?? null,
      seasonImageTag: primaryImageTag(item),
      seriesId: item.SeriesId ?? item.Id,
      seriesImageTag: seriesImageTag(item),
      failedIds,
    })
  }

  const failed = new Set(failedIds)
  const own = primaryImageTag(item)
  if (own && !failed.has(item.Id)) {
    return { kind: 'season', itemId: item.Id, imageTag: own, label: null }
  }
  const series = seriesImageTag(item)
  if (item.SeriesId && series && !failed.has(item.SeriesId)) {
    return { kind: 'series', itemId: item.SeriesId, imageTag: series, label: null }
  }
  return { kind: 'placeholder', itemId: null, imageTag: null, label: initialsFor(item.Name) }
}

/** Same-origin proxy route; already whitelisted server-side (library.js). */
export function artworkSrc(artwork: SeasonArtwork, type = 'Primary'): string | null {
  return artwork.itemId ? `/api/library/image/${artwork.itemId}?type=${type}` : null
}

export function backdropSrc(itemId: string | null | undefined): string | null {
  return itemId ? `/api/library/image/${itemId}?type=Backdrop` : null
}

// ── the one failed-image registry ───────────────────────────────────────────

const failedIds = new Set<string>()
const listeners = new Set<() => void>()
let version = 0

export function noteArtworkFailure(itemId: string): void {
  if (failedIds.has(itemId)) return
  failedIds.add(itemId)
  version += 1
  for (const listener of listeners) listener()
}

export function failedArtworkIds(): string[] {
  return [...failedIds]
}

export function artworkFailureVersion(): number {
  return version
}

export function subscribeArtworkFailures(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** Tests only — the registry is deliberately process-wide at runtime. */
export function resetArtworkFailures(): void {
  failedIds.clear()
  version += 1
}
