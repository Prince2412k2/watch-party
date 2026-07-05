import { useEffect, useRef, useState } from 'react'
import { createPlayer } from '@videojs/react'
import { VideoSkin, videoFeatures } from '@videojs/react/video'
import { HlsVideo } from '@videojs/react/media/hls-video'
import '@videojs/react/video/skin.css'
import { useSyncPlay } from '../hooks/useSyncPlay.js'
import { useIsMobile, usePhone, useWideBar } from '../hooks/useIsMobile.js'
import { glass } from '../glass.jsx'
import { Z } from '../watchLayers.js'
import { createTransportIntent } from '../sync/transportIntent.js'
import { isBuffered } from '../sync/bufferSeek.js'
import { BUFFER_AHEAD_SEC } from '../sync/syncCore.js'

// Fullscreen is owned by WatchView (Party.jsx) via a single `immersive` state and
// an enterImmersive()/exitImmersive() pair that branches by platform capability
// (element FS today; iOS CSS faux-FS in Phase B). The controls here just render
// the enter/exit icon from `immersive` and call those callbacks — no per-device
// branching lives in the button path anymore.
const VPlayer = createPlayer({ features: videoFeatures })

export default function Player({
  hlsUrl, isHost, collaborativeControl, syncMode, onStruggle,
  onToggleMic, onToggleCam, micOn, camOn,
  talking, onTalkStart, onTalkEnd,
  onToggleLayout, onOpenChat, layoutMode,
  hideSelf, onToggleHideSelf,
  visible = true, immersive, enterImmersive, exitImmersive,
  phone = false, camStripOpen, onToggleCamStrip, seekBridgeRef,
}) {
  const canControl = isHost || collaborativeControl

  // A freshly-opened movie is authored as "playing" immediately (so muted
  // guests autoplay) but the host's own video needs a real .play() call —
  // if the browser blocks that unmuted (no fresh-enough gesture), useSyncPlay
  // forces it muted so playback still starts in sync, and flips this so we
  // can offer the host a one-tap way to restore sound. Lives here (not in
  // SyncBridge) because this is the component that owns the `muted` prop.
  const [hostMuted, setHostMuted] = useState(false)

  // Whether audio is muted, independent of playback-control permission — a
  // guest with no control rights must still be able to unmute and stay
  // unmuted. Everyone starts muted so autoplay (synced play()) isn't blocked
  // by the browser; the 'm' key / mute button flips this, not canControl.
  const [userMuted, setUserMuted] = useState(true)

  // Local (non-shared) playback phase from useSyncPlay, surfaced here so the
  // mobile transport button (owned by Player, not the hook) can tell a real
  // user pause apart from useSyncPlay's own catch-up/buffering pauses instead
  // of reading raw media.paused. Lifted out of SyncBridge because it's a
  // sibling of MobileBottomBar, not an ancestor.
  const [localPhase, setLocalPhase] = useState('ready')

  return (
    <VPlayer.Provider>
      {/* isolate so the skin's internal z-indexed layers don't paint over the
          camera tiles / chat that render as siblings of this player */}
      <div style={{ position: 'relative', width: '100%', height: '100%', background: '#000', isolation: 'isolate' }}>
        {/* Skin is interactive only for controllers; guests can't drive transport.
            On phones we hide the skin's own bottom control bar (watch-skin--nobar):
            the app's MobileBottomBar fully replaces it, and leaving it would peek
            out under the app bar (bug 7). Desktop controllers keep the skin's
            scrubber; guests get the read-only GuestTimeline below (bug 6). */}
        <VideoSkin className={phone ? 'watch-skin watch-skin--nobar' : 'watch-skin'} style={{ width: '100%', height: '100%', pointerEvents: canControl ? 'auto' : 'none' }}>
          {/* Everyone starts muted so synced play() autoplays without a gesture;
              `userMuted` (not canControl) governs mute state so guests can
              unmute and stay unmuted. Host forced muted only when
              autoplay-with-sound was blocked (see hostMuted above). */}
          <HlsVideo src={hlsUrl} playsInline preload="auto" muted={userMuted || hostMuted} style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
        </VideoSkin>

        {canControl && hostMuted && (
          <RestoreSoundPrompt onClick={() => setHostMuted(false)} />
        )}

        {/* Route all playback through SyncPlay + keyboard control */}
        <SyncBridge isHost={isHost} collaborativeControl={collaborativeControl} syncMode={syncMode} onStruggle={onStruggle}
          onOpenChat={onOpenChat} immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive} srcUrl={hlsUrl}
          seekBridgeRef={seekBridgeRef} onAutoplayBlocked={() => setHostMuted(true)}
          userMuted={userMuted} onToggleMuted={() => setUserMuted(m => !m)} onLocalPhase={setLocalPhase} />

        {userMuted && !hostMuted && (
          <UnmuteButton onClick={() => setUserMuted(false)} phone={phone} />
        )}

        {/* Desktop-only "Host controls playback" hint. On phones the same state
            is shown as a lock glyph inside the consolidated bottom bar. */}
        {!canControl && !phone && (
          <div style={{
            ...glass('light'),
            position: 'absolute', bottom: 150, left: '50%', transform: 'translateX(-50%)',
            zIndex: 20, display: 'flex', alignItems: 'center', gap: 7,
            padding: '7px 13px', borderRadius: 999, color: 'rgba(255,255,255,.75)',
            fontSize: 12.5, fontWeight: 600, pointerEvents: 'none',
            opacity: visible ? 1 : 0, transition: 'opacity .25s',
          }}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>
            Host controls playback
          </div>
        )}

        {phone ? (
          /* Phones: a single consolidated bottom bar — transport + call + settings
             + fullscreen — replacing the three floating desktop clusters. */
          <MobileBottomBar
            canControl={canControl} localPhase={localPhase}
            micOn={micOn} camOn={camOn}
            talking={talking} onTalkStart={onTalkStart} onTalkEnd={onTalkEnd}
            onToggleMic={onToggleMic} onToggleCam={onToggleCam}
            onToggleLayout={onToggleLayout} layoutMode={layoutMode}
            hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
            camStripOpen={camStripOpen} onToggleCamStrip={onToggleCamStrip}
            visible={visible} immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive}
          />
        ) : (
          <>
            {/* Guests can't drive the skin's scrubber, so give them a read-only
                timeline they can SEE (bug 6). Controllers use the skin's own. */}
            {!canControl && <GuestTimeline visible={visible} />}

            {/* Call controls (mic / cam / layout) — bottom-center */}
            <AVControls
              micOn={micOn} camOn={camOn}
              talking={talking}
              onToggleMic={onToggleMic} onToggleCam={onToggleCam}
              onToggleLayout={onToggleLayout} layoutMode={layoutMode}
              hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
              visible={visible}
            />

            {/* Playback controls (settings / fullscreen) — anchored above the timeline */}
            <TimelineControls visible={visible} immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive} />
          </>
        )}
      </div>
    </VPlayer.Provider>
  )
}

