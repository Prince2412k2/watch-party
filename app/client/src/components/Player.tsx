import { useEffect, useMemo, useRef, useState, useCallback, type ComponentType, type CSSProperties, type MouseEvent, type ReactNode, type RefObject, type MutableRefObject } from 'react'
import { createPlayer } from '@videojs/react'
import { VideoSkin, videoFeatures } from '@videojs/react/video'
import { HlsVideo } from '@videojs/react/media/hls-video'
import '@videojs/react/video/skin.css'
import { useSyncPlay } from '../hooks/useSyncPlay.ts'
import { Z } from '../watchLayers.ts'
import { createTransportIntent } from '../sync/transportIntent.ts'
import { createLocalTransport } from '../sync/transportCommand.ts'
import { isBuffered } from '../sync/bufferSeek.ts'
import { BUFFER_AHEAD_SEC } from '../sync/syncCore.ts'
import { IS_NATIVE } from '../native/env.ts'
import { IPC } from '../native/contract.ts'
import { invoke } from '../native/ipc.ts'
import { MpvBackend } from '../native/MpvBackend.ts'
import { apiJson, stringField } from '../types/guards.ts'
import { parseTrickplayManifest, trickplayFrame, trickplaySheetUrl, type TrickplayManifest } from './trickplay.ts'
import { hlsIndexForJellyfin, subtitleContentUrl } from './subtitleTracks.ts'
import {
  AnalogSettingsStack,
  AnalogTimeline,
  AnalogVolume,
  CHROME_HOLD,
  formatClock,
  shouldToggleChatFromEvent,
  useDisplayPreferences,
  type TimeSpan,
  type TimelinePreview,
} from '../analog/player/index.ts'
import { analogTokens } from '../design/analogTokens.ts'
import type { SubtitlePreferences } from '../types.ts'

type LocalPhase = 'ready' | 'catchingUp' | 'buffering'
type VoidCallback = () => void
interface SeekBridge { canControl: boolean; seekBy: (delta: number) => void; guardToggle: (fn: () => unknown) => Promise<void> }
type SeekBridgeRef = MutableRefObject<SeekBridge | null>
interface MediaLike {
  currentTime: number; duration: number; paused: boolean; playbackRate: number; volume: number; muted: boolean
  buffered: TimeRanges; engine?: HlsLike
  play: () => Promise<void>; pause: () => void
  addEventListener: (type: string, listener: EventListenerOrEventListenerObject) => void
  removeEventListener: (type: string, listener: EventListenerOrEventListenerObject) => void
}
interface HlsLevel { height?: number; width?: number; bitrate?: number }
interface HlsTrack { id: number; name: string; lang?: string; url: string; default?: boolean }
interface HlsLike { levels?: HlsLevel[]; currentLevel: number; nextLevel: number; autoLevelEnabled?: boolean; audioTrack: number; audioTracks: HlsTrack[]; subtitleTrack: number; subtitleTracks: HlsTrack[]; on: (event: string, fn: (...a: unknown[]) => void) => void; off: (event: string, fn: (...a: unknown[]) => void) => void }
interface QualityState { levels: HlsLevel[]; current: number; selected: number; choose: (index: number) => void }
type TrackSelection = { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null }
export interface PlayerTrack { index: number; displayTitle?: string; title?: string; language?: string; codec?: string; isDefault?: boolean; isExternal?: boolean; deliveryUrl?: string | null }
export interface PlayerPlayback { mediaSourceId?: string | null; audioStreams?: PlayerTrack[]; subtitleStreams?: PlayerTrack[]; selectedAudioIndex?: number | null; selectedSubtitleIndex?: number | null }
export interface PlayerProps {
  hlsUrl?: string; playback?: PlayerPlayback; mediaItemId?: string; isHost?: boolean; collaborativeControl?: boolean; syncMode?: 'hopping' | 'dragging'; onStruggle?: VoidCallback
  onToggleMic?: VoidCallback; onToggleCam?: VoidCallback; micOn?: boolean; camOn?: boolean
  // Purely-local display toggle: "hide every camera tile from MY screen". Owned
  // by WatchView (Party.tsx); it is never published to the room, so the eye
  // button below is available to guests as well as controllers.
  hideAllFeeds?: boolean; onToggleHideAllFeeds?: VoidCallback
  // onOpenChat / onToggleLayout / layoutMode / hideSelf / onToggleHideSelf are
  // no longer rendered by the redesigned web bars, but NativePlayer (the Tauri
  // docked chrome row) still consumes every one of them — do not drop them.
  onToggleLayout?: VoidCallback; onOpenChat?: VoidCallback; layoutMode?: 'float' | 'dock'; hideSelf?: boolean; onToggleHideSelf?: VoidCallback
  // Ctrl+C toggles the drawer (guarded by playerCore's shouldToggleChat); plain
  // 'c' still opens-and-focuses it through onOpenChat. Two callbacks because
  // they are two different actions, not two names for one.
  onToggleChat?: VoidCallback
  visible?: boolean; immersive?: boolean; enterImmersive?: VoidCallback; exitImmersive?: VoidCallback; phone?: boolean; camStripOpen?: boolean
  seekBridgeRef?: SeekBridgeRef; onSetPlaybackTracks?: (tracks: TrackSelection) => void
  subtitlePreferences?: SubtitlePreferences; onSetSubtitlePreferences?: (preferences: SubtitlePreferences) => void
  // The chrome auto-hide lives in WatchView over playerCore's hold set. A menu
  // or a scrub in progress takes a named hold so the bar cannot fade out from
  // under the interaction that opened it.
  onHoldChrome?: (reason: string) => void; onReleaseChrome?: (reason: string) => void
  /** Playback state for the auto-hide rule "never hide while paused". */
  onPlayingChange?: (playing: boolean) => void
}

// Fullscreen is owned by WatchView (Party.jsx) via a single `immersive` state and
// an enterImmersive()/exitImmersive() pair that branches by platform capability
// (element FS today; iOS CSS faux-FS in Phase B). The controls here just render
// the enter/exit icon from `immersive` and call those callbacks — no per-device
// branching lives in the button path anymore.
const VPlayer = createPlayer({ features: videoFeatures })

const MONO_F = "'JetBrains Mono', ui-monospace, monospace"
const DEFAULT_SUBTITLE_PREFERENCES: SubtitlePreferences = {
  delayMs: 0,
  fontScalePercent: 100,
  verticalOffsetPercent: 0,
  fontFamily: 'sans',
  textColor: '#FFFFFF',
  backgroundOpacityPercent: 65,
}

const originalCueState = new WeakMap<TextTrackCue, { startTime: number; endTime: number }>()

function applyCuePreferences(track: TextTrack, preferences: SubtitlePreferences) {
  const previousMode = track.mode
  if (previousMode === 'disabled') track.mode = 'hidden'
  const cues = track.cues
  if (cues) {
    for (let i = 0; i < cues.length; i++) {
      const cue = cues[i]
      let original = originalCueState.get(cue)
      if (!original) {
        original = { startTime: cue.startTime, endTime: cue.endTime }
        originalCueState.set(cue, original)
      }
      const offset = preferences.delayMs / 1000
      cue.startTime = Math.max(0, original.startTime + offset)
      cue.endTime = Math.max(cue.startTime + 0.05, original.endTime + offset)
      if (cue instanceof VTTCue) {
        // A percentage down from the top, which is what VTTCue.line means when
        // snapToLines is false. The preference counts UP from the bottom, so
        // the two are complements. This replaced three hardcoded line
        // positions; the setting could only say top, middle or bottom, and
        // subtitles have to clear things that are not at any of those heights.
        //
        // Clamped to 92 rather than 100: a cue placed flush with the bottom
        // edge is cut off by the frame, and the old 'bottom' case leaned on
        // snapToLines with line = -3 to avoid exactly that.
        const offset = Math.min(100, Math.max(0, preferences.verticalOffsetPercent))
        cue.snapToLines = false
        cue.line = 92 - (offset * 0.92)
        cue.align = 'center'
      }
    }
  }
  if (previousMode === 'disabled') track.mode = previousMode
}

function useSubtitlePreferences(videoRef?: RefObject<HTMLVideoElement | null>, canonical?: SubtitlePreferences, onSet?: (preferences: SubtitlePreferences) => void) {
  const preferences = canonical ?? DEFAULT_SUBTITLE_PREFERENCES

  useEffect(() => {
    const video = videoRef?.current
    if (video) {
      for (let i = 0; i < video.textTracks.length; i++) applyCuePreferences(video.textTracks[i], preferences)
    }
  }, [preferences, videoRef])

  useEffect(() => {
    const id = 'watchparty-subtitle-style'
    let style = document.getElementById(id) as HTMLStyleElement | null
    if (!style) {
      style = document.createElement('style')
      style.id = id
      document.head.append(style)
    }
    const family = preferences.fontFamily === 'serif'
      ? "Georgia, 'Times New Roman', serif"
      : preferences.fontFamily === 'mono' ? MONO_F : "'Circular XX', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    style.textContent = `.watch-video::cue { color: ${preferences.textColor}; background-color: rgba(0,0,0,${preferences.backgroundOpacityPercent / 100}); font-family: ${family}; font-size: ${preferences.fontScalePercent}%; }`
  }, [preferences])

  const update = (patch: Partial<SubtitlePreferences>) => onSet?.({ ...preferences, ...patch })
  const reset = () => onSet?.(DEFAULT_SUBTITLE_PREFERENCES)
  return { preferences, update, reset }
}

