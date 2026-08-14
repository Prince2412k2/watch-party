import { useEffect, useRef } from 'react'
import {
  PENDING_KEY,
  REPORT_INTERVAL_MS,
  mergePending,
  newSessionId,
  parsePending,
  shouldReportProgress,
  ticksOf,
  type PlaybackReport,
  type PlaybackReportKind,
} from '../analog/watchHistory.ts'

/**
 * Tells the server what is being watched, so a watch history exists.
 *
 * Everything the app shows about what you have seen is Jellyfin's `UserData`,
 * and Jellyfin fills it in only for playback it was told about. The desktop
 * client reports; the web client did not, so watching here left no trace —
 * Continue Watching and Next Up simply never learned about it.
 *
 * Reports on start, every ten seconds while playing, on every pause, at the
 * end, and when the tab goes away — that last one matters most, because
 * closing the tab mid-film is the ordinary way of stopping and was the one way
 * that lost the position entirely.
 *
 * Deliberately does NOT seek anywhere on open. Every web playback happens
 * inside a room, and a room's position is the host's; seeking to your own
 * resume point would drag the film to a scene nobody else is on until sync
 * pulled it back. The rewind constant still lives in `watchHistory.ts` for the
 * day this player is used outside a party.
 *
 * The rules live in `analog/watchHistory.ts` and are tested there; this holds
 * only the element, the clock and the requests.
 */
export function useWatchHistory(
  video: HTMLVideoElement | null,
  itemId: string | undefined,
  mediaSourceId?: string,
) {
  // Refs, not state: none of this is rendered, and re-rendering the player on
  // every tick would be a real cost for no visible change.
  const session = useRef<{ id: string; itemId: string } | null>(null)
  const lastSent = useRef<number | null>(null)
  const elementRef = useRef<HTMLVideoElement | null>(null)
  elementRef.current = video

  const post = useRef(async (kind: PlaybackReportKind, report: PlaybackReport, keepalive = false) => {
    try {
      const response = await fetch(`/api/playback/${kind}`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(report),
        keepalive,
      })
      if (!response.ok) throw new Error(String(response.status))
      drainPending()
    } catch {
      // A dropped progress tick is worth nothing — a newer position follows in
      // ten seconds. A dropped STOP is the resume point itself, so that is the
      // only kind kept for later.
      if (kind === 'stopped') queuePending(report)
    }
  }).current

  useEffect(() => {
    drainPending()
  }, [])

  useEffect(() => {
    if (!video || !itemId) return
    const started: PlaybackReport = {
      itemId,
      positionTicks: 0,
      mediaSourceId,
      playSessionId: newSessionId(),
      isPaused: false,
    }
    session.current = { id: started.playSessionId!, itemId }
    lastSent.current = null
    void post('started', started)

    const positionTicks = () => ticksOf(elementRef.current?.currentTime ?? 0)

    const report = (kind: PlaybackReportKind, opts: { paused?: boolean; force?: boolean } = {}) => {
      const current = session.current
      if (!current) return
      const ticks = positionTicks()
      const paused = opts.paused ?? elementRef.current?.paused ?? false
      if (kind === 'progress' && !opts.force &&
          !shouldReportProgress(ticks, lastSent.current, opts.paused !== undefined)) {
        return
      }
      lastSent.current = ticks
      void post(kind, {
        itemId: current.itemId,
        positionTicks: ticks,
        mediaSourceId,
        playSessionId: current.id,
        isPaused: paused,
      }, kind === 'stopped')
    }

    const onPlay = () => report('progress', { paused: false })
    const onPause = () => report('progress', { paused: true })
    const onEnded = () => report('stopped')
    // pagehide, not beforeunload: it is the one that fires on a mobile tab
    // being backgrounded away, which is where a process is killed without
    // further notice. `keepalive` is what lets the request outlive the page.
    const onHide = () => report('stopped')

    video.addEventListener('play', onPlay)
    video.addEventListener('pause', onPause)
    video.addEventListener('ended', onEnded)
    window.addEventListener('pagehide', onHide)

    const ticker = window.setInterval(() => {
      if (!elementRef.current?.paused) report('progress')
    }, REPORT_INTERVAL_MS)

    return () => {
      window.clearInterval(ticker)
      video.removeEventListener('play', onPlay)
      video.removeEventListener('pause', onPause)
      video.removeEventListener('ended', onEnded)
      window.removeEventListener('pagehide', onHide)
      // Leaving the title — a new film, or the room closing — still has to say
      // where this one got to, or it keeps whatever position the last tick
      // happened to carry.
      report('stopped')
      session.current = null
    }
  }, [video, itemId, mediaSourceId, post])
}

function queuePending(report: PlaybackReport) {
  try {
    const queue = mergePending(parsePending(localStorage.getItem(PENDING_KEY)), report)
    localStorage.setItem(PENDING_KEY, JSON.stringify(queue))
  } catch {
    // Private mode, or a full quota. Losing a queued position is not worth an
    // error in front of someone watching a film.
  }
}

/** Send everything a previous session could not, and keep what still fails. */
function drainPending() {
  let queue: PlaybackReport[]
  try {
    queue = parsePending(localStorage.getItem(PENDING_KEY))
  } catch {
    return
  }
  if (queue.length === 0) return

  void (async () => {
    const unsent: PlaybackReport[] = []
    for (const report of queue) {
      try {
        const response = await fetch('/api/playback/stopped', {
          method: 'POST',
          credentials: 'include',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(report),
        })
        if (!response.ok) throw new Error(String(response.status))
      } catch {
        // Still unreachable — keep it rather than hammering a server that is
        // plainly down.
        unsent.push(report)
      }
    }
    try {
      localStorage.setItem(PENDING_KEY, JSON.stringify(unsent))
    } catch { /* see queuePending */ }
  })()
}
