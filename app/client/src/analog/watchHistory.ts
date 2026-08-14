/**
 * Watch history — the client half, minus the DOM.
 *
 * Jellyfin keeps per-user progress (`UserData`) only for playback it was TOLD
 * about, and the web app told it nothing: Continue Watching, Next Up, the
 * "Resume 1h 30m" label this app already renders, and every progress bar were
 * fed entirely by whatever the desktop client happened to report. Watch on the
 * web and it left no trace at all.
 *
 * The rules here are deliberately the same ones `flutter_app/lib/state/
 * watch_history_provider.dart` follows, because both talk to one server and one
 * Jellyfin: the two clients disagreeing about when a title counts as watched
 * would be a bug with no owner.
 *
 * Kept free of React and of the DOM so it can be tested directly — see
 * `useWatchHistory.ts` for the part that holds a <video>.
 */

/** Jellyfin counts in 100-nanosecond ticks. */
export const TICKS_PER_SECOND = 10_000_000

/** How often a playing title reports its position. */
export const REPORT_INTERVAL_MS = 10_000

/**
 * How far before the stored mark playback resumes.
 *
 * Unused by the web player today — every web playback is a room, and a room's
 * position is the host's — but the constant lives with the rest of the rules so
 * the two clients cannot drift on what "resume" means.
 */
export const RESUME_REWIND_SECONDS = 5

/**
 * The most reports held for a browser that has been offline. Oldest first out:
 * a stale position from last week is worth less than one from an hour ago, and
 * an unbounded queue in localStorage is a slow leak.
 */
export const PENDING_LIMIT = 200

/** Where unsent reports wait between page loads. */
export const PENDING_KEY = 'playback.pendingReports'

export type PlaybackReportKind = 'started' | 'progress' | 'stopped'

export interface PlaybackReport {
  itemId: string
  positionTicks: number
  mediaSourceId?: string
  playSessionId?: string
  isPaused?: boolean
}

/** Seconds (what a media element deals in) → Jellyfin ticks. */
export function ticksOf(seconds: number): number {
  if (!Number.isFinite(seconds) || seconds <= 0) return 0
  return Math.round(seconds * TICKS_PER_SECOND)
}

/** Jellyfin ticks → seconds. */
export function secondsOf(ticks: number): number {
  if (!Number.isFinite(ticks) || ticks <= 0) return 0
  return ticks / TICKS_PER_SECOND
}

/**
 * Where playback should start given a stored mark: a few seconds early, and
 * never before the beginning.
 *
 * You stop watching a moment before you stop the film, so the mark sits just
 * past the last thing you took in and landing on it drops you mid-sentence.
 * Only the START moves — the stored mark is left alone, or a title would walk
 * backwards five seconds every time it was opened and closed.
 */
export function resumeStartSeconds(ticks: number): number {
  return Math.max(0, secondsOf(ticks) - RESUME_REWIND_SECONDS)
}

/** A fresh session id, tying one play's reports together for Jellyfin. */
export function newSessionId(): string {
  const bytes = new Uint8Array(16)
  globalThis.crypto.getRandomValues(bytes)
  return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('')
}

/**
 * Whether a progress tick is worth spending a request on.
 *
 * A paused/unpaused edge always is — that is the moment a viewer stops for the
 * night and the position they will come back to. Otherwise only a position that
 * has actually moved: a paused player ticking every ten seconds would report
 * the same number forever.
 */
export function shouldReportProgress(
  positionTicks: number,
  lastSentTicks: number | null,
  pausedChanged: boolean,
): boolean {
  if (pausedChanged) return true
  return positionTicks !== lastSentTicks
}

/**
 * Add [report] to the pending queue.
 *
 * One entry per title: a newer position supersedes an older one, and replaying
 * both would move the resume point BACKWARDS depending on which landed last.
 * Over the cap, the oldest go first.
 */
export function mergePending(
  queue: readonly PlaybackReport[],
  report: PlaybackReport,
): PlaybackReport[] {
  const next = queue.filter(r => r.itemId !== report.itemId)
  next.push(report)
  return next.length > PENDING_LIMIT ? next.slice(next.length - PENDING_LIMIT) : next
}

/** Parse a stored queue, discarding anything that is not a usable report. */
export function parsePending(raw: string | null): PlaybackReport[] {
  if (!raw) return []
  let value: unknown
  try {
    value = JSON.parse(raw)
  } catch {
    return []
  }
  if (!Array.isArray(value)) return []
  return value.filter(isReport)
}

function isReport(value: unknown): value is PlaybackReport {
  if (typeof value !== 'object' || value === null) return false
  const r = value as Record<string, unknown>
  return typeof r.itemId === 'string' && typeof r.positionTicks === 'number'
}