// ── Bridges the videojs Media instance into our SyncPlay protocol ────────────
function SyncBridge({ isHost, collaborativeControl, syncMode, onStruggle, onOpenChat, immersive, enterImmersive, exitImmersive, srcUrl, seekBridgeRef, onAutoplayBlocked, userMuted, onToggleMuted, onLocalPhase }) {
  const toggleFullscreen = () => (immersive ? exitImmersive?.() : enterImmersive?.())
  const media = VPlayer.useMedia()
  const mediaRef = useRef(null)
  mediaRef.current = media

  const {
    canControl, applyingRef, holdApplying, releaseApplying, notifyUserSeeking, reportStall,
    requestPlay, requestPause, requestSeek, localPhase,
    TICKS_PER_SECOND,
  } = useSyncPlay({ playerRef: mediaRef, isHost, collaborativeControl, syncMode, onStruggle, onAutoplayBlocked })

  // Surface localPhase to Player (MobileBottomBar's transport button needs it
  // and is a sibling of this component, not a descendant).
  useEffect(() => { onLocalPhase?.(localPhase) }, [localPhase, onLocalPhase])

  const seekTimer = useRef(null)
  const transportIntent = useRef(createTransportIntent())
  const [buffering, setBuffering] = useState(false)
  const [switchingQuality, setSwitchingQuality] = useState(false)

  // ── Imperative seek for the surface gesture layer (Party.jsx double-tap) ────
  // Driving media.currentTime here is the SAME authoring path as the keyboard
  // j/l seek and the scrubber drag: it fires a 'seeked' event, and the onSeeked
  // handler below emits requestSeek → the host-authority schedule is re-authored
  // and every guest follows. This is deliberately NOT a bare, sync-bypassing
  // currentTime write. Gated to controllers (host, or a guest under
  // collaborativeControl); the WatchView caller also gates, so guests never seek.
  useEffect(() => {
    if (!seekBridgeRef) return
    seekBridgeRef.current = {
      canControl,
      seekBy: (delta) => {
        const m = mediaRef.current
        if (!m || !canControl) return
        const dur = m.duration
        let t = (m.currentTime || 0) + delta
        if (t < 0) t = 0
        if (Number.isFinite(dur) && dur > 0 && t > dur - 0.5) t = dur - 0.5
        holdApplying()
        m.currentTime = t
        requestSeek(Math.round(t * TICKS_PER_SECOND))
        setTimeout(releaseApplying, 250)
      },
      // ── Bug 2: camera/mic toggle guard ──────────────────────────────────────
      // Enabling/disabling the camera or mic drives getUserMedia, which on some
      // platforms briefly reconfigures the media pipeline and can emit a spurious
      // 'pause' on the movie element. Left alone, SyncBridge's onPause would author
      // that as a shared requestPause → everyone pauses. Hold the SAME authoring
      // guard the quality-swap path uses (holdApplying/releaseApplying — exposed by
      // useSyncPlay; we do NOT touch the sync engine) across the whole toggle, then
      // undo any spurious local pause of a movie that was playing. Net effect:
      // toggling the camera/mic never touches playback, locally or for the room.
      guardToggle: async (fn) => {
        const before = mediaRef.current
        const wasPlaying = before ? !before.paused : false
        holdApplying()
        try { await fn?.() } catch {}
        // Let any device-(re)acquisition pause/play events settle.
        await new Promise(r => setTimeout(r, 400))
        const m = mediaRef.current
        if (m && wasPlaying && m.paused) { try { await m.play() } catch {} }
        releaseApplying()
      },
    }
    return () => { seekBridgeRef.current = null }
  }, [seekBridgeRef, canControl, holdApplying, releaseApplying, requestSeek, TICKS_PER_SECOND])

  // ── Quality-tier / source swap: preserve position across the reload ──────
  // Changing quality fetches a new transcode URL, which swaps <HlsVideo src>.
  // A src swap tears down and rebuilds the stream from position 0, firing a
  // full reload sequence (emptied → loadstart → loadedmetadata → canplay) plus
  // transient seeked/play/pause events at 0. Without intervention that (a)
  // restarts the movie and (b) leaks a bogus sync:seek(0) from the event
  // handlers below. We capture the pre-swap position/paused state, hold the
  // authoring guard across the whole reload window, restore currentTime once
  // the new source has metadata, and only then re-author (controllers) or
  // release (guests) so the control loop reconverges.
  //
  // Scoped to the src-swap path only; Phase 1.2's master-playlist ABR switches
  // levels inside hls.js without changing src, so this effect won't fire there.
  const firstSrc = useRef(true)
  useEffect(() => {
    const m = mediaRef.current
    if (!m || !srcUrl) return
    // Skip the initial mount — there is no prior position to preserve, and the
    // first load must be authored/converged through the normal path.
    if (firstSrc.current) { firstSrc.current = false; return }

    const resumeTime = m.currentTime || 0
    const wasPaused = m.paused
    setSwitchingQuality(true)
    holdApplying()   // suppress schedule authoring for the entire reload

    let done = false
    const finish = () => {
      if (done) return
      done = true
      m.removeEventListener('loadedmetadata', onReady)
      m.removeEventListener('loadeddata', onReady)
      // Restore local playback position + play/pause state on the new source.
      // These mutations fire their own seeked/play/pause events shortly after;
      // the guard stays held here so those don't author, then is released.
      try { if (Math.abs((m.currentTime || 0) - resumeTime) > 0.25) m.currentTime = resumeTime } catch {}
      if (!wasPaused) m.play().catch(() => {})
      else m.pause()

      if (canControl) {
        // Controller: re-author the shared schedule at the RESTORED position so
        // guests follow across the switch (never 0). Briefly release just to let
        // the request emit pass the guard, then re-hold so the restore's own
        // seeked/play don't double-author; a short timer clears it once settled.
        const ticks = Math.round(resumeTime * TICKS_PER_SECOND)
        releaseApplying()
        if (wasPaused) requestPause(ticks)
        else { requestSeek(ticks); requestPlay(ticks) }
        holdApplying()
        setTimeout(releaseApplying, 400)
      } else {
        // Guest local quality change: purely local. Do NOT author the shared
        // schedule — swallow the restore's transient events, then release so the
        // control loop re-snaps this client to the live timeline.
        setTimeout(releaseApplying, 400)
      }
      setSwitchingQuality(false)
    }
    const onReady = () => finish()
    m.addEventListener('loadedmetadata', onReady)
    m.addEventListener('loadeddata', onReady)
    // Safety net: never leave the guard held / overlay stuck if events don't fire.
    const guardTimer = setTimeout(finish, 8000)
    return () => {
      clearTimeout(guardTimer)
      m.removeEventListener('loadedmetadata', onReady)
      m.removeEventListener('loadeddata', onReady)
      if (!done) releaseApplying()
    }
  }, [srcUrl]) // eslint-disable-line

  // ── Keyboard controls ──────────────────────────────────────────────────
  // Transport keys author commands directly. Media events are observations;
  // browser stalls and pipeline reconfiguration must never become room intent.
  // Volume / mute / fullscreen / chat are local and available to everyone.
  useEffect(() => {
    const ticks = (m) => Math.round((m.currentTime || 0) * TICKS_PER_SECOND)
    const play = (m) => { requestPlay(ticks(m)); holdApplying(); m.play().catch(() => {}); setTimeout(releaseApplying, 250) }
    const pause = (m) => { requestPause(ticks(m)); holdApplying(); m.pause(); setTimeout(releaseApplying, 250) }
    const seek = (m, time) => {
      const dur = m.duration
      const max = Number.isFinite(dur) && dur > 0 ? Math.max(0, dur - 0.5) : Infinity
      const target = Math.min(max, Math.max(0, time))
      requestSeek(Math.round(target * TICKS_PER_SECOND))
      holdApplying(); m.currentTime = target; setTimeout(releaseApplying, 250)
    }
    function onKey(e) {
      const t = e.target
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return
      const m = mediaRef.current
      const k = e.key.toLowerCase()
      // Ctrl/Cmd+F → fullscreen (also plain 'f' below)
      if (k === 'f' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); toggleFullscreen(); return }
      if (e.ctrlKey || e.metaKey || e.altKey) return
      const transport = () => { if (!m || !canControl) return false; return true }
      switch (k) {
        case ' ': case 'k':
          if (!transport()) return; e.preventDefault(); m.paused ? play(m) : pause(m); break
        case 'arrowright':
          if (!transport()) return; e.preventDefault(); seek(m, (m.currentTime || 0) + 5); break
        case 'arrowleft':
          if (!transport()) return; e.preventDefault(); seek(m, (m.currentTime || 0) - 5); break
        case 'l': if (transport()) seek(m, (m.currentTime || 0) + 10); break
        case 'j': if (transport()) seek(m, (m.currentTime || 0) - 10); break
        case 'arrowup': if (m) { e.preventDefault(); m.volume = Math.min(1, (m.volume ?? 1) + 0.1); m.muted = false } break
        case 'arrowdown': if (m) { e.preventDefault(); m.volume = Math.max(0, (m.volume ?? 1) - 0.1) } break
        case 'm': onToggleMuted?.(); break
        case 'f': toggleFullscreen(); break
        case 'c': e.preventDefault(); onOpenChat?.(); break
        default: return
      }
      // We handled it — stop the skin's built-in shortcut from also firing
      // (otherwise its space/arrow handler double-toggles and cancels ours).
      e.stopPropagation()
    }
    // Capture phase so we run before the vidstack skin's own key handler.
    window.addEventListener('keydown', onKey, true)
    const onCommand = (e) => {
      const m = mediaRef.current
      if (!m || !canControl) return
      if (e.detail?.kind === 'play') play(m)
      else if (e.detail?.kind === 'pause') pause(m)
      else if (e.detail?.kind === 'seek') seek(m, e.detail.time)
    }
    window.addEventListener('watch:transport', onCommand)
    return () => {
      window.removeEventListener('keydown', onKey, true)
      window.removeEventListener('watch:transport', onCommand)
    }
  }, [canControl, onOpenChat, onToggleMuted, immersive, enterImmersive, exitImmersive, requestPlay, requestPause, requestSeek, holdApplying, releaseApplying, TICKS_PER_SECOND])

  // The desktop skin is third-party UI, so mark its pointer gestures before its
  // media mutations occur. Only the next matching event may author a command.
  useEffect(() => {
    if (!canControl) return
    const onPointerDown = (e) => {
      if (e.target?.closest?.('.watch-skin')) transportIntent.current.arm('*')
    }
    document.addEventListener('pointerdown', onPointerDown, true)
    return () => document.removeEventListener('pointerdown', onPointerDown, true)
  }, [canControl])

  // "Catching up…" for guests reflects a real stall only. We turn it on when the
  // player actually stalls ('waiting') and clear it as soon as the frame is
  // ready again — a plain seek while playing must NOT leave the overlay stuck.
  // 'seeked'/'canplay' are essential for the PAUSED case: while paused neither
  // 'playing' nor 'timeupdate' ever fires, so without them a paused guest that
  // seeks to the frozen position would sit on the spinner forever, covering the
  // frame it just loaded.
  useEffect(() => {
    if (!media || isHost) return
    const on = () => setBuffering(true)
    const off = () => setBuffering(false)
    media.addEventListener('waiting', on)
    media.addEventListener('stalled', on)
    media.addEventListener('playing', off)
    media.addEventListener('timeupdate', off)
    media.addEventListener('seeked', off)
    media.addEventListener('canplay', off)
    return () => {
      media.removeEventListener('waiting', on)
      media.removeEventListener('stalled', on)
      media.removeEventListener('playing', off)
      media.removeEventListener('timeupdate', off)
      media.removeEventListener('seeked', off)
      media.removeEventListener('canplay', off)
    }
  }, [media, isHost])

  // Dragging mode: report our buffering state so the group waits for us.
  // Readiness is measured directly off buffered runway ahead of the current
  // position (the same isBuffered() check bufferSeek.js's catch-up routines
  // use), not inferred from 'canplaythrough' (unreliable on adaptive HLS,
  // which may never fire it) or 'playing' (only proves playback started, not
  // that there's enough runway left to keep it going). Polled on a timer plus
  // the events that can plausibly change the answer, since there's no single
  // reliable "buffer changed" DOM event across engines.
  useEffect(() => {
    if (!media || syncMode !== 'dragging') return
    let stalled = false
    const set = (v) => { if (stalled !== v) { stalled = v; reportStall(v) } }
    const check = () => {
      const t = media.currentTime || 0
      const ready = isBuffered(media, t) && isBuffered(media, t + BUFFER_AHEAD_SEC)
      set(!ready)
    }
    check()
    const poll = setInterval(check, 250)
    media.addEventListener('waiting', check)
    media.addEventListener('stalled', check)
    media.addEventListener('playing', check)
    media.addEventListener('timeupdate', check)
    media.addEventListener('progress', check)
    return () => {
      clearInterval(poll)
      if (stalled) reportStall(false)   // don't leave the group frozen on unmount
      media.removeEventListener('waiting', check)
      media.removeEventListener('stalled', check)
      media.removeEventListener('playing', check)
      media.removeEventListener('timeupdate', check)
      media.removeEventListener('progress', check)
    }
  }, [media, syncMode, reportStall])

  // Translate only explicitly armed desktop-skin gestures into requests.
  // Unarmed media events (buffering, catch-up, device/source changes) are
  // observations and can never alter shared playback intent.
  useEffect(() => {
    if (!media) return
    const ticks = () => Math.round((media.currentTime || 0) * TICKS_PER_SECOND)

    const explicit = (kind) => !applyingRef.current && canControl && transportIntent.current.consume(kind)
    const onPlay   = () => { if (explicit('play')) requestPlay(ticks()) }
    const onPause  = () => { if (explicit('pause')) requestPause(ticks()) }
    // Scrub start → tell the loop to stop correcting so it doesn't snap us back.
    const onSeeking = () => { if (!applyingRef.current && canControl) notifyUserSeeking() }
    // A scrubber drag fires many 'seeked' events — author only the settled one.
    // consume() burns the arm token on the FIRST matching event, so once a
    // debounce window is already pending (from that first authorized event)
    // later 'seeked' events in the same drag must still restart the timer even
    // though the token is gone — otherwise the request fires at whatever
    // position the drag happened to be at 200ms in, not where it settled.
    const onSeeked = () => {
      const pending = seekTimer.current != null
      if (!pending && !explicit('seek')) return
      clearTimeout(seekTimer.current)
      seekTimer.current = setTimeout(() => { seekTimer.current = null; requestSeek(ticks()) }, 200)
    }

    media.addEventListener('play', onPlay)
    media.addEventListener('pause', onPause)
    media.addEventListener('seeking', onSeeking)
    media.addEventListener('seeked', onSeeked)
    return () => {
      clearTimeout(seekTimer.current)
      media.removeEventListener('play', onPlay)
      media.removeEventListener('pause', onPause)
      media.removeEventListener('seeking', onSeeking)
      media.removeEventListener('seeked', onSeeked)
    }
  }, [media, canControl, applyingRef, notifyUserSeeking, requestPlay, requestPause, requestSeek, TICKS_PER_SECOND])

  if (!buffering && !switchingQuality) return null
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 25, display: 'grid', placeItems: 'center',
      background: 'rgba(6,8,15,.55)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
        <div style={{
          width: 44, height: 44, borderRadius: '50%',
          border: '3px solid var(--stroke2)', borderTopColor: 'var(--accent)',
          animation: 'spin .9s linear infinite',
        }} />
        <span style={{ fontSize: 14, fontWeight: 600, color: 'var(--text)' }}>{switchingQuality ? 'Switching quality…' : 'Catching up…'}</span>
      </div>
    </div>
  )
}

