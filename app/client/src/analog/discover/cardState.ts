// What a Discover title is currently doing.
//
// The surface this replaces derived this twice — once for the poster card and
// once for the detail page — from the same five booleans, and the two copies had
// already drifted (the card treated `added` as terminal, the detail page did
// not). One derivation, one set of names, tested.
//
// Pure: the caller owns the request map and the live torrent list, this owns the
// answer.

import { isPausedState } from '../../lib/format.ts'
import { isAdded, type CatalogItem, type TorrentLike } from './catalog.ts'

/**
 * What the server said happened, mapped to a state the surface can render.
 *
 * The movie request flow is server-authoritative (add + live interactive search
 * + grab-or-remove in one call), so the client never has to guess:
 *   grabbed       → downloading; the live torrent match takes over the progress
 *   no_release    → the search ran and found nothing usable; the entry was
 *                   removed again, so the title is requestable
 *   search_failed → could not check right now — transient, offer a retry
 *   monitoring    → series only: added, and Sonarr is watching for episodes
 *   exists        → already in the library
 * Anything else is an error, including an outcome this client does not know:
 * silently treating an unrecognised outcome as success is how a failed request
 * ends up looking like a download that never starts.
 */
export type RequestState =
  | 'searching'
  | 'grabbed'
  | 'monitoring'
  | 'no_release'
  | 'search_failed'
  | 'added'
  | 'error'

export function outcomeToState(outcome?: string): RequestState {
  switch (outcome) {
    case 'grabbed':
      return 'grabbed'
    case 'no_release':
      return 'no_release'
    case 'search_failed':
      return 'search_failed'
    case 'monitoring':
      return 'monitoring'
    case 'exists':
      return 'added'
    default:
      return 'error'
  }
}

export type TitlePhase =
  | 'idle'
  | 'searching'
  | 'downloading'
  | 'monitoring'
  | 'no_release'
  | 'search_failed'
  | 'added'
  | 'error'

export interface TitleState {
  /** Which action panel the stage renders. */
  phase: TitlePhase
  /** The catalog already tracks this title. Drives the badge and Remove. */
  inLibrary: boolean
  /** Live download progress 0–100, or null when nothing is running for it. */
  pct: number | null
  /** A matched torrent that is not paused — "Downloading 42%" vs "Starting…". */
  live: boolean
  /** Whether the panel offers another go at the one-tap request. */
  retryable: boolean
  /** Short status the rail poster carries, so state is never hover-only. */
  badge: string | null
  /** Progress the rail poster's hairline shows. Null unless downloading. */
  progressPct: number | null
}

export interface TitleStateInput {
  item: CatalogItem
  /** The state this session's own request left behind, if the user made one. */
  requested?: RequestState | null
  /** The live download matched to this title, from the shared hub. */
  torrent?: TorrentLike | null
}

/**
 * The rail poster's badge.
 *
 * Deliberately terse: a rail poster is 68px wide on a phone, and a badge that
 * needs two lines to say "Monitoring for releases" stops being readable at a
 * glance — which is the only thing a badge is for. The stage says the same
 * thing in full for whichever title is focused.
 */
const PHASE_BADGES: Partial<Record<TitlePhase, string>> = {
  searching: 'Finding',
  monitoring: 'Monitored',
  no_release: 'No source',
  search_failed: 'Retry',
  added: 'Library',
  error: 'Retry',
}

/**
 * A live download outranks everything.
 *
 * A title can be in the library AND downloading (an upgrade, a re-grab, a season
 * arriving), and it can be marked `no_release` by a request that has since been
 * superseded by a manually added source. The torrent is the only one of these
 * signals that is measured rather than remembered, so it wins.
 *
 * `inLibrary` stays separate from `phase` rather than collapsing into it,
 * because they answer different questions — "what is happening" and "do I
 * already have it" — and the old surface's single value could only carry one,
 * which is why grabbing a release for a title already in the library showed
 * "In library" while it downloaded.
 */
export function titleState({ item, requested = null, torrent = null }: TitleStateInput): TitleState {
  const inLibrary = isAdded(item)
  const pct = torrent ? Math.max(0, Math.min(100, Math.round((torrent.progress || 0) * 100))) : null
  const live = torrent != null && !isPausedState(torrent.state)
  const downloading = live && pct != null && pct < 100

  // `grabbed` means the server handed a release to the download client moments
  // ago; the torrent list polls every couple of seconds, so there is a window
  // where nothing matches yet and the only honest label is "Starting".
  if (downloading || requested === 'grabbed') {
    return {
      phase: 'downloading',
      inLibrary,
      pct: downloading ? pct : null,
      live: downloading,
      retryable: false,
      badge: downloading ? `${pct}%` : 'Starting',
      progressPct: downloading ? pct : null,
    }
  }

  const phase: TitlePhase = requested ?? (inLibrary ? 'added' : 'idle')
  return {
    phase,
    inLibrary,
    pct: null,
    live: false,
    retryable: phase === 'no_release' || phase === 'search_failed' || phase === 'error',
    badge: PHASE_BADGES[phase] ?? null,
    progressPct: null,
  }
}

/**
 * The label the primary action carries.
 *
 * Named rather than inlined so the rail's accessible name, the stage's button
 * and the season chooser cannot describe the same state three different ways.
 */
export function primaryActionLabel(state: TitleState): string {
  switch (state.phase) {
    case 'downloading':
      return state.live ? `Downloading · ${state.pct}%` : 'Starting download…'
    case 'searching':
      return 'Finding a release…'
    case 'monitoring':
      return 'Added — monitoring'
    case 'no_release':
      return 'Try again'
    case 'search_failed':
      return 'Retry'
    case 'added':
      return 'In library'
    case 'error':
      return 'Retry download'
    default:
      return 'Download'
  }
}

/** The sentence under the primary action. Null when the label says it all. */
export function stateDetail(state: TitleState, kind: 'movie' | 'series'): string | null {
  switch (state.phase) {
    case 'searching':
      return 'It’s in your library. We’re looking for a release to download right now.'
    case 'monitoring':
      return 'It’s in your library and being monitored — episodes download on their own as they become available.'
    case 'no_release':
      return 'No release available right now — try again later, or add a source yourself.'
    case 'search_failed':
      return 'Couldn’t check for a release right now. Please try again.'
    case 'error':
      return `Couldn’t request this ${kind === 'movie' ? 'movie' : 'series'}. Please try again.`
    default:
      return null
  }
}

/**
 * Whether the release picker and the manual-source button are worth offering.
 *
 * Both are ways to choose a source, so neither has anything to do while a grab
 * is already in flight — the old surface hid them behind the same condition and
 * this keeps the two in one place.
 */
export const canChooseSource = (state: TitleState): boolean =>
  state.phase !== 'downloading' && state.phase !== 'searching'
