import { BUFFER_AHEAD_SEC } from './syncCore.ts'

/** A local seek briefly discards decoded frames even though all bytes exist.
 * Only a sustained decoder stall should stop the other viewers. */
export function createPlaybackStallGate(localFile: boolean) {
  let unreadySince: number | null = null
  return (ready: boolean, nowMs: number): boolean => {
    if (ready) {
      unreadySince = null
      return false
    }
    if (!localFile) return true
    unreadySince ??= nowMs
    return nowMs - unreadySince >= 1000
  }
}

/** Readiness for Follow mode; downloaded files need decoded frames, not
 * network runway. Safari's buffered ranges need not describe the whole file. */
export function isPlaybackReady(media: {
  currentTime: number
  duration: number
  readyState: number
  ended?: boolean
  seeking?: boolean
  buffered: TimeRanges
}, localFile: boolean, aheadSec = BUFFER_AHEAD_SEC): boolean {
  if (media.ended) return true
  if (media.seeking) return false
  if (localFile) return media.readyState >= 3 // HAVE_FUTURE_DATA
  const time = media.currentTime || 0
  const end = Number.isFinite(media.duration) && media.duration > 0
    ? Math.min(time + aheadSec, media.duration)
    : time + aheadSec
  try {
    const ranges = media.buffered
    for (let i = 0; i < ranges.length; i++) {
      // Require a single contiguous range, not two sides of a missing segment.
      if (time >= ranges.start(i) - 0.25 && end <= ranges.end(i) + 0.25) return true
    }
  } catch { /* source replaced or element torn down */ }
  return false
}
