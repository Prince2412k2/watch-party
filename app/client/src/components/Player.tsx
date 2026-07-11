import { useEffect, useRef, useState, useCallback, type CSSProperties, type MouseEvent, type PointerEvent as ReactPointerEvent, type ReactNode, type RefObject, type MutableRefObject } from 'react'
import { createPlayer } from '@videojs/react'
import { VideoSkin, videoFeatures } from '@videojs/react/video'
import { HlsVideo } from '@videojs/react/media/hls-video'
import '@videojs/react/video/skin.css'
import { useSyncPlay } from '../hooks/useSyncPlay'
import { useWideBar } from '../hooks/useIsMobile'
import { Z } from '../watchLayers'
import { createTransportIntent } from '../sync/transportIntent'
import { isBuffered } from '../sync/bufferSeek'
import { BUFFER_AHEAD_SEC } from '../sync/syncCore'
import { IS_NATIVE } from '../native/env'
import { IPC } from '../native/contract.ts'
import { invoke } from '../native/ipc'
import { MpvBackend } from '../native/MpvBackend'
import { apiJson, stringField } from '../types/guards'

type LocalPhase = 'ready' | 'catchingUp' | 'buffering'
type VoidCallback = () => void
interface SeekBridge { canControl: boolean; seekBy: (delta: number) => void; guardToggle: (fn: () => Promise<void> | void) => Promise<void> }
type SeekBridgeRef = MutableRefObject<SeekBridge | null>
interface MediaLike {
  currentTime: number; duration: number; paused: boolean; playbackRate: number; volume: number; muted: boolean
  buffered: TimeRanges; engine?: HlsLike
  play: () => Promise<void>; pause: () => void
  addEventListener: (type: string, listener: EventListenerOrEventListenerObject) => void
  removeEventListener: (type: string, listener: EventListenerOrEventListenerObject) => void
}
interface HlsLevel { height?: number; width?: number; bitrate?: number }
interface HlsTrack { id: number; name: string; lang?: string; url: string }
interface HlsLike { levels?: HlsLevel[]; currentLevel: number; nextLevel: number; autoLevelEnabled?: boolean; audioTrack: number; audioTracks: HlsTrack[]; subtitleTrack: number; subtitleTracks: HlsTrack[]; on: (event: string, fn: (...a: unknown[]) => void) => void; off: (event: string, fn: (...a: unknown[]) => void) => void }
interface QualityState { levels: HlsLevel[]; current: number; selected: number; choose: (index: number) => void }
type TrackSelection = { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null }
export interface PlayerTrack { index: number; displayTitle?: string; title?: string; language?: string; codec?: string; isDefault?: boolean }
export interface PlayerPlayback { audioStreams?: PlayerTrack[]; subtitleStreams?: PlayerTrack[]; selectedAudioIndex?: number | null; selectedSubtitleIndex?: number | null }
export interface PlayerProps {
  hlsUrl?: string; playback?: PlayerPlayback; mediaItemId?: string; isHost?: boolean; collaborativeControl?: boolean; syncMode?: 'hopping' | 'dragging'; onStruggle?: VoidCallback
  onToggleMic?: VoidCallback; onToggleCam?: VoidCallback; micOn?: boolean; camOn?: boolean; talking?: boolean; onTalkStart?: VoidCallback; onTalkEnd?: VoidCallback
  onToggleLayout?: VoidCallback; onOpenChat?: VoidCallback; layoutMode?: 'float' | 'dock'; hideSelf?: boolean; onToggleHideSelf?: VoidCallback
  visible?: boolean; immersive?: boolean; enterImmersive?: VoidCallback; exitImmersive?: VoidCallback; phone?: boolean; camStripOpen?: boolean; onToggleCamStrip?: VoidCallback
  seekBridgeRef?: SeekBridgeRef; onSetPlaybackTracks?: (tracks: TrackSelection) => void
}

// Fullscreen is owned by WatchView (Party.jsx) via a single `immersive` state and
// an enterImmersive()/exitImmersive() pair that branches by platform capability
// (element FS today; iOS CSS faux-FS in Phase B). The controls here just render
// the enter/exit icon from `immersive` and call those callbacks — no per-device
// branching lives in the button path anymore.
const VPlayer = createPlayer({ features: videoFeatures })

const MONO_F = "'JetBrains Mono', ui-monospace, monospace"

export default function Player({
  hlsUrl, playback, mediaItemId, isHost, collaborativeControl, syncMode, onStruggle,
  onToggleMic, onToggleCam, micOn, camOn,
  talking, onTalkStart, onTalkEnd,
  onToggleLayout, onOpenChat, layoutMode,
  hideSelf, onToggleHideSelf,
  visible = true, immersive, enterImmersive, exitImmersive,
  phone = false, camStripOpen, onToggleCamStrip, seekBridgeRef, onSetPlaybackTracks,
}: PlayerProps = {}) {
  const canControl = Boolean(isHost || collaborativeControl)
  const videoRef = useRef<HTMLVideoElement | null>(null)

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
  const toggleMuted = () => setUserMuted(m => !m)

  // Local (non-shared) playback phase from useSyncPlay, surfaced here so the
  // mobile transport button (owned by Player, not the hook) can tell a real
  // user pause apart from useSyncPlay's own catch-up/buffering pauses instead
  // of reading raw media.paused. Lifted out of SyncBridge because it's a
  // sibling of MobileBottomBar, not an ancestor.
  const [localPhase, setLocalPhase] = useState<'ready' | 'catchingUp' | 'buffering'>('ready')

  // Native (Tauri) desktop shell: the video surface + its transport are
  // rendered by mpv itself (own OSC), not React — see PLAN.md §0.6/§2. Player
  // only owns an opaque region for Rust to position the mpv window over, plus
  // the non-video room chrome (chat/mic/cam/layout toggles), docked beside/
  // below that region so nothing ever paints over the native surface. The web
  // branch below (vidstack + the custom control bar) is untouched.
  if (IS_NATIVE) {
    return (
      <NativePlayer
        hlsUrl={hlsUrl} isHost={isHost} collaborativeControl={collaborativeControl}
        syncMode={syncMode} onStruggle={onStruggle} canControl={canControl}
        onToggleMic={onToggleMic} onToggleCam={onToggleCam} micOn={micOn} camOn={camOn}
        talking={talking} onToggleLayout={onToggleLayout} onOpenChat={onOpenChat} layoutMode={layoutMode}
        hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
        immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive}
        phone={phone} camStripOpen={camStripOpen} onToggleCamStrip={onToggleCamStrip}
        seekBridgeRef={seekBridgeRef}
      />
    )
  }

  return (
    <VPlayer.Provider>
      {/* isolate so the skin's internal z-indexed layers don't paint over the
          camera tiles / chat that render as siblings of this player */}
      <div style={{ position: 'relative', width: '100%', height: '100%', background: '#000', isolation: 'isolate' }}>
        {/* The vidstack skin's own control bar is fully replaced by the flat,
            single-row control bar below (desktop: DesktopControlBar; phone:
            MobileBottomBar) — always hide it, on every platform. Skin is
            interactive only for controllers; guests can't drive transport. */}
        <VideoSkin className="watch-skin watch-skin--nobar" style={{ width: '100%', height: '100%', pointerEvents: canControl ? 'auto' : 'none' }}>
          {/* Everyone starts muted so synced play() autoplays without a gesture;
              `userMuted` (not canControl) governs mute state so guests can
              unmute and stay unmuted. Host forced muted only when
              autoplay-with-sound was blocked (see hostMuted above). */}
          <HlsVideo ref={videoRef} src={hlsUrl} playsInline preload="auto" muted={userMuted || hostMuted} style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
        </VideoSkin>

        {canControl && hostMuted && (
          <RestoreSoundPrompt onClick={() => setHostMuted(false)} />
        )}

        {/* Route all playback through SyncPlay + keyboard control */}
        <SyncBridge isHost={isHost} collaborativeControl={collaborativeControl} syncMode={syncMode} onStruggle={onStruggle}
          onOpenChat={onOpenChat} immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive} srcUrl={hlsUrl}
          seekBridgeRef={seekBridgeRef} onAutoplayBlocked={() => setHostMuted(true)}
          userMuted={userMuted} onToggleMuted={toggleMuted} onLocalPhase={setLocalPhase} />

        {userMuted && !hostMuted && (
          <UnmuteButton onClick={toggleMuted} />
        )}

        {phone ? (
          /* Phones: a single consolidated bottom bar — transport + call + settings
             + fullscreen — replacing the three floating desktop clusters. */
            <MobileBottomBar
            mediaItemId={mediaItemId}
            mediaElementRef={videoRef}
            playback={playback}
            onSetPlaybackTracks={onSetPlaybackTracks}
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
            {/* Quiet top-of-stage row: only meaningful while chrome is visible.
                Room-essential toggles only — no labels, no boxes. */}
            <TopBar
              visible={visible} onOpenChat={onOpenChat}
              micOn={micOn} camOn={camOn} onToggleMic={onToggleMic} onToggleCam={onToggleCam}
              talking={talking} hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
              onToggleLayout={onToggleLayout} layoutMode={layoutMode}
            />

            {/* One control row, pinned bottom, over the single allowed black-alpha
                scrim. Read-only for guests (no thumb, no pointer events on the
                scrubber) — canControl gates interactivity throughout. */}
            <DesktopControlBar
              mediaItemId={mediaItemId}
              mediaElementRef={videoRef}
              playback={playback}
              onSetPlaybackTracks={onSetPlaybackTracks}
              visible={visible} canControl={canControl}
              immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive}
              userMuted={userMuted} onToggleMuted={toggleMuted}
              localPhase={localPhase}
            />
          </>
        )}
      </div>
    </VPlayer.Provider>
  )
}

