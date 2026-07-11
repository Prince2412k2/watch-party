// Shared display formatters + download-state mapping. Previously reimplemented
// (with subtle drift) across Library.jsx / Downloads.jsx / FindDownload.jsx /
// DownloadDetail.jsx — consolidated here so every surface reads identically.
import { C } from './ui'

// Raw bytes → "12.4 MB". Returns "—" for missing/zero.
export function fmtSize(bytes: number | null | undefined) {
  if (bytes == null || !Number.isFinite(bytes) || bytes <= 0) return '—'
  const u = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0, n = bytes
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
  return `${n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)} ${u[i]}`
}

// Bytes-per-second → "12.4 MB/s". Floors to "0 B/s" for missing/zero.
export function fmtSpeed(bps: number | null | undefined) {
  if (bps == null || !Number.isFinite(bps) || bps <= 0) return '0 B/s'
  return `${fmtSize(bps)}/s`
}

// The download client uses 8640000 (100 days) as its "unknown/∞" ETA sentinel.
export function fmtEta(secs: number | null | undefined) {
  if (secs == null || !Number.isFinite(secs) || secs < 0 || secs >= 8640000) return '∞'
  if (secs === 0) return '—'
  const d = Math.floor(secs / 86400)
  const h = Math.floor((secs % 86400) / 3600)
  const m = Math.floor((secs % 3600) / 60)
  const s = Math.floor(secs % 60)
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m`
  return `${s}s`
}

// Runtime from Jellyfin RunTimeTicks (100ns units) → "1h 42m".
export function fmtRuntimeFromTicks(ticks: number | null | undefined) {
  if (!ticks) return null
  const m = Math.round(ticks / 600_000_000)
  const h = Math.floor(m / 60)
  return h > 0 ? `${h}h ${m % 60}m` : `${m}m`
}

// Runtime from a plain minutes count (Radarr/Sonarr metadata) → "1h 42m".
export function fmtRuntimeFromMinutes(mins: number | null | undefined) {
  if (!mins || !Number.isFinite(mins) || mins <= 0) return null
  const h = Math.floor(mins / 60)
  return h > 0 ? `${h}h ${mins % 60}m` : `${mins}m`
}

/* Map the download client's raw state strings → friendly label, dot color, and
 * whether the item is paused (drives the pause/resume toggle). (qBittorrent 5.x
 * renamed paused* → stopped*; both are kept so a version bump can't mislabel.) */
export function stateInfo(state: string | null | undefined) {
  switch (state) {
    case 'downloading': case 'forcedDL': case 'metaDL': case 'checkingDL': case 'allocating':
      return { label: 'Downloading', color: C.live, paused: false }
    case 'uploading': case 'forcedUP': case 'checkingUP':
      return { label: 'Finishing up', color: C.dim, paused: false }
    case 'stalledDL':
      return { label: 'Waiting', color: C.dim, paused: false }
    case 'stalledUP':
      return { label: 'Finishing up', color: C.dim, paused: false }
    case 'queuedDL': case 'queuedUP': case 'checkingResumeData':
      return { label: 'Queued', color: C.faint, paused: false }
    case 'pausedDL': case 'stoppedDL':
      return { label: 'Paused', color: C.faint, paused: true }
    case 'pausedUP': case 'stoppedUP':
      return { label: 'Completed', color: C.green, paused: true }
    case 'error': case 'missingFiles':
      return { label: 'Error', color: C.red, paused: true }
    default:
      return { label: state || 'Unknown', color: C.faint, paused: false }
  }
}

// Single source of truth for "is this torrent paused?" — derived from stateInfo
// so error/missingFiles are treated consistently (as paused) everywhere.
export const isPausedState = (s: string | null | undefined) => stateInfo(s).paused
