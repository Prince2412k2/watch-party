import { useCallback, useEffect, useRef } from 'react'

// NTP-lite clock sync: estimate this client's offset from the server clock so
// every client agrees on `serverNow()` within a few ms. We keep a rolling
// window of samples and trust the offset from the lowest-RTT one (least noise).
export function useServerClock(socket) {
  const offsetRef = useRef(0)
  const readyRef = useRef(false)
  // Quality metadata for the best sample currently backing offsetRef, so
  // callers can optionally judge confidence instead of trusting a bare
  // ready flag. Not required for existing consumers — see clockQuality().
  const qualityRef = useRef({ rttMs: null, uncertaintyMs: null, sampledAt: null })

  useEffect(() => {
    if (!socket) return
    let stopped = false
    const samples = []

    function sample() {
      const t1 = Date.now()
      socket.timeout(2000).emit('clock:ping', t1, (err, serverTs) => {
        if (stopped || err || typeof serverTs !== 'number') return
        const t4 = Date.now()
        const rtt = t4 - t1
        const offset = serverTs - (t1 + t4) / 2   // add to local clock → server clock
        samples.push({ rtt, offset })
        if (samples.length > 12) samples.shift()
        const best = samples.reduce((a, b) => (b.rtt < a.rtt ? b : a))
        offsetRef.current = best.offset
        readyRef.current = true
        // Rough uncertainty bound: half the best sample's RTT is the max
        // one-way error the offset could carry (standard NTP assumption).
        qualityRef.current = { rttMs: best.rtt, uncertaintyMs: best.rtt / 2, sampledAt: t4 }
      })
    }

    sample()
    let n = 0
    const burst = setInterval(() => { sample(); if (++n >= 5) clearInterval(burst) }, 500)
    const drift = setInterval(sample, 5000)
    return () => { stopped = true; clearInterval(burst); clearInterval(drift) }
  }, [socket])

  const serverNow = useCallback(() => Date.now() + offsetRef.current, [])
  const clockReady = useCallback(() => readyRef.current, [])
  // Extended, opt-in status for callers that want more than a boolean.
  // ageMs is measured fresh on each call (ms since the best sample was taken),
  // not cached, so it stays accurate between samples.
  const clockQuality = useCallback(() => {
    const q = qualityRef.current
    return {
      offset: offsetRef.current,
      rttMs: q.rttMs,
      uncertaintyMs: q.uncertaintyMs,
      ageMs: q.sampledAt == null ? null : Date.now() - q.sampledAt,
      ready: readyRef.current,
    }
  }, [])
  return { serverNow, clockReady, clockQuality }
}
