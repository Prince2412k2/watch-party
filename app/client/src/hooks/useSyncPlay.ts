import { useEffect, useRef, useState } from 'react'
import type { RefObject } from 'react'
import { useSocket } from './useSocket'
import { useServerClock } from './useServerClock'
import {
  decideSyncAction, predictPosition, TICKS, CONTROL_MS,
  BUFFER_AHEAD_SEC, PAUSED_BUFFER_AHEAD_SEC, SEEK_TIMEOUT_MS, BUFFER_TIMEOUT_MS,
  HARD_SEEK_COOLDOWN_MS,
} from '../sync/syncCore'
import { waitForSeeked, waitForBuffer, isBuffered, ensureHlsLoad, selectBufferedResumeTarget } from '../sync/bufferSeek'

const STRUGGLE_WINDOW_MS = 15_000
const STRUGGLE_HARD_SEEKS = 3

const REPORT_MS = 1000             // drift-telemetry throttle

/**
 * Playback sync with two modes:
 *   hopping  — host plays natively and never waits; guests follow/catch up.
 *   dragging — the group waits for the slowest; a stall freezes everyone
 *              (including the host) until all members are buffered again.
 */
export function useSyncPlay({
  playerRef, isHost, collaborativeControl, syncMode = 'hopping', onStruggle, onAutoplayBlocked,
}: {
  playerRef?: RefObject<HTMLVideoElement | null>
  isHost?: boolean
  collaborativeControl?: boolean
  syncMode?: 'hopping' | 'dragging'
  onStruggle?: () => void
  onAutoplayBlocked?: () => void
} = {}) {
  const { socket } = useSocket()
  const { serverNow, clockReady } = useServerClock(socket)

  // Reference-counted, not a boolean: catch-up, source swaps, camera-toggle
  // guards, and ordinary corrections can overlap (e.g. a camera toggle guard
  // spans a window during which a buffer-aware catch-up also starts). A plain
  // boolean let one operation's release close the gate while another was still
  // mid-flight. Every hold (holdApplying / markApplying) increments; every
  // release (releaseApplying, or markApplying's own timeout) decrements — the
  // gate is only truly open again once the count returns to 0. `!applyingRef
  // .current` still reads correctly as "not applying" at 0 and "applying" at
  // any positive count, so no caller (Player.jsx included) needs to change.
  const applyingRef = useRef(0)
  const scheduleRef = useRef<any>(null)
  const userSeekRef = useRef(false)
  const userSeekTimer = useRef<number | null>(null)
  const hardSeeks = useRef<number[]>([])
  const lastHardSeekAt = useRef(0)
  const lastReport = useRef(0)
  const syncModeRef = useRef(syncMode)
  syncModeRef.current = syncMode
  // Last schedule.version this hook has applied, and the media generation it
  // was observed under. schedule.version is monotonic per party SESSION (never
  // reset by a media change), so a stale/duplicate/out-of-order sync:schedule
  // (replayed snapshot, reconnect race) can be detected and dropped by simply
  // requiring strictly-increasing versions. The baseline resets whenever
  // mediaGeneration changes, since that's the signal for "different media /
  // effectively a new timeline", not a version rollback.
  const lastAppliedVersionRef = useRef(-Infinity)
  const lastMediaGenRef = useRef<any>(undefined)
  // Local (non-shared) playback phase for this player: 'ready' during normal
  // operation, 'catchingUp' while bufferAwareSeek is chasing the live position
  // (video.pause() is an implementation detail of that routine, not a user
  // pause), 'buffering' while bufferAwarePausedSeek is loading the frozen
  // frame. Consumers should render "waiting" overlays from this instead of
  // media.paused, which can't tell a real pause from either of these.
  const [localPhase, setLocalPhase] = useState<'ready' | 'catchingUp' | 'buffering'>('ready')

  // Phase 12: a buffer-aware hard seek is in flight for this guest. While set,
  // the control loop early-returns so it can't stack corrections on top of an
  // in-progress HLS seek+buffer (the chase loop). mountedRef gates the async
  // routine's post-await steps so it aborts on unmount / media swap.
  const isSeekingRef = useRef(false)
  const mountedRef = useRef(true)

  const canControl = isHost || collaborativeControl

  // Self-releasing hold: bumps the count and schedules its own matching
  // decrement 150ms later. Independent per call — concurrent markApplying (or
  // markApplying overlapping a holdApplying) calls stack correctly instead of
  // one's timer wiping out another's still-active hold.
  function markApplying() {
    applyingRef.current += 1
    setTimeout(() => { applyingRef.current = Math.max(0, applyingRef.current - 1) }, 150)
  }

  // Hold the authoring guard open indefinitely across an event window that the
  // 150ms markApplying() timer is too short to cover — namely a source (quality
  // tier) swap, which fires a whole reload sequence (emptied → loadstart →
  // loadedmetadata → canplay) plus transient seeked/play/pause at position 0.
  // Every such event runs through the applyingRef check below, so while held no
  // bogus sync:seek/sync:play(0) can leak. Must be paired with exactly one
  // releaseApplying() call.
  function holdApplying() {
    applyingRef.current += 1
  }
  function releaseApplying() {
    applyingRef.current = Math.max(0, applyingRef.current - 1)
  }

  function notifyUserSeeking() {
    userSeekRef.current = true
    if (userSeekTimer.current != null) window.clearTimeout(userSeekTimer.current)
    userSeekTimer.current = window.setTimeout(() => { userSeekRef.current = false }, 3000)
  }

  function reportStall(stalled: boolean) {
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
  function kickHostPlay(video: HTMLVideoElement | null | undefined) {
    if (!video) return
    if (!(isHost && syncModeRef.current !== 'dragging'
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
  async function bufferAwareSeek(video: HTMLVideoElement | null | undefined) {
    if (!video) return
    if (isSeekingRef.current) return
    isSeekingRef.current = true
    holdApplying()
    setLocalPhase('catchingUp')
    const originSchedule = scheduleRef.current
    const originVersion = originSchedule?.version
    const originSource = video.currentSrc || video.src || null
    const stillCurrent = () => {
      const current = scheduleRef.current
      const sameSchedule = originVersion == null
        ? current === originSchedule
        : current?.version === originVersion
      return mountedRef.current && playerRef?.current === video && sameSchedule
        && (video.currentSrc || video.src || null) === originSource
    }
    try {
      if (!video.paused) video.pause()
      const predicted = predictPosition(originSchedule, serverNow())
      video.currentTime = predicted

      await waitForSeeked(video, SEEK_TIMEOUT_MS)
      if (!stillCurrent()) return
      await waitForBuffer(video, predicted, BUFFER_AHEAD_SEC, BUFFER_TIMEOUT_MS)
      if (!stillCurrent()) return

      // Re-read the live position ONCE now that seek+buffer has consumed some
      // wall time, and snap to it before resuming.
      if (clockReady()) {
        const live = predictPosition(originSchedule, serverNow())
        if (live >= 0) video.currentTime = selectBufferedResumeTarget(video, predicted, live)
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
      setLocalPhase('ready')
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
  async function bufferAwarePausedSeek(video: HTMLVideoElement | null | undefined) {
    if (!video) return
    if (isSeekingRef.current) return
    isSeekingRef.current = true
    holdApplying()
    setLocalPhase('buffering')
    // Same operation-identity guard as bufferAwareSeek: if the schedule moves
    // on (a play/seek/media-generation change) or the source swaps (quality
    // change) while we're mid-await, this stale operation must not keep
    // driving a video element / target that's no longer current.
    const originSchedule = scheduleRef.current
    const originVersion = originSchedule?.version
    const originSource = video.currentSrc || video.src || null
    const stillCurrent = () => {
      const current = scheduleRef.current
      const sameSchedule = originVersion == null
        ? current === originSchedule
        : current?.version === originVersion
      return mountedRef.current && playerRef?.current === video && sameSchedule
        && (video.currentSrc || video.src || null) === originSource
    }
    try {
      if (!video.paused) video.pause()
      video.playbackRate = 1
      const target = originSchedule.positionTicks / TICKS
      video.currentTime = target
      if (!isBuffered(video, target)) ensureHlsLoad(video as any, target)

      await waitForSeeked(video, SEEK_TIMEOUT_MS)
      if (!stillCurrent()) return
      await waitForBuffer(video, target, PAUSED_BUFFER_AHEAD_SEC, BUFFER_TIMEOUT_MS)
      // Intentionally NO play(): stay paused, just render the frozen frame.
    } finally {
      isSeekingRef.current = false
      releaseApplying()
      setLocalPhase('ready')
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
    function onSchedule(s: any) {
      // Reset the version baseline on a media-generation change (new media
      // selected, or back-to-lobby) — schedule.version keeps climbing across
      // generations within one party session, it does not restart at 0.
      const gen = s?.mediaGeneration
      if (gen !== lastMediaGenRef.current) {
        lastMediaGenRef.current = gen
        lastAppliedVersionRef.current = -Infinity
      }
      // Drop a stale/duplicate schedule (replayed snapshot, reconnect race,
      // out-of-order delivery on a future transport) — only ever move forward.
      if (s?.version != null) {
        if (s.version <= lastAppliedVersionRef.current) return
        lastAppliedVersionRef.current = s.version
      }

      scheduleRef.current = s
      userSeekRef.current = false
      if (userSeekTimer.current != null) window.clearTimeout(userSeekTimer.current)

      // A hopping host is exempt from the correction loop below (plays
      // natively, its own 'play' event is what authors the schedule) — but
      // party:selectMedia authors an immediately-"playing" schedule so muted
      // guests can autoplay right away, and nothing else ever starts the
      // host's own video. Left alone the host sits paused indefinitely while
      // everyone else plays. Kick it here (also re-tried idempotently in the
      // control loop in case the element hadn't mounted yet when this arrived).
      kickHostPlay(playerRef?.current ?? null)
    }
    function onHostGone() {
      const v = playerRef?.current ?? null
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
      const video = playerRef?.current ?? null
      if (!s || !video) return
      // A buffer-aware hard seek is in flight — do not correct or nudge on top
      // of it (that stacking is exactly the chase loop we're killing).
      if (isSeekingRef.current) return
      // A locally-authored play/pause/seek is in flight and hasn't round-tripped
      // to the server yet — scheduleRef is still stale. Without this guard a
      // controller's own pause gets raced by this loop, which still sees the
      // old "playing" schedule and calls video.play() right back, so pause
      // silently "doesn't stick" until the stale window happens to close.
      if (applyingRef.current) return

      // Idempotently (re)start a hopping host's own video. decideSyncAction
      // returns null for a hopping host, so this loop is the only place that
      // honors a 'playing' schedule which arrived before the media element was
      // ready (or that the host later paused out of band). No-op otherwise.
      kickHostPlay(video)

      const intent: any = decideSyncAction({
        schedule: s,
        serverNowMs: serverNow,
        clockReady,
        currentTime: video.currentTime,
        paused: video.paused,
        isHost,
        mode,
        userSeeking: userSeekRef.current,
        suppressHardSeek: Date.now() - lastHardSeekAt.current < HARD_SEEK_COOLDOWN_MS,
      })
      if (!intent) return

      // A guest's hard catch-up in hopping mode goes through the buffer-aware
      // routine (fire-and-forget; it sets isSeekingRef and suppresses the loop
      // until it settles). Every other correction — dragging-host gross-drift,
      // paused-hold, resume — keeps the original synchronous path unchanged.
      if (intent.hardSeek && !isHost && mode === 'hopping') {
        recordHardSeek()
        lastHardSeekAt.current = Date.now()
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

  function requestPlay(positionTicks: number) {
    if (!applyingRef.current && canControl) socket.emit('sync:play', { positionTicks, t0: serverNow() })
  }
  function requestPause(positionTicks: number) {
    if (!applyingRef.current && canControl) socket.emit('sync:pause', { positionTicks })
  }
  function requestSeek(positionTicks: number) {
    if (!applyingRef.current && canControl) socket.emit('sync:seek', { positionTicks, t0: serverNow() })
  }

  return {
    canControl, applyingRef, holdApplying, releaseApplying, notifyUserSeeking, reportStall,
    requestPlay, requestPause, requestSeek, TICKS_PER_SECOND: TICKS,
    // 'ready' | 'catchingUp' | 'buffering' — local playback phase, distinct
    // from shared intent. See the comment on the localPhase state above.
    localPhase,
  }
}