export default function Player({
  hlsUrl, playback, mediaItemId, isHost, collaborativeControl, syncMode, onStruggle,
  onToggleMic, onToggleCam, micOn, camOn,
  hideAllFeeds, onToggleHideAllFeeds,
  onToggleLayout, onOpenChat, onToggleChat, layoutMode,
  hideSelf, onToggleHideSelf,
  visible = true, immersive, enterImmersive, exitImmersive,
  phone = false, camStripOpen, seekBridgeRef, onSetPlaybackTracks, subtitlePreferences, onSetSubtitlePreferences,
  onHoldChrome, onReleaseChrome, onPlayingChange,
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
        onToggleLayout={onToggleLayout} onOpenChat={onOpenChat} layoutMode={layoutMode}
        hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
        immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive}
        phone={phone} camStripOpen={camStripOpen}
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
          <HlsVideo ref={videoRef} className="watch-video" src={hlsUrl} playsInline preload="auto" muted={userMuted || hostMuted} style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
        </VideoSkin>

        {canControl && hostMuted && (
          <RestoreSoundPrompt onClick={() => setHostMuted(false)} />
        )}

        {/* Route all playback through SyncPlay + keyboard control */}
        <SyncBridge isHost={isHost} collaborativeControl={collaborativeControl} syncMode={syncMode} onStruggle={onStruggle}
          onOpenChat={onOpenChat} onToggleChat={onToggleChat} immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive} srcUrl={hlsUrl}
          seekBridgeRef={seekBridgeRef} onAutoplayBlocked={() => setHostMuted(true)}
          userMuted={userMuted} onToggleMuted={toggleMuted} onLocalPhase={setLocalPhase} onPlayingChange={onPlayingChange} />

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
            subtitlePreferences={subtitlePreferences}
            onSetSubtitlePreferences={onSetSubtitlePreferences}
            canManageMedia={Boolean(isHost)}
            canControl={canControl} localPhase={localPhase}
            micOn={micOn} camOn={camOn}
            onToggleMic={onToggleMic} onToggleCam={onToggleCam}
            hideAllFeeds={hideAllFeeds} onToggleHideAllFeeds={onToggleHideAllFeeds}
            userMuted={userMuted} onToggleMuted={toggleMuted}
            onHoldChrome={onHoldChrome} onReleaseChrome={onReleaseChrome}
            visible={visible} immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive}
          />
        ) : (
          <>
            {/* The primary transport on desktop: one big knob over the middle of
                the frame. Controllers only — a guest gets no transport at all,
                just the "Host controls playback" hint in the bar. Deliberately
                NOT rendered on phones, where the surface owns single-tap
                (chrome) and double-tap (±10s) gestures a center knob would
                fight; phones keep play/pause in the bar instead. */}
            {canControl && <CenterTransport visible={visible} localPhase={localPhase} />}

            {/* Timeline row + one control row, pinned bottom, over the single
                allowed black-alpha scrim. Read-only for guests (no handle, no
                pointer events on the timeline) — canControl gates
                interactivity throughout. */}
            <DesktopControlBar
              mediaItemId={mediaItemId}
              mediaElementRef={videoRef}
              playback={playback}
              onSetPlaybackTracks={onSetPlaybackTracks}
              subtitlePreferences={subtitlePreferences}
              onSetSubtitlePreferences={onSetSubtitlePreferences}
              canManageMedia={Boolean(isHost)}
              visible={visible} canControl={canControl}
              immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive}
              userMuted={userMuted} onToggleMuted={toggleMuted}
              micOn={micOn} camOn={camOn}
              onToggleMic={onToggleMic} onToggleCam={onToggleCam}
              hideAllFeeds={hideAllFeeds} onToggleHideAllFeeds={onToggleHideAllFeeds}
              onHoldChrome={onHoldChrome} onReleaseChrome={onReleaseChrome}
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
  onToggleMic, onToggleCam, micOn, camOn,
  onToggleLayout, onOpenChat, layoutMode,
  hideSelf, onToggleHideSelf,
  immersive, enterImmersive, exitImmersive,
  phone, camStripOpen, seekBridgeRef,
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
    requestPlay, requestPause, requestSeek,
    holdApplying, releaseApplying, TICKS_PER_SECOND,
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
  const transport = useMemo(() => createLocalTransport({
    ticksPerSecond: TICKS_PER_SECOND,
    hold: holdApplying, release: releaseApplying,
    emitPlay: ticks => requestPlay(ticks, 'local'),
    emitPause: ticks => requestPause(ticks, 'local'),
    emitSeek: ticks => requestSeek(ticks, 'local'),
  }), [holdApplying, releaseApplying, requestPlay, requestPause, requestSeek, TICKS_PER_SECOND])

  useEffect(() => {
    if (!seekBridgeRef) return
    seekBridgeRef.current = {
      canControl: Boolean(canControl),
      seekBy: (delta: number) => {
        const m = playerRef.current
        if (!m || !canControl) return
        transport.seekBy(m, delta)
      },
      // Device toggles must not author playback, but a failure must not vanish
      // either: the caller (Party) turns a rejection into a visible banner.
      guardToggle: async (fn: () => unknown) => { await fn?.() },
    }
    return () => { seekBridgeRef.current = null }
  }, [seekBridgeRef, canControl, transport])

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
          <IconBtn onClick={onToggleMic} title={micOn ? 'Mute mic' : 'Unmute mic'} danger={!micOn}>
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
interface SyncBridgeProps extends Pick<PlayerProps, 'isHost' | 'collaborativeControl' | 'syncMode' | 'onStruggle' | 'onOpenChat' | 'onToggleChat' | 'onPlayingChange' | 'immersive' | 'enterImmersive' | 'exitImmersive' | 'seekBridgeRef'> {
  srcUrl?: string; onAutoplayBlocked?: VoidCallback; userMuted?: boolean; onToggleMuted?: VoidCallback; onLocalPhase?: (phase: LocalPhase) => void
}
function SyncBridge({ isHost, collaborativeControl, syncMode, onStruggle, onOpenChat, onToggleChat, onPlayingChange, immersive, enterImmersive, exitImmersive, srcUrl, seekBridgeRef, onAutoplayBlocked, userMuted, onToggleMuted, onLocalPhase }: SyncBridgeProps = {}) {
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
  // Mirrored into refs so the transport below keeps a stable identity: these say
  // whether media.currentTime currently means anything, and both change often.
  const swappingSrcRef = useRef(false)
  const phaseRef = useRef<LocalPhase>(localPhase)
  phaseRef.current = localPhase

  // The single sequencer for deliberate local commands (keyboard, watch:transport,
  // double-tap bridge): emit exactly one request with origin 'local' — which the
  // authoring guard may never suppress — then hold the guard across the local
  // mutation so the media events it fires cannot author a duplicate.
  const transport = useMemo(() => createLocalTransport({
    ticksPerSecond: TICKS_PER_SECOND,
    hold: holdApplying, release: releaseApplying,
    emitPlay: ticks => requestPlay(ticks, 'local'),
    emitPause: ticks => requestPause(ticks, 'local'),
    emitSeek: ticks => requestSeek(ticks, 'local'),
    // Mid source-swap the element is rebuilding from 0, and mid catch-up it is
    // being driven to a transient position. Authoring the room off either would
    // teleport everyone; the command is dropped instead.
    blocked: () => swappingSrcRef.current || phaseRef.current !== 'ready',
  }), [holdApplying, releaseApplying, requestPlay, requestPause, requestSeek, TICKS_PER_SECOND])

  // ── Imperative seek for the surface gesture layer (Party.jsx double-tap) ────
  // Authors the shared seek itself (origin 'local') and then holds the guard
  // across the local currentTime write, so the room gets EXACTLY ONE sync:seek:
  // the command, never the 'seeked' event it provokes. The old order held the
  // guard first and then called requestSeek, which meant requestSeek's own
  // applyingRef check dropped it — the imperative seek moved this player only
  // and every guest stayed where they were. Gated to controllers (host, or a
  // guest under collaborativeControl); the WatchView caller also gates.
  useEffect(() => {
    if (!seekBridgeRef) return
    seekBridgeRef.current = {
      canControl: Boolean(canControl),
      seekBy: (delta: number) => {
        const m = mediaRef.current
        if (!m || !canControl) return
        transport.seekBy(m, delta)
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
      guardToggle: async (fn: () => unknown) => {
        const before = mediaRef.current
        const wasPlaying = before ? !before.paused : false
        holdApplying()
        // A device failure (permission denied, camera in use) must still leave
        // the guard balanced and the movie playing — but it must NOT be
        // swallowed the way it used to be: re-thrown below so the caller can
        // put it in front of the user.
        let failure: unknown = null
        try { await fn?.() } catch (err) { failure = err }
        // Let any device-(re)acquisition pause/play events settle.
        await new Promise(r => setTimeout(r, 400))
        const m = mediaRef.current
        if (m && wasPlaying && m.paused) { try { await m.play() } catch {} }
        releaseApplying()
        if (failure) throw failure
      },
    }
    return () => { seekBridgeRef.current = null }
  }, [seekBridgeRef, canControl, holdApplying, releaseApplying, transport])

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
    // Same window, but readable synchronously: currentTime is meaningless until
    // the new source has metadata, so no local command may author off it.
    swappingSrcRef.current = true
    holdApplying()   // suppress schedule authoring for the entire reload

    let done = false
    const finish = () => {
      if (done) return
      done = true
      m.removeEventListener('loadedmetadata', onReady)
      m.removeEventListener('loadeddata', onReady)
      swappingSrcRef.current = false
      // Restore local playback position + play/pause state on the new source.
      // These mutations fire their own seeked/play/pause events shortly after;
      // the guard stays held here so those don't author, then is released.
      try { if (Math.abs((m.currentTime || 0) - resumeTime) > 0.25) m.currentTime = resumeTime } catch {}
      if (!wasPaused) m.play().catch(() => {})
      else m.pause()

      if (canControl) {
        // Controller: re-author the shared schedule at the RESTORED position so
        // guests follow across the switch (never 0). These are deliberate local
        // commands (origin 'local'), so the guard stays held straight through —
        // no release/re-hold dance to sneak the emit past our own gate — and the
        // restore's own seeked/play events still can't double-author.
        const ticks = Math.round(resumeTime * TICKS_PER_SECOND)
        if (wasPaused) requestPause(ticks, 'local')
        else { requestSeek(ticks, 'local'); requestPlay(ticks, 'local') }
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
      if (!done) { swappingSrcRef.current = false; releaseApplying() }
    }
  }, [srcUrl]) // eslint-disable-line

  // ── Keyboard controls ──────────────────────────────────────────────────
  // Transport keys author commands directly. Media events are observations;
  // browser stalls and pipeline reconfiguration must never become room intent.
  // Volume / mute / fullscreen / chat are local and available to everyone.
  useEffect(() => {
    const play = (m: MediaLike) => transport.play(m)
    const pause = (m: MediaLike) => transport.pause(m)
    const seek = (m: MediaLike, time: number) => { transport.seekTo(m, time) }
    function onKey(e: KeyboardEvent) {
      const t = e.target instanceof HTMLElement ? e.target : null
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return
      const m = mediaRef.current
      const k = e.key.toLowerCase()
      // Ctrl/Cmd+F → fullscreen (also plain 'f' below)
      if (k === 'f' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); toggleFullscreen(); return }
      // Ctrl/Cmd+C → toggle chat, but only when it is not a copy. The blanket
      // modifier bail below is what has kept copy working, so the one binding
      // allowed past it goes through the shared guard: focus in an editable
      // field, or any selection in the document, and the platform keeps the key.
      // The cheap half of the test runs first — reading the document selection
      // on every keystroke, for a handler bound at window capture, is not free.
      if ((e.ctrlKey || e.metaKey) && k === 'c' && shouldToggleChatFromEvent(e, {
        activeElement: document.activeElement,
        selectionText: String(window.getSelection() ?? ''),
      })) {
        e.preventDefault()
        onToggleChat?.()
        e.stopPropagation()
        return
      }
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
        // ↑ force-unmutes, and has to do it through the state that owns the
        // element's `muted` prop as well as the element itself. Setting
        // m.muted = false alone left `userMuted` true, so the bar still read
        // "muted" and the next M press produced no change React could see.
        case 'arrowup': if (m) { e.preventDefault(); m.volume = Math.min(1, (m.volume ?? 1) + 0.1); m.muted = false; if (userMuted) onToggleMuted?.() } break
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
  }, [canControl, onOpenChat, onToggleChat, userMuted, onToggleMuted, immersive, enterImmersive, exitImmersive, transport])

  // Playback state for the chrome auto-hide, which must never hide over a
  // paused frame. Read through the same localPhase guard the transport glyphs
  // use: useSyncPlay pauses the element itself while catching up, and that is
  // not the user pausing the movie.
  useEffect(() => {
    if (!media || !onPlayingChange) return
    const sync = () => onPlayingChange(!(media.paused && phaseRef.current === 'ready'))
    sync()
    media.addEventListener('play', sync)
    media.addEventListener('pause', sync)
    return () => {
      media.removeEventListener('play', sync)
      media.removeEventListener('pause', sync)
    }
  }, [media, onPlayingChange, localPhase])

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

// ── Desktop centre transport ─────────────────────────────────────────────────
// The big play/pause knob over the middle of the frame — the primary transport
// on the web desktop player (the bottom row carries no play button any more).
// Rendered only for controllers, so a guest sees an unobstructed frame and gets
// the "Host controls playback" hint in the bar instead.
//
// Authoring is unchanged from the button it replaces: dispatch `watch:transport`
// and let SyncBridge's own handler do requestPlay/requestPause under
// holdApplying. `localPhase` keeps the glyph honest — useSyncPlay pauses the
// element itself while catching up/buffering, and without this guard the knob
// would flip to "Play" even though shared intent is still "playing" (and a tap
// would author a spurious play).
function CenterTransport({ visible, localPhase = 'ready' }: { visible?: boolean; localPhase?: LocalPhase } = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const [paused, setPaused] = useState(true)

  useEffect(() => {
    if (!media) return
    const sync = () => setPaused(!!media.paused && localPhase === 'ready')
    sync()
    media.addEventListener('play', sync)
    media.addEventListener('pause', sync)
    return () => { media.removeEventListener('play', sync); media.removeEventListener('pause', sync) }
  }, [media, localPhase])

  const togglePlay = () => window.dispatchEvent(new CustomEvent('watch:transport', { detail: { kind: paused ? 'play' : 'pause' } }))

  return (
    // The wrapper spans the whole stage but is pointer-events:none, so only the
    // knob is clickable and the video surface below keeps its own gestures.
    <div style={{
      position: 'absolute', inset: 0, zIndex: Z.controlBar, display: 'grid', placeItems: 'center',
      opacity: visible ? 1 : 0, transition: 'opacity .25s', pointerEvents: 'none',
    }}>
      <button
        onClick={(e) => { e.stopPropagation(); togglePlay() }}
        title={paused ? 'Play (Space)' : 'Pause (Space)'} aria-label={paused ? 'Play' : 'Pause'}
        style={{
          width: 78, height: 78, borderRadius: '50%', border: 'none',
          display: 'grid', placeItems: 'center', cursor: 'pointer',
          background: 'rgba(0,0,0,.42)', color: '#f4f4f5',
          pointerEvents: visible ? 'auto' : 'none',
          transition: 'background-color .15s, transform .12s',
        }}
        onMouseEnter={e => { e.currentTarget.style.backgroundColor = 'rgba(0,0,0,.62)'; e.currentTarget.style.transform = 'scale(1.05)' }}
        onMouseLeave={e => { e.currentTarget.style.backgroundColor = 'rgba(0,0,0,.42)'; e.currentTarget.style.transform = 'scale(1)' }}
      >
        {paused
          ? <svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor" style={{ marginLeft: 3 }}><path d="M8 5v14l11-7z"/></svg>
          : <svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>}
      </button>
    </div>
  )
}

// ── The three feed controls shared by both web bars ──────────────────────────
// hide-all-feeds, camera, mic — in that order, dead centre of the bottom row on
// desktop and on phones. `Btn` is the host bar's own button shell (IconBtn on
// desktop, the 44px-touch-target BarBtn on phones) so each bar keeps its own
// hit-area rules while the glyph set and wiring stay in one place.
//
// None of the three is gated on canControl: they're room/display controls, not
// playback, so a guest gets all of them. Hide-all-feeds in particular is purely
// local — it hides every camera tile from THIS screen only.
type FeedControlProps = Pick<PlayerProps, 'micOn' | 'camOn' | 'onToggleMic' | 'onToggleCam' | 'hideAllFeeds' | 'onToggleHideAllFeeds'>
function FeedControls({ Btn, glyph, micOn, camOn, onToggleMic, onToggleCam, hideAllFeeds, onToggleHideAllFeeds }: FeedControlProps & { Btn: ComponentType<ButtonProps>; glyph: number }) {
  return (
    <>
      {onToggleHideAllFeeds && (
        <Btn onClick={onToggleHideAllFeeds} active={hideAllFeeds} title={hideAllFeeds ? 'Show camera feeds' : 'Hide camera feeds'}>
          {hideAllFeeds
            ? <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4"/></svg>
            : <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>}
        </Btn>
      )}
      {onToggleCam && (
        <Btn onClick={onToggleCam} title={camOn ? 'Camera off' : 'Camera on'} danger={!camOn}>
          {camOn
            ? <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="2" y="6" width="14" height="12" rx="2"/><path d="m16 10 6-3v10l-6-3"/></svg>
            : <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M16 16H4a2 2 0 0 1-2-2V8m4-2h8a2 2 0 0 1 2 2v3l4-2v8"/></svg>}
        </Btn>
      )}
      {onToggleMic && (
        <Btn onClick={onToggleMic} title={micOn ? 'Mute mic' : 'Unmute mic'} danger={!micOn}>
          {micOn
            ? <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
            : <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V5a3 3 0 0 0-5.7-1.3M19 10v2a7 7 0 0 1-.7 3M12 19v3"/></svg>}
        </Btn>
      )}
    </>
  )
}

// Gear glyph — one copy, used by both bars' settings button.
function GearGlyph({ size }: { size: number }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
}

// Fullscreen enter/exit glyph — one copy, used by both bars.
function FullscreenGlyph({ size, immersive }: { size: number; immersive?: boolean }) {
  return immersive
    ? <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M8 3v4a1 1 0 0 1-1 1H3M21 8h-4a1 1 0 0 1-1-1V3M16 21v-4a1 1 0 0 1 1-1h4M3 16h4a1 1 0 0 1 1 1v4"/></svg>
    : <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M3 8V5a2 2 0 0 1 2-2h3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M21 16v3a2 2 0 0 1-2 2h-3"/></svg>
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
      const idx = hlsIndexForJellyfin(hls.audioTracks, target, 'AudioStreamIndex', playback?.audioStreams)
      if (idx >= 0 && hls.audioTrack !== idx) hls.audioTrack = idx
    }
    apply()
    const onManifest = () => apply()
    hls.on('hlsManifestParsed', onManifest)
    return () => { hls.off('hlsManifestParsed', onManifest) }
  }, [media, playback?.selectedAudioIndex, playback?.audioStreams])

  const choose = useCallback((jellyfinIndex: number) => {
    const hls = media?.engine
    if (!hls) return
    const idx = hlsIndexForJellyfin(hls.audioTracks, jellyfinIndex, 'AudioStreamIndex', playback?.audioStreams)
    if (idx >= 0) hls.audioTrack = idx
  }, [media, playback?.audioStreams])

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
function useSubtitleTrack(media: MediaLike | null | undefined, videoRef: RefObject<HTMLVideoElement | null> | undefined, playback: PlayerPlayback | undefined, preferences: SubtitlePreferences, mediaItemId?: string): SubtitleTrackState {
  const ownedTracks = useRef(new Map<number, TextTrack>())
  const externalTracks = useRef(new Map<number, HTMLTrackElement>())
  const selectedIndex = useRef<number | null>(playback?.selectedSubtitleIndex ?? null)
  const preferencesRef = useRef(preferences)
  preferencesRef.current = preferences
  const resolveHlsIdx = useCallback((hls: HlsLike, jellyfinIndex: number | null | undefined) => {
    if (jellyfinIndex == null || jellyfinIndex < 0) return -1
    return hlsIndexForJellyfin(hls.subtitleTracks, jellyfinIndex, 'SubtitleStreamIndex', playback?.subtitleStreams)
  }, [playback?.subtitleStreams])

  const ensureExternalTrack = useCallback((stream: PlayerTrack) => {
    const video = videoRef?.current
    if (!video || !mediaItemId || !stream.isExternal) return null
    let trackElement = externalTracks.current.get(stream.index)
    if (trackElement) return trackElement
    trackElement = document.createElement('track')
    trackElement.kind = 'subtitles'
    trackElement.label = stream.displayTitle || stream.title || stream.language || `Subtitle ${stream.index}`
    if (stream.language) trackElement.srclang = stream.language
    trackElement.src = subtitleContentUrl(mediaItemId, stream.index, playback?.mediaSourceId)
    trackElement.dataset.watchpartySubtitle = String(stream.index)
    trackElement.addEventListener('load', () => applyCuePreferences(trackElement!.track, preferencesRef.current))
    video.append(trackElement)
    externalTracks.current.set(stream.index, trackElement)
    return trackElement
  }, [mediaItemId, playback?.mediaSourceId, videoRef])

  useEffect(() => {
    for (const stream of playback?.subtitleStreams ?? []) {
      if (!stream.isExternal) continue
      const element = ensureExternalTrack(stream)
      if (element && stream.index !== selectedIndex.current) element.track.mode = 'hidden'
    }
  }, [playback?.subtitleStreams, ensureExternalTrack])

  useEffect(() => () => {
    for (const element of externalTracks.current.values()) element.remove()
    externalTracks.current.clear()
    ownedTracks.current.clear()
  }, [mediaItemId])

  const applySubtitle = useCallback((hls: HlsLike, target: number | null | undefined) => {
    const video = videoRef?.current
    const tracks = video?.textTracks
    const stream = playback?.subtitleStreams?.find(candidate => candidate.index === target)
    const hlsIdx = resolveHlsIdx(hls, target)
    const hlsTrack = hlsIdx >= 0 ? hls.subtitleTracks[hlsIdx] : null

    if (video && stream?.isExternal) {
      // Uploaded external subtitles are fetched through the authenticated app
      // endpoint, which always returns browser-ready WebVTT.
      hls.subtitleTrack = -1
      const trackElement = ensureExternalTrack(stream)
      if (!trackElement) return
      applyCuePreferences(trackElement.track, preferencesRef.current)
      if (tracks) {
        for (let i = 0; i < tracks.length; i++) {
          const tt = tracks[i]
          if (tt.kind !== 'subtitles' && tt.kind !== 'captions') continue
          const preloaded = [...externalTracks.current.values()].some(element => element.track === tt)
          tt.mode = tt === trackElement.track ? 'showing' : preloaded ? 'hidden' : 'disabled'
        }
      }
      return
    }

    // Tell hls.js which subtitle track to load (or -1 to disable)
    hls.subtitleTrack = hlsIdx

    // @videojs/core creates its own tracks but drops their cues. Keep a browser
    // track we own for each HLS rendition instead, so track labels/languages
    // cannot accidentally route Movie A's cues to Movie B's selected subtitle.
    if (hlsTrack && !ownedTracks.current.has(hlsIdx) && video) {
      ownedTracks.current.set(hlsIdx, video.addTextTrack('subtitles', hlsTrack.name, hlsTrack.lang))
    }
    // Sync DOM text track modes. Third-party tracks remain disabled; only our
    // exact HLS-rendition track is allowed to render.
    if (!tracks) return
    for (let i = 0; i < tracks.length; i++) {
      const tt = tracks[i]
      if (tt.kind !== 'subtitles' && tt.kind !== 'captions') continue
      const preloaded = [...externalTracks.current.values()].some(element => element.track === tt)
      tt.mode = ownedTracks.current.get(hlsIdx) === tt ? 'showing' : preloaded ? 'hidden' : 'disabled'
    }
  }, [playback?.subtitleStreams, resolveHlsIdx, videoRef, ensureExternalTrack])

  useEffect(() => {
    selectedIndex.current = playback?.selectedSubtitleIndex ?? null
    if (!media) return
    let hls: HlsLike | undefined
    let poll: ReturnType<typeof setInterval> | undefined

    // Deliver cues from hlsCuesParsed directly to the correct DOM track,
    // bypassing the mixin's broken getTrackById-based cue delivery.
    const onCuesParsed = (...args: unknown[]) => {
      const engine = hls
      if (!engine) return
      const data = args[1] as { cues: unknown[] }
      const selectedStream = playback?.subtitleStreams?.find(stream => stream.index === selectedIndex.current)
      if (selectedStream?.isExternal) return
      const hlsIdx = resolveHlsIdx(engine, selectedIndex.current)
      if (hlsIdx < 0) return
      if (!engine.subtitleTracks[hlsIdx]) return
      // hls.js only loads and parses the selected subtitle rendition. Its cue
      // batch name is based on an internal fragment level, which is not stable
      // enough to compare with either the array index or public track id.
      const tt = ownedTracks.current.get(hlsIdx)
      if (!tt) return
      const wasDisabled = tt.mode === 'disabled'
      if (wasDisabled) tt.mode = 'hidden'
      for (const cue of data.cues) {
        if (tt.cues?.getCueById((cue as VTTCue).id)) continue
        tt.addCue(cue as VTTCue)
      }
      applyCuePreferences(tt, preferencesRef.current)
      if (wasDisabled) tt.mode = 'showing'
    }

    const onManifest = () => { if (hls) applySubtitle(hls, selectedIndex.current) }
    const attach = () => {
      const engine = media.engine
      if (!engine) return false
      hls = engine
      applySubtitle(engine, selectedIndex.current)
      engine.on('hlsCuesParsed', onCuesParsed)
      engine.on('hlsManifestParsed', onManifest)
      return true
    }
    if (!attach()) poll = setInterval(() => { if (attach() && poll) clearInterval(poll) }, 50)
    return () => {
      if (poll) clearInterval(poll)
      hls?.off('hlsCuesParsed', onCuesParsed)
      hls?.off('hlsManifestParsed', onManifest)
    }
  }, [media, playback?.selectedSubtitleIndex, playback?.subtitleStreams, applySubtitle, resolveHlsIdx])

  const choose = useCallback((jellyfinIndex: number | null) => {
    selectedIndex.current = jellyfinIndex
    const hls = media?.engine
    if (!hls) return
    applySubtitle(hls, jellyfinIndex)
  }, [media, applySubtitle])

  useEffect(() => {
    const video = videoRef?.current
    if (!video) return
    for (let i = 0; i < video.textTracks.length; i++) applyCuePreferences(video.textTracks[i], preferences)
  }, [preferences, videoRef])

  return { choose }
}

function levelLabel(l: HlsLevel | null | undefined) {
  if (!l) return ''
  const h = l.height ? `${l.height}p` : (l.width ? `${l.width}w` : '')
  const mbps = l.bitrate ? `${(l.bitrate / 1_000_000).toFixed(1)} Mbps` : ''
  return [h, mbps].filter(Boolean).join(' · ') || 'Auto'
}

// ── Read-only playback clock (position / duration / buffered ranges) ────────
//
// The buffer used to be a single number — `buffered.end(length - 1)`, the
// furthest loaded point — and the bar drew from zero to it. That painted every
// hole in the buffer as loaded: after a forward seek, the whole span behind the
// new position reads as buffered when none of it is. The real range list is read
// here instead, and AnalogTimeline renders the holes.
function readBufferedRanges(media: MediaLike | null | undefined): TimeSpan[] {
  const ranges: TimeSpan[] = []
  try {
    const buffered = media?.buffered
    if (buffered) {
      for (let i = 0; i < buffered.length; i++) ranges.push({ start: buffered.start(i), end: buffered.end(i) })
    }
  } catch {}
  return ranges
}

function useMediaClock(media: MediaLike | null | undefined) {
  const [c, setC] = useState<{ cur: number; dur: number; ranges: TimeSpan[] }>({ cur: 0, dur: 0, ranges: [] })
  useEffect(() => {
    if (!media) return
    const sync = () => setC({ cur: media.currentTime || 0, dur: media.duration || 0, ranges: readBufferedRanges(media) })
    sync()
    const evs = ['timeupdate', 'durationchange', 'progress', 'seeked', 'loadedmetadata']
    evs.forEach(e => media.addEventListener(e, sync))
    return () => evs.forEach(e => media.removeEventListener(e, sync))
  }, [media])
  return c
}

// One clock format for the bar's own label and the scrub preview alike; see
// analog/player/format.ts.
const fmtClock = formatClock

// ── The timeline: AnalogTimeline over the media element ─────────────────────
//
// One component for both bars (the desktop scrubber and the phone timeline row
// were two near-identical implementations that had already drifted — the phone
// one had no hover state and no thumb at all).
//
// What lives here rather than in the kit is everything that needs a media
// element or the network: the trickplay manifest, and the seek itself. Dragging
// still mutates media.currentTime directly, exactly as before — the surrounding
// row carries the `.watch-skin` class so SyncBridge's capture-phase
// pointerdown-arm fires before the mutation, and the existing seeking/seeked →
// requestSeek pipeline authors the room unchanged.
//
// `cached` is left unset: there is no on-disk cache in this client to read time
// spans from, so the layer renders empty rather than being faked out of the
// network buffer.
interface PlayerTimelineProps {
  canControl?: boolean
  mediaItemId?: string
  mediaSourceId?: string | null
  labels?: boolean
  trailing?: ReactNode
  onHoldChrome?: (reason: string) => void
  onReleaseChrome?: (reason: string) => void
}
function PlayerTimeline({ canControl, mediaItemId, mediaSourceId, labels, trailing, onHoldChrome, onReleaseChrome }: PlayerTimelineProps = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const { cur, dur, ranges } = useMediaClock(media)
  const preferences = useDisplayPreferences()
  const [manifest, setManifest] = useState<TrickplayManifest | null>(null)
  const [failedSheet, setFailedSheet] = useState<number | null>(null)

  useEffect(() => {
    setManifest(null)
    setFailedSheet(null)
    if (!mediaItemId) return
    const controller = new AbortController()
    const query = mediaSourceId ? `?mediaSourceId=${encodeURIComponent(mediaSourceId)}` : ''
    fetch(`/api/library/items/${encodeURIComponent(mediaItemId)}/trickplay${query}`, { credentials: 'include', signal: controller.signal })
      .then(response => response.ok ? response.json() as Promise<unknown> : null)
      .then(value => { if (value) setManifest(parseTrickplayManifest(value)) })
      .catch(() => {})
    return () => controller.abort()
  }, [mediaItemId, mediaSourceId])

  // Titles with no trickplay manifest return null here and AnalogTimeline falls
  // back to a bare time chip — those used to get no scrub preview at all.
  const renderPreview = (time: number): TimelinePreview | null => {
    if (!manifest) return null
    const frame = trickplayFrame(manifest, time)
    if (!frame || frame.sheetIndex === failedSheet) return null
    const scale = Math.min(1, 240 / manifest.width)
    const width = manifest.width * scale
    const height = manifest.height * scale
    return {
      width,
      node: (
        <div style={{
          width, overflow: 'hidden', borderRadius: analogTokens.radius.chromePx,
          background: 'var(--an-color-stage-void)', border: '1px solid var(--an-color-line-strong)',
          boxShadow: '0 4px 18px var(--an-color-shadow-cast)',
        }}>
          <div style={{ position: 'relative', width, height, overflow: 'hidden' }}>
            <img
              src={trickplaySheetUrl(manifest, frame.sheetIndex)} alt=""
              onError={() => setFailedSheet(frame.sheetIndex)}
              style={{ position: 'absolute', width: manifest.width * frame.columns * scale, height: manifest.height * frame.rows * scale, left: -frame.x * scale, top: -frame.y * scale, maxWidth: 'none' }}
            />
          </div>
          <div style={{ padding: '5px 8px', textAlign: 'center', fontFamily: MONO_F, fontSize: 11, color: 'var(--an-color-ink)' }}>{fmtClock(time)}</div>
        </div>
      ),
    }
  }

  return (
    <AnalogTimeline
      positionSec={cur}
      durationSec={dur}
      buffered={ranges}
      canControl={canControl}
      onScrub={(seconds) => { if (media) media.currentTime = seconds }}
      onScrubStart={() => onHoldChrome?.(CHROME_HOLD.scrubbing)}
      onScrubEnd={() => onReleaseChrome?.(CHROME_HOLD.scrubbing)}
      renderPreview={renderPreview}
      labels={labels}
      trailing={trailing}
      preferences={preferences}
      ariaLabel="Playback progress"
    />
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

// Mute + the vertical volume hairline, over the media element.
//
// Replaces the horizontal `<input type="range">` that used to sit in the desktop
// bar's LEFT cluster; the vertical control lives near the right edge instead,
// per the reference. The phone bar had no volume control at all — it does now.
//
// Volume is purely local (media.volume) and — like the mute toggle itself — is
// deliberately NOT gated on canControl: audio is independent of playback-control
// permission, so a guest can unmute and set their own level.
//
// The `volumechange` subscription is new. Without it the ↑/↓ keys moved the
// element's volume while the control kept rendering its own stale copy, so the
// two disagreed until the component happened to remount.
function PlayerVolume({ userMuted, onToggleMuted, size = 34, glyph = 18, reveal, onHoldChrome, onReleaseChrome }: {
  userMuted?: boolean; onToggleMuted?: VoidCallback; size?: number; glyph?: number
  reveal?: 'hover' | 'always'
  onHoldChrome?: (reason: string) => void; onReleaseChrome?: (reason: string) => void
} = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const preferences = useDisplayPreferences()
  const [volume, setVolume] = useState(1)

  useEffect(() => {
    if (!media) return
    const sync = () => setVolume(media.volume ?? 1)
    sync()
    media.addEventListener('volumechange', sync)
    return () => media.removeEventListener('volumechange', sync)
  }, [media])

  return (
    <AnalogVolume
      volume={volume}
      muted={Boolean(userMuted) || volume === 0}
      onSetVolume={(next) => { setVolume(next); if (media) media.volume = next }}
      onToggleMute={() => onToggleMuted?.()}
      reveal={reveal}
      size={size}
      glyph={glyph}
      preferences={preferences}
      onHold={() => onHoldChrome?.(CHROME_HOLD.volume)}
      onRelease={() => onReleaseChrome?.(CHROME_HOLD.volume)}
    />
  )
}

// ── Desktop control chrome ───────────────────────────────────────────────────
// Two stacked rows over the one allowed black-alpha scrim, no box or border
// around either:
//   1. a full-width timeline hairline, edge to edge of the bar
//   2. one control row in three clusters — left: a compact mono
//      `current / total`; centre: hide-feeds, camera, mic; right: mute + the
//      vertical volume hairline, gear, fullscreen
// Volume moved from the left cluster to the right in the analog redesign: the
// reference puts it "near the right edge" as a compact vertical control rather
// than a long horizontal slider in the transport.
// Play/pause is NOT here: on desktop it's the big CenterTransport knob over the
// middle of the frame. Guests get no transport at all, and the "Host controls
// playback" hint sits in the left cluster instead.
interface ControlBarProps extends Pick<PlayerProps, 'mediaItemId' | 'playback' | 'onSetPlaybackTracks' | 'subtitlePreferences' | 'onSetSubtitlePreferences' | 'visible' | 'immersive' | 'enterImmersive' | 'exitImmersive' | 'micOn' | 'camOn' | 'onToggleMic' | 'onToggleCam' | 'hideAllFeeds' | 'onToggleHideAllFeeds' | 'onHoldChrome' | 'onReleaseChrome'> {
  mediaElementRef?: RefObject<HTMLVideoElement | null>; canControl?: boolean; canManageMedia?: boolean; userMuted?: boolean; onToggleMuted?: VoidCallback; localPhase?: LocalPhase
}
function DesktopControlBar({
  mediaItemId, playback, mediaElementRef, onSetPlaybackTracks,
  subtitlePreferences: canonicalSubtitlePreferences, onSetSubtitlePreferences,
  visible, canControl, canManageMedia, immersive, enterImmersive, exitImmersive,
  userMuted, onToggleMuted, micOn, camOn, onToggleMic, onToggleCam, hideAllFeeds, onToggleHideAllFeeds,
  onHoldChrome, onReleaseChrome,
}: ControlBarProps = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const quality = useQualityLevels(media)
  const audioTrack = useAudioTrack(media, playback)
  const subtitlePreferences = useSubtitlePreferences(mediaElementRef, canonicalSubtitlePreferences, onSetSubtitlePreferences)
  const subtitleTrack = useSubtitleTrack(media, mediaElementRef, playback, subtitlePreferences.preferences, mediaItemId)
  const { cur, dur } = useMediaClock(media)
  const [settingsOpen, setSettingsOpen] = useState(false)

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
        position: 'absolute', left: 0, right: 0, bottom: 0, height: 140,
        background: 'linear-gradient(0deg, rgba(0,0,0,.8), transparent)',
        pointerEvents: 'none',
      }} />
      <div style={{
        position: 'relative', display: 'flex', flexDirection: 'column', gap: 2,
        padding: '0 18px 12px',
      }}>
        {/* Row 1 — the timeline, spanning the full width of the bar. The row
            wrapper is a flex ROW on purpose: the track sizes itself with
            `flex: 1`, which would resolve against the column axis (and collapse
            its height to 0) if it were a direct child of the column above. */}
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <PlayerTimeline
            canControl={canControl} mediaItemId={mediaItemId} mediaSourceId={playback?.mediaSourceId}
            onHoldChrome={onHoldChrome} onReleaseChrome={onReleaseChrome}
          />
        </div>

        {/* Row 2 — three clusters. A 1fr/auto/1fr grid so the centre trio is
            truly centred in the bar regardless of how wide the side clusters
            grow (long durations, the guest hint). */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr', alignItems: 'center', gap: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
            <span style={{ fontFamily: MONO_F, fontSize: 12, fontVariantNumeric: 'tabular-nums', color: 'rgba(244,244,245,.62)', flexShrink: 0, whiteSpace: 'nowrap' }}>
              <span style={{ color: '#f4f4f5' }}>{fmtClock(cur)}</span> / {fmtClock(dur)}
            </span>
            {!canControl && <HostControlsHint />}
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
            <FeedControls
              Btn={IconBtn} glyph={18}
              micOn={micOn} camOn={camOn} onToggleMic={onToggleMic} onToggleCam={onToggleCam}
              hideAllFeeds={hideAllFeeds} onToggleHideAllFeeds={onToggleHideAllFeeds}
            />
          </div>

          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 4 }}>
            {/* Volume moved here from the left cluster: "a compact vertical
                control near the right edge rather than a long horizontal slider
                in the bottom transport". */}
            <PlayerVolume
              userMuted={userMuted} onToggleMuted={onToggleMuted}
              onHoldChrome={onHoldChrome} onReleaseChrome={onReleaseChrome}
            />
            <div style={{ position: 'relative' }}>
              <IconBtn onClick={() => setSettingsOpen(o => !o)} title="Settings" active={settingsOpen}>
                <GearGlyph size={18} />
              </IconBtn>
              {/* Mounted only while open, as before: the menu's own view stack
                  and search box reset each time it is opened. */}
              {settingsOpen && <SettingsMenu open playback={playback} mediaItemId={mediaItemId} quality={quality} canManageMedia={canManageMedia} onSetPlaybackTracks={onSetPlaybackTracks} onChooseAudio={audioTrack.choose} onChooseSubtitle={subtitleTrack.choose} subtitlePreferences={subtitlePreferences.preferences} onUpdateSubtitlePreferences={subtitlePreferences.update} onResetSubtitlePreferences={subtitlePreferences.reset} onClose={() => setSettingsOpen(false)} onHoldChrome={onHoldChrome} onReleaseChrome={onReleaseChrome} />}
            </div>

            <IconBtn onClick={() => (immersive ? exitImmersive?.() : enterImmersive?.())} title={immersive ? 'Exit full screen (Ctrl+F)' : 'Full screen (Ctrl+F)'}>
              <FullscreenGlyph size={18} immersive={immersive} />
            </IconBtn>
          </div>
        </div>
      </div>
    </div>
  )
}

