import { useCallback, useEffect, useRef, useState } from 'react'

const jpost = (url, body) => fetch(url, {
  method: 'POST', credentials: 'include',
  headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
})

/* Map the download client's raw state strings → whether the item is paused.
 * Shared with stateInfo() in FindDownload.jsx / Downloads.jsx presentational
 * layers, which each map to their own label/color. (qBittorrent 5.x renamed
 * paused* → stopped*; both are kept so a version bump can't silently mislabel.) */
const PAUSED_STATES = new Set(['pausedDL', 'stoppedDL', 'pausedUP', 'stoppedUP'])
export const isPausedState = (s) => PAUSED_STATES.has(s)

/* "Actively downloading" — the states that mean a title is still working toward
 * a complete file. Deliberately EXCLUDES seeding/completed (uploading*, *UP),
 * paused/stopped, and error states, so the "N downloading" nav badge and the
 * "Downloading now" rail don't count finished-but-seeding or errored torrents as
 * downloads. Shared across every surface so those counts always agree. */
const DOWNLOADING_STATES = new Set([
  'downloading', 'forcedDL', 'metaDL', 'forcedMetaDL',
  'stalledDL', 'queuedDL', 'checkingDL', 'allocating', 'checkingResumeData',
])
export const isActiveState = (s) => DOWNLOADING_STATES.has(s)

/* ── Live downloads poller ──────────────────────────────────────────────────
   Visibility-aware ~2.5s polling with a single shared AbortController; a failed
   poll keeps the last good data and flags a subtle reconnect. Exposes torrents +
   pause/resume/remove so every surface that shows the download queue (Browse,
   Library's "downloading now" rail, the Downloads tab) can share ONE poller
   shape without re-implementing the lifecycle. */
export function useTorrents(ready) {
  const [torrents, setTorrents] = useState(null)   // null = never loaded
  const [loadError, setLoadError] = useState(false)
  const [busy, setBusy] = useState(() => new Set())
  const abortRef = useRef(null)

  const poll = useCallback(() => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    return fetch('/api/servarr/downloads/enriched', { credentials: 'include', signal: ctrl.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then((data) => {
        if (ctrl.signal.aborted) return
        setTorrents(Array.isArray(data) ? data : [])
        setLoadError(false)
      })
      .catch((e) => { if (e?.name === 'AbortError' || ctrl.signal.aborted) return; setLoadError(true) })
  }, [])

  useEffect(() => {
    if (!ready) { setTorrents(null); return }
    let timer = null
    const start = () => { if (timer == null) { poll(); timer = setInterval(poll, 2500) } }
    const stop = () => { if (timer != null) { clearInterval(timer); timer = null } abortRef.current?.abort() }
    const onVis = () => (document.hidden ? stop() : start())
    if (!document.hidden) start()
    document.addEventListener('visibilitychange', onVis)
    return () => { document.removeEventListener('visibilitychange', onVis); stop() }
  }, [ready, poll])

  const runAction = useCallback((hash, endpoint, body, optimistic) => {
    setBusy((prev) => new Set(prev).add(hash))
    if (optimistic) setTorrents((cur) => cur && cur.map((t) => (t.hash === hash ? { ...t, ...optimistic } : t)))
    jpost(`/api/servarr/qbittorrent/${endpoint}`, { hashes: hash, ...body })
      .catch(() => {})
      .finally(() => {
        setBusy((prev) => { const n = new Set(prev); n.delete(hash); return n })
        poll()
      })
  }, [poll])

  const pause = (t) => runAction(t.hash, 'pause', {}, { state: 'pausedDL' })
  const resume = (t) => runAction(t.hash, 'resume', {}, { state: 'downloading' })
  const remove = (hash, deleteFiles) => {
    setTorrents((cur) => cur && cur.filter((t) => t.hash !== hash))
    runAction(hash, 'delete', { deleteFiles })
  }

  const list = torrents || []
  const activeCount = list.filter((t) => isActiveState(t.state)).length
  return { ready, torrents, list, loadError, busy, activeCount, pause, resume, remove }
}