// ── Separate liquid-glass control buttons: media group ‖ call group ──────────
function GBtn({ onClick, title, active, danger, children }) {
  return (
    // stopPropagation so a mic/cam/hide/layout click is self-contained and can
    // never reach the surface tap / any video gesture layer (bug 2 hardening).
    <button onClick={(e) => { e.stopPropagation(); onClick?.(e) }} title={title} style={{
      ...glass('light'), width: 48, height: 48, borderRadius: 16, display: 'grid', placeItems: 'center',
      cursor: 'pointer', color: danger ? '#FF6B6B' : '#fff',
      ...(active ? { backgroundColor: 'rgba(255,255,255,.26)' } : {}),
      transition: 'background-color .15s, transform .12s',
    }}
      onMouseDown={e => e.currentTarget.style.transform = 'scale(.94)'}
      onMouseUp={e => e.currentTarget.style.transform = 'scale(1)'}
      onMouseLeave={e => e.currentTarget.style.transform = 'scale(1)'}>
      {children}
    </button>
  )
}

// Call controls only (mic / cam / layout). Playback (volume, seek, fullscreen)
// lives in the video timeline; sound was removed to de-dup with it.
function AVControls({ micOn, camOn, talking, onToggleMic, onToggleCam, onToggleLayout, layoutMode, hideSelf, onToggleHideSelf, visible }) {
  const mobile = useIsMobile()
  return (
    <div style={{
      position: 'absolute', bottom: mobile ? 80 : 92, left: '50%', transform: 'translateX(-50%)', zIndex: 18,
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
      opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s',
    }}>
      {/* Talking indicator ↔ hold-to-talk hint (see PTTHint) */}
      <PTTHint talking={talking} muted={!micOn} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      {/* Mic button reflects three states: muted (danger), unmuted (default),
          and actively talking via PTT (active highlight, mic-open icon). */}
      <GBtn onClick={onToggleMic} title={micOn ? 'Mute mic' : 'Unmute mic'} danger={!micOn} active={talking}>
        {micOn
          ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
          : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V5a3 3 0 0 0-5.7-1.3M19 10v2a7 7 0 0 1-.7 3M12 19v3"/></svg>}
      </GBtn>
      <GBtn onClick={onToggleCam} title={camOn ? 'Camera off' : 'Camera on'} danger={!camOn}>
        {camOn
          ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="2" y="6" width="14" height="12" rx="2"/><path d="m16 10 6-3v10l-6-3"/></svg>
          : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M16 16H4a2 2 0 0 1-2-2V8m4-2h8a2 2 0 0 1 2 2v3l4-2v8"/></svg>}
      </GBtn>
      {/* Hide self-view: purely local — camera keeps publishing, we just drop our
          own tile. Kept here (not on the tile) so it stays reachable to re-show. */}
      {onToggleHideSelf && (
        <GBtn onClick={onToggleHideSelf} active={hideSelf} title={hideSelf ? 'Show my camera to me' : 'Hide my camera from me'}>
          {hideSelf
            ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4"/></svg>
            : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>}
        </GBtn>
      )}
      <GBtn onClick={onToggleLayout} title="Camera layout">
        {layoutMode === 'float'
          ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="3" y="3" width="18" height="18" rx="2"/><rect x="13" y="12" width="6" height="6" rx="1" fill="currentColor" stroke="none"/></svg>
          : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="3" y="3" width="6" height="18" rx="1.5"/><rect x="11" y="3" width="10" height="18" rx="1.5"/></svg>}
      </GBtn>
      </div>
    </div>
  )
}

// Small glass affordance sitting just above the desktop AV controls. When idle
// it advertises the shortcut ("Hold T to talk"); while a PTT hold is active it
// flips to a live "Talking…" state with a pulsing green dot. Hidden when the
// user has manually unmuted (nothing to advertise — they're already live).
// Shown to the host only, only when autoplay-with-sound was blocked and
// playback was forced muted to start in sync. One tap restores audio — safe
// because a click handler is itself a fresh user gesture.
function RestoreSoundPrompt({ onClick }) {
  return (
    <button onClick={onClick} style={{
      ...glass('clear'), position: 'absolute', top: 16, left: '50%', transform: 'translateX(-50%)',
      zIndex: Z.controlBar, display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '8px 14px', borderRadius: 999, fontSize: 13, fontWeight: 600,
      color: '#fff', cursor: 'pointer', border: '1px solid rgba(255,255,255,.22)',
    }}>
      🔇 Tap for sound
    </button>
  )
}

// Guests (no playback control) get a dedicated unmute affordance, since they
// have no other way to enable audio — audio is independent of control rights.
function UnmuteButton({ onClick, phone }) {
  return (
    <button onClick={onClick} style={{
      ...glass('clear'), position: 'absolute', top: 16, left: '50%', transform: 'translateX(-50%)',
      zIndex: Z.controlBar, display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '8px 14px', borderRadius: 999, fontSize: 13, fontWeight: 600,
      color: '#fff', cursor: 'pointer', border: '1px solid rgba(255,255,255,.22)',
    }}>
      🔇 Tap for sound
    </button>
  )
}

function PTTHint({ talking, muted }) {
  if (!talking && !muted) return null
  return (
    <div style={{
      ...glass('clear'), display: 'inline-flex', alignItems: 'center', gap: 7,
      padding: '5px 11px', borderRadius: 999, fontSize: 12, fontWeight: 600,
      color: talking ? '#7CFFB2' : 'rgba(255,255,255,.72)',
      border: talking ? '1px solid rgba(124,255,178,.4)' : undefined,
      transition: 'color .15s',
    }}>
      {talking ? (
        <>
          <span style={{ width: 7, height: 7, borderRadius: '50%', background: '#3ddc84', animation: 'pulse 1.2s ease-in-out infinite' }} />
          Talking…
        </>
      ) : (
        <>
          <kbd style={{
            fontFamily: 'inherit', fontSize: 11, fontWeight: 700, lineHeight: 1,
            padding: '2px 6px', borderRadius: 5, background: 'rgba(255,255,255,.14)',
            border: '1px solid rgba(255,255,255,.22)',
          }}>T</kbd>
          Hold to talk
        </>
      )}
    </div>
  )
}

// ── ABR level control via hls.js (Phase 1.2) ────────────────────────────────
// @videojs/react's HlsVideo builds an `HlsMedia` whose `.engine` getter returns
// the live hls.js `Hls` instance (verified in @videojs/core dom/media/hls). We
// read the real variant ladder off `hls.levels` and drive selection there:
//   • Auto   → hls.currentLevel = -1 (autoLevelEnabled): hls.js adapts by
//              bandwidth on the SAME loaded stream — no src swap, no reload.
//   • Manual → hls.nextLevel = i: an instant cap applied at the next segment
//              boundary, again on the same stream (no re-transcode / reload).
// This is entirely local to each client, so guests may sit on different rungs
// than the host — bitrate is per-client, transport (play/pause/seek) is shared.
function useQualityLevels(media) {
  const [levels, setLevels] = useState([])       // hls.levels snapshot
  const [current, setCurrent] = useState(-1)     // active level index (-1 = none yet)
  const [selected, setSelected] = useState(-1)   // user choice; -1 = Auto

  useEffect(() => {
    if (!media) return
    let hls = null
    let poll = null
    const sync = () => {
      if (!hls) return
      setLevels(hls.levels || [])
      // hls.currentLevel is the actual playing level; -1 while unknown.
      setCurrent(typeof hls.currentLevel === 'number' ? hls.currentLevel : -1)
      // Reflect external auto/manual state (autoLevelEnabled true → Auto).
      setSelected(hls.autoLevelEnabled === false ? hls.nextLevel : -1)
    }
    // Level list appears at MANIFEST_PARSED; current level changes fire
    // LEVEL_SWITCHED; LEVELS_UPDATED covers ladder edits. Event names are
    // hls.js string constants ('hlsManifestParsed', etc.).
    const evs = ['hlsManifestParsed', 'hlsLevelSwitched', 'hlsLevelsUpdated', 'hlsLevelSwitching']
    const attach = () => {
      hls = media.engine
      if (!hls) return false
      evs.forEach(e => hls.on(e, sync))
      sync()
      return true
    }
    // The engine is created in HlsJsMedia's constructor during load(); it's
    // normally present as soon as `media` is, but poll briefly in case not.
    if (!attach()) poll = setInterval(() => { if (attach()) clearInterval(poll) }, 100)
    return () => {
      if (poll) clearInterval(poll)
      if (hls) evs.forEach(e => { try { hls.off(e, sync) } catch {} })
    }
  }, [media])

  const choose = (i) => {
    const hls = media?.engine
    if (!hls) return
    setSelected(i)
    if (i === -1) {
      hls.currentLevel = -1        // re-enable auto ABR (adapts by bandwidth)
    } else {
      hls.nextLevel = i            // instant cap at next segment boundary
    }
  }

  return { levels, current, selected, choose }
}

function levelLabel(l) {
  if (!l) return ''
  const h = l.height ? `${l.height}p` : (l.width ? `${l.width}w` : '')
  const mbps = l.bitrate ? `${(l.bitrate / 1_000_000).toFixed(1)} Mbps` : ''
  return [h, mbps].filter(Boolean).join(' · ') || 'Auto'
}

// ── Read-only playback timeline (bug 6) ──────────────────────────────────────
// Guests must SEE the shared position/duration/progress even though they can't
// scrub. The vidstack skin's own scrubber only reveals on pointer activity, which
// the guest `pointerEvents:none` suppresses — so guests never saw it. This is a
// pure-display timeline (no seek handlers) shown to non-controllers on desktop,
// and embedded in the phone bar (where the skin's bar is hidden) for everyone.
function useMediaClock(media) {
  const [c, setC] = useState({ cur: 0, dur: 0, buf: 0 })
  useEffect(() => {
    if (!media) return
    const sync = () => {
      let buf = 0
      try { const b = media.buffered; if (b && b.length) buf = b.end(b.length - 1) } catch {}
      setC({ cur: media.currentTime || 0, dur: media.duration || 0, buf })
    }
    sync()
    const evs = ['timeupdate', 'durationchange', 'progress', 'seeked', 'loadedmetadata']
    evs.forEach(e => media.addEventListener(e, sync))
    return () => evs.forEach(e => media.removeEventListener(e, sync))
  }, [media])
  return c
}

function fmtClock(s) {
  if (!Number.isFinite(s) || s < 0) s = 0
  s = Math.floor(s)
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
  const mm = h > 0 ? String(m).padStart(2, '0') : String(m)
  return `${h > 0 ? `${h}:` : ''}${mm}:${String(sec).padStart(2, '0')}`
}

// The timeline row: current time · progress (played + buffered) · duration.
function TimelineTrack() {
  const media = VPlayer.useMedia()
  const { cur, dur, buf } = useMediaClock(media)
  const pct = dur > 0 ? Math.min(100, (cur / dur) * 100) : 0
  const bufPct = dur > 0 ? Math.min(100, (buf / dur) * 100) : 0
  const time = { fontSize: 11.5, fontVariantNumeric: 'tabular-nums', flexShrink: 0 }
  return (
    <div aria-label="Playback progress" style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%' }}>
      <span style={{ ...time, minWidth: 40, textAlign: 'right', color: 'rgba(255,255,255,.78)' }}>{fmtClock(cur)}</span>
      <div style={{ position: 'relative', flex: 1, height: 4, borderRadius: 999, background: 'rgba(255,255,255,.2)', overflow: 'hidden' }}>
        <div style={{ position: 'absolute', top: 0, bottom: 0, left: 0, width: `${bufPct}%`, background: 'rgba(255,255,255,.3)' }} />
        <div style={{ position: 'absolute', top: 0, bottom: 0, left: 0, width: `${pct}%`, background: '#EDEFF2' }} />
      </div>
      <span style={{ ...time, minWidth: 40, color: 'rgba(255,255,255,.5)' }}>{fmtClock(dur)}</span>
    </div>
  )
}

// Desktop read-only timeline for guests: a floating glass bar pinned to the
// bottom, clear of the AV cluster + settings gear. Fades with the chrome.
function GuestTimeline({ visible }) {
  return (
    <div style={{
      position: 'absolute', left: 16, right: 16, bottom: 16, zIndex: 17,
      ...glass('clear'), borderRadius: 12, padding: '9px 16px',
      opacity: visible ? 1 : 0, pointerEvents: 'none', transition: 'opacity .25s',
    }}>
      <TimelineTrack />
    </div>
  )
}

// Settings + fullscreen — anchored bottom-right, ABOVE the video timeline row
// (bug 7: the vidstack control bar sits at bottom:0.5rem, so a bottom:14 gear
// landed on top of it). The FS button reads the single `immersive` state and
// calls the enter/exit callbacks owned by WatchView; no per-device branching here.
function TimelineControls({ visible, immersive, enterImmersive, exitImmersive }) {
  const media = VPlayer.useMedia()
  const quality = useQualityLevels(media)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const smallBtn = {
    width: 40, height: 40, borderRadius: 12, border: 'none', cursor: 'pointer', display: 'grid', placeItems: 'center',
    background: 'transparent', color: '#fff', transition: 'background .15s',
  }
  return (
    <div style={{
      position: 'absolute', right: 14, bottom: 68, zIndex: 19, display: 'flex', alignItems: 'center', gap: 2,
      ...glass('clear'), borderRadius: 14, padding: 3,
      opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s',
    }}>
      <div style={{ position: 'relative' }}>
        <button onClick={() => setSettingsOpen(o => !o)} title="Settings" style={{ ...smallBtn, background: settingsOpen ? 'rgba(255,255,255,.18)' : 'transparent' }}>
          <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
        </button>
        {settingsOpen && <SettingsMenu media={media} quality={quality} onClose={() => setSettingsOpen(false)} />}
      </div>
      <button onClick={() => (immersive ? exitImmersive?.() : enterImmersive?.())} title={immersive ? 'Exit full screen (Ctrl+F)' : 'Full screen (Ctrl+F)'} style={smallBtn}>
        {immersive
          ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M8 3v4a1 1 0 0 1-1 1H3M21 8h-4a1 1 0 0 1-1-1V3M16 21v-4a1 1 0 0 1 1-1h4M3 16h4a1 1 0 0 1 1 1v4"/></svg>
          : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M3 8V5a2 2 0 0 1 2-2h3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M21 16v3a2 2 0 0 1-2 2h-3"/></svg>}
      </button>
    </div>
  )
}

// ── Mobile consolidated bottom bar ───────────────────────────────────────────
// One glass bar pinned to the bottom (clear of the home-indicator via safe-area).
// It carries a PRIMARY cluster that is always one tap away — transport
// (host-only play/pause, or a lock glyph for guests), mic, cam, and fullscreen —
// plus the SECONDARY controls (push-to-talk, hide-self, camera-strip toggle,
// quality/settings). On short/narrow phones (< 820px, see `useWideBar`) the
// secondary set collapses behind a "⋯" overflow popover so nothing clips or
// horizontally scrolls at e.g. 740×360; on roomy phones (≥ 820px, e.g. 844-wide
// landscape) they inline back into the bar. Fullscreen is NEVER in the overflow.
// Fades with the auto-hide `visible` layer. Touch targets are 44px with ≥8px gaps.
function MobileBottomBar({
  canControl, localPhase, micOn, camOn, talking, onTalkStart, onTalkEnd, onToggleMic, onToggleCam, onToggleLayout, layoutMode,
  hideSelf, onToggleHideSelf, camStripOpen, onToggleCamStrip, visible, immersive, enterImmersive, exitImmersive,
}) {
  const media = VPlayer.useMedia()
  const quality = useQualityLevels(media)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [moreOpen, setMoreOpen] = useState(false)
  const [paused, setPaused] = useState(true)
  const wide = useWideBar()
  const barRef = useRef(null)

  // Reflect real play/pause state on the transport button — but only while
  // localPhase is 'ready'. useSyncPlay pauses the element itself as an
  // implementation detail of hard-seek catch-up ('catchingUp') and the
  // paused-frozen-frame load ('buffering'); without this guard those would
  // flip the button to a "Play" glyph even though shared intent is still
  // "playing", and tapping it would author a spurious requestPlay.
  useEffect(() => {
    if (!media) return
    const sync = () => setPaused(!!media.paused && localPhase === 'ready')
    sync()
    media.addEventListener('play', sync)
    media.addEventListener('pause', sync)
    return () => { media.removeEventListener('play', sync); media.removeEventListener('pause', sync) }
  }, [media, localPhase])

  // Publish the real (measured) bar height so the camera strip can clear it
  // exactly — no hard-coded offset that drifts if the bar's contents change.
  useEffect(() => {
    const el = barRef.current
    if (!el) return
    const publish = () => document.documentElement.style.setProperty('--watch-bar-h', `${el.offsetHeight}px`)
    publish()
    const ro = new ResizeObserver(publish)
    ro.observe(el)
    return () => { ro.disconnect(); document.documentElement.style.removeProperty('--watch-bar-h') }
  }, [])

  // Roomy phones inline everything — close any open overflow so it can't linger.
  useEffect(() => { if (wide) setMoreOpen(false) }, [wide])

  const togglePlay = () => {
    if (!media || !canControl) return
    // Use the same localPhase-aware `paused` the button renders from, not raw
    // media.paused, so tapping the button during a catch-up/buffering pause
    // sends 'pause' (matching what the button visually shows) rather than a
    // redundant/confusing 'play'.
    window.dispatchEvent(new CustomEvent('watch:transport', { detail: { kind: paused ? 'play' : 'pause' } }))
  }
  const closeMore = () => setMoreOpen(false)

  // Secondary controls — identical wiring whether inlined (wide) or in the
  // overflow popover (narrow). Tap-actions (hide-self, camera strip) also close
  // the popover on selection; talk (press-and-hold) and settings (opens a
  // submenu) keep it open.
  const talkControl = <TalkBtn key="talk" talking={talking} onStart={onTalkStart} onStop={onTalkEnd} />
  const hideSelfControl = onToggleHideSelf ? (
    <BarBtn key="hide" onClick={() => { onToggleHideSelf(); closeMore() }} active={hideSelf} title={hideSelf ? 'Show my camera to me' : 'Hide my camera from me'}>
      {hideSelf
        ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4"/></svg>
        : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>}
    </BarBtn>
  ) : null
  const camStripControl = (
    <BarBtn key="camstrip" onClick={() => { onToggleCamStrip?.(); closeMore() }} active={camStripOpen} title={camStripOpen ? 'Hide cameras' : 'Show cameras'}>
      {camStripOpen
        ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="3" y="8" width="5" height="8" rx="1"/><rect x="9.5" y="8" width="5" height="8" rx="1"/><rect x="16" y="8" width="5" height="8" rx="1"/></svg>
        : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M3 8h1m4.5 0H14m2 0h5v8h-1M3 8v8h9"/></svg>}
    </BarBtn>
  )
  const settingsControl = (
    <div key="settings" style={{ position: 'relative' }}>
      <BarBtn onClick={() => setSettingsOpen(o => !o)} active={settingsOpen} title="Settings">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
      </BarBtn>
      {settingsOpen && <SettingsMenu media={media} quality={quality} onClose={() => setSettingsOpen(false)} />}
    </div>
  )
  const secondary = [talkControl, hideSelfControl, camStripControl, settingsControl].filter(Boolean)

  return (
    <div style={{
      position: 'absolute', zIndex: Z.controlBar,
      left: 'calc(var(--sa-l) + 8px)', right: 'calc(var(--sa-r) + 8px)',
      bottom: 'calc(var(--sa-b) + 8px)',
      opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s',
    }}>
      {/* Bottom scrim (G5 / icon-contrast): a soft dark gradient rising behind the
          bar so white glyphs hold ≥3:1 contrast even over a bright video frame —
          the glass tint alone is only ~30% opaque and lets bright frames bleed
          through. On-brand and light-touch (fades to nothing above the bar). */}
      <div aria-hidden style={{
        position: 'absolute', left: -8, right: -8, bottom: -8, top: -48,
        background: 'linear-gradient(180deg, rgba(0,0,0,0) 0%, rgba(0,0,0,.28) 60%, rgba(0,0,0,.42) 100%)',
        borderRadius: 24, pointerEvents: 'none',
      }} />
      <div ref={barRef} style={{
        position: 'relative',
        ...glass('medium'), borderRadius: 18, padding: '6px 8px',
        display: 'flex', flexDirection: 'column', gap: 6,
      }}>
        {/* Read-only timeline row (bug 6): everyone on a phone sees position /
            progress / duration here. The skin's own scrubber is hidden on phones
            (watch-skin--nobar); controllers still scrub via double-tap-seek. */}
        <div style={{ padding: '2px 6px 0' }}><TimelineTrack /></div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'space-between' }}>
        {/* Transport: play/pause for controllers, lock glyph for guests */}
        {canControl ? (
          <BarBtn onClick={togglePlay} title={paused ? 'Play' : 'Pause'} primary>
            {paused
              ? <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
              : <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>}
          </BarBtn>
        ) : (
          <div title="Host controls playback" style={{
            width: 44, height: 44, borderRadius: 14, display: 'grid', placeItems: 'center',
            color: 'rgba(255,255,255,.6)', flexShrink: 0,
          }}>
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>
          </div>
        )}

        {/* PRIMARY call cluster (mic + cam) — always in the bar */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1, justifyContent: 'center' }}>
          <BarBtn onClick={onToggleMic} title={micOn ? 'Mute mic' : 'Unmute mic'} danger={!micOn} active={talking}>
            {micOn
              ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
              : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V5a3 3 0 0 0-5.7-1.3M19 10v2a7 7 0 0 1-.7 3M12 19v3"/></svg>}
          </BarBtn>
          <BarBtn onClick={onToggleCam} title={camOn ? 'Camera off' : 'Camera on'} danger={!camOn}>
            {camOn
              ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="2" y="6" width="14" height="12" rx="2"/><path d="m16 10 6-3v10l-6-3"/></svg>
              : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M16 16H4a2 2 0 0 1-2-2V8m4-2h8a2 2 0 0 1 2 2v3l4-2v8"/></svg>}
          </BarBtn>
          {/* Roomy phones (≥820px): inline the secondary controls right here. */}
          {wide && secondary}
        </div>

        {/* PRIMARY tail: fullscreen (never in overflow) + the "⋯" more button on
            narrow phones. */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
          {/* PRIMARY fullscreen: reads the single `immersive` state and calls the
              enter/exit callbacks owned by WatchView. On iPhone this triggers the
              CSS faux-fullscreen that KEEPS the whole party (chat, cameras, PTT,
              room code) — it is NOT the native video player. Kept as a primary,
              one-tap action; it is intentionally NOT placed in the overflow. */}
          <BarBtn onClick={() => (immersive ? exitImmersive?.() : enterImmersive?.())} title={immersive ? 'Exit full screen' : 'Full screen'}>
            {immersive
              ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M8 3v4a1 1 0 0 1-1 1H3M21 8h-4a1 1 0 0 1-1-1V3M16 21v-4a1 1 0 0 1 1-1h4M3 16h4a1 1 0 0 1 1 1v4"/></svg>
              : <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M3 8V5a2 2 0 0 1 2-2h3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M21 16v3a2 2 0 0 1-2 2h-3"/></svg>}
          </BarBtn>

          {/* Overflow "⋯": secondary controls for narrow phones. Anchored to the
              bar, dismisses on outside tap / selection, sits above the bar. */}
          {!wide && (
            <div style={{ position: 'relative' }}>
              <BarBtn onClick={() => setMoreOpen(o => !o)} active={moreOpen} title="More controls">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>
              </BarBtn>
              {moreOpen && (
                <>
                  {/* Outside-tap dismiss. stopPropagation so tapping it doesn't
                      also toggle chrome via the surface tap handler. */}
                  <div onClick={(e) => { e.stopPropagation(); closeMore() }} style={{ position: 'fixed', inset: 0, zIndex: Z.controlBar }} />
                  <div onClick={(e) => e.stopPropagation()} style={{
                    ...glass('heavy', { refract: true }),
                    position: 'absolute', bottom: 'calc(100% + 10px)', right: 0, zIndex: Z.controlBar + 1,
                    display: 'flex', alignItems: 'center', gap: 8, padding: 8, borderRadius: 16,
                    animation: 'up .18s ease both',
                  }}>
                    {secondary}
                  </div>
                </>
              )}
            </div>
          )}
          {/* SEAM — secondary "expand video only" (chrome-free) native FS, DEMOTED.
              iPhone Safari can play the bare <video> fullscreen via
              video.webkitEnterFullscreen(), but that throws away every overlay
              (the whole point of a watch PARTY), so it is intentionally NOT the
              default FS button above. If we ever want a chrome-free movie, wire a
              small secondary control here that reaches the underlying
              HTMLVideoElement and, only when `video.webkitSupportsFullscreen`,
              calls video.webkitEnterFullscreen(). Left as a commented seam for now
              because reaching the element through the videojs skin cleanly is
              disproportionate to the value — see PHONE-UX-PLAN §2.2/§4 Phase B. */}
        </div>
        </div>
      </div>
    </div>
  )
}

// 44px touch-target button used across the mobile bar.
function BarBtn({ onClick, title, active, danger, primary, children }) {
  return (
    <button onClick={(e) => { e.stopPropagation(); onClick?.(e) }} title={title} aria-label={title} style={{
      width: 44, height: 44, flexShrink: 0, borderRadius: 14, border: 'none', display: 'grid', placeItems: 'center',
      cursor: 'pointer', color: danger ? '#FF6B6B' : (primary ? '#0a0a0c' : '#fff'),
      // Idle fill bumped .08 → .14 (G5): gives idle buttons more material so the
      // glyph reads over bright frames; paired with the bar scrim for ≥3:1.
      background: primary ? '#EDEFF2' : (active ? 'rgba(255,255,255,.24)' : 'rgba(255,255,255,.14)'),
      transition: 'background-color .15s, transform .12s',
    }}
      onTouchStart={e => e.currentTarget.style.transform = 'scale(.94)'}
      onTouchEnd={e => e.currentTarget.style.transform = 'scale(1)'}>
      {children}
    </button>
  )
}

// Mobile press-and-hold talk button. Uses pointer events (covers touch + mouse)
// so pointerup/cancel/leave all release — the mic can't stay open if the finger
// slides off. touchAction:none stops the hold from scrolling the bar. Reflects
// the live "talking" state with a green highlight; a no-op if the user already
// manually unmuted (the PTT hook swallows start() in that case).
function TalkBtn({ talking, onStart, onStop }) {
  const down = (e) => { e.stopPropagation(); e.preventDefault(); onStart?.() }
  const up = (e) => { e.stopPropagation(); onStop?.() }
  return (
    <button
      title="Hold to talk" aria-label="Hold to talk"
      onPointerDown={down} onPointerUp={up} onPointerCancel={up} onPointerLeave={up} onLostPointerCapture={up}
      onContextMenu={(e) => e.preventDefault()}
      style={{
        width: 44, height: 44, flexShrink: 0, borderRadius: 14, border: 'none', display: 'grid', placeItems: 'center',
        cursor: 'pointer', touchAction: 'none', userSelect: 'none', WebkitUserSelect: 'none',
        color: talking ? '#0a0a0c' : '#fff',
        background: talking ? '#7CFFB2' : 'rgba(255,255,255,.14)',
        transition: 'background-color .12s, transform .12s',
        transform: talking ? 'scale(.94)' : 'scale(1)',
      }}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
    </button>
  )
}

// ── Settings — two-level menu that scales to many tracks (search + scroll) ────
const MONO_F = "'JetBrains Mono', ui-monospace, monospace"
function SettingsMenu({ media, quality, onClose }) {
  const [view, setView] = useState('main')     // main | quality | subs | audio
  const [q, setQ] = useState('')
  const [subs, setSubs] = useState([])
  const [subActive, setSubActive] = useState(-1)
  const [audios, setAudios] = useState([])
  const [audioActive, setAudioActive] = useState(0)

  useEffect(() => {
    if (!media) return
    const tt = media.textTracks
    const list = tt ? Array.from(tt).filter(t => t.kind === 'subtitles' || t.kind === 'captions') : []
    setSubs(list); setSubActive(list.findIndex(t => t.mode === 'showing'))
    const at = media.audioTracks
    const alist = at ? Array.from(at) : []
    setAudios(alist); setAudioActive(Math.max(0, alist.findIndex(t => t.enabled)))
  }, [media])
  useEffect(() => { setQ('') }, [view])

  function chooseSub(i) { subs.forEach((t, idx) => { t.mode = idx === i ? 'showing' : 'disabled' }); setSubActive(i) }
  function chooseAudio(i) { audios.forEach((t, idx) => { t.enabled = idx === i }); setAudioActive(i) }
  const trackName = (t, i) => t.label || t.language || `Track ${i + 1}`

  // Quality summary: in Auto, show the level hls.js is actually playing
  // ("Auto (1080p)"); pinned, show the chosen rung's label.
  const qLevels = quality?.levels ?? []
  const hasLevels = qLevels.length > 0
  const autoLabel = quality?.current >= 0 && qLevels[quality.current]
    ? `Auto (${levelLabel(qLevels[quality.current]).split(' · ')[0]})`
    : 'Auto'
  const curQuality = !hasLevels
    ? 'Auto'
    : (quality.selected === -1 ? autoLabel : levelLabel(qLevels[quality.selected]))
  const curSub = subActive === -1 ? 'Off' : trackName(subs[subActive] || {}, subActive)
  const curAudio = audios.length ? trackName(audios[audioActive] || {}, audioActive) : '—'

  const panel = {
    ...glass('heavy', { refract: true }),
    position: 'absolute', bottom: 52, right: 0, zIndex: 31, width: 272, maxHeight: '60vh',
    display: 'flex', flexDirection: 'column', borderRadius: 16, overflow: 'hidden', color: '#fff',
    animation: 'up .18s ease both',
  }
  const navRow = (label, value, onClick) => (
    <button onClick={onClick} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, width: '100%', padding: '12px 14px', border: 'none', cursor: 'pointer', background: 'transparent', color: '#fff', fontSize: 14, fontWeight: 500, textAlign: 'left' }}>
      <span>{label}</span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'rgba(255,255,255,.5)', fontSize: 13, maxWidth: 130, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {value}
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m9 18 6-6-6-6" /></svg>
      </span>
    </button>
  )
  const optRow = (label, active, onClick, key) => (
    <button key={key} onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', padding: '10px 14px', border: 'none', cursor: 'pointer', background: active ? 'rgba(255,255,255,.1)' : 'transparent', color: active ? '#fff' : 'rgba(255,255,255,.7)', fontSize: 13.5, fontWeight: active ? 600 : 500, textAlign: 'left' }}>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" style={{ opacity: active ? 1 : 0, flexShrink: 0 }}><path d="M20 6 9 17l-5-5" /></svg>
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</span>
    </button>
  )
  const subHeader = (title) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '11px 12px', borderBottom: '1px solid rgba(255,255,255,.08)', flexShrink: 0 }}>
      <button onClick={() => setView('main')} style={{ width: 26, height: 26, borderRadius: 8, border: 'none', background: 'rgba(255,255,255,.08)', color: '#fff', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="m15 18-6-6 6-6" /></svg>
      </button>
      <span style={{ fontFamily: MONO_F, fontSize: 11, letterSpacing: '.14em', textTransform: 'uppercase', color: 'rgba(255,255,255,.6)' }}>{title}</span>
    </div>
  )
  const searchBox = (
    <div style={{ padding: 10, flexShrink: 0 }}>
      <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search…" autoFocus
        style={{ width: '100%', padding: '9px 12px', borderRadius: 9, border: '1px solid rgba(255,255,255,.12)', background: 'rgba(255,255,255,.05)', color: '#fff', fontSize: 13, outline: 'none' }} />
    </div>
  )
  const filtered = (arr) => arr.map((t, i) => [t, i]).filter(([t, i]) => trackName(t, i).toLowerCase().includes(q.toLowerCase()))

  return (
    <>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 30 }} />
      <div style={panel}>
        {view === 'main' && (
          <div style={{ padding: '6px 0' }}>
            {navRow('Quality', curQuality, () => setView('quality'))}
            {navRow('Subtitles', curSub, () => setView('subs'))}
            {audios.length > 1 && navRow('Audio', curAudio, () => setView('audio'))}
          </div>
        )}

        {view === 'quality' && (
          <>
            {subHeader('Quality')}
            <div style={{ overflowY: 'auto', padding: '6px 0' }}>
              {!hasLevels && <div style={{ padding: '8px 14px', fontSize: 12.5, color: 'rgba(255,255,255,.4)' }}>Loading available qualities…</div>}
              {/* Auto = real ABR (bandwidth-driven). Shows the level currently playing. */}
              {optRow(autoLabel, quality.selected === -1, () => { quality.choose(-1); setView('main') }, 'auto')}
              {/* Real variant rungs reported by hls.js, highest bitrate first */}
              {qLevels
                .map((l, i) => [l, i])
                .sort((a, b) => (b[0].bitrate || 0) - (a[0].bitrate || 0))
                .map(([l, i]) => optRow(levelLabel(l), quality.selected === i, () => { quality.choose(i); setView('main') }, i))}
            </div>
          </>
        )}

        {view === 'subs' && (
          <>
            {subHeader('Subtitles')}
            {subs.length > 8 && searchBox}
            <div style={{ overflowY: 'auto', padding: '6px 0' }}>
              {optRow('Off', subActive === -1, () => { chooseSub(-1); setView('main') }, 'off')}
              {subs.length === 0 && <div style={{ padding: '8px 14px', fontSize: 12.5, color: 'rgba(255,255,255,.4)' }}>None available in this stream</div>}
              {filtered(subs).map(([t, i]) => optRow(trackName(t, i), subActive === i, () => { chooseSub(i); setView('main') }, i))}
            </div>
          </>
        )}

        {view === 'audio' && (
          <>
            {subHeader('Audio')}
            {audios.length > 8 && searchBox}
            <div style={{ overflowY: 'auto', padding: '6px 0' }}>
              {filtered(audios).map(([t, i]) => optRow(trackName(t, i), audioActive === i, () => { chooseAudio(i); setView('main') }, i))}
            </div>
          </>
        )}
      </div>
    </>
  )
}