// ── Mobile consolidated bottom bar ───────────────────────────────────────────
// One flat bar pinned to the bottom (clear of the home-indicator via safe-area),
// over the same black-alpha scrim as the desktop row, and the same philosophy as
// the desktop chrome: a draggable timeline row on top, then ONE control row in
// three clusters — left: play/pause (a lock glyph for guests); centre:
// hide-feeds, camera, mic; right: gear, fullscreen.
//
// Six controls fit a narrow phone directly, so the old `useWideBar` split (a
// primary cluster plus a "⋯" overflow popover below 820px) is gone along with
// push-to-talk and the hide-self toggle it used to hold.
//
// Phones deliberately keep play/pause IN THE BAR rather than getting desktop's
// big CenterTransport knob: the video surface already binds single-tap (toggle
// chrome) and double-tap (±10s seek) in WatchView, and a centre button would
// fight both. Fades with the auto-hide `visible` layer. Touch targets are 44px
// with ≥8px gaps.
function MobileBottomBar({
  mediaItemId,
  playback,
  mediaElementRef,
  onSetPlaybackTracks,
  subtitlePreferences: canonicalSubtitlePreferences,
  onSetSubtitlePreferences,
  canManageMedia,
  canControl, localPhase, micOn, camOn, onToggleMic, onToggleCam,
  hideAllFeeds, onToggleHideAllFeeds, visible, immersive, enterImmersive, exitImmersive,
  userMuted, onToggleMuted, onHoldChrome, onReleaseChrome,
}: ControlBarProps = {}) {
  const media = VPlayer.useMedia() as unknown as MediaLike
  const quality = useQualityLevels(media)
  const audioTrack = useAudioTrack(media, playback)
  const subtitlePreferences = useSubtitlePreferences(mediaElementRef, canonicalSubtitlePreferences, onSetSubtitlePreferences)
  const subtitleTrack = useSubtitleTrack(media, mediaElementRef, playback, subtitlePreferences.preferences, mediaItemId)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [paused, setPaused] = useState(true)
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

  const togglePlay = () => {
    if (!media || !canControl) return
    // Use the same localPhase-aware `paused` the button renders from, not raw
    // media.paused, so tapping the button during a catch-up/buffering pause
    // sends 'pause' (matching what the button visually shows) rather than a
    // redundant/confusing 'play'.
    window.dispatchEvent(new CustomEvent('watch:transport', { detail: { kind: paused ? 'play' : 'pause' } }))
  }

  // Menus never auto-hide: keep the bar visible while settings is open.
  const shown = visible || settingsOpen

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
        {/* Timeline row: everyone on a phone sees position / progress / duration
            here. The skin's own scrubber is hidden on phones (watch-skin--nobar);
            controllers can drag this one directly, or double-tap-seek.
            The mute + vertical volume control rides at the right END OF THIS ROW
            rather than in the control row below it: a seventh 44px button does
            not fit a 360px-wide phone alongside the six that are already there,
            and this row is a stretchy track that simply gives up the width. */}
        <div style={{ padding: '2px 6px 0' }}>
          <PlayerTimeline
            canControl={canControl} mediaItemId={mediaItemId} mediaSourceId={playback?.mediaSourceId}
            labels
            onHoldChrome={onHoldChrome} onReleaseChrome={onReleaseChrome}
            trailing={
              <>
                {!canControl && <span style={{ fontSize: 10.5, color: 'rgba(244,244,245,.36)', flexShrink: 0 }}>Host controls</span>}
                <PlayerVolume
                  userMuted={userMuted} onToggleMuted={onToggleMuted}
                  // Touch has no hover: the track is permanently revealed on a
                  // phone, otherwise there is no gesture that opens it.
                  reveal="always" size={44} glyph={19}
                  onHoldChrome={onHoldChrome} onReleaseChrome={onReleaseChrome}
                />
              </>
            }
          />
        </div>

        {/* The one control row — three clusters, centre trio truly centred via
            a 1fr/auto/1fr grid so it doesn't drift with the side clusters. */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr', alignItems: 'center', gap: 8 }}>
          {/* Left — transport: play/pause for controllers, lock glyph for
              guests. Phones keep transport in the bar (see the component
              comment) rather than getting desktop's centre knob. */}
          <div style={{ display: 'flex', alignItems: 'center' }}>
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
          </div>

          {/* Centre — the same three feed controls as the desktop bar. */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <FeedControls
              Btn={BarBtn} glyph={19}
              micOn={micOn} camOn={camOn} onToggleMic={onToggleMic} onToggleCam={onToggleCam}
              hideAllFeeds={hideAllFeeds} onToggleHideAllFeeds={onToggleHideAllFeeds}
            />
          </div>

          {/* Right — gear (the unchanged SettingsMenu) + fullscreen. */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 8 }}>
            <div style={{ position: 'relative' }}>
              <BarBtn onClick={() => setSettingsOpen(o => !o)} active={settingsOpen} title="Settings">
                <GearGlyph size={19} />
              </BarBtn>
              {settingsOpen && <SettingsMenu open playback={playback} mediaItemId={mediaItemId} quality={quality} canManageMedia={canManageMedia} onSetPlaybackTracks={onSetPlaybackTracks} onChooseAudio={audioTrack.choose} onChooseSubtitle={subtitleTrack.choose} subtitlePreferences={subtitlePreferences.preferences} onUpdateSubtitlePreferences={subtitlePreferences.update} onResetSubtitlePreferences={subtitlePreferences.reset} onClose={() => setSettingsOpen(false)} onHoldChrome={onHoldChrome} onReleaseChrome={onReleaseChrome} compact />}
            </div>

            {/* Fullscreen: reads the single `immersive` state and calls the
                enter/exit callbacks owned by WatchView. On iPhone this triggers
                the CSS faux-fullscreen that KEEPS the whole party (chat,
                cameras, room code) — it is NOT the native video player. */}
            <BarBtn onClick={() => (immersive ? exitImmersive?.() : enterImmersive?.())} title={immersive ? 'Exit full screen' : 'Full screen'}>
              <FullscreenGlyph size={19} immersive={immersive} />
            </BarBtn>
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

// ── Settings — two-level menu that scales to many tracks (search + scroll) ────
// Flat solid surface, hairline border, radius 12 — no blur, no gradient.

// Density scale for the gear menu. `regular` is the verbatim desktop sizing —
// nothing here is reachable without passing `compact`, so DesktopControlBar
// renders pixel-identically to before. `compact` is what MobileBottomBar passes:
// a phone is held ~30cm from the eye and the landscape viewport is only ~400px
// tall, so type, padding, width and the panel's own max height all come down.
//
// Two numbers deliberately go UP on phone, because MOBILE-SPEC §5.3/§5.4 are
// hard constraints that outrank "make it smaller":
//   · text inputs and <select> stay at 16px — below that iOS zooms the field on
//     focus and the whole page shifts (the styles.css `pointer: coarse` rule
//     can't save us, an inline fontSize beats a stylesheet).
//   · every tappable row/button gets minHeight 44 on phone.
// So "scale down" here means type, padding, panel width and panel height — the
// per-row hit boxes stay finger-sized.
interface MenuScale {
  width: number; radius: number; bottom: number; right: number; maxHeight: string; maxWidth?: string
  listPad: string; mainPad: string
  navPad: string; navFont: number; navValFont: number; navValMax: number; navGap: number; navChev: number
  optPad: string; optFont: number; optGap: number; optTick: number
  headPad: string; headBtn: number; headGlyph: number; headFont: number; headGap: number
  searchPad: number; inputPad: string; inputFont: number; inputRadius: number
  rowMin?: number
  setPad: string; setLabel: number; setValue: number; setGap: number
  selPad: string; selFont: number
  btnPad: string; btnFont: number; btnRadius: number; noteFont: number; hintFont: number
  emptyPad: string; emptyFont: number
  footPad: number
}
const MENU_REGULAR: MenuScale = {
  width: 292, radius: 12, bottom: 52, right: 0, maxHeight: '70vh',
  listPad: '6px 0', mainPad: '6px 0',
  navPad: '12px 14px', navFont: 13.5, navValFont: 12.5, navValMax: 130, navGap: 12, navChev: 14,
  optPad: '10px 14px', optFont: 13, optGap: 10, optTick: 15,
  headPad: '11px 12px', headBtn: 26, headGlyph: 14, headFont: 11, headGap: 8,
  searchPad: 10, inputPad: '9px 12px', inputFont: 13, inputRadius: 9,
  setPad: '10px 14px', setLabel: 12.5, setValue: 11.5, setGap: 8,
  selPad: '8px 10px', selFont: 12.5,
  btnPad: '9px 12px', btnFont: 13, btnRadius: 9, noteFont: 11.5, hintFont: 11,
  emptyPad: '8px 14px', emptyFont: 12.5,
  footPad: 12,
}
const MENU_COMPACT: MenuScale = {
  width: 232, radius: 10, bottom: 50,
  // Right-aligned to the bar's own right edge rather than to the gear button:
  // the gear is followed by the (unconditional) 44px fullscreen button plus the
  // row's 8px gap, so -52 lines the panel up with the end of the bar and buys
  // 52px of horizontal room instead of hanging off the gear.
  right: -52,
  // Fit the space that actually exists ABOVE the bar instead of a bare 70vh.
  // 76 = bar offset (8) + bar padding (2) + button (44) + menu gap (6) + 16px of
  // clearance under the notch; --app-vh is the visualViewport height MobileApp
  // publishes, falling back to dvh when the party route is mounted outside it.
  // The 248 cap keeps the popover under ~2/3 of a 402px landscape screen — the
  // lists inside scroll, the panel itself never overflows the viewport.
  maxHeight: 'min(248px, calc(var(--app-vh, 100dvh) - var(--sa-t, 0px) - var(--sa-b, 0px) - 76px))',
  maxWidth: 'calc(100vw - var(--sa-l, 0px) - var(--sa-r, 0px) - 28px)',
  listPad: '3px 0', mainPad: '4px 0',
  navPad: '5px 10px', navFont: 12, navValFont: 11, navValMax: 96, navGap: 8, navChev: 12,
  optPad: '5px 10px', optFont: 11.5, optGap: 8, optTick: 13,
  headPad: '2px 6px 2px 2px', headBtn: 44, headGlyph: 15, headFont: 10, headGap: 6,
  searchPad: 6, inputPad: '8px 10px', inputFont: 16, inputRadius: 8,
  rowMin: 44,
  setPad: '6px 10px', setLabel: 11, setValue: 10.5, setGap: 5,
  selPad: '6px 8px', selFont: 16,
  btnPad: '9px 12px', btnFont: 12, btnRadius: 8, noteFont: 10.5, hintFont: 10,
  emptyPad: '6px 10px', emptyFont: 11,
  footPad: 6,
}

interface SettingsMenuProps {
  open?: boolean
  playback?: PlayerPlayback; mediaItemId?: string; quality: QualityState; canManageMedia?: boolean
  onSetPlaybackTracks?: (tracks: TrackSelection) => void; onChooseAudio?: (jellyfinIndex: number) => void; onChooseSubtitle?: (jellyfinIndex: number | null) => void
  subtitlePreferences?: SubtitlePreferences; onUpdateSubtitlePreferences?: (patch: Partial<SubtitlePreferences>) => void; onResetSubtitlePreferences?: VoidCallback; onClose?: VoidCallback
  onHoldChrome?: (reason: string) => void; onReleaseChrome?: (reason: string) => void
  /** Phone density (MobileBottomBar). Omitted/false keeps the desktop scale. */
  compact?: boolean
}
function SettingsMenu({ open = false, playback, mediaItemId, quality, canManageMedia, onSetPlaybackTracks, onChooseAudio, onChooseSubtitle, subtitlePreferences = DEFAULT_SUBTITLE_PREFERENCES, onUpdateSubtitlePreferences, onResetSubtitlePreferences, onClose, onHoldChrome, onReleaseChrome, compact = false }: SettingsMenuProps) {
  const S = compact ? MENU_COMPACT : MENU_REGULAR
  const displayPreferences = useDisplayPreferences()
  const [view, setView] = useState<'main' | 'quality' | 'subs' | 'subtitleStyle' | 'audio'>('main')
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
    if (!canManageMedia) return
    onChooseAudio?.(index)
    onSetPlaybackTracks?.({ audioStreamIndex: index, subtitleStreamIndex: selectedSubtitleIndex })
    setView('main')
  }

  function chooseSub(index: number | null) {
    if (!canManageMedia) return
    onChooseSubtitle?.(index)
    onSetPlaybackTracks?.({ audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: index })
    setView('main')
  }

  async function uploadSubtitle(file?: File) {
    if (!file || !mediaItemId || !canManageMedia) return
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
      if (typeof data === 'object' && data !== null && 'subtitleStreamIndex' in data && typeof data.subtitleStreamIndex === 'number') {
        onChooseSubtitle?.(data.subtitleStreamIndex)
        onSetPlaybackTracks?.({ audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: data.subtitleStreamIndex })
        setView('main')
      }
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

  const navRow =(label: string, value: string, onClick: VoidCallback) => (
    <button onClick={onClick} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: S.navGap, width: '100%', ...(S.rowMin ? { minHeight: S.rowMin } : {}), padding: S.navPad, border: 'none', cursor: 'pointer', background: 'transparent', color: '#f4f4f5', fontSize: S.navFont, fontWeight: 500, textAlign: 'left' }}>
      <span>{label}</span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'rgba(244,244,245,.62)', fontSize: S.navValFont, maxWidth: S.navValMax, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {value}
        <svg width={S.navChev} height={S.navChev} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m9 18 6-6-6-6" /></svg>
      </span>
    </button>
  )
  const optRow = (label: string, active: boolean, onClick: VoidCallback, key: string | number, disabled = false) => (
    <button key={key} disabled={disabled} onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: S.optGap, width: '100%', ...(S.rowMin ? { minHeight: S.rowMin } : {}), padding: S.optPad, border: 'none', cursor: disabled ? 'default' : 'pointer', opacity: disabled ? .55 : 1, background: active ? 'rgba(255,255,255,.06)' : 'transparent', color: active ? '#f4f4f5' : 'rgba(244,244,245,.62)', fontSize: S.optFont, fontWeight: active ? 600 : 500, textAlign: 'left' }}>
      <svg width={S.optTick} height={S.optTick} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" style={{ opacity: active ? 1 : 0, flexShrink: 0 }}><path d="M20 6 9 17l-5-5" /></svg>
      <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</span>
    </button>
  )
  const subHeader = (title: string) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: S.headGap, padding: S.headPad, borderBottom: '1px solid rgba(255,255,255,.08)', flexShrink: 0 }}>
      <button onClick={() => setView('main')} style={{ width: S.headBtn, height: S.headBtn, borderRadius: 8, border: 'none', background: 'rgba(255,255,255,.06)', color: '#f4f4f5', display: 'grid', placeItems: 'center', cursor: 'pointer', flexShrink: 0 }}>
        <svg width={S.headGlyph} height={S.headGlyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="m15 18-6-6 6-6" /></svg>
      </button>
      <span style={{ fontFamily: MONO_F, fontSize: S.headFont, letterSpacing: '.14em', textTransform: 'uppercase', color: 'rgba(244,244,245,.62)' }}>{title}</span>
    </div>
  )
  const searchBox = (
    <div style={{ padding: S.searchPad, flexShrink: 0 }}>
      <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search…" autoFocus
        style={{ width: '100%', padding: S.inputPad, borderRadius: S.inputRadius, border: '1px solid rgba(255,255,255,.1)', background: 'rgba(255,255,255,.04)', color: '#f4f4f5', fontSize: S.inputFont, outline: 'none' }} />
    </div>
  )
  const filtered = (arr: PlayerTrack[]) => arr.filter((t, i) => trackName(t, i).toLowerCase().includes(q.toLowerCase()))
  const settingRow = (label: string, value: ReactNode, control: ReactNode) => (
    <div style={{ padding: S.setPad, borderBottom: '1px solid rgba(255,255,255,.06)' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, marginBottom: S.setGap, fontSize: S.setLabel }}>
        <span style={{ color: 'rgba(244,244,245,.62)' }}>{label}</span>
        <span style={{ color: '#f4f4f5', fontFamily: MONO_F, fontSize: S.setValue }}>{value}</span>
      </div>
      {control}
    </div>
  )
  const selectStyle: CSSProperties = {
    width: '100%', padding: S.selPad, borderRadius: 8, border: '1px solid rgba(255,255,255,.1)',
    background: '#1d1d20', color: '#f4f4f5', fontSize: S.selFont,
  }
  const rangeStyle: CSSProperties = { width: '100%', accentColor: '#f4f4f5', cursor: 'pointer' }

  return (
    // AnalogSettingsStack owns the anchoring, the upward entrance, the dismiss
    // layer and the surface — "a compact vertical stack upward from the
    // lower-right control area … not a full-screen modal". The tuned density
    // numbers (S.bottom / S.right / S.width / S.maxHeight, and MENU_COMPACT's
    // iOS-zoom and 44px touch-floor guards) are passed straight through: the
    // container changed, the menu did not.
    <AnalogSettingsStack
      open={open}
      onDismiss={() => onClose?.()}
      bottom={S.bottom}
      right={S.right}
      width={S.width}
      maxWidth={S.maxWidth}
      maxHeight={S.maxHeight}
      radius={S.radius}
      preferences={displayPreferences}
      onHold={() => onHoldChrome?.(CHROME_HOLD.settings)}
      onRelease={() => onReleaseChrome?.(CHROME_HOLD.settings)}
    >
      <>
        {view === 'main' && (
          <div style={{ padding: S.mainPad }}>
            {navRow('Quality', curQuality, () => setView('quality'))}
            {navRow('Subtitles', curSub, () => setView('subs'))}
            {audioStreams.length > 1 && navRow('Audio', curAudio, () => setView('audio'))}
          </div>
        )}

        {view === 'quality' && (
          <>
            {subHeader('Quality')}
            <div style={{ overflowY: 'auto', padding: S.listPad }}>
              {!hasLevels && <div style={{ padding: S.emptyPad, fontSize: S.emptyFont, color: 'rgba(244,244,245,.36)' }}>Loading available qualities…</div>}
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
            <div style={{ borderBottom: '1px solid rgba(255,255,255,.08)', padding: S.listPad }}>
              {navRow('Appearance & timing', `${subtitlePreferences.delayMs > 0 ? '+' : ''}${subtitlePreferences.delayMs} ms`, () => setView('subtitleStyle'))}
            </div>
            {subtitleStreams.length > 8 && searchBox}
            <div style={{ overflowY: 'auto', padding: S.listPad }}>
              {optRow('Off', selectedSubtitleIndex == null || selectedSubtitleIndex < 0, () => chooseSub(null), 'off', !canManageMedia)}
              {subtitleStreams.length === 0 && <div style={{ padding: S.emptyPad, fontSize: S.emptyFont, color: 'rgba(244,244,245,.36)' }}>None available in this stream</div>}
              {filtered(subtitleStreams).map((t, i) => optRow(trackName(t, i), selectedSubtitleIndex === t.index, () => chooseSub(t.index), t.index, !canManageMedia))}
              <div style={{ borderTop: '1px solid rgba(255,255,255,.08)', marginTop: 6, padding: S.optPad }}>
                <input ref={uploadInputRef} type="file" accept=".srt,.vtt,text/vtt,application/x-subrip" hidden
                  onChange={(e) => uploadSubtitle(e.target.files?.[0])} />
                <button disabled={uploadingSub || !mediaItemId || !canManageMedia} onClick={() => uploadInputRef.current?.click()} style={{
                  width: '100%', padding: S.btnPad, borderRadius: S.btnRadius, cursor: uploadingSub ? 'wait' : 'pointer',
                  border: '1px solid rgba(255,255,255,.12)', background: 'rgba(255,255,255,.06)',
                  color: '#f4f4f5', fontSize: S.btnFont, fontWeight: 600, opacity: (mediaItemId && canManageMedia) ? 1 : .45,
                }}>{uploadingSub ? 'Uploading…' : 'Upload subtitle file'}</button>
                {uploadError && <div role="alert" style={{ color: '#e0655e', fontSize: S.noteFont, marginTop: 7 }}>{uploadError}</div>}
                <div style={{ color: 'rgba(244,244,245,.36)', fontSize: S.hintFont, marginTop: 6 }}>SRT or WebVTT · 5 MB max</div>
              </div>
            </div>
          </>
        )}

        {view === 'subtitleStyle' && (
          <>
            {subHeader('Subtitle settings')}
            <div style={{ overflowY: 'auto' }}>
              {settingRow('Timing offset', `${subtitlePreferences.delayMs > 0 ? '+' : ''}${subtitlePreferences.delayMs} ms`,
                <input disabled={!canManageMedia} aria-label="Subtitle timing offset" type="range" min={-10000} max={10000} step={250} value={subtitlePreferences.delayMs} onChange={e => onUpdateSubtitlePreferences?.({ delayMs: Number(e.target.value) })} style={rangeStyle} />)}
              {settingRow('Font size', `${subtitlePreferences.fontScalePercent}%`,
                <input disabled={!canManageMedia} aria-label="Subtitle font size" type="range" min={60} max={200} step={10} value={subtitlePreferences.fontScalePercent} onChange={e => onUpdateSubtitlePreferences?.({ fontScalePercent: Number(e.target.value) })} style={rangeStyle} />)}
              {settingRow('Background', `${subtitlePreferences.backgroundOpacityPercent}%`,
                <input disabled={!canManageMedia} aria-label="Subtitle background opacity" type="range" min={0} max={100} step={5} value={subtitlePreferences.backgroundOpacityPercent} onChange={e => onUpdateSubtitlePreferences?.({ backgroundOpacityPercent: Number(e.target.value) })} style={rangeStyle} />)}
              {settingRow('Font', '',
                <select disabled={!canManageMedia} aria-label="Subtitle font" value={subtitlePreferences.fontFamily} onChange={e => onUpdateSubtitlePreferences?.({ fontFamily: e.target.value as SubtitlePreferences['fontFamily'] })} style={selectStyle}>
                  <option value="sans">Sans serif</option><option value="serif">Serif</option><option value="mono">Monospace</option>
                </select>)}
              {settingRow('Text color', '',
                <select disabled={!canManageMedia} aria-label="Subtitle text color" value={subtitlePreferences.textColor.toLowerCase()} onChange={e => onUpdateSubtitlePreferences?.({ textColor: e.target.value.toUpperCase() })} style={selectStyle}>
                  <option value="#ffffff">White</option><option value="#ffe66d">Yellow</option><option value="#7fdbff">Cyan</option><option value="#a8ffb0">Green</option>
                </select>)}
              {settingRow('Height', subtitlePreferences.verticalOffsetPercent === 0 ? 'Bottom' : `${subtitlePreferences.verticalOffsetPercent}%`,
                <input type="range" disabled={!canManageMedia} aria-label="Subtitle height above the bottom" min={0} max={100} step={5}
                  value={subtitlePreferences.verticalOffsetPercent}
                  onChange={e => onUpdateSubtitlePreferences?.({ verticalOffsetPercent: Number(e.target.value) })} style={{ width: '100%' }} />)}
              <div style={{ padding: S.footPad }}>
                <button disabled={!canManageMedia} onClick={onResetSubtitlePreferences} style={{ width: '100%', padding: S.btnPad, borderRadius: S.btnRadius, border: '1px solid rgba(255,255,255,.1)', background: 'transparent', color: 'rgba(244,244,245,.62)', cursor: 'pointer', fontSize: S.btnFont }}>Reset subtitle settings</button>
              </div>
            </div>
          </>
        )}

        {view === 'audio' && (
          <>
            {subHeader('Audio')}
            {audioStreams.length > 8 && searchBox}
            <div style={{ overflowY: 'auto', padding: S.listPad }}>
              {filtered(audioStreams).map((t, i) => optRow(trackName(t, i), selectedAudioIndex === t.index, () => chooseAudio(t.index), t.index, !canManageMedia))}
            </div>
          </>
        )}
      </>
    </AnalogSettingsStack>
  )
}
