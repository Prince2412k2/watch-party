/**
 * Deleting a title from the server: finding the record that actually holds the
 * files, and refusing to offer the action when there isn't one.
 *
 * A Jellyfin item and a Radarr/Sonarr record are two views of the same film,
 * joined only by the metadata provider id both carry — Tmdb for a movie, Tvdb
 * for a series. Jellyfin's own id means nothing to either *arr.
 *
 * The same join `flutter_app/lib/state/servarr_provider.dart` makes. Free of
 * React so it can be tested directly.
 */

export type ArrKind = 'movie' | 'series'

export interface ArrRecord {
  id: number
  title: string
}

/**
 * The `Tmdb`/`Tvdb` id off a Jellyfin item's `ProviderIds`, case-insensitively.
 *
 * The key's casing varies by metadata plugin — `Tmdb`, `TMDB` and `tmdb` have
 * all been seen — so matching it exactly is a join that works on one server and
 * silently fails on the next.
 */
export function providerIdOf(
  providerIds: unknown,
  kind: ArrKind,
): number | null {
  if (typeof providerIds !== 'object' || providerIds === null) return null
  const wanted = kind === 'movie' ? 'tmdb' : 'tvdb'
  for (const [key, value] of Object.entries(providerIds as Record<string, unknown>)) {
    if (key.toLowerCase() !== wanted) continue
    const parsed = Number.parseInt(String(value), 10)
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

/**
 * Which *arr record — if any — holds the files behind a library title.
 *
 * Null is the ordinary answer, not a failure: a title Jellyfin has but Radarr
 * or Sonarr never added (hand-copied, imported by something else, or the
 * service simply isn't configured) has no record to delete. The caller shows
 * nothing rather than a control that cannot work.
 */
export function matchArrRecord(
  rows: unknown,
  kind: ArrKind,
  providerId: number | null,
): ArrRecord | null {
  if (providerId === null || !Array.isArray(rows)) return null
  const idKey = kind === 'movie' ? 'tmdbId' : 'tvdbId'
  for (const row of rows) {
    if (typeof row !== 'object' || row === null) continue
    const record = row as Record<string, unknown>
    if (Number(record[idKey]) !== providerId) continue
    const id = Number(record.id)
    if (!Number.isInteger(id)) return null
    return { id, title: String(record.title ?? '') }
  }
  return null
}

/** The library listing to join against. */
export function arrLibraryPath(kind: ArrKind): string {
  return kind === 'movie' ? 'radarr/movies' : 'sonarr/series'
}

/** The record to delete, files and all. */
export function arrDeletePath(kind: ArrKind, id: number): string {
  return kind === 'movie' ? `radarr/movie/${id}` : `sonarr/series/${id}`
}

/**
 * What the confirmation says.
 *
 * Names the title and says plainly that this is everyone's copy — the same
 * wording the desktop client uses, because it is the same irreversible act.
 */
export function deleteConfirmation(kind: ArrKind, title: string): string {
  const what = kind === 'movie' ? 'movie' : 'show'
  return (
    `${title} and its files are deleted from the server, and the ${what} is ` +
    `excluded so nothing re-downloads it. This is everyone's copy, not just ` +
    `yours, and it can't be undone.`
  )
}