// ── Native (Tauri) branch — opaque video-stage + docked non-video chrome ────
// The mpv window is a separate, OPAQUE native surface that Rust positions to
// exactly cover the div rendered here (via mpv_set_region, in device px) — it
// is never a transparent hole with DOM drawn over it, so there is no
// compositing problem to solve on the React side (PLAN.md §0.6/§2). mpv's own
// OSC provides play/pause/scrubber/volume/settings; this component does not
// render any of that. It only:
//   1. reports the video-stage rect to Rust (mount/resize/scroll/fullscreen)
//   2. hands an MpvBackend to useSyncPlay so REMOTE sync corrections still
//      flow through the exact same host-authority engine the web player uses
//   3. mirrors `canControl` to mpv_set_can_control so a plain guest can't
//      drive playback via the OSC
//   4. renders the non-video room chrome (chat/mic/cam/layout toggles) docked
//      below the video stage — never overlapping it
function NativePlayer({
  hlsUrl, isHost, collaborativeControl, syncMode, onStruggle, canControl,
  onToggleMic, onToggleCam, micOn, camOn, talking,
  onToggleLayout, onOpenChat, layoutMode,
  hideSelf, onToggleHideSelf,
  immersive, enterImmersive, exitImmersive,
  phone, camStripOpen, onToggleCamStrip, seekBridgeRef,
}: PlayerProps & { canControl?: boolean } = {}) {
  const stageRef = useRef<HTMLDivElement | null>(null)
  // One MpvBackend per mounted native player, torn down on unmount — mirrors
  // the lifetime of the <HlsVideo> element it replaces.
  const backendRef = useRef<MpvBackend | null>(null)
  if (!backendRef.current) backendRef.current = new MpvBackend()
  const playerRef = useRef<MpvBackend | null>(null)
  playerRef.current = backendRef.current

  // Drop-in for the web path's SyncBridge: useSyncPlay only ever touches the
  // HTMLMediaElement duck-type surface (contract.ts §4.1), so handing it an
  // MpvBackend instead of a real element reuses the entire host-authority
  // sync engine unmodified.
  const {
    requestPlay, requestPause, requestSeek, holdApplying, releaseApplying,
    TICKS_PER_SECOND,
  } = useSyncPlay({ playerRef: playerRef as unknown as RefObject<HTMLVideoElement | null>, isHost, collaborativeControl, syncMode, onStruggle })

  useEffect(() => {
    return () => { backendRef.current?.destroy(); backendRef.current = null }
  }, [])

  // Load/replace the source. The web path plays a transcoded HLS URL; the
  // native path must instead direct-play the ORIGINAL file via N3's signed
  // stream-url proxy (no transcode). We reuse `hlsUrl` only to recover the
  // Jellyfin item id (…/Videos/<itemId>/master.m3u8), then resolve the signed
  // absolute file URL and hand THAT to mpv. Passing hlsUrl straight to mpv was
  // the bug: it's a relative /api/library/hls/… path, which mpv treats as a
  // local file and fails to open.
  useEffect(() => {
    if (!hlsUrl) return
    const m = hlsUrl.match(/\/Videos\/([^/?]+)\//)
    const itemId = m && m[1]
    if (!itemId) { console.error('[native] could not extract itemId from', hlsUrl); return }
    let cancelled = false
    ;(async () => {
      try {
        const r = await fetch(`/api/library/native/stream-url/${itemId}`, { credentials: 'include' })
        if (!r.ok) throw new Error(`stream-url ${r.status}`)
        const url = stringField(await apiJson(r), 'url')
        if (!url) throw new Error('stream-url response missing url')
        if (!cancelled) backendRef.current?.load(url, { paused: false })
      } catch (e) {
        console.error('[native] failed to resolve native stream URL:', e)
      }
    })()
    return () => { cancelled = true }
  }, [hlsUrl])

  // Gate mpv's own OSC interactivity — a plain guest must not be able to
  // perceptibly disrupt playback via the native controls (PLAN.md §2 risk 2).
  useEffect(() => { invoke(IPC.MPV_SET_CAN_CONTROL, { canControl }) }, [canControl])

  // Report the opaque video-stage rect (device px) so Rust can position the
  // embedded mpv window exactly over it, on every layout-affecting event.
  useEffect(() => {
    const el = stageRef.current
    if (!el) return
    const report = () => {
      const r = el.getBoundingClientRect()
      const dpr = window.devicePixelRatio || 1
      invoke(IPC.MPV_SET_REGION, {
        x: Math.round(r.left * dpr), y: Math.round(r.top * dpr),
        w: Math.round(r.width * dpr), h: Math.round(r.height * dpr), dpr,
      })
    }
    report()
    const ro = new ResizeObserver(report)
    ro.observe(el)
    window.addEventListener('resize', report)
    window.addEventListener('scroll', report, true)
    document.addEventListener('fullscreenchange', report)
    return () => {
      ro.disconnect()
      window.removeEventListener('resize', report)
      window.removeEventListener('scroll', report, true)
      document.removeEventListener('fullscreenchange', report)
    }
  }, [])
  // Re-report whenever a prop that can move/resize the stage without firing
  // the observers above changes (fullscreen toggle, camera-strip open/close,
  // phone/desktop chrome swap).
  useEffect(() => {
    const el = stageRef.current
    if (!el) return
    const r = el.getBoundingClientRect()
    const dpr = window.devicePixelRatio || 1
    invoke(IPC.MPV_SET_REGION, {
      x: Math.round(r.left * dpr), y: Math.round(r.top * dpr),
      w: Math.round(r.width * dpr), h: Math.round(r.height * dpr), dpr,
    })
  }, [immersive, camStripOpen, phone])

  // Imperative seek for the surface gesture layer, mirroring the web path's
  // seekBridgeRef contract — kept for callers that still reach for it, even
  // though there's no double-tap gesture layer over an opaque native surface.
  useEffect(() => {
    if (!seekBridgeRef) return
    seekBridgeRef.current = {
      canControl: Boolean(canControl),
        seekBy: (delta: number) => {
        const m = playerRef.current
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
      guardToggle: async (fn: () => Promise<void> | void) => { try { await fn?.() } catch {} },
    }
    return () => { seekBridgeRef.current = null }
  }, [seekBridgeRef, canControl, holdApplying, releaseApplying, requestSeek, TICKS_PER_SECOND])

  return (
    <div style={{ position: 'relative', width: '100%', height: '100%', display: 'flex', flexDirection: 'column', background: '#000' }}>
      {/* OPAQUE video stage — Rust embeds/positions the real mpv window over
          this exact rect. Nothing (no DOM, no overlay) may render on top of
          it; that's the whole point of the native-player decision. */}
      <div ref={stageRef} style={{ flex: 1, minHeight: 0, background: '#000' }} />

      {/* Non-video room chrome, docked BELOW the video stage — never
          overlapping it. mpv's own OSC (skinned in Rust/Lua, see N1) provides
          play/pause/scrubber/volume/settings; only room-essential toggles
          (chat/mic/cam/layout) live here. */}
      <div style={{
        flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 4,
        padding: '10px 14px', background: '#0a0a0b', borderTop: '1px solid rgba(255,255,255,.08)',
      }}>
        {onOpenChat && (
          <IconBtn onClick={onOpenChat} title="Chat">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M21 11.5a8.4 8.4 0 0 1-1.1 4.2L21 20l-4.3-1a8.4 8.4 0 1 1 4.3-7.5Z"/></svg>
          </IconBtn>
        )}
        {onToggleMic && (
          <IconBtn onClick={onToggleMic} title={micOn ? 'Mute mic' : 'Unmute mic'} danger={!micOn} active={talking}>
            {micOn
              ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
              : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="m2 2 20 20M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V5a3 3 0 0 0-5.7-1.3M19 10v2a7 7 0 0 1-.7 3M12 19v3"/></svg>}
          </IconBtn>
        )}
        {onToggleCam && (
          <IconBtn onClick={onToggleCam} title={camOn ? 'Camera off' : 'Camera on'} danger={!camOn}>
            {camOn
              ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="2" y="6" width="14" height="12" rx="2"/><path d="m16 10 6-3v10l-6-3"/></svg>
              : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="m2 2 20 20M16 16H4a2 2 0 0 1-2-2V8m4-2h8a2 2 0 0 1 2 2v3l4-2v8"/></svg>}
          </IconBtn>
        )}
        {onToggleHideSelf && (
          <IconBtn onClick={onToggleHideSelf} active={hideSelf} title={hideSelf ? 'Show my camera to me' : 'Hide my camera from me'}>
            {hideSelf
              ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4"/></svg>
              : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>}
          </IconBtn>
        )}
        {onToggleCamStrip && (
          <IconBtn onClick={onToggleCamStrip} active={camStripOpen} title={camStripOpen ? 'Hide cameras' : 'Show cameras'}>
            {camStripOpen
              ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="8" width="5" height="8" rx="1"/><rect x="9.5" y="8" width="5" height="8" rx="1"/><rect x="16" y="8" width="5" height="8" rx="1"/></svg>
              : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="m2 2 20 20M3 8h1m4.5 0H14m2 0h5v8h-1M3 8v8h9"/></svg>}
          </IconBtn>
        )}
        {onToggleLayout && (
          <IconBtn onClick={onToggleLayout} title="Camera layout">
            {layoutMode === 'float'
              ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="3" width="18" height="18" rx="2"/><rect x="13" y="12" width="6" height="6" rx="1" fill="currentColor" stroke="none"/></svg>
              : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="3" width="6" height="18" rx="1.5"/><rect x="11" y="3" width="10" height="18" rx="1.5"/></svg>}
          </IconBtn>
        )}
        {!phone && (
          <IconBtn onClick={() => (immersive ? exitImmersive?.() : enterImmersive?.())} title={immersive ? 'Exit full screen' : 'Full screen'}>
            {immersive
              ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M8 3v4a1 1 0 0 1-1 1H3M21 8h-4a1 1 0 0 1-1-1V3M16 21v-4a1 1 0 0 1 1-1h4M3 16h4a1 1 0 0 1 1 1v4"/></svg>
              : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M3 8V5a2 2 0 0 1 2-2h3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M21 16v3a2 2 0 0 1-2 2h-3"/></svg>}
          </IconBtn>
        )}
      </div>
    </div>
  )
}

// ── Bridges the videojs Media instance into our SyncPlay protocol ────────────
// NOTE: nothing in this function was touched for the visual redesign — it is
// the sync/transport authority (useSyncPlay, transportIntent arm/consume,
// holdApplying/releaseApplying, buffer-aware seek, ABR wiring) and stays exactly
// as it was. Only its own overlay render (buffering/switching-quality) at the
// bottom was restyled to the neutral spinner spec.
interface SyncBridgeProps extends Pick<PlayerProps, 'isHost' | 'collaborativeControl' | 'syncMode' | 'onStruggle' | 'onOpenChat' | 'immersive' | 'enterImmersive' | 'exitImmersive' | 'seekBridgeRef'> {
  srcUrl?: string; onAutoplayBlocked?: VoidCallback; userMuted?: boolean; onToggleMuted?: VoidCallback; onLocalPhase?: (phase: LocalPhase) => void
}
function SyncBridge({ isHost, collaborativeControl, syncMode, onStruggle, onOpenChat, immersive, enterImmersive, exitImmersive, srcUrl, seekBridgeRef, onAutoplayBlocked, userMuted, onToggleMuted, onLocalPhase }: SyncBridgeProps = {}) {
  const toggleFullscreen = () => (immersive ? exitImmersive?.() : enterImmersive?.())
  const media = VPlayer.useMedia() as unknown as MediaLike
  const mediaRef = useRef<MediaLike | null>(null)
  mediaRef.current = media

  const {
    canControl, applyingRef, holdApplying, releaseApplying, notifyUserSeeking, reportStall,
    requestPlay, requestPause, requestSeek, localPhase,
    TICKS_PER_SECOND,
  } = useSyncPlay({ playerRef: mediaRef as unknown as RefObject<HTMLVideoElement | null>, isHost, collaborativeControl, syncMode, onStruggle, onAutoplayBlocked })

  // Surface localPhase to Player (MobileBottomBar's transport button needs it
  // and is a sibling of this component, not a descendant).
  useEffect(() => { onLocalPhase?.(localPhase) }, [localPhase, onLocalPhase])

  const seekTimer = useRef<number | null>(null)
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
      canControl: Boolean(canControl),
      seekBy: (delta: number) => {
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
      guardToggle: async (fn: () => Promise<void> | void) => {
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
    const ticks = (m: MediaLike) => Math.round((m.currentTime || 0) * TICKS_PER_SECOND)
    const play = (m: MediaLike) => { requestPlay(ticks(m)); holdApplying(); m.play().catch(() => {}); setTimeout(releaseApplying, 250) }
    const pause = (m: MediaLike) => { requestPause(ticks(m)); holdApplying(); m.pause(); setTimeout(releaseApplying, 250) }
    const seek = (m: MediaLike, time: number) => {
      const dur = m.duration
      const max = Number.isFinite(dur) && dur > 0 ? Math.max(0, dur - 0.5) : Infinity
      const target = Math.min(max, Math.max(0, time))
      requestSeek(Math.round(target * TICKS_PER_SECOND))
      holdApplying(); m.currentTime = target; setTimeout(releaseApplying, 250)
    }
    function onKey(e: KeyboardEvent) {
      const t = e.target instanceof HTMLElement ? e.target : null
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return
      const m = mediaRef.current
      const k = e.key.toLowerCase()
      // Ctrl/Cmd+F → fullscreen (also plain 'f' below)
      if (k === 'f' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); toggleFullscreen(); return }
      if (e.ctrlKey || e.metaKey || e.altKey) return
      if (!m) {
        if ([' ', 'k', 'arrowright', 'arrowleft', 'l', 'j'].includes(k)) return
      }
      const transport = () => Boolean(m && canControl)
      switch (k) {
        case ' ': case 'k':
          if (!transport()) return; e.preventDefault(); m!.paused ? play(m!) : pause(m!); break
        case 'arrowright':
          if (!transport()) return; e.preventDefault(); seek(m!, (m!.currentTime || 0) + 5); break
        case 'arrowleft':
          if (!transport()) return; e.preventDefault(); seek(m!, (m!.currentTime || 0) - 5); break
        case 'l': if (transport()) seek(m!, (m!.currentTime || 0) + 10); break
        case 'j': if (transport()) seek(m!, (m!.currentTime || 0) - 10); break
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
    const onCommand = (event: Event) => {
      const e = event as CustomEvent<{ kind?: string; time?: number }>
      const m = mediaRef.current
      if (!m || !canControl) return
      if (e.detail?.kind === 'play') play(m)
      else if (e.detail?.kind === 'pause') pause(m)
      else if (e.detail?.kind === 'seek' && typeof e.detail.time === 'number') seek(m, e.detail.time)
    }
    window.addEventListener('watch:transport', onCommand)
    return () => {
      window.removeEventListener('keydown', onKey, true)
      window.removeEventListener('watch:transport', onCommand)
    }
  }, [canControl, onOpenChat, onToggleMuted, immersive, enterImmersive, exitImmersive, requestPlay, requestPause, requestSeek, holdApplying, releaseApplying, TICKS_PER_SECOND])

  // The desktop skin is third-party UI, so mark its pointer gestures before its
  // media mutations occur. Only the next matching event may author a command.
  // The check is a plain `.watch-skin` class match — our own custom scrubber
  // (rendered outside VideoSkin) also carries this class for the same reason.
  useEffect(() => {
    if (!canControl) return
    const onPointerDown = (e: PointerEvent) => {
      if (e.target instanceof Element && e.target.closest('.watch-skin')) transportIntent.current.arm('*')
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
    const set = (v: boolean) => { if (stalled !== v) { stalled = v; reportStall(v) } }
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

    const explicit = (kind: string) => !applyingRef.current && canControl && transportIntent.current.consume(kind)
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
      if (seekTimer.current != null) window.clearTimeout(seekTimer.current)
      seekTimer.current = window.setTimeout(() => { seekTimer.current = null; requestSeek(ticks()) }, 200)
    }

    media.addEventListener('play', onPlay)
    media.addEventListener('pause', onPause)
    media.addEventListener('seeking', onSeeking)
    media.addEventListener('seeked', onSeeked)
    return () => {
      if (seekTimer.current != null) window.clearTimeout(seekTimer.current)
      media.removeEventListener('play', onPlay)
      media.removeEventListener('pause', onPause)
      media.removeEventListener('seeking', onSeeking)
      media.removeEventListener('seeked', onSeeked)
    }
  }, [media, canControl, applyingRef, notifyUserSeeking, requestPlay, requestPause, requestSeek, TICKS_PER_SECOND])

  if (!buffering && !switchingQuality) return null
  // Neutral spinner: 2px ring, white top segment, transparent rest. Flat
  // black-alpha backdrop, no blur, no color.
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: Z.buffering, display: 'grid', placeItems: 'center',
      background: 'rgba(0,0,0,.55)',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
        <div style={{
          width: 32, height: 32, borderRadius: '50%',
          border: '2px solid rgba(255,255,255,.14)', borderTopColor: '#f4f4f5',
          animation: 'spin .9s linear infinite',
        }} />
        <span style={{ fontSize: 13, fontWeight: 500, color: 'rgba(244,244,245,.62)' }}>{switchingQuality ? 'Switching quality…' : 'Catching up…'}</span>
      </div>
    </div>
  )
}

// ── Shared monochrome icon button ────────────────────────────────────────────
// No box, no border, no fill at rest — dim glyph brightens to text on hover.
// Used by the top bar and the desktop control row alike.
interface ButtonProps { onClick?: (event: MouseEvent<HTMLButtonElement>) => void; title?: string; active?: boolean; danger?: boolean; size?: number; children?: ReactNode; style?: CSSProperties }
function IconBtn({ onClick, title, active, danger, size = 34, children, style }: ButtonProps = {}) {
  return (
    <button
      onClick={(e) => { e.stopPropagation(); onClick?.(e) }}
      title={title} aria-label={title}
      style={{
        width: size, height: size, border: 'none', background: 'transparent', borderRadius: 8,
        display: 'grid', placeItems: 'center', cursor: 'pointer',
        color: danger ? '#e0655e' : (active ? '#f4f4f5' : 'rgba(244,244,245,.62)'),
        transition: 'color .15s',
        ...style,
      }}
      onMouseEnter={e => { if (!danger) e.currentTarget.style.color = '#f4f4f5' }}
      onMouseLeave={e => { if (!danger) e.currentTarget.style.color = active ? '#f4f4f5' : 'rgba(244,244,245,.62)' }}
    >
      {children}
    </button>
  )
}

// Quiet top-of-stage row (desktop). Only renders content while chrome is
// visible; fades with it. No title/back affordance is wired here — Player
// isn't handed a title or a back handler, only room-essential toggles.
function TopBar({ visible, onOpenChat, micOn, camOn, onToggleMic, onToggleCam, talking, hideSelf, onToggleHideSelf, onToggleLayout, layoutMode }: PlayerProps = {}) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, zIndex: Z.controlBar,
      display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 4,
      padding: '10px 14px',
      opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s',
    }}>
      {onOpenChat && (
        <IconBtn onClick={onOpenChat} title="Chat">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M21 11.5a8.4 8.4 0 0 1-1.1 4.2L21 20l-4.3-1a8.4 8.4 0 1 1 4.3-7.5Z"/></svg>
        </IconBtn>
      )}
      {onToggleMic && (
        <IconBtn onClick={onToggleMic} title={micOn ? 'Mute mic' : 'Unmute mic'} danger={!micOn} active={talking}>
          {micOn
            ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
            : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="m2 2 20 20M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V5a3 3 0 0 0-5.7-1.3M19 10v2a7 7 0 0 1-.7 3M12 19v3"/></svg>}
        </IconBtn>
      )}
      {onToggleCam && (
        <IconBtn onClick={onToggleCam} title={camOn ? 'Camera off' : 'Camera on'} danger={!camOn}>
          {camOn
            ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="2" y="6" width="14" height="12" rx="2"/><path d="m16 10 6-3v10l-6-3"/></svg>
            : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="m2 2 20 20M16 16H4a2 2 0 0 1-2-2V8m4-2h8a2 2 0 0 1 2 2v3l4-2v8"/></svg>}
        </IconBtn>
      )}
      {onToggleHideSelf && (
        <IconBtn onClick={onToggleHideSelf} active={hideSelf} title={hideSelf ? 'Show my camera to me' : 'Hide my camera from me'}>
          {hideSelf
            ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4"/></svg>
            : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>}
        </IconBtn>
      )}
      {onToggleLayout && (
        <IconBtn onClick={onToggleLayout} title="Camera layout">
          {layoutMode === 'float'
            ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="3" width="18" height="18" rx="2"/><rect x="13" y="12" width="6" height="6" rx="1" fill="currentColor" stroke="none"/></svg>
            : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="3" width="6" height="18" rx="1.5"/><rect x="11" y="3" width="10" height="18" rx="1.5"/></svg>}
        </IconBtn>
      )}
    </div>
  )
}

