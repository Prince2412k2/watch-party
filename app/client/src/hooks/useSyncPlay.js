import { useEffect, useRef } from 'react'
import { useSocket } from './useSocket.js'
import { useServerClock } from './useServerClock.js'

const TICKS = 10_000_000           // Jellyfin ticks per second

// Follower control tuning (guests only)
const CONTROL_MS = 200
const HARD_SEEK_SEC = 1.0          // drift beyond this → jump to live
const SOFT_SEC = 0.08              // drift beyond this → speed nudge
const RATE_GAIN = 0.12
const MAX_RATE_ADJ = 0.08
const HOLD_TOLERANCE = 0.4

// Struggle detection → request a lower bitrate
const STRUGGLE_WINDOW_MS = 15_000
const STRUGGLE_HARD_SEEKS = 3      // this many forced jumps in the window ⇒ can't keep up

/**
 * Host-authority playback sync.
 *   Host: plays/scrubs natively, never waits; authors the schedule on its actions.
 *   Guests: follow the shared schedule (expected = P0 + rate*(serverNow - t0)),
 *           seeking to live and letting the browser buffer natively. The player's
 *           own waiting/playing events drive the "Catching up…" overlay. A guest
 *           that keeps falling behind asks for a lower bitrate. Reconciliation is
 *           entirely local — it never disturbs the host or other guests.
 */
export function useSyncPlay({ playerRef, isHost, collaborativeControl, onStruggle }) {
  const { socket } = useSocket()
  const { serverNow, clockReady } = useServerClock(socket)

  const applyingRef = useRef(false)
  const applyTimer = useRef(null)
  const scheduleRef = useRef(null)
  const userSeekRef = useRef(false)     // a controller is scrubbing
  const userSeekTimer = useRef(null)
  const hardSeeks = useRef([])          // timestamps of recent forced jumps

  const canControl = isHost || collaborativeControl

  function markApplying() {
    applyingRef.current = true
    clearTimeout(applyTimer.current)
    applyTimer.current = setTimeout(() => { applyingRef.current = false }, 150)
  }

  function notifyUserSeeking() {
    userSeekRef.current = true
    clearTimeout(userSeekTimer.current)
    userSeekTimer.current = setTimeout(() => { userSeekRef.current = false }, 3000)
  }

  // A forced jump means we couldn't keep up. Too many in a window ⇒ downshift.
  function recordHardSeek() {
    const now = Date.now()
    hardSeeks.current = hardSeeks.current.filter(t => now - t < STRUGGLE_WINDOW_MS)
    hardSeeks.current.push(now)
    if (hardSeeks.current.length >= STRUGGLE_HARD_SEEKS) {
      hardSeeks.current = []
      onStruggle?.()
    }
  }

  // ── Receive schedule updates ──────────────────────────────────────────────
  useEffect(() => {
    function onSchedule(s) {
      scheduleRef.current = s
      userSeekRef.current = false
      clearTimeout(userSeekTimer.current)
    }
    function onHostGone() {
      const v = playerRef.current
      if (v) { markApplying(); v.pause() }
    }
    socket.on('sync:schedule', onSchedule)
    socket.on('sync:host_gone', onHostGone)
    // Now that we're listening, pull the current timeline (covers the join race)
    socket.emit('sync:hello')
    return () => {
      socket.off('sync:schedule', onSchedule)
      socket.off('sync:host_gone', onHostGone)
    }
  }, [socket, playerRef])

  // ── Follower control loop (guests only; the host plays natively) ──────────
  useEffect(() => {
    if (isHost) return
    const id = setInterval(() => {
      const s = scheduleRef.current
      const video = playerRef.current
      if (!s || !video) return
      if (userSeekRef.current) return
      const P0 = s.positionTicks / TICKS

      // Paused → hold at P0
      if (s.phase === 'paused') {
        video.playbackRate = 1
        if (!video.paused) { markApplying(); video.pause() }
        if (Math.abs(video.currentTime - P0) > HOLD_TOLERANCE) { markApplying(); video.currentTime = P0 }
        return
      }

      // Playing — need the shared clock to know where "live" is
      if (!clockReady()) return
      const expected = P0 + (serverNow() - s.t0) / 1000
      if (expected < 0) return

      // Paused but should be playing (just joined / missed a play) → start
      if (video.paused) {
        markApplying()
        video.currentTime = expected
        video.playbackRate = 1
        video.play().catch(() => {})
        return
      }

      const err = expected - video.currentTime   // positive ⇒ we're behind
      const ae = Math.abs(err)
      if (ae > HARD_SEEK_SEC) {
        // Too far off → jump to live; the engine buffers natively from here
        markApplying()
        video.currentTime = expected
        video.playbackRate = 1
        recordHardSeek()
      } else if (ae > SOFT_SEC) {
        video.playbackRate = 1 + Math.max(-MAX_RATE_ADJ, Math.min(MAX_RATE_ADJ, err * RATE_GAIN))
      } else {
        video.playbackRate = 1
      }
    }, CONTROL_MS)
    return () => clearInterval(id)
  }, [isHost, socket, playerRef, serverNow, clockReady])

  // ── Outgoing: controllers author schedule changes ────────────────────────
  function requestPlay(positionTicks) {
    if (!applyingRef.current && canControl) socket.emit('sync:play', { positionTicks, t0: serverNow() })
  }
  function requestPause(positionTicks) {
    if (!applyingRef.current && canControl) socket.emit('sync:pause', { positionTicks })
  }
  function requestSeek(positionTicks) {
    if (!applyingRef.current && canControl) socket.emit('sync:seek', { positionTicks, t0: serverNow() })
  }

  return {
    canControl, applyingRef, notifyUserSeeking,
    requestPlay, requestPause, requestSeek, TICKS_PER_SECOND: TICKS,
  }
}
