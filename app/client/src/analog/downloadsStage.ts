// Downloads on the analog stage — the half that is not React.
//
// The surface this replaces was a poster grid plus a separate full-screen detail
// overlay, and each of them carried its own answer to the same three questions:
// what does this download-client state mean, what do these bytes read as, and
// what does "Remove" actually delete. Three questions worth pinning, so they
// live here rather than inside a component — the repo has no DOM tests at all
// and every suite runs on extracted logic.
//
// Nothing here polls or fetches. The live data arrives from
// context/DownloadsContext, which is the one owner of both pollers
// (hooks/downloadsCore.test.ts asserts that by source text).

import { fmtEta, fmtRuntimeFromMinutes, fmtSize, fmtSpeed } from '../lib/format.ts'
import { arrayOf, isRecord } from '../types/guards.ts'
import { serviceReady, type Health, type ServiceName } from '../hooks/downloadsCore.ts'
import { failureReasons, queueTitle, type FailingQueueItem } from '../hooks/useFailingDownloads.ts'
import type { StageSize } from './stageLayout.ts'

// ── the two modes ───────────────────────────────────────────────────────────
//
// A download that died before it ever became a torrent never reaches the
// download client, so it cannot be a row in the same list — it is a Radarr or
// Sonarr queue record with a failure reason and no progress. The old screen
// stacked that as a second section above the grid; on a stage with ONE rail it
// becomes the second position on the mode slider instead.

export type DownloadsMode = 'active' | 'attention'

/** Slider order, top to bottom. Up moves towards the first, Down the last. */
export const DOWNLOADS_MODES: readonly DownloadsMode[] = ['active', 'attention']

export const DOWNLOADS_MODE_LABELS: Record<DownloadsMode, string> = {
  active: 'Active',
  attention: 'Needs attention',
}

export const isDownloadsMode = (value: unknown): value is DownloadsMode =>
  value === 'active' || value === 'attention'

/**
 * One step of the mode slider. Clamped rather than wrapping, for the same
 * reason the Movies slider is: holding Down must settle on the last position
 * instead of flickering between two.
 */
export function stepDownloadsMode(mode: DownloadsMode, direction: number): DownloadsMode {
  const index = DOWNLOADS_MODES.indexOf(mode)
  const next = index + Math.sign(direction)
  return DOWNLOADS_MODES[Math.max(0, Math.min(next, DOWNLOADS_MODES.length - 1))]
}

// ── the record this surface reads ───────────────────────────────────────────

/**
 * What /api/servarr/downloads/enriched guarantees is the hash; everything else
 * is best-effort, which is why every accessor below narrows rather than asserts.
 */
export interface TorrentLike {
  hash: string
  name?: string
  state?: string
  progress?: number
  dlspeed?: number
  upspeed?: number
  displayTitle?: string
  subtitle?: string
  posterUrl?: string
  kind?: string
  [key: string]: unknown
}

