import { useCallback, useEffect, useRef } from 'react'

// NTP-lite clock sync: estimate this client's offset from the server clock so
// every client agrees on `serverNow()` within a few ms. We keep a rolling
// window of samples and trust the offset from the lowest-RTT one (least noise).
export function useServerClock(socket) {
  const offsetRef = useRef(0)
  const readyRef = useRef(false)

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
  return { serverNow, clockReady }
}
