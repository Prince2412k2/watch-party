import { useEffect, useRef } from 'react'
import { useSocket } from './useSocket.js'
import { useServerClock } from './useServerClock.js'
import {
  decideSyncAction, predictPosition, TICKS, CONTROL_MS,
  BUFFER_AHEAD_SEC, PAUSED_BUFFER_AHEAD_SEC, SEEK_TIMEOUT_MS, BUFFER_TIMEOUT_MS,
} from '../sync/syncCore.js'
import { waitForSeeked, waitForBuffer, isBuffered, ensureHlsLoad } from '../sync/bufferSeek.js'

const STRUGGLE_WINDOW_MS = 15_000
const STRUGGLE_HARD_SEEKS = 3

const REPORT_MS = 1000             // drift-telemetry throttle

/**
 * Playback sync with two modes:
 *   hopping  — host plays natively and never waits; guests follow/catch up.
 *   dragging — the group waits for the slowest; a stall freezes everyone
 *              (including the host) until all members are buffered again.
 */
export function useSyncPlay({ playerRef, isHost, collaborativeControl, syncMode = 'hopping', onStruggle, onAutoplayBlocked }) {
  const { socket } = useSocket()
  const { serverNow, clockReady } = useServerClock(socket)

  const applyingRef = useRef(false)
  const applyTimer = useRef(null)
  const scheduleRef = useRef(null)
  const userSeekRef = useRef(false)
  const userSeekTimer = useRef(null)
  const hardSeeks = useRef([])
  const lastReport = useRef(0)
  const syncModeRef = useRef(syncMode)
  syncModeRef.current = syncMode

  // Phase 12: a buffer-aware hard seek is in flight for this guest. While set,
  // the control loop early-returns so it can't stack corrections on top of an
  // in-progress HLS seek+buffer (the chase loop). mountedRef gates the async
  // routine's post-await steps so it aborts on unmount / media swap.
  const isSeekingRef = useRef(false)
  const mountedRef = useRef(true)

  const canControl = isHost || collaborativeControl

  function markApplying() {
    applyingRef.current = true
    clearTimeout(applyTimer.current)
    applyTimer.current = setTimeout(() => { applyingRef.current = false }, 150)
  }

  // Hold the authoring guard open indefinitely across an event window that the
  // 150ms markApplying() timer is too short to cover — namely a source (quality
  // tier) swap, which fires a whole reload sequence (emptied → loadstart →
  // loadedmetadata → canplay) plus transient seeked/play/pause at position 0.
  // Every such event runs through the applyingRef check below, so while held no
  // bogus sync:seek/sync:play(0) can leak. Must be paired with releaseApplying().
  function holdApplying() {
    applyingRef.current = true
    clearTimeout(applyTimer.current)   // cancel any pending auto-release
  }
  function releaseApplying() {
    clearTimeout(applyTimer.current)
    applyingRef.current = false
  }

  function notifyUserSeeking() {
    userSeekRef.current = true
    clearTimeout(userSeekTimer.current)
    userSeekTimer.current = setTimeout(() => { userSeekRef.current = false }, 3000)
  }

  function reportStall(stalled) {
    socket.emit('sync:stall', { stalled })
  }

  function recordHardSeek() {
    const now = Date.now()
    hardSeeks.current = hardSeeks.current.filter(t => now - t < STRUGGLE_WINDOW_MS)
    hardSeeks.current.push(now)
    if (hardSeeks.current.length >= STRUGGLE_HARD_SEEKS) { hardSeeks.current = []; onStruggle?.() }
  }

  // Start a hopping host's own video in sync with the schedule it just authored.
  // A hopping host is exempt from the correction loop (plays natively), and
  // party:selectMedia authors an immediately-"playing" schedule so muted guests
  // can autoplay right away — but nothing else ever starts the host's own video.
  // Idempotent: safe to call from both the schedule handler AND the control loop
  // (a schedule that arrived before the media element mounted is still honored
  // once the element is ready). No-op unless the host is genuinely paused under a
  // hopping 'playing' schedule.
  function kickHostPlay(video) {
    if (!(video && isHost && syncModeRef.current !== 'dragging'
          && scheduleRef.current?.phase === 'playing' && video.paused)) return
    video.play().catch(() => {
      // Autoplay-with-sound was blocked (no recent user gesture by the time this
      // fired). Force muted so playback still starts in sync; onAutoplayBlocked
      // lets the caller show a one-tap "restore sound" affordance. Set
      // video.muted directly (not just via the callback) so this retry doesn't
      // wait on a React re-render to take effect.
      video.muted = true
      onAutoplayBlocked?.()
      video.play().catch(() => {})
    })
  }

  // ── Buffer-aware hard seek (hopping-mode guest only) ───────────────────────
  // Replaces the naive "set currentTime = live and keep playing" for a guest's
  // hard catch-up. On HLS that naive path stalls buffering while the host clock
  // marches on, so the guest lands behind, re-seeks, stalls again — the chase
  // loop. Instead we:
  //   1. pause() so a stall doesn't accrue drift we'll chase,
  //   2. seek to the predicted host position,
  //   3. await 'seeked' (hls.js has switched segments) — timeout fallback,
  //   4. await BUFFER_AHEAD_SEC of runway buffered ahead — timeout fallback,
  //   5. re-read the (now advanced) live position ONCE and snap to it — because
  //      we buffered a runway larger than the wall-time spent, this lands inside
  //      the freshly buffered window, so it plays smoothly instead of re-stalling,
  //   6. play().
  // The whole window is wrapped in holdApplying()/releaseApplying() so none of
  // the pause/seek/play events it fires leak back out as schedule authoring, and
  // isSeekingRef suppresses the control loop for the duration (re-entry guard).
  async function bufferAwareSeek(video) {
    if (isSeekingRef.current) return
    isSeekingRef.current = true
    holdApplying()
    try {
      if (!video.paused) video.pause()
      const predicted = predictPosition(scheduleRef.current, serverNow())
      video.currentTime = predicted

      await waitForSeeked(video, SEEK_TIMEOUT_MS)
      if (!mountedRef.current || playerRef.current !== video) return
      await waitForBuffer(video, video.currentTime, BUFFER_AHEAD_SEC, BUFFER_TIMEOUT_MS)
      if (!mountedRef.current || playerRef.current !== video) return

      // Re-read the live position ONCE now that seek+buffer has consumed some
      // wall time, and snap to it before resuming.
      if (clockReady()) {
        const live = predictPosition(scheduleRef.current, serverNow())
        if (live >= 0) video.currentTime = live
      }
      // The timeline may have been paused/seeked while we awaited — only resume
      // if it's still 'playing'. Reset playbackRate so we don't resume at a
      // stale soft-nudge rate from before the catch-up.
      if (scheduleRef.current?.phase === 'playing') {
        video.playbackRate = 1
        await video.play().catch(() => {})
      }
    } finally {
      isSeekingRef.current = false
      releaseApplying()
    }
  }

  // ── Buffer-aware PAUSED seek (guest only) ──────────────────────────────────
  // When the shared timeline is paused/stalled and this guest is positioned
  // somewhere other than the frozen point (a late joiner still at 0, a quality
  // reload that reset to 0, a host-gone freeze, a dragging stall), it must show
  // the frozen frame immediately WITHOUT resuming. A bare `currentTime = P0`
  // while paused is not enough on HLS: hls.js is autoStartLoad:false and only
  // (re)drives its loader on play()/startLoad(), and the "Catching up…" overlay
  // only clears on play/timeupdate — so the guest sits on a spinner over an
  // unloaded frame until someone resumes. Here we:
  //   1. pause() (belt-and-suspenders — the intent said hold),
  //   2. seek to the frozen position,
  //   3. if that target isn't already buffered, kick hls.js (startLoad(P0)) so
  //      the fragment is fetched + decoded while paused,
  //   4. await 'seeked' (frame decoded) then a small buffered runway (ready to
  //      resume instantly) — both with timeout fallbacks,
  //   5. DO NOT play() — the guest stays paused, now showing the correct frame.
  // Wrapped in holdApplying()/releaseApplying() so the local seek/pause events
  // never leak out as schedule authoring (matters for a collaborative guest),
  // and isSeekingRef suppresses the control loop so it can't stack on top.
  async function bufferAwarePausedSeek(video) {
    if (isSeekingRef.current) return
    isSeekingRef.current = true
    holdApplying()
    try {
      if (!video.paused) video.pause()
      video.playbackRate = 1
      const target = scheduleRef.current.positionTicks / TICKS
      video.currentTime = target
      if (!isBuffered(video, target)) ensureHlsLoad(video, target)

      await waitForSeeked(video, SEEK_TIMEOUT_MS)
      if (!mountedRef.current || playerRef.current !== video) return
      await waitForBuffer(video, target, PAUSED_BUFFER_AHEAD_SEC, BUFFER_TIMEOUT_MS)
      // Intentionally NO play(): stay paused, just render the frozen frame.
    } finally {
      isSeekingRef.current = false
      releaseApplying()
    }
  }

  // Abort any in-flight buffer-aware seek on unmount, and release the guard so
  // we never leave authoring suppressed after this hook goes away.
  useEffect(() => {
    mountedRef.current = true
    return () => {
      mountedRef.current = false
      isSeekingRef.current = false
      releaseApplying()
    }
  }, [])   // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    function onSchedule(s) {
      scheduleRef.current = s
      userSeekRef.current = false
      clearTimeout(userSeekTimer.current)

      // A hopping host is exempt from the correction loop below (plays
      // natively, its own 'play' event is what authors the schedule) — but
      // party:selectMedia authors an immediately-"playing" schedule so muted
      // guests can autoplay right away, and nothing else ever starts the
      // host's own video. Left alone the host sits paused indefinitely while
      // everyone else plays. Kick it here (also re-tried idempotently in the
      // control loop in case the element hadn't mounted yet when this arrived).
      kickHostPlay(playerRef.current)
    }
    function onHostGone() {
      const v = playerRef.current
      if (v) { markApplying(); v.pause() }
    }
    socket.on('sync:schedule', onSchedule)
    socket.on('sync:host_gone', onHostGone)
    socket.emit('sync:hello')
    return () => {
      socket.off('sync:schedule', onSchedule)
      socket.off('sync:host_gone', onHostGone)
    }
  }, [socket, playerRef])

  // Control loop. Runs for guests always, and for the host only in dragging
  // mode (so the host waits for the group). A hopping host plays natively.
  useEffect(() => {
    const id = setInterval(() => {
      const mode = syncModeRef.current
      const s = scheduleRef.current
      const video = playerRef.current
      if (!s || !video) return
      // A buffer-aware hard seek is in flight — do not correct or nudge on top
      // of it (that stacking is exactly the chase loop we're killing).
      if (isSeekingRef.current) return

      // Idempotently (re)start a hopping host's own video. decideSyncAction
      // returns null for a hopping host, so this loop is the only place that
      // honors a 'playing' schedule which arrived before the media element was
      // ready (or that the host later paused out of band). No-op otherwise.
      kickHostPlay(video)

      const intent = decideSyncAction({
        schedule: s,
        serverNowMs: serverNow,
        clockReady,
        currentTime: video.currentTime,
        paused: video.paused,
        isHost,
        mode,
        userSeeking: userSeekRef.current,
      })
      if (!intent) return

      // A guest's hard catch-up in hopping mode goes through the buffer-aware
      // routine (fire-and-forget; it sets isSeekingRef and suppresses the loop
      // until it settles). Every other correction — dragging-host gross-drift,
      // paused-hold, resume — keeps the original synchronous path unchanged.
      if (intent.hardSeek && !isHost && mode === 'hopping') {
        recordHardSeek()
        bufferAwareSeek(video)
        return
      }

      // A guest positioned while the timeline is paused/stalled buffers the
      // frozen frame through the paused buffer-aware routine (fire-and-forget;
      // sets isSeekingRef, never resumes). Applies in both modes — it's a purely
      // local render+buffer that never touches the shared timeline. Runs at most
      // once per frozen position: once seeked, currentTime ≈ P0 so the next tick
      // no longer emits pausedSeek.
      if (intent.pausedSeek && !isHost) {
        bufferAwarePausedSeek(video)
        return
      }

      // Apply the intent to the real player. Only mutations that fire media
      // events (seek/play) are wrapped in markApplying — a bare playbackRate
      // change never was, so the "controller re-authors on event" flow is
      // preserved exactly as before.
      if (intent.seekTo != null) { markApplying(); video.currentTime = intent.seekTo }
      if (intent.rate != null) video.playbackRate = intent.rate
      if (intent.play) { markApplying(); video.play().catch(() => {}) }
      if (intent.pause && !video.paused) { markApplying(); video.pause() }
      if (intent.hardSeek) recordHardSeek()

      // Drift telemetry — guests only (a hopping host returns null above and
      // never reaches here). Throttled to ~REPORT_MS, reusing the core's drift.
      if (!isHost && intent.drift != null) {
        const now = Date.now()
        if (now - lastReport.current >= REPORT_MS) {
          lastReport.current = now
          socket.emit('sync:report', {
            position: video.currentTime,
            drift: intent.drift,
            rate: video.playbackRate,
          })
        }
      }
    }, CONTROL_MS)
    return () => clearInterval(id)
  }, [isHost, socket, playerRef, serverNow, clockReady])

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
    canControl, applyingRef, holdApplying, releaseApplying, notifyUserSeeking, reportStall,
    requestPlay, requestPause, requestSeek, TICKS_PER_SECOND: TICKS,
  }
}