/** A finite number off a loosely-typed record, or null. */
function numberAt(record: TorrentLike, key: string): number | null {
  const value = record[key]
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

/** What to call a download. A nameless one is still something you have to act on. */
export function torrentTitle(torrent: TorrentLike): string {
  return torrent.displayTitle?.trim() || torrent.name?.trim() || 'Untitled download'
}

/**
 * The second line: the release the title came from, when it says something the
 * title does not. A torrent whose only name IS the title adds nothing by
 * repeating it.
 */
export function torrentSubtitle(torrent: TorrentLike): string | null {
  const subtitle = torrent.subtitle?.trim()
  if (subtitle) return subtitle
  const name = torrent.name?.trim()
  return name && name !== torrentTitle(torrent) ? name : null
}

// ── state ───────────────────────────────────────────────────────────────────

/**
 * Semantic only. `danger` and `success` are the two states that mean something
 * about the download itself; everything else is plain ink, because status colour
 * is not available for emphasis or decoration.
 */
export type DownloadTone = 'neutral' | 'danger' | 'success'

export interface DownloadState {
  /**
   * The word. The ring and the percentage are a second reading of progress, not
   * a replacement for this one — state must never be carried by a shape and a
   * colour alone.
   */
  label: string
  paused: boolean
  /** Nothing left to fetch: seeding, or finished and stopped. */
  complete: boolean
  failed: boolean
  tone: DownloadTone
}

const state = (
  label: string,
  paused: boolean,
  extra: Partial<DownloadState> = {},
): DownloadState => ({ label, paused, complete: false, failed: false, tone: 'neutral', ...extra })

/**
 * Download-client state string → what the stage says about it.
 *
 * qBittorrent 5.x renamed `paused*` to `stopped*`; both spellings are kept so a
 * version bump cannot silently relabel a whole queue. An unrecognised state is
 * shown verbatim rather than swallowed — "Unknown" for a state the client really
 * did send would hide a working download behind a shrug.
 */
export function downloadState(raw: string | null | undefined): DownloadState {
  switch (raw) {
    case 'downloading':
    case 'forcedDL':
    case 'metaDL':
    case 'forcedMetaDL':
    case 'checkingDL':
    case 'allocating':
      return state('Downloading', false)
    case 'stalledDL':
      return state('Waiting', false)
    case 'queuedDL':
    case 'queuedUP':
    case 'checkingResumeData':
      return state('Queued', false)
    case 'uploading':
    case 'forcedUP':
    case 'checkingUP':
    case 'stalledUP':
      return state('Finishing up', false)
    case 'pausedDL':
    case 'stoppedDL':
      return state('Paused', true)
    case 'pausedUP':
    case 'stoppedUP':
      return state('Completed', true, { complete: true, tone: 'success' })
    case 'error':
    case 'missingFiles':
      return state('Failed', true, { failed: true, tone: 'danger' })
    default:
      return state(raw || 'Unknown', false)
  }
}

/** Every state string the two clients name, so the mapping can be swept in a test. */
export const KNOWN_STATES: readonly string[] = [
  'downloading', 'forcedDL', 'metaDL', 'forcedMetaDL', 'stalledDL', 'queuedDL',
  'checkingDL', 'allocating', 'checkingResumeData', 'uploading', 'forcedUP',
  'checkingUP', 'stalledUP', 'queuedUP', 'pausedDL', 'stoppedDL', 'pausedUP',
  'stoppedUP', 'error', 'missingFiles',
]

export type PrimaryKind = 'pause' | 'resume' | 'retry' | 'none'

export interface PrimaryAction {
  kind: PrimaryKind
  label: string
  disabled: boolean
}

/**
 * The one button that is not destructive.
 *
 * A failed download is resumable — that IS the retry, and calling it "Resume"
 * is why the old grid looked like it had no answer to a failure. A finished one
 * has nothing to pause, so the control stays but says so instead of vanishing
 * and reflowing the action row.
 */
export function primaryAction(current: DownloadState, busy = false): PrimaryAction {
  if (current.failed) return { kind: 'retry', label: 'Retry', disabled: busy }
  if (current.complete) return { kind: 'none', label: 'Completed', disabled: true }
  if (current.paused) return { kind: 'resume', label: 'Resume', disabled: busy }
  return { kind: 'pause', label: 'Pause', disabled: busy }
}

// ── progress + numbers ──────────────────────────────────────────────────────

/** qBittorrent reports 0..1; the stage shows 0..100 and never a fraction of one. */
export function progressPct(progress: number | null | undefined): number {
  if (progress == null || !Number.isFinite(progress)) return 0
  return Math.max(0, Math.min(100, Math.round(progress * 100)))
}

/**
 * The stats block, already formatted, in reading order.
 *
 * An array of finished strings rather than a record of numbers: this is the one
 * place the unit rules live, and a component that received raw bytes would be a
 * second place for them to be got wrong.
 */
export function downloadStats(torrent: TorrentLike, current: DownloadState): string[] {
  const eta = numberAt(torrent, 'eta')
  return [
    `↓ ${fmtSpeed(numberAt(torrent, 'dlspeed'))}`,
    `↑ ${fmtSpeed(numberAt(torrent, 'upspeed'))}`,
    // A finished transfer has no arrival time; the sentinel would read "∞".
    `ETA ${current.complete ? '—' : fmtEta(eta)}`,
    `Seeds ${numberAt(torrent, 'numSeeds') ?? 0}`,
    `Peers ${numberAt(torrent, 'numLeechs') ?? 0}`,
    fmtSize(numberAt(torrent, 'size')),
  ]
}

export interface AggregateRates {
  downBps: number
  upBps: number
  total: number
}

export function aggregateRates(list: readonly TorrentLike[]): AggregateRates {
  let downBps = 0
  let upBps = 0
  for (const torrent of list) {
    downBps += numberAt(torrent, 'dlspeed') ?? 0
    upBps += numberAt(torrent, 'upspeed') ?? 0
  }
  return { downBps, upBps, total: list.length }
}

/**
 * The header line, as parts.
 *
 * `activeCount` comes from the shared hub rather than being recounted here: it
 * is what the nav badge shows, and two counts of "how many are downloading" that
 * are derived separately are two counts that will eventually disagree.
 */
export function aggregateParts(rates: AggregateRates, activeCount: number): string[] {
  if (rates.total === 0) return []
  return [
    `${activeCount} downloading`,
    `↓ ${fmtSpeed(rates.downBps)}`,
    `↑ ${fmtSpeed(rates.upBps)}`,
  ]
}

// ── availability ────────────────────────────────────────────────────────────

export type Availability = 'loading' | 'ready' | 'unreachable' | 'unconfigured'

/**
 * Three different nothings, which the old screen showed as two.
 *
 * "Configured but unreachable" is a transient the user should wait out; "never
 * configured" is an admin task that will never resolve on its own. Telling them
 * apart is the difference between waiting and going to look for a settings page.
 */
export function availability(
  health: Health | null,
  loading: boolean,
  services: readonly ServiceName[],
): Availability {
  if (loading) return 'loading'
  if (services.some((name) => serviceReady(health, name))) return 'ready'
  if (services.some((name) => health?.services?.[name]?.configured === true)) return 'unreachable'
  return 'unconfigured'
}

/** The download client backs the Active rail; either *arr backs the other one. */
export const MODE_SERVICES: Record<DownloadsMode, readonly ServiceName[]> = {
  active: ['qbittorrent'],
  attention: ['radarr', 'sonarr'],
}

export const modeAvailability = (
  mode: DownloadsMode,
  health: Health | null,
  loading: boolean,
): Availability => availability(health, loading, MODE_SERVICES[mode])

export interface StageMessage {
  title: string
  hint: string
}

const UNAVAILABLE: Record<DownloadsMode, Record<'unreachable' | 'unconfigured', StageMessage>> = {
  active: {
    unreachable: {
      title: 'Download client unreachable',
      hint: 'It is set up but not answering right now. Progress and controls come back on their own.',
    },
    unconfigured: {
      title: 'No download client connected',
      hint: 'Connect one and anything you grab lands here with live progress and controls.',
    },
  },
  attention: {
    unreachable: {
      title: 'Library manager unreachable',
      hint: 'Radarr and Sonarr are set up but not answering, so stuck grabs cannot be listed.',
    },
    unconfigured: {
      title: 'No library manager connected',
      hint: 'Connect Radarr or Sonarr and grabs that die before they become a download show up here.',
    },
  },
}

const EMPTY: Record<DownloadsMode, StageMessage> = {
  active: {
    title: 'Nothing downloading',
    hint: 'Find something in Discover and it arrives here with live progress, speed and controls.',
  },
  attention: {
    title: 'Nothing stuck',
    hint: 'A grab that fails before it becomes a download would be waiting here.',
  },
}

/** What the stage says instead of a focused item, or null when it has one. */
export function stageMessage(
  mode: DownloadsMode,
  kind: Availability,
  count: number,
): StageMessage | null {
  if (kind === 'loading') return null
  if (kind === 'unreachable' || kind === 'unconfigured') return UNAVAILABLE[mode][kind]
  return count === 0 ? EMPTY[mode] : null
}

// ── rail entries ────────────────────────────────────────────────────────────

export interface RailEntry {
  /** Stable across polls: a torrent's hash, a queue record's service + id. */
  key: string
  title: string
  /** Art from Radarr/Sonarr — a public poster URL, not a Jellyfin item. */
  posterUrl: string | null
  kind: string | null
  /** null when there is no progress to draw: a stuck grab never started one. */
  progressPct: number | null
  /**
   * Marks the states that are not "quietly getting on with it". Normal progress
   * is carried by the bar, so the badge stays empty rather than repeating a
   * percentage that is already drawn two pixels below it.
   */
  badge: string | null
}

export const queueKey = (item: FailingQueueItem): string => `${item.service}:${item.id}`

export function torrentEntry(torrent: TorrentLike): RailEntry {
  const current = downloadState(torrent.state)
  return {
    key: torrent.hash,
    title: torrentTitle(torrent),
    posterUrl: torrent.posterUrl?.trim() || null,
    kind: torrent.kind ?? null,
    progressPct: progressPct(torrent.progress),
    badge: current.paused || current.failed ? current.label : null,
  }
}

export function queueEntry(item: FailingQueueItem): RailEntry {
  return {
    key: queueKey(item),
    title: queueTitle(item),
    posterUrl: null,
    kind: null,
    progressPct: null,
    badge: 'Stuck',
  }
}

/** Up to two initials, for the placeholder a download with no artwork falls to. */
export function entryInitials(title: string): string {
  const parts = title.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return '—'
  return parts.slice(0, 2).map((part) => part[0]!.toUpperCase()).join('')
}

/** The stuck item's reasons and where it came from, for the stage. */
export function queueDetail(item: FailingQueueItem): { reasons: string[]; meta: string[] } {
  return {
    reasons: failureReasons(item),
    meta: [item.indexer, fmtSize(item.size)].filter((part): part is string => Boolean(part)),
  }
}

// ── catalog enrichment ──────────────────────────────────────────────────────
//
// /api/servarr/downloads/:hash/detail resolves a download back to the Radarr or
// Sonarr record it came from: the synopsis, the genres, the rating, the runtime.
// A title that is still downloading is not in Jellyfin yet, so this is the only
// place that copy exists — and it is precisely what the full-screen overlay this
// stage replaces was worth opening for. Losing it would make the stage a smaller
// view than the thing it removed.
//
// Fetched once per hash and cached, after a short delay, so a fast scroll along
// the rail costs one request rather than one per download it passed.

export interface DownloadCatalog {
  title: string | null
  subtitle: string | null
  posterUrl: string | null
  overview: string | null
  genres: string[]
  rating: number | null
  /** Minutes, as the *arr metadata reports it — not Jellyfin's 100ns ticks. */
  runtime: number | null
  year: string | null
  certification: string | null
  network: string | null
  status: string | null
}

const text = (value: unknown): string | null =>
  typeof value === 'string' && value.trim() ? value.trim() : null

const finite = (value: unknown): number | null =>
  typeof value === 'number' && Number.isFinite(value) ? value : null

const isString = (value: unknown): value is string => typeof value === 'string'

/** Every field is optional: the lookup answers from whichever *arr knows it. */
export function parseCatalog(value: unknown): DownloadCatalog | null {
  if (!isRecord(value)) return null
  return {
    title: text(value.title),
    subtitle: text(value.subtitle),
    posterUrl: text(value.posterUrl),
    overview: text(value.overview),
    genres: arrayOf(value.genres, isString).filter((genre) => genre.trim().length > 0),
    rating: finite(value.rating),
    runtime: finite(value.runtime),
    // *arr sends a number for a film and a string for an air range.
    year: typeof value.year === 'number' ? String(value.year) : text(value.year),
    certification: text(value.certification),
    network: text(value.network),
    status: text(value.status),
  }
}

/** Rating, runtime, year, certificate, network, status, then genres. */
export function catalogParts(catalog: DownloadCatalog | null): string[] {
  if (!catalog) return []
  return [
    catalog.rating == null ? null : `★ ${catalog.rating.toFixed(1)}`,
    fmtRuntimeFromMinutes(catalog.runtime),
    catalog.year,
    catalog.certification,
    catalog.network,
    catalog.status,
    ...catalog.genres.slice(0, 3),
  ].filter((value): value is string => Boolean(value))
}

export interface FocusedDownload {
  title: string
  /** The release or episode line: what the torrent is, rather than what it is of. */
  subtitle: string | null
  posterUrl: string | null
  overview: string | null
}

/**
 * The catalog over the torrent, never the other way round: the lookup is the
 * same download with strictly better copy. Merging rather than replacing is what
 * keeps the stage from blanking between the poll and the lookup.
 */
export function focusedDownload(
  torrent: TorrentLike,
  catalog: DownloadCatalog | null,
): FocusedDownload {
  return {
    title: catalog?.title ?? torrentTitle(torrent),
    subtitle: catalog?.subtitle ?? torrentSubtitle(torrent),
    posterUrl: catalog?.posterUrl ?? torrent.posterUrl?.trim() ?? null,
    overview: catalog?.overview ?? null,
  }
}

/**
 * The dimmer line above the live numbers.
 *
 * The release line only appears here when a synopsis has taken the paragraph it
 * would otherwise have had; when there is no synopsis it IS the paragraph, and
 * printing it twice is noise.
 */
export function contextParts(focused: FocusedDownload, catalog: DownloadCatalog | null): string[] {
  return [focused.overview ? focused.subtitle : null, ...catalogParts(catalog)].filter(
    (value): value is string => Boolean(value),
  )
}

// ── removal ─────────────────────────────────────────────────────────────────

export interface RemovalIntent {
  hash: string
  title: string
  /**
   * Opt-in, and it starts OFF every single time the confirmation opens.
   *
   * "Remove" means "stop fetching this"; erasing what is already on disk is a
   * different and unrecoverable decision. A toggle that remembered the last
   * answer would quietly delete the next thing the user removed, so the state is
   * created per-open rather than held beside the list.
   */
  deleteFiles: boolean
}

export const openRemoval = (torrent: TorrentLike): RemovalIntent => ({
  hash: torrent.hash,
  title: torrentTitle(torrent),
  deleteFiles: false,
})

export const withDeleteFiles = (intent: RemovalIntent, deleteFiles: boolean): RemovalIntent => ({
  ...intent,
  deleteFiles,
})

export const toggleDeleteFiles = (intent: RemovalIntent): RemovalIntent =>
  withDeleteFiles(intent, !intent.deleteFiles)

/**
 * The two ways out of a stuck grab, in this order and neither pre-selected.
 *
 * Blocking a release tells the library manager never to take that file again,
 * which is right when it is broken and wrong when the failure was local — so it
 * is a second button rather than a default the reversible one inherits.
 */
export const QUEUE_REMOVALS: readonly { blocklist: boolean; label: string; hint: string }[] = [
  { blocklist: false, label: 'Remove', hint: 'Drop it from the queue and let it be grabbed again.' },
  {
    blocklist: true,
    label: 'Remove & block',
    hint: 'Drop it and stop this exact release being grabbed again.',
  },
]

// ── stage sizing ────────────────────────────────────────────────────────────
//
// The focused download's poster is on the stage rather than in the rail, so it
// is sized against the detail block beside it rather than against the row.

export const STAGE_POSTER_PX: Record<StageSize, number> = { phone: 92, tablet: 128, desktop: 156 }
export const GAUGE_RING_PX: Record<StageSize, number> = { phone: 68, tablet: 84, desktop: 96 }
