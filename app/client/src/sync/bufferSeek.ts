// Buffer-aware hard-seek primitives (Phase 12).
//
// These are the two async, media-touching helpers the guest hopping hard-seek
// uses to catch up smoothly on HLS. They live here — not in syncCore.js — so
// the core stays a pure, DOM-free decision function. They operate on any object
// with the minimal HTMLMediaElement surface (addEventListener/removeEventListener
// + a `buffered` TimeRanges), so the browser hook and the headless VirtualPlayer
// both drive the identical catch-up routine.

// Resolve when the element fires 'seeked', or after timeoutMs (fallback). HLS
// seeks can be slow; never hang the routine on a missing event.
export function waitForSeeked(media: {
  addEventListener: (type: string, cb: () => void) => void
  removeEventListener: (type: string, cb: () => void) => void
}, timeoutMs: number) {
  return new Promise((resolve) => {
    let done = false
    const finish = (via: string) => {
      if (done) return
      done = true
      clearTimeout(timer)
      media.removeEventListener('seeked', onSeeked)
      resolve(via)
    }
    const onSeeked = () => finish('seeked')
    const timer = setTimeout(() => finish('timeout'), timeoutMs)
    media.addEventListener('seeked', onSeeked)
  })
}

// True when `t` falls inside a buffered range — i.e. the frame there is loaded
// and can render. Small slack on both ends so a seek that lands a hair inside a
// segment (or right at its edge) still counts. Used to skip the hls.js load-kick
// when the paused target is already buffered (no need to disturb the loader).
export function isBuffered(media: { buffered?: TimeRanges | null }, t: number) {
  try {
    const b = media.buffered
    if (!b) return false
    for (let i = 0; i < b.length; i++) {
      if (t >= b.start(i) - 0.25 && t <= b.end(i) + 0.25) return true
    }
  } catch { /* buffered can throw on a torn-down element */ }
  return false
}

// Kick hls.js to fetch (and decode) the fragment at `position`, even while the
// media is paused. hls.js is configured autoStartLoad:false and only (re)starts
// its loader on play() or an explicit startLoad(); a bare paused currentTime
// write does NOT reliably drive the loader to a far seek target. startLoad(pos)
// (re)anchors the loader at pos so the segment is fetched while paused. No-op
// when the element has no hls.js engine (native HLS playback, or the headless
// VirtualPlayer, which has no `.engine`) — those buffer on the seek alone.
export function ensureHlsLoad(media: { engine?: { startLoad?: (position: number) => void } | null }, position: number) {
  const hls = media && media.engine
  if (!hls || typeof hls.startLoad !== 'function') return false
  try { hls.startLoad(position); return true } catch { return false }
}

// Choose the newest desired position that remains inside the buffered range
// which was confirmed around `anchor`. Keeping a margin from the range end
// avoids resuming exactly on the download frontier. If ranges disappeared
// during inspection, fall back to the anchor we already sought to.
export function selectBufferedResumeTarget(media: { buffered?: TimeRanges | null }, anchor: number, desired: number, endMarginSec = 0.25) {
  try {
    const b = media?.buffered
    if (!b) return anchor
    for (let i = 0; i < (b?.length || 0); i++) {
      const start = b.start(i)
      const end = b.end(i)
      if (anchor >= start - 0.25 && anchor <= end + 0.25) {
        const safeEnd = Math.max(anchor, end - Math.max(0, endMarginSec))
        return Math.max(anchor, Math.min(desired, safeEnd))
      }
    }
  } catch { /* torn-down media */ }
  return anchor
}

// Resolve once `targetTime` is buffered with at least `aheadSec` of runway ahead
// of it (i.e. some buffered range covers [targetTime, targetTime + aheadSec]),
// or after timeoutMs. Polls video.buffered because there is no single reliable
// "enough buffered" DOM event across engines.
export function waitForBuffer(media: { duration?: number; buffered?: TimeRanges | null }, targetTime: number, aheadSec: number, timeoutMs: number) {
  // A target within aheadSec of the media end can never accumulate the full
  // look-ahead (there simply isn't that much media left), so the wait would
  // hang until timeout. Clamp the required runway to what's actually reachable:
  // min(aheadSec, duration - targetTime). Guard against unknown/NaN duration
  // (live/unloaded) by leaving aheadSec unchanged in that case.
  const dur = media && media.duration
  const need = (typeof dur === 'number' && isFinite(dur))
    ? Math.min(aheadSec, Math.max(0, dur - targetTime))
    : aheadSec
  const hasRunway = () => {
    try {
      const b = media.buffered
      if (!b) return false
      for (let i = 0; i < b.length; i++) {
        // small slack on the start so a seek that lands a hair inside a segment
        // still counts as "in this range".
        if (targetTime >= b.start(i) - 0.25 && b.end(i) >= targetTime + need) return true
      }
    } catch { /* buffered can throw on a torn-down element */ }
    return false
  }
  return new Promise((resolve) => {
    if (hasRunway()) { resolve('ready'); return }
    let done = false
    const finish = (via: string) => {
      if (done) return
      done = true
      clearTimeout(timer)
      clearInterval(poll)
      resolve(via)
    }
    const poll = setInterval(() => { if (hasRunway()) finish('buffered') }, 100)
    const timer = setTimeout(() => finish('timeout'), timeoutMs)
  })
}
