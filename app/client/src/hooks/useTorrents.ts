import { useCallback, useEffect, useRef, useState } from 'react'
import { apiJson, arrayOf, isTorrentJson } from '../types/guards'

const jpost = (url: string, body: unknown) => fetch(url, {
  method: 'POST', credentials: 'include',
  headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
})

export interface TorrentRecord {
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

/* Map the download client's raw state strings → whether the item is paused.
 * Shared with stateInfo() in FindDownload.jsx / Downloads.jsx presentational
 * layers, which each map to their own label/color. (qBittorrent 5.x renamed
 * paused* → stopped*; both are kept so a version bump can't silently mislabel.) */
const PAUSED_STATES = new Set(['pausedDL', 'stoppedDL', 'pausedUP', 'stoppedUP'])
export const isPausedState = (s: string | null | undefined) => PAUSED_STATES.has(s ?? '')

/* "Actively downloading" — the states that mean a title is still working toward
 * a complete file. Deliberately EXCLUDES seeding/completed (uploading*, *UP),
 * paused/stopped, and error states, so the "N downloading" nav badge and the
 * "Downloading now" rail don't count finished-but-seeding or errored torrents as
 * downloads. Shared across every surface so those counts always agree. */
const DOWNLOADING_STATES = new Set([
  'downloading', 'forcedDL', 'metaDL', 'forcedMetaDL',
  'stalledDL', 'queuedDL', 'checkingDL', 'allocating', 'checkingResumeData',
])
export const isActiveState = (s: string | null | undefined) => DOWNLOADING_STATES.has(s ?? '')

/* ── Live downloads poller ──────────────────────────────────────────────────
   Visibility-aware ~2.5s polling with a single shared AbortController; a failed
   poll keeps the last good data and flags a subtle reconnect. Exposes torrents +
   pause/resume/remove so every surface that shows the download queue (Browse,
   Library's "downloading now" rail, the Downloads tab) can share ONE poller
   shape without re-implementing the lifecycle. */
export function useTorrents(ready: boolean) {
  const [torrents, setTorrents] = useState<TorrentRecord[] | null>(null)   // null = never loaded
  const [loadError, setLoadError] = useState(false)
  const [busy, setBusy] = useState<Set<string>>(() => new Set())
  const abortRef = useRef<AbortController | null>(null)

  const poll = useCallback(() => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    return fetch('/api/servarr/downloads/enriched', { credentials: 'include', signal: ctrl.signal })
      .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
      .then((data) => {
        if (ctrl.signal.aborted) return
        setTorrents(arrayOf(data, isTorrentJson))
        setLoadError(false)
      })
      .catch((e) => { if (e?.name === 'AbortError' || ctrl.signal.aborted) return; setLoadError(true) })
  }, [])

  useEffect(() => {
    if (!ready) { setTorrents(null); return }
    let timer: ReturnType<typeof setInterval> | null = null
    const start = () => { if (timer == null) { poll(); timer = setInterval(poll, 2500) } }
    const stop = () => { if (timer != null) { clearInterval(timer); timer = null } abortRef.current?.abort() }
    const onVis = () => (document.hidden ? stop() : start())
    if (!document.hidden) start()
    document.addEventListener('visibilitychange', onVis)
    return () => { document.removeEventListener('visibilitychange', onVis); stop() }
  }, [ready, poll])

  const runAction = useCallback((hash: string, endpoint: string, body: unknown, optimistic: Record<string, unknown> = {}) => {
    setBusy((prev) => new Set(prev).add(hash))
    if (optimistic) setTorrents((cur) => cur && cur.map((t) => (t.hash === hash ? { ...t, ...(optimistic as Record<string, unknown>) } : t)))
    jpost(`/api/servarr/qbittorrent/${endpoint}`, { hashes: hash, ...(body as Record<string, unknown>) })
      .catch(() => {})
      .finally(() => {
        setBusy((prev) => { const n = new Set(prev); n.delete(hash); return n })
        poll()
      })
  }, [poll])

  const pause = (t: { hash: string }) => runAction(t.hash, 'pause', {}, { state: 'pausedDL' })
  const resume = (t: { hash: string }) => runAction(t.hash, 'resume', {}, { state: 'downloading' })
  const remove = (hash: string, deleteFiles: boolean) => {
    setTorrents((cur) => cur && cur.filter((t) => t.hash !== hash))
    runAction(hash, 'delete', { deleteFiles })
  }

  const list = torrents || []
  const activeCount = list.filter((torrent) => isActiveState(torrent.state)).length
  return { ready, torrents, list, loadError, busy, activeCount, pause, resume, remove }
}