// Host restores audio after autoplay-with-sound was blocked. Flat, no glass,
// no color — a plain dim pill that brightens on hover.
function RestoreSoundPrompt({ onClick }: { onClick?: VoidCallback } = {}) {
  return (
    <button onClick={onClick} style={{
      position: 'absolute', top: 16, left: '50%', transform: 'translateX(-50%)',
      zIndex: Z.controlBar, display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '8px 14px', borderRadius: 999, fontSize: 13, fontWeight: 600,
      color: '#f4f4f5', cursor: 'pointer', background: 'rgba(0,0,0,.5)',
      border: '1px solid rgba(255,255,255,.14)',
    }}>
      Tap for sound
    </button>
  )
}

// Guests (no playback control) get a dedicated unmute affordance, since they
// have no other way to enable audio — audio is independent of control rights.
function UnmuteButton({ onClick }: { onClick?: VoidCallback } = {}) {
  return (
    <button onClick={onClick} style={{
      position: 'absolute', top: 16, left: '50%', transform: 'translateX(-50%)',
      zIndex: Z.controlBar, display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '8px 14px', borderRadius: 999, fontSize: 13, fontWeight: 600,
      color: '#f4f4f5', cursor: 'pointer', background: 'rgba(0,0,0,.5)',
      border: '1px solid rgba(255,255,255,.14)',
    }}>
      Tap for sound
    </button>
  )
}

