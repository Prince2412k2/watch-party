import { useEffect, useState } from 'react'
import { apiJson, arrayOf, isQueueJson } from '../types/guards'

/* Lightweight poll of Radarr + Sonarr's queues for the *count* of items stuck
 * in a warning/failed state — just enough to drive a nav badge. The full list
 * (with reasons + remove/blocklist actions) is fetched separately by the
 * Downloads page itself; this hook exists so Library/Browse can show "hey,
 * something needs your attention" without pulling in the whole queue. Polls
 * only while the tab is visible; a failed/unconfigured service silently
 * contributes 0 rather than surfacing an error. */
export function useFailingCount(enabled: boolean) {
  const [count, setCount] = useState(0)
  useEffect(() => {
    if (!enabled) { setCount(0); return }
    let timer: ReturnType<typeof setInterval> | null = null
    let ctrl: AbortController | null = null
    const poll = () => {
      ctrl?.abort()
      // Capture this run's controller locally so a slower earlier response can't
      // read a newer run's `ctrl` and slip past the aborted-guard to overwrite state.
      const c = new AbortController()
      ctrl = c
      Promise.all([
        fetch('/api/servarr/radarr/queue', { credentials: 'include', signal: c.signal }).then((r) => (r.ok ? apiJson(r) : [])).catch(() => []),
        fetch('/api/servarr/sonarr/queue', { credentials: 'include', signal: c.signal }).then((r) => (r.ok ? apiJson(r) : [])).catch(() => []),
      ]).then(([a, b]) => {
        if (c.signal.aborted) return
        const items = [...arrayOf(a, isQueueJson), ...arrayOf(b, isQueueJson)]
        setCount(items.filter((q) => q.failing).length)
      })
    }
    const start = () => { if (timer == null) { poll(); timer = setInterval(poll, 8000) } }
    const stop = () => { if (timer != null) { clearInterval(timer); timer = null } ctrl?.abort() }
    const onVis = () => (document.hidden ? stop() : start())
    if (!document.hidden) start()
    document.addEventListener('visibilitychange', onVis)
    return () => { document.removeEventListener('visibilitychange', onVis); stop() }
  }, [enabled])
  return count
}
