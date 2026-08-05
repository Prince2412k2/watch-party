import { useCallback, useEffect, useRef, useState } from 'react'
import { jget } from '../lib/api'
import { apiJson, arrayOf, isQueueJson, type QueueJson } from '../types/guards'

export interface FailingQueueItem {
  id: string | number
  service: string
  title?: string
  failing?: boolean
  statusMessages?: string[]
  errorMessage?: string
  indexer?: string
  size?: number
}

/* isQueueJson only guarantees identity (id + service) — every field the UI shows
 * beyond that is a *arr optional, so narrow each one here rather than asserting
 * the whole record and reading `undefined.map` at render time. */
const toFailingItem = (q: QueueJson): FailingQueueItem => ({
  id: q.id,
  service: q.service,
  failing: q.failing,
  title: typeof q.title === 'string' ? q.title : undefined,
  statusMessages: Array.isArray(q.statusMessages)
    ? q.statusMessages.filter((message): message is string => typeof message === 'string')
    : undefined,
  errorMessage: typeof q.errorMessage === 'string' ? q.errorMessage : undefined,
  indexer: typeof q.indexer === 'string' ? q.indexer : undefined,
  size: typeof q.size === 'number' ? q.size : undefined,
})

/* ── Failing queue items (Radarr/Sonarr) poller ──────────────────────────────
   Visibility-aware ~6s polling of both *arr queues for items stuck in a
   warning/failed state, with a single shared AbortController so an in-flight
   poll is cancelled on the next tick / unmount and never lands stale state. A
   failed poll flags a subtle reconnect and keeps the last good list; remove() is
   optimistic and re-polls to confirm.

   This is the ONE implementation. It used to exist three times over — a
   count-only variant for nav badges plus verbatim copies inside the desktop and
   phone Downloads screens — so a phone sitting on the Downloads tab polled both
   *arr queues twice per cycle (once for the tab-bar badge, once for the list).
   Mounted once by DownloadsProvider; every surface reads the result from there. */
export function useFailingQueue(enabled: boolean) {
  const [items, setItems] = useState<FailingQueueItem[] | null>(null)   // null = never loaded
  const [loadError, setLoadError] = useState(false)
  const [busy, setBusy] = useState<Set<FailingQueueItem['id']>>(() => new Set())
  const abortRef = useRef<AbortController | null>(null)

  const poll = useCallback(() => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    return Promise.all([
      jget('/api/servarr/radarr/queue', ctrl.signal).then((r) => (r.ok ? apiJson(r) : Promise.reject(r))).catch(() => null),
      jget('/api/servarr/sonarr/queue', ctrl.signal).then((r) => (r.ok ? apiJson(r) : Promise.reject(r))).catch(() => null),
    ]).then(([a, b]) => {
      if (ctrl.signal.aborted) return
      if (a == null && b == null) { setLoadError(true); return }
      const merged = [...arrayOf(a, isQueueJson), ...arrayOf(b, isQueueJson)].map(toFailingItem)
      setItems(merged.filter((q) => q.failing))
      setLoadError(false)
    })
  }, [])

  useEffect(() => {
    if (!enabled) { setItems(null); return }
    let timer: ReturnType<typeof setInterval> | null = null
    const start = () => { if (timer == null) { poll(); timer = setInterval(poll, 6000) } }
    const stop = () => { if (timer != null) { clearInterval(timer); timer = null } abortRef.current?.abort() }
    const onVis = () => (document.hidden ? stop() : start())
    if (!document.hidden) start()
    document.addEventListener('visibilitychange', onVis)
    return () => { document.removeEventListener('visibilitychange', onVis); stop() }
  }, [enabled, poll])

  const remove = (item: FailingQueueItem, blocklist: boolean) => {
    setBusy((prev) => new Set(prev).add(item.id))
    setItems((cur) => cur?.filter((q) => q.id !== item.id) ?? null)
    fetch(`/api/servarr/${item.service}/queue/${item.id}`, {
      method: 'DELETE', credentials: 'include',
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ blocklist: !!blocklist }),
    }).catch(() => {}).finally(() => {
      setBusy((prev) => { const n = new Set(prev); n.delete(item.id); return n })
      poll()
    })
  }

  return { items, loadError, busy, remove }
}

export type FailingQueueState = ReturnType<typeof useFailingQueue>

/** What to call a stuck item. *arr leaves `title` off some queue records, and a
 *  nameless row is still something the user has to act on. */
export function queueTitle(item: FailingQueueItem): string {
  return item.title?.trim() || 'Untitled item'
}

/** Why a queue item is stuck, in the order *arr reports it. Always non-empty —
 *  "needs attention" with no stated reason is not actionable. */
export function failureReasons(item: FailingQueueItem): string[] {
  if (item.statusMessages?.length) return item.statusMessages
  return item.errorMessage ? [item.errorMessage] : ['No reason given.']
}