// Hold-T-to-talk hint / live "Talking…" state, shown above the AV cluster.
// Neutral — no green. Active state = brighter + a plain white pulse dot, per
// the "active = brightness, not color" rule.
function PTTHint({ talking, muted }: { talking?: boolean; muted?: boolean } = {}) {
  if (!talking && !muted) return null
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 7,
      padding: '5px 11px', borderRadius: 999, fontSize: 12, fontWeight: 600,
      background: 'rgba(0,0,0,.5)', color: talking ? '#f4f4f5' : 'rgba(244,244,245,.62)',
      transition: 'color .15s',
    }}>
      {talking ? (
        <>
          <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#f4f4f5', animation: 'pulse 1.2s ease-in-out infinite' }} />
          Talking…
        </>
      ) : (
        <>
          <kbd style={{
            fontFamily: 'inherit', fontSize: 11, fontWeight: 700, lineHeight: 1,
            padding: '2px 6px', borderRadius: 5, background: 'rgba(255,255,255,.1)',
            border: '1px solid rgba(255,255,255,.14)',
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
function useQualityLevels(media: MediaLike | null | undefined): QualityState {
  const [levels, setLevels] = useState<HlsLevel[]>([])       // hls.levels snapshot
  const [current, setCurrent] = useState(-1)     // active level index (-1 = none yet)
  const [selected, setSelected] = useState(-1)   // user choice; -1 = Auto

  useEffect(() => {
    if (!media) return
    let hls: HlsLike | undefined
    let poll: ReturnType<typeof setInterval> | undefined
    const sync = () => {
      if (!hls) return
      setLevels(hls.levels ?? [])
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
      const engine = hls
      evs.forEach(e => engine.on(e, sync))
      sync()
      return true
    }
    // The engine is created in HlsJsMedia's constructor during load(); it's
    // normally present as soon as `media` is, but poll briefly in case not.
    if (!attach()) poll = setInterval(() => { if (attach()) clearInterval(poll) }, 100)
    return () => {
      if (poll) clearInterval(poll)
      const engine = hls
      if (engine) evs.forEach(e => { try { engine.off(e, sync) } catch {} })
    }
  }, [media])

  const choose = (i: number) => {
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

// ── Jellyfin ↔ hls.js track index mapping ───────────────────────────────────
// Jellyfin embeds AudioStreamIndex / SubtitleStreamIndex as query params in each
// rendition URI inside the HLS master playlist. hls.js assigns its own 0-based
// indices to audioTracks[] / subtitleTracks[]. We need to map between them.
function jellyfinStreamIndex(url: string, param: string): number | null {
  try {
    const u = new URL(url, window.location.origin)
    const v = u.searchParams.get(param)
    return v != null && !isNaN(Number(v)) ? Number(v) : null
  } catch { return null }
}

function hlsIndexForJellyfin(tracks: HlsTrack[], jellyfinIndex: number, param: string): number {
  return tracks.findIndex(t => jellyfinStreamIndex(t.url, param) === jellyfinIndex)
}

// ── In-stream audio track switching (no reload) ─────────────────────────────
// Mirrors useQualityLevels: reads playback.selectedAudioIndex from the session,
// maps it to hls.js's audioTracks[], and sets hls.audioTrack. This avoids the
// full HLS teardown + rebuild that a src-swap causes.
interface AudioTrackState { choose: (jellyfinIndex: number) => void }
function useAudioTrack(media: MediaLike | null | undefined, playback?: PlayerPlayback): AudioTrackState {
  useEffect(() => {
    const hls = media?.engine
    if (!hls) return
    const target = playback?.selectedAudioIndex
    if (target == null) return
    const apply = () => {
      const idx = hlsIndexForJellyfin(hls.audioTracks, target, 'AudioStreamIndex')
      if (idx >= 0 && hls.audioTrack !== idx) hls.audioTrack = idx
    }
    apply()
    const onManifest = () => apply()
    hls.on('hlsManifestParsed', onManifest)
    return () => { hls.off('hlsManifestParsed', onManifest) }
  }, [media, playback?.selectedAudioIndex])

  const choose = useCallback((jellyfinIndex: number) => {
    const hls = media?.engine
    if (!hls) return
    const idx = hlsIndexForJellyfin(hls.audioTracks, jellyfinIndex, 'AudioStreamIndex')
    if (idx >= 0) hls.audioTrack = idx
  }, [media])

  return { choose }
}

// ── In-stream subtitle track switching (no reload) ──────────────────────────
// Same pattern as useAudioTrack but also enables the browser's native text track
// display mode so subtitles actually render on screen.
//
// The @videojs/core text-tracks mixin has a cue-delivery bug: it creates
// <track> elements with mode="disabled" and tries to forward hls.js CUES_PARSED
// cues via getTrackById(). However the ID it assigns to the <track> (computed
// via findIndex on lang/name/type) doesn't always match the ID hls.js sends in
// CUES_PARSED (which is 'subtitles' + fragLevel). When the IDs don't match the
// mixin silently discards every cue. Even when they DO match, line 55 resets the
// track mode back to "disabled" after adding cues, so nothing renders.
//
// Fix: we listen for hlsCuesParsed directly and deliver cues ourselves using
// language/name matching instead of the mixin's broken ID lookup.
interface SubtitleTrackState { choose: (jellyfinIndex: number | null) => void }
function useSubtitleTrack(media: MediaLike | null | undefined, playback?: PlayerPlayback): SubtitleTrackState {
  const resolveHlsIdx = useCallback((hls: HlsLike, jellyfinIndex: number | null | undefined) => {
    if (jellyfinIndex == null || jellyfinIndex < 0) return -1
    return hlsIndexForJellyfin(hls.subtitleTracks, jellyfinIndex, 'SubtitleStreamIndex')
  }, [])

  const applySubtitle = useCallback((hls: HlsLike, target: number | null | undefined) => {
    const video = media as unknown as { textTracks?: TextTrackList }
    const tracks = video?.textTracks
    const hlsIdx = resolveHlsIdx(hls, target)
    const hlsTrack = hlsIdx >= 0 ? hls.subtitleTracks[hlsIdx] : null

    // Tell hls.js which subtitle track to load (or -1 to disable)
    hls.subtitleTrack = hlsIdx

    // Sync DOM text track modes
    if (!tracks) return
    for (let i = 0; i < tracks.length; i++) {
      const tt = tracks[i]
      if (tt.kind !== 'subtitles' && tt.kind !== 'captions') continue
      if (hlsTrack) {
        const matches = (hlsTrack.lang && tt.language === hlsTrack.lang) || tt.label === hlsTrack.name
        tt.mode = matches ? 'showing' : 'disabled'
      } else {
        tt.mode = 'disabled'
      }
    }
  }, [media, resolveHlsIdx])

  const disableSubtitles = useCallback((hls: HlsLike) => {
    applySubtitle(hls, null)
  }, [applySubtitle])

  useEffect(() => {
    const hls = media?.engine
    if (!hls) return
    const target = playback?.selectedSubtitleIndex

    // Deliver cues from hlsCuesParsed directly to the correct DOM track,
    // bypassing the mixin's broken getTrackById-based cue delivery.
    const onCuesParsed = (...args: unknown[]) => {
      const data = args[1] as { track: string; cues: unknown[] }
      const hlsIdx = resolveHlsIdx(hls, target)
      if (hlsIdx < 0) return
      const hlsTrack = hls.subtitleTracks[hlsIdx]
      if (!hlsTrack) return
      const video = media as unknown as { textTracks?: TextTrackList }
      const tracks = video?.textTracks
      if (!tracks) return
      for (let i = 0; i < tracks.length; i++) {
        const tt = tracks[i]
        if (tt.kind !== 'subtitles' && tt.kind !== 'captions') continue
        const matches = (hlsTrack.lang && tt.language === hlsTrack.lang) || tt.label === hlsTrack.name
        if (!matches) continue
        // Temporarily set mode to "hidden" so the browser accepts new cues
        const wasDisabled = tt.mode === 'disabled'
        if (wasDisabled) tt.mode = 'hidden'
        for (const cue of data.cues) {
          if (tt.cues?.getCueById((cue as VTTCue).id)) continue
          tt.addCue(cue as VTTCue)
        }
        // Restore to "showing" — the applySubtitle call below finalises the mode
        if (wasDisabled) tt.mode = 'showing'
        break
      }
    }

    applySubtitle(hls, target)
    hls.on('hlsCuesParsed', onCuesParsed)
    const onManifest = () => applySubtitle(hls, target)
    hls.on('hlsManifestParsed', onManifest)
    return () => {
      hls.off('hlsCuesParsed', onCuesParsed)
      hls.off('hlsManifestParsed', onManifest)
    }
  }, [media, playback?.selectedSubtitleIndex, applySubtitle, resolveHlsIdx])

  const choose = useCallback((jellyfinIndex: number | null) => {
    const hls = media?.engine
    if (!hls) return
    applySubtitle(hls, jellyfinIndex)
  }, [media, applySubtitle])

  return { choose }
}

function levelLabel(l: HlsLevel | null | undefined) {
  if (!l) return ''
  const h = l.height ? `${l.height}p` : (l.width ? `${l.width}w` : '')
  const mbps = l.bitrate ? `${(l.bitrate / 1_000_000).toFixed(1)} Mbps` : ''
  return [h, mbps].filter(Boolean).join(' · ') || 'Auto'
}

// ── Read-only playback clock (position / duration / buffer) ─────────────────
function useMediaClock(media: MediaLike | null | undefined) {
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

function fmtClock(s: number) {
  if (!Number.isFinite(s) || s < 0) s = 0
  s = Math.floor(s)
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60
  const mm = h > 0 ? String(m).padStart(2, '0') : String(m)
  return `${h > 0 ? `${h}:` : ''}${mm}:${String(sec).padStart(2, '0')}`
}

// ── The scrubber: thin (4px, 6px on hover/scrub), white played, white-alpha
// buffered/track, round thumb visible only on hover/scrub. Read-only for
// guests — no thumb, no pointer events, position/buffer still shown. Dragging
// mutates media.currentTime directly (same authoring path the old skin
// scrubber used); the surrounding row carries the `.watch-skin` class so the
// pointerdown-arm listener in SyncBridge still arms before we mutate, and the
// existing seeking/seeked → requestSeek pipeline authors the room exactly as
// before.
function Scrubber({ canControl }: { canControl?: boolean } = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const { cur, dur, buf } = useMediaClock(media)
  const [hover, setHover] = useState(false)
  const [dragging, setDragging] = useState(false)
  const trackRef = useRef<HTMLDivElement | null>(null)

  const pct = dur > 0 ? Math.min(100, (cur / dur) * 100) : 0
  const bufPct = dur > 0 ? Math.min(100, (buf / dur) * 100) : 0
  const active = hover || dragging
  const barH = active ? 6 : 4

  const ratioFromEvent = (e: PointerEvent | ReactPointerEvent<HTMLDivElement>) => {
    const el = trackRef.current
    if (!el) return 0
    const r = el.getBoundingClientRect()
    const clientX = e.clientX
    return Math.min(1, Math.max(0, (clientX - r.left) / r.width))
  }

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!canControl || !media) return
    e.stopPropagation()
    setDragging(true)
    const seekTo = (ev: PointerEvent | ReactPointerEvent<HTMLDivElement>) => {
      const dur2 = media.duration || 0
      media.currentTime = ratioFromEvent(ev) * dur2
    }
    seekTo(e)
    const move = (ev: PointerEvent) => seekTo(ev)
    const up = () => {
      setDragging(false)
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
    }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up, { once: true })
  }

  return (
    <div
      ref={trackRef}
      onMouseEnter={() => canControl && setHover(true)}
      onMouseLeave={() => setHover(false)}
      onPointerDown={onPointerDown}
      style={{
        position: 'relative', flex: 1, height: 16, display: 'flex', alignItems: 'center',
        cursor: canControl ? 'pointer' : 'default', pointerEvents: canControl ? 'auto' : 'none',
      }}
    >
      <div style={{ position: 'absolute', left: 0, right: 0, height: barH, borderRadius: 999, background: 'rgba(255,255,255,.14)', transition: 'height .15s' }} />
      <div style={{ position: 'absolute', left: 0, height: barH, width: `${bufPct}%`, borderRadius: 999, background: 'rgba(255,255,255,.28)', transition: 'height .15s' }} />
      <div style={{ position: 'absolute', left: 0, height: barH, width: `${pct}%`, borderRadius: 999, background: '#f4f4f5', transition: 'height .15s' }} />
      {canControl && (
        <div style={{
          position: 'absolute', left: `${pct}%`, width: 10, height: 10, marginLeft: -5,
          borderRadius: '50%', background: '#f4f4f5', opacity: active ? 1 : 0, transition: 'opacity .15s',
        }} />
      )}
    </div>
  )
}

// Guest-only "who's driving" hint — text only, no lock box.
function HostControlsHint() {
  return (
    <div style={{ fontSize: 11.5, fontWeight: 500, color: 'rgba(244,244,245,.36)', flexShrink: 0, whiteSpace: 'nowrap' }}>
      Host controls playback
    </div>
  )
}

// Hover-reveal volume slider. Desktop only, purely local (media.volume) —
// independent of the shared `userMuted` flag, which callers still flip via
// the mute icon.
function VolumeControl({ userMuted, onToggleMuted }: { userMuted?: boolean; onToggleMuted?: VoidCallback } = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const [open, setOpen] = useState(false)
  const [volume, setVolume] = useState(1)

  useEffect(() => {
    if (!media) return
    setVolume(media.volume ?? 1)
  }, [media])

  const muted = userMuted || volume === 0
  return (
    <div
      onMouseEnter={() => setOpen(true)} onMouseLeave={() => setOpen(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 6 }}
    >
      <IconBtn onClick={onToggleMuted} title={muted ? 'Unmute' : 'Mute'}>
        {muted
          ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M11 5 6 9H2v6h4l5 4V5Z"/><path d="M23 9l-6 6M17 9l6 6"/></svg>
          : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M11 5 6 9H2v6h4l5 4V5Z"/><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 6a9 9 0 0 1 0 12"/></svg>}
      </IconBtn>
      <div style={{ width: open ? 70 : 0, overflow: 'hidden', transition: 'width .18s' }}>
        <input
          type="range" min={0} max={1} step={0.01} value={userMuted ? 0 : volume}
          onChange={(e) => {
            const v = Number(e.target.value)
            setVolume(v)
            if (media) media.volume = v
            if (v > 0 && userMuted) onToggleMuted?.()
            if (v === 0 && !userMuted) onToggleMuted?.()
          }}
          style={{ width: 64, accentColor: '#f4f4f5', height: 16, cursor: 'pointer' }}
        />
      </div>
    </div>
  )
}

// ── Desktop control row ──────────────────────────────────────────────────────
// The single pinned-bottom row: play/pause, current time, scrubber, duration,
// volume, settings, fullscreen — over the one allowed black-alpha scrim. No
// box, no border around the row itself.
interface ControlBarProps extends Pick<PlayerProps, 'mediaItemId' | 'playback' | 'onSetPlaybackTracks' | 'visible' | 'immersive' | 'enterImmersive' | 'exitImmersive' | 'micOn' | 'camOn' | 'talking' | 'onTalkStart' | 'onTalkEnd' | 'onToggleMic' | 'onToggleCam' | 'onToggleLayout' | 'layoutMode' | 'hideSelf' | 'onToggleHideSelf' | 'camStripOpen' | 'onToggleCamStrip'> {
  mediaElementRef?: RefObject<HTMLVideoElement | null>; canControl?: boolean; userMuted?: boolean; onToggleMuted?: VoidCallback; localPhase?: LocalPhase
}
function DesktopControlBar({ mediaItemId, playback, mediaElementRef, onSetPlaybackTracks, visible, canControl, immersive, enterImmersive, exitImmersive, userMuted, onToggleMuted, localPhase = 'ready' }: ControlBarProps = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const quality = useQualityLevels(media)
  const audioTrack = useAudioTrack(media, playback)
  const subtitleTrack = useSubtitleTrack(media, playback)
  const { cur, dur } = useMediaClock(media)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [paused, setPaused] = useState(true)

  useEffect(() => {
    if (!media) return
    const sync = () => setPaused(!!media.paused && localPhase === 'ready')
    sync()
    media.addEventListener('play', sync)
    media.addEventListener('pause', sync)
    return () => { media.removeEventListener('play', sync); media.removeEventListener('pause', sync) }
  }, [media, localPhase])

  const togglePlay = () => {
    if (!canControl) return
    window.dispatchEvent(new CustomEvent('watch:transport', { detail: { kind: paused ? 'play' : 'pause' } }))
  }

  // Menus never auto-hide: force the row visible while settings is open, even
  // if the idle timer (owned by the party frame) has already faded `visible`.
  const shown = visible || settingsOpen

  return (
    <div className="watch-skin" style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: Z.controlBar,
      opacity: shown ? 1 : 0, pointerEvents: shown ? 'auto' : 'none', transition: 'opacity .25s',
    }}>
      {/* The one allowed gradient: a neutral black-alpha legibility scrim. */}
      <div aria-hidden style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, height: 120,
        background: 'linear-gradient(0deg, rgba(0,0,0,.8), transparent)',
        pointerEvents: 'none',
      }} />
      <div style={{
        position: 'relative', display: 'flex', alignItems: 'center', gap: 12,
        padding: '0 18px 14px',
      }}>
        <IconBtn onClick={togglePlay} title={paused ? 'Play' : 'Pause'} active size={36}>
          {paused
            ? <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
            : <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>}
        </IconBtn>

        <span style={{ fontFamily: MONO_F, fontSize: 12, fontVariantNumeric: 'tabular-nums', color: '#f4f4f5', minWidth: 40, flexShrink: 0 }}>{fmtClock(cur)}</span>

        <Scrubber canControl={canControl} />

        <span style={{ fontFamily: MONO_F, fontSize: 12, fontVariantNumeric: 'tabular-nums', color: 'rgba(244,244,245,.62)', minWidth: 40, flexShrink: 0 }}>{fmtClock(dur)}</span>

        {!canControl && <HostControlsHint />}

        <VolumeControl userMuted={userMuted} onToggleMuted={onToggleMuted} />

        <div style={{ position: 'relative' }}>
          <IconBtn onClick={() => setSettingsOpen(o => !o)} title="Settings" active={settingsOpen}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
          </IconBtn>
          {settingsOpen && <SettingsMenu playback={playback} mediaItemId={mediaItemId} quality={quality} canControl={canControl} onSetPlaybackTracks={onSetPlaybackTracks} onChooseAudio={audioTrack.choose} onChooseSubtitle={subtitleTrack.choose} onClose={() => setSettingsOpen(false)} />}
        </div>

        <IconBtn onClick={() => (immersive ? exitImmersive?.() : enterImmersive?.())} title={immersive ? 'Exit full screen (Ctrl+F)' : 'Full screen (Ctrl+F)'}>
          {immersive
            ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M8 3v4a1 1 0 0 1-1 1H3M21 8h-4a1 1 0 0 1-1-1V3M16 21v-4a1 1 0 0 1 1-1h4M3 16h4a1 1 0 0 1 1 1v4"/></svg>
            : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M3 8V5a2 2 0 0 1 2-2h3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M21 16v3a2 2 0 0 1-2 2h-3"/></svg>}
        </IconBtn>
      </div>
    </div>
  )
}

// ── Mobile consolidated bottom bar ───────────────────────────────────────────
// One flat bar pinned to the bottom (clear of the home-indicator via safe-area),
// over the same black-alpha scrim as the desktop row. It carries a PRIMARY
// cluster that is always one tap away — transport (host-only play/pause, or a
// lock glyph for guests), mic, cam, and fullscreen — plus the SECONDARY
// controls (push-to-talk, hide-self, camera-strip toggle, quality/settings). On
// short/narrow phones (< 820px, see `useWideBar`) the secondary set collapses
// behind a "⋯" overflow popover so nothing clips or horizontally scrolls at
// e.g. 740×360; on roomy phones (≥ 820px, e.g. 844-wide landscape) they inline
// back into the bar. Fullscreen is NEVER in the overflow. Fades with the
// auto-hide `visible` layer. Touch targets are 44px with ≥8px gaps.
function MobileBottomBar({
  mediaItemId,
  playback,
  mediaElementRef,
  onSetPlaybackTracks,
  canControl, localPhase, micOn, camOn, talking, onTalkStart, onTalkEnd, onToggleMic, onToggleCam, onToggleLayout, layoutMode,
  hideSelf, onToggleHideSelf, camStripOpen, onToggleCamStrip, visible, immersive, enterImmersive, exitImmersive,
}: ControlBarProps = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const quality = useQualityLevels(media)
  const audioTrack = useAudioTrack(media, playback)
  const subtitleTrack = useSubtitleTrack(media, playback)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [moreOpen, setMoreOpen] = useState(false)
  const [paused, setPaused] = useState(true)
  const wide = useWideBar()
  const barRef = useRef<HTMLDivElement | null>(null)

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
        ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4"/></svg>
        : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>}
    </BarBtn>
  ) : null
  const camStripControl = (
    <BarBtn key="camstrip" onClick={() => { onToggleCamStrip?.(); closeMore() }} active={camStripOpen} title={camStripOpen ? 'Hide cameras' : 'Show cameras'}>
      {camStripOpen
        ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="3" y="8" width="5" height="8" rx="1"/><rect x="9.5" y="8" width="5" height="8" rx="1"/><rect x="16" y="8" width="5" height="8" rx="1"/></svg>
        : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M3 8h1m4.5 0H14m2 0h5v8h-1M3 8v8h9"/></svg>}
    </BarBtn>
  )
  const settingsControl = (
    <div key="settings" style={{ position: 'relative' }}>
      <BarBtn onClick={() => setSettingsOpen(o => !o)} active={settingsOpen} title="Settings">
        <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
      </BarBtn>
      {settingsOpen && <SettingsMenu playback={playback} mediaItemId={mediaItemId} quality={quality} canControl={canControl} onSetPlaybackTracks={onSetPlaybackTracks} onChooseAudio={audioTrack.choose} onChooseSubtitle={subtitleTrack.choose} onClose={() => setSettingsOpen(false)} />}
    </div>
  )
  const secondary = [talkControl, hideSelfControl, camStripControl, settingsControl].filter(Boolean)

  // Menus never auto-hide: keep the bar visible while settings/overflow is open.
  const shown = visible || settingsOpen || moreOpen

  return (
    <div className="watch-skin" style={{
      position: 'absolute', zIndex: Z.controlBar,
      left: 'calc(var(--sa-l) + 8px)', right: 'calc(var(--sa-r) + 8px)',
      bottom: 'calc(var(--sa-b) + 8px)',
      opacity: shown ? 1 : 0, pointerEvents: shown ? 'auto' : 'none', transition: 'opacity .25s',
    }}>
      {/* The one allowed gradient: a neutral black-alpha legibility scrim rising
          behind the bar so glyphs hold contrast over a bright video frame. */}
      <div aria-hidden style={{
        position: 'absolute', left: -8, right: -8, bottom: -8, top: -48,
        background: 'linear-gradient(180deg, rgba(0,0,0,0) 0%, rgba(0,0,0,.4) 60%, rgba(0,0,0,.6) 100%)',
        pointerEvents: 'none',
      }} />
      <div ref={barRef} style={{
        position: 'relative',
        display: 'flex', flexDirection: 'column', gap: 6, padding: '6px 6px 2px',
      }}>
        {/* Read-only timeline row (bug 6): everyone on a phone sees position /
            progress / duration here. The skin's own scrubber is hidden on phones
            (watch-skin--nobar); controllers still scrub via double-tap-seek. */}
        <div style={{ padding: '2px 6px 0' }}>
          <MobileTimelineRow canControl={canControl} />
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 8, justifyContent: 'space-between' }}>
        {/* Transport: play/pause for controllers, lock glyph for guests */}
        {canControl ? (
          <BarBtn onClick={togglePlay} title={paused ? 'Play' : 'Pause'} primary>
            {paused
              ? <svg width="21" height="21" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
              : <svg width="21" height="21" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>}
          </BarBtn>
        ) : (
          <div title="Host controls playback" style={{
            width: 44, height: 44, borderRadius: 14, display: 'grid', placeItems: 'center',
            color: 'rgba(244,244,245,.62)', flexShrink: 0,
          }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>
          </div>
        )}

        {/* PRIMARY call cluster (mic + cam) — always in the bar */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1, justifyContent: 'center' }}>
          <BarBtn onClick={onToggleMic} title={micOn ? 'Mute mic' : 'Unmute mic'} danger={!micOn} active={talking}>
            {micOn
              ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
              : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V5a3 3 0 0 0-5.7-1.3M19 10v2a7 7 0 0 1-.7 3M12 19v3"/></svg>}
          </BarBtn>
          <BarBtn onClick={onToggleCam} title={camOn ? 'Camera off' : 'Camera on'} danger={!camOn}>
            {camOn
              ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="2" y="6" width="14" height="12" rx="2"/><path d="m16 10 6-3v10l-6-3"/></svg>
              : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M16 16H4a2 2 0 0 1-2-2V8m4-2h8a2 2 0 0 1 2 2v3l4-2v8"/></svg>}
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
              ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M8 3v4a1 1 0 0 1-1 1H3M21 8h-4a1 1 0 0 1-1-1V3M16 21v-4a1 1 0 0 1 1-1h4M3 16h4a1 1 0 0 1 1 1v4"/></svg>
              : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M3 8V5a2 2 0 0 1 2-2h3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M21 16v3a2 2 0 0 1-2 2h-3"/></svg>}
          </BarBtn>

          {/* Overflow "⋯": secondary controls for narrow phones. Anchored to the
              bar, dismisses on outside tap / selection, sits above the bar. */}
          {!wide && (
            <div style={{ position: 'relative' }}>
              <BarBtn onClick={() => setMoreOpen(o => !o)} active={moreOpen} title="More controls">
                <svg width="19" height="19" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>
              </BarBtn>
              {moreOpen && (
                <>
                  {/* Outside-tap dismiss. stopPropagation so tapping it doesn't
                      also toggle chrome via the surface tap handler. */}
                  <div onClick={(e) => { e.stopPropagation(); closeMore() }} style={{ position: 'fixed', inset: 0, zIndex: Z.controlBar }} />
                  <div onClick={(e) => e.stopPropagation()} style={{
                    backgroundColor: '#141416', border: '1px solid rgba(255,255,255,.08)',
                    position: 'absolute', bottom: 'calc(100% + 10px)', right: 0, zIndex: Z.controlBar + 1,
                    display: 'flex', alignItems: 'center', gap: 8, padding: 8, borderRadius: 12,
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

// Compact read-only mono time row for the mobile bar — time / scrubber / time,
// matching the desktop scrubber but sized for the touch bar. Read-only, same
// as the desktop guest scrubber (mobile transport is via double-tap-seek).
function MobileTimelineRow({ canControl }: { canControl?: boolean } = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const { cur, dur, buf } = useMediaClock(media)
  const pct = dur > 0 ? Math.min(100, (cur / dur) * 100) : 0
  const bufPct = dur > 0 ? Math.min(100, (buf / dur) * 100) : 0
  return (
    <div aria-label="Playback progress" style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%' }}>
      <span style={{ fontFamily: MONO_F, fontSize: 11, fontVariantNumeric: 'tabular-nums', minWidth: 36, textAlign: 'right', color: '#f4f4f5', flexShrink: 0 }}>{fmtClock(cur)}</span>
      <div style={{ position: 'relative', flex: 1, height: 4, borderRadius: 999, overflow: 'hidden', background: 'rgba(255,255,255,.14)' }}>
        <div style={{ position: 'absolute', top: 0, bottom: 0, left: 0, width: `${bufPct}%`, background: 'rgba(255,255,255,.28)' }} />
        <div style={{ position: 'absolute', top: 0, bottom: 0, left: 0, width: `${pct}%`, background: '#f4f4f5' }} />
      </div>
      <span style={{ fontFamily: MONO_F, fontSize: 11, fontVariantNumeric: 'tabular-nums', minWidth: 36, color: 'rgba(244,244,245,.62)', flexShrink: 0 }}>{fmtClock(dur)}</span>
      {!canControl && <span style={{ fontSize: 10.5, color: 'rgba(244,244,245,.36)', flexShrink: 0 }}>Host controls</span>}
    </div>
  )
}

// 44px touch-target button used across the mobile bar. Flat: no glass, active
// state is brightness only (never a color fill) except the semantic `danger`
// (muted mic/cam) and the near-white `primary` transport knob.
function BarBtn({ onClick, title, active, danger, primary, children }: ButtonProps & { primary?: boolean } = {}) {
  return (
    <button onClick={(e) => { e.stopPropagation(); onClick?.(e) }} title={title} aria-label={title} style={{
      width: 44, height: 44, flexShrink: 0, borderRadius: 12, border: 'none', display: 'grid', placeItems: 'center',
      cursor: 'pointer', color: danger ? '#e0655e' : (primary ? '#0a0a0b' : '#f4f4f5'),
      background: primary ? '#f4f4f5' : (active ? 'rgba(255,255,255,.14)' : 'transparent'),
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
// slides off. touchAction:none stops the hold from scrolling the bar. Active
// state (currently talking) is brightness only — near-white fill, never a
// color highlight. No-op if the user already manually unmuted (the PTT hook
// swallows start() in that case).
function TalkBtn({ talking, onStart, onStop }: { talking?: boolean; onStart?: VoidCallback; onStop?: VoidCallback } = {}) {
  const down = (e: ReactPointerEvent<HTMLButtonElement>) => { e.stopPropagation(); e.preventDefault(); onStart?.() }
  const up = (e: ReactPointerEvent<HTMLButtonElement>) => { e.stopPropagation(); onStop?.() }
  return (
    <button
      title="Hold to talk" aria-label="Hold to talk"
      onPointerDown={down} onPointerUp={up} onPointerCancel={up} onPointerLeave={up} onLostPointerCapture={up}
      onContextMenu={(e) => e.preventDefault()}
      style={{
        width: 44, height: 44, flexShrink: 0, borderRadius: 12, border: 'none', display: 'grid', placeItems: 'center',
        cursor: 'pointer', touchAction: 'none', userSelect: 'none', WebkitUserSelect: 'none',
        color: talking ? '#0a0a0b' : '#f4f4f5',
        background: talking ? '#f4f4f5' : 'rgba(255,255,255,.14)',
        transition: 'background-color .12s, transform .12s',
        transform: talking ? 'scale(.94)' : 'scale(1)',
      }}>
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
    </button>
  )
}

// ── Settings — two-level menu that scales to many tracks (search + scroll) ────
// Flat solid surface, hairline border, radius 12 — no blur, no gradient.
interface SettingsMenuProps { playback?: PlayerPlayback; mediaItemId?: string; quality: QualityState; canControl?: boolean; onSetPlaybackTracks?: (tracks: TrackSelection) => void; onChooseAudio?: (jellyfinIndex: number) => void; onChooseSubtitle?: (jellyfinIndex: number | null) => void; onClose?: VoidCallback }
function SettingsMenu({ playback, mediaItemId, quality, canControl, onSetPlaybackTracks, onChooseAudio, onChooseSubtitle, onClose }: SettingsMenuProps) {
  const [view, setView] = useState<'main' | 'quality' | 'subs' | 'audio'>('main')
  const [q, setQ] = useState('')
  const [uploadingSub, setUploadingSub] = useState(false)
  const [uploadError, setUploadError] = useState('')
  const uploadInputRef = useRef<HTMLInputElement | null>(null)

  const audioStreams = playback?.audioStreams ?? []
  const subtitleStreams = playback?.subtitleStreams ?? []
  const selectedAudioIndex = playback?.selectedAudioIndex ?? audioStreams.find(t => t.isDefault)?.index ?? audioStreams[0]?.index ?? null
  const selectedSubtitleIndex = playback?.selectedSubtitleIndex ?? null
  const trackName = (t: Partial<PlayerTrack>, i: number) => t.displayTitle || t.title || t.language || `${t.codec || 'Track'} ${t.index ?? (i + 1)}`

  useEffect(() => { setQ('') }, [view])

  function chooseAudio(index: number) {
    if (!canControl) return
    onChooseAudio?.(index)
    onSetPlaybackTracks?.({ audioStreamIndex: index, subtitleStreamIndex: selectedSubtitleIndex })
    setView('main')
  }

  function chooseSub(index: number | null) {
    if (!canControl) return
    onChooseSubtitle?.(index)
    onSetPlaybackTracks?.({ audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: index })
    setView('main')
  }

  async function uploadSubtitle(file?: File) {
    if (!file || !mediaItemId || !canControl) return
    setUploadingSub(true); setUploadError('')
    try {
      const params = new URLSearchParams({ mediaItemId })
      const res = await fetch(`/api/library/subtitles/upload?${params}`, {
        method: 'POST', credentials: 'include', body: file,
        headers: {
          'Content-Type': file.type || 'application/octet-stream',
          'X-Subtitle-Filename': encodeURIComponent(file.name),
        },
      })
      const data: unknown = await apiJson(res).catch(() => ({}))
      const message = typeof data === 'object' && data !== null && 'error' in data && typeof data.error === 'string' ? data.error : 'Upload failed'
      if (!res.ok) throw new Error(message)
    } catch (err) {
      setUploadError(err instanceof Error ? err.message : 'Could not upload subtitle')
    } finally {
      setUploadingSub(false)
      if (uploadInputRef.current) uploadInputRef.current.value = ''
    }
  }

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
  const curSub = selectedSubtitleIndex == null || selectedSubtitleIndex < 0 ? 'Off' : trackName(subtitleStreams.find(s => s.index === selectedSubtitleIndex) || {}, 0)
  const curAudio = audioStreams.length ? trackName(audioStreams.find(s => s.index === selectedAudioIndex) || {}, 0) : '—'

  const panel: CSSProperties = {
    backgroundColor: '#141416', border: '1px solid rgba(255,255,255,.08)',
    position: 'absolute', bottom: 52, right: 0, zIndex: 31, width: 272, maxHeight: '60vh',
    display: 'flex', flexDirection: 'column', borderRadius: 12, overflow: 'hidden', color: '#f4f4f5',
    animation: 'up .18s ease both',
  }
  const navRow = (label: string, value: string, onClick: VoidCallback) => (
    <button onClick={onClick} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, width: '100%', padding: '12px 14px', border: 'none', cursor: 'pointer', background: 'transparent', color: '#f4f4f5', fontSize: 13.5, fontWeight: 500, textAlign: 'left' }}>
      <span>{label}</span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'rgba(244,244,245,.62)', fontSize: 12.5, maxWidth: 130, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {value}
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m9 18 6-6-6-6" /></svg>
      </span>
    </button>
  )
  const optRow = (label: string, active: boolean, onClick: VoidCallback, key: string | number) => (
    <button key={key} onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', padding: '10px 14px', border: 'none', cursor: 'pointer', background: active ? 'rgba(255,255,255,.06)' : 'transparent', color: active ? '#f4f4f5' : 'rgba(244,244,245,.62)', fontSize: 13, fontWeight: active ? 600 : 500, textAlign: 'left' }}>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" style={{ opacity: active ? 1 : 0, flexShrink: 0 }}><path d="M20 6 9 17l-5-5" /></svg>
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</span>
    </button>
  )
  const subHeader = (title: string) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '11px 12px', borderBottom: '1px solid rgba(255,255,255,.08)', flexShrink: 0 }}>
      <button onClick={() => setView('main')} style={{ width: 26, height: 26, borderRadius: 8, border: 'none', background: 'rgba(255,255,255,.06)', color: '#f4f4f5', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="m15 18-6-6 6-6" /></svg>
      </button>
      <span style={{ fontFamily: MONO_F, fontSize: 11, letterSpacing: '.14em', textTransform: 'uppercase', color: 'rgba(244,244,245,.62)' }}>{title}</span>
    </div>
  )
  const searchBox = (
    <div style={{ padding: 10, flexShrink: 0 }}>
      <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search…" autoFocus
        style={{ width: '100%', padding: '9px 12px', borderRadius: 9, border: '1px solid rgba(255,255,255,.1)', background: 'rgba(255,255,255,.04)', color: '#f4f4f5', fontSize: 13, outline: 'none' }} />
    </div>
  )
  const filtered = (arr: PlayerTrack[]) => arr.filter((t, i) => trackName(t, i).toLowerCase().includes(q.toLowerCase()))

  return (
    <>
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 30 }} />
      <div style={panel}>
        {view === 'main' && (
          <div style={{ padding: '6px 0' }}>
            {navRow('Quality', curQuality, () => setView('quality'))}
            {navRow('Subtitles', curSub, () => setView('subs'))}
            {audioStreams.length > 1 && navRow('Audio', curAudio, () => setView('audio'))}
          </div>
        )}

        {view === 'quality' && (
          <>
            {subHeader('Quality')}
            <div style={{ overflowY: 'auto', padding: '6px 0' }}>
              {!hasLevels && <div style={{ padding: '8px 14px', fontSize: 12.5, color: 'rgba(244,244,245,.36)' }}>Loading available qualities…</div>}
              {/* Auto = real ABR (bandwidth-driven). Shows the level currently playing. */}
              {optRow(autoLabel, quality.selected === -1, () => { quality.choose(-1); setView('main') }, 'auto')}
              {/* Real variant rungs reported by hls.js, highest bitrate first */}
              {qLevels
                .map((l, i): [HlsLevel, number] => [l, i])
                .sort((a, b) => (b[0].bitrate || 0) - (a[0].bitrate || 0))
                .map(([l, i]) => optRow(levelLabel(l), quality.selected === i, () => { quality.choose(i); setView('main') }, i))}
            </div>
          </>
        )}

        {view === 'subs' && (
          <>
            {subHeader('Subtitles')}
            {subtitleStreams.length > 8 && searchBox}
            <div style={{ overflowY: 'auto', padding: '6px 0' }}>
              {optRow('Off', selectedSubtitleIndex == null || selectedSubtitleIndex < 0, () => chooseSub(null), 'off')}
              {subtitleStreams.length === 0 && <div style={{ padding: '8px 14px', fontSize: 12.5, color: 'rgba(244,244,245,.36)' }}>None available in this stream</div>}
              {filtered(subtitleStreams).map((t, i) => optRow(trackName(t, i), selectedSubtitleIndex === t.index, () => chooseSub(t.index), t.index))}
              <div style={{ borderTop: '1px solid rgba(255,255,255,.08)', marginTop: 6, padding: '10px 14px 6px' }}>
                <input ref={uploadInputRef} type="file" accept=".srt,.vtt,text/vtt,application/x-subrip" hidden
                  onChange={(e) => uploadSubtitle(e.target.files?.[0])} />
                <button disabled={uploadingSub || !mediaItemId || !canControl} onClick={() => uploadInputRef.current?.click()} style={{
                  width: '100%', padding: '9px 12px', borderRadius: 9, cursor: uploadingSub ? 'wait' : 'pointer',
                  border: '1px solid rgba(255,255,255,.12)', background: 'rgba(255,255,255,.06)',
                  color: '#f4f4f5', fontSize: 13, fontWeight: 600, opacity: (mediaItemId && canControl) ? 1 : .45,
                }}>{uploadingSub ? 'Uploading…' : 'Upload subtitle file'}</button>
                {uploadError && <div role="alert" style={{ color: '#e0655e', fontSize: 11.5, marginTop: 7 }}>{uploadError}</div>}
                <div style={{ color: 'rgba(244,244,245,.36)', fontSize: 11, marginTop: 6 }}>SRT or WebVTT · 5 MB max</div>
              </div>
            </div>
          </>
        )}

        {view === 'audio' && (
          <>
            {subHeader('Audio')}
            {audioStreams.length > 8 && searchBox}
            <div style={{ overflowY: 'auto', padding: '6px 0' }}>
              {filtered(audioStreams).map((t, i) => optRow(trackName(t, i), selectedAudioIndex === t.index, () => chooseAudio(t.index), t.index))}
            </div>
          </>
        )}
      </div>
    </>
  )
}
