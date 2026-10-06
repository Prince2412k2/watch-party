import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { CSSProperties, MouseEvent, PointerEvent } from 'react'
import { useParty } from '../context/PartyContext.tsx'
import { useAuth } from '../context/AuthContext.tsx'
import { useSocket } from '../hooks/useSocket.ts'
import { useLiveKit } from '../hooks/useLiveKit.ts'
import type { LiveKitParticipantView } from '../hooks/useLiveKit.ts'
import { useHideSelf } from '../hooks/useHideSelf.ts'
import { navigate } from '../router.ts'
import { IS_NATIVE } from '../native/env.ts'
import Player from '../components/Player.tsx'
import { RoomOverlay, usePlayerPresentation, useRoomConnection } from '../components/PlayerPresentation.tsx'
import { cachePlayback, infoFor, localSubtitles, playbackSource, OFFLINE_SUPPORTED, type SavedMedia } from '../offline/client.ts'
import type { PlayerProps } from '../components/Player.tsx'
import CameraGrid from '../components/CameraGrid.tsx'
import Chat from '../components/Chat.tsx'
import RoomControls from '../components/RoomControls.tsx'
import { usePhone } from '../hooks/useIsMobile.ts'
import { Z } from '../watchLayers.ts'
import {
  useAutoHideControls,
} from '../analog/player/index.ts'
import Lobby from './Lobby.tsx'
import type { ChatMessage, PartyContextValue, PartySession, SubtitlePreferences } from '../types.ts'
import { apiJson, stringField } from '../types/guards.ts'
import { partyJoinTransition } from '../partyAuthority.ts'

type LiveKitState = ReturnType<typeof useLiveKit>
type CameraProps = {
  localParticipant: LiveKitParticipantView | null
  participants: LiveKitParticipantView[]
  isHost: boolean
  removedCameras: Set<string>
  hideSelf: boolean
  onRemove: (identity: string) => void
}
type SeekBridge = {
  canControl: boolean
  seekBy: (seconds: number) => void
  // Returns a promise that REJECTS when the toggle failed — the caller is
  // responsible for putting that in front of the user.
  guardToggle: (action: () => unknown) => Promise<void>
}

export default function Party({ partyId, isNew, itemId, initialTracks, initialShare }: { initialShare?: 'camera' | 'microphone'; partyId?: string; isNew?: boolean; itemId?: string; initialTracks?: { mediaSourceId?: string; audioStreamIndex?: number | null; subtitleStreamIndex?: number | null; resumePositionTicks?: number | null } } = {}) {
  const { socket } = useSocket()
  const party = useParty()
  const { user } = useAuth()
  const {
    session, role, messages, layoutMode, chatOpen, chatRipple, alertMode,
    setLayout, toggleChat, openChat, closeChat, selectMedia, setPlaybackTracks, setSubtitlePreferences,
    localSubtitleSelection, subtitlePreferences,
    peerPlayback, showPeerPointers,
  } = party

  const lk = useRoomConnection()
  const [removedCameras, setRemovedCameras] = useState<Set<string>>(new Set())
  const [hideSelf, toggleHideSelf, setHideSelf] = useHideSelf()
  const [joinError, setJoinError] = useState<string | null>(null)
  const phone = usePhone()

  // Bug 4: couple camera ⇄ self-view ONE WAY. Turning the camera OFF auto-hides
  // my own tile; turning it back ON shows it again (sensible default). Hiding my
  // self-view by hand (toggleHideSelf) never touches the camera — I stay
  // published to everyone, I just don't see myself. Driven only by camOn, so the
  // coupling is strictly camera → self-view, never the reverse.
  useEffect(() => { setHideSelf(!lk.camOn) }, [lk.camOn, setHideSelf])

  // Which party id this surface has actually created/joined. App.jsx renders ONE
  // mount-stable <Party> for every /party/* URL, so navigating straight from
  // /party/AAA to /party/BBB only changes the prop — with the old boolean latch
  // that navigation was a no-op and the AAA session (its LiveKit room, its
  // schedule, its chat) stayed live under the BBB URL. Keyed on the target so
  // the same navigation leaves AAA and joins BBB, while StrictMode's
  // double-invoke and ordinary re-renders still can't join twice.
  const joinedFor = useRef<string | null>(null)
  useEffect(() => {
    if (!isNew && partyId && partyId === party.session?.id && (role === 'host' || role === 'guest')) { joinedFor.current = partyId; return }
    const action = partyJoinTransition({ joinedFor: joinedFor.current, partyId, isNew })
    if (action.kind === 'idle') return
    joinedFor.current = action.target
    if (action.leavePrevious) {
      party.leaveParty()
      setRemovedCameras(new Set())
      setJoinError(null)
    }
    if (action.kind === 'create') {
      // itemId → room preloaded with a title; no itemId → empty lobby room
      const create = itemId ? party.createParty(itemId, initialTracks) : party.createRoom()
      create
        .then(id => window.history.replaceState({}, '', `/party/${id}`))
        .catch(() => navigate('/library'))
    } else {
      party.joinParty(action.target).catch(err => setJoinError(err?.message || 'not found'))
    }
  }, [partyId, isNew]) // eslint-disable-line

  // Rules-of-Hooks: this must run UNCONDITIONALLY, above the joinError early
  // return below. A failed join (invalid/expired code — the common case for a
  // shared link or QR scan on a party that has ended) flips joinError, and if a
  // hook lived after that return the hook count would shrink between renders and
  // React would crash ("rendered fewer hooks than expected") instead of showing
  // the friendly "Party not found" screen.
  useEffect(() => {
    const handler = ({ userId }: { userId: string }) => setRemovedCameras(prev => new Set([...prev, userId]))
    socket.on('camera:removed', handler)
    return () => { socket.off('camera:removed', handler) }
  }, [socket])

  if (joinError) {
    return (
      <div style={{ position: 'fixed', inset: 0, background: 'var(--bg)', display: 'grid', placeItems: 'center', padding: 24 }}>
        <div style={{ maxWidth: 360, textAlign: 'center' }}>
          <div style={{ fontSize: 22, fontWeight: 800, letterSpacing: '-.02em', marginBottom: 8 }}>Party not found</div>
          <p style={{ fontSize: 14.5, color: 'var(--text2)', lineHeight: 1.55, marginBottom: 24 }}>
            <span style={{ fontFamily: 'JetBrains Mono, monospace' }}>{partyId}</span> doesn't exist or has ended. Ask the host for a fresh invite, or start your own.
          </p>
          <button onClick={() => navigate('/library')} style={{
            padding: '12px 22px', border: 'none', borderRadius: 10, background: 'var(--accent)', color: 'var(--on-accent)',
            fontSize: 14.5, fontWeight: 700, cursor: 'pointer',
          }}>Back to library</button>
        </div>
      </div>
    )
  }

  if (role === 'waiting') return <Lobby partyId={partyId} />
  if (!session) {
    return (
      <div style={{ position: 'fixed', inset: 0, background: 'var(--bg)', display: 'grid', placeItems: 'center' }}>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16 }}>
          <div style={{ width: 40, height: 40, borderRadius: '50%', border: '3px solid var(--stroke2)', borderTopColor: 'var(--accent)', animation: 'spin .9s linear infinite' }} />
          <span style={{ color: 'var(--text2)', fontSize: 14 }}>Connecting…</span>
        </div>
      </div>
    )
  }

  const isHost = role === 'host'
  const canDrive = isHost || session.collaborativeControl
  const participantCount = 1 + (session.guests?.length ?? 0)

  const cameraProps = {
    localParticipant: lk.localParticipant,
    participants: lk.participants,
    isHost,
    removedCameras,
    hideSelf,
    onRemove: (identity: string) => {
      party.removeCamera(identity)
      setRemovedCameras(prev => new Set([...prev, identity]))
    },
  }

  if (session.stage === 'lobby') {
    return <RoomOverlay>
      <CameraGrid {...cameraProps} />
      <RoomControls stage="lobby" phone={phone} onOpenChat={() => openChat(true)} chatOpen={chatOpen}
        micOn={lk.micOn} camOn={lk.camOn} onToggleMic={() => { void lk.enableMic(!lk.micOn) }} onToggleCam={() => { void lk.enableCamera(!lk.camOn) }}
        hideSelf={hideSelf} onToggleHideSelf={toggleHideSelf} onReconnect={lk.reconnect} />
      <Chat />
    </RoomOverlay>
  }

  // ── WATCHING: a title is selected, playback sync is live ─────────────────
  return (
    <WatchView
      session={session} isHost={isHost} cameraProps={cameraProps} lk={lk}
      initialShare={initialShare}
      chatOpen={chatOpen} chatRipple={chatRipple} alertMode={alertMode}
      messages={messages} selfUserId={user?.userId}
      peerPlayback={peerPlayback} showPeerPointers={showPeerPointers}
      layoutMode={layoutMode} setLayout={setLayout} openChat={openChat} closeChat={closeChat} toggleChat={toggleChat}
      setPlaybackTracks={setPlaybackTracks}
      setSubtitlePreferences={setSubtitlePreferences}
      localSubtitleSelection={localSubtitleSelection}
      subtitlePreferences={subtitlePreferences}
      hideSelf={hideSelf} onToggleHideSelf={toggleHideSelf}
    />
  )
}

// A shared empty log, so an unsupplied `messages` prop does not hand the toast
// feed a new array identity on every render.
const NO_MESSAGES: ChatMessage[] = []

// The immersive watch screen: real fullscreen (whole container, feeds stay
// visible), and chrome that auto-hides after idle and returns on mouse move
// (desktop) or a tap (phone). See watchLayers.js for the z-index scale.
function WatchView({
  session, isHost, cameraProps, lk, chatOpen, chatRipple = 0, alertMode, layoutMode,
  messages = NO_MESSAGES, selfUserId,
  peerPlayback = {}, showPeerPointers = false,
  setLayout = () => {}, openChat = () => {}, closeChat = () => {}, toggleChat = () => {}, setPlaybackTracks = () => {}, setSubtitlePreferences = () => {}, hideSelf, onToggleHideSelf = () => {},
  localSubtitleSelection = null, subtitlePreferences, initialShare,
}: {
  initialShare?: 'camera' | 'microphone'
  session: PartySession
  isHost?: boolean
  cameraProps: CameraProps
  lk: LiveKitState
  chatOpen?: boolean
  chatRipple?: number
  alertMode?: 'focus' | 'on' | 'mute'
  messages?: ChatMessage[]
  selfUserId?: string
  peerPlayback?: PartyContextValue['peerPlayback']
  showPeerPointers?: boolean
  layoutMode?: 'float' | 'dock'
  setLayout?: (mode: 'float' | 'dock') => void
  openChat?: (focus?: boolean) => void
  closeChat?: () => void
  toggleChat?: () => void
  setPlaybackTracks?: (tracks?: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null }) => void
  setSubtitlePreferences?: (preferences: SubtitlePreferences) => void
  localSubtitleSelection?: { itemId: string; index: number | null } | null
  subtitlePreferences?: SubtitlePreferences
  hideSelf?: boolean
  onToggleHideSelf?: () => void
}) {
  const phone = usePhone()
  const rootRef = useRef<HTMLDivElement | null>(null)
  // Playback state, reported up by the player, purely so the chrome can obey
  // "controls hide after three seconds DURING PLAYBACK" — a paused frame keeps
  // its controls.
  const [playing, setPlaying] = useState(true)
  const [mediaTitle, setMediaTitle] = useState('')
  const chrome = useAutoHideControls({ playing })
  useEffect(() => {
    if (!chatOpen) return
    chrome.hold('chat')
    return () => chrome.release('chat')
  }, [chatOpen, chrome.hold, chrome.release])
  const presentation = usePlayerPresentation()
  const visible = chrome.visible && !presentation.floating
  // Single "are we in the app's fullscreen presentation?" state. Derived from
  // whichever mechanism the platform supports (element FS today; iOS faux-FS in
  // Phase B). Drives the button icon, orientation lock, and the control-layer poke.
  const [immersive, setImmersive] = useState(false)
  const [ripple, setRipple] = useState(0)
  // Shown whenever there's a camera actually worth looking at — mine or a
  // remote participant's — instead of a separate manual show/hide toggle.
  // That toggle used to mean turning your camera on and SEEING it were two
  // different taps; this makes "camera on" the only action needed.
  const camStripOpen = lk.camOn || lk.participants.some(p => !!p.videoTrack)

  // ── Audio interaction model ──────────────────────────────────────────────
  // Default-mute-on-movie-start: WatchView mounts exactly when the session
  // enters the watching stage, so muting once here (on mount) fires exactly on
  // that lobby→watching transition and never fights later manual unmutes. If
  // the mic is already off (the common case) this is a harmless no-op. Going
  // back to the lobby unmounts WatchView, so re-entering re-arms this.
  useEffect(() => {
    if (lk.micOn) lk.enableMic(false)
  }, []) // eslint-disable-line

  // Hide every camera tile from MY screen — a purely-local display toggle (the
  // cameras keep publishing; other people's views are untouched), driven by the
  // bottom bar's eye-with-slash button.
  const [hideAllFeeds, setHideAllFeeds] = useState(false)

  // Edge ripple when a message arrives in 'on' alert mode
  useEffect(() => {
    if (chatRipple > 0 && alertMode === 'on' && !chatOpen) setRipple(r => r + 1)
  }, [chatRipple]) // eslint-disable-line

  // The 3000ms lived here as a bare setTimeout with one blocker (an open
  // settings menu, ORed in locally by each bar). It is now playerCore's
  // `tickAutoHide`, shared with the Flutter player and driven by the same
  // interaction cases: the timeout is a token, holds pin the chrome open
  // mid-interaction, and a paused movie keeps its controls.
  const poke = () => chrome.note('pointer')

  // On phones a tap on the video TOGGLES the control layer (show → hide); when
  // shown it re-arms the idle timer. A desktop click toggles the same layer.
  const toggleChrome = () => chrome.toggle()
  const onSurfaceTap = () => chrome.toggle()

  // ── Phone surface gestures (Phase F) ──────────────────────────────────────
  // Single tap = toggle chrome; double-tap on the LEFT third = seek −10s, RIGHT
  // third = +10s (controllers only), MIDDLE third = toggle chrome. Controller
  // seeks are routed through the media element (seekBridgeRef → SyncBridge), so
  // the existing seeked→requestSeek authoring runs and guests follow — never a
  // bare currentTime write. Guests without control get chrome-toggle only.
  //
  // Detection rides the proven `click` path: clicks bubble to this root, and every
  // interactive overlay (bottom-bar buttons, chat sheet, camera strip, overflow
  // popover, scrim, rotate hint) already stopPropagation on click, so taps on
  // controls never reach here. A capture-phase pointerdown records the press so a
  // tap that slid past MOVE_TOL (a scroll/drag) is rejected. `touch-action:
  // manipulation` on the stage kills the tap delay + double-tap-zoom without
  // touching pan/pinch, and we attach NO horizontal swipe so iOS edge back-swipe
  // is left alone.
  const canControl = isHost || session.collaborativeControl
  const seekBridgeRef = useRef<SeekBridge | null>(null)          // wired by Player/SyncBridge → { seekBy, canControl, guardToggle }
  // Bug 2: route camera/mic toggles through the sync bridge's guard so a spurious
  // pause/play the browser can emit while (re)acquiring a device via getUserMedia
  // never authors a pause/seek to the shared timeline — and any spurious local
  // pause of a playing movie is undone. Falls back to a plain call pre-wiring.
  //
  // The guard used to `catch {}` whatever the toggle threw, so a device that
  // failed outside useLiveKit's own try/catch (or before the room existed) left
  // the user pressing a button that silently did nothing. Every rejection now
  // lands in the same visible banner useLiveKit uses.
  const guardedToggle = (fn: () => unknown) => {
    const g = seekBridgeRef.current?.guardToggle
    const run = g ? g(fn) : Promise.resolve().then(fn)
    return run.catch((err: unknown) => {
      lk.reportError(err instanceof Error ? err.message : 'Could not change your camera or microphone.')
    })
  }
  const initialShareStarted = useRef(false)
  useEffect(() => {
    if (!initialShare || initialShareStarted.current || !lk.localParticipant) return
    initialShareStarted.current = true
    void guardedToggle(() => initialShare === 'camera' ? lk.enableCamera(true) : lk.enableMic(true))
  }, [initialShare, lk.localParticipant])
  const DOUBLE_MS = 280                        // single/double discrimination window
  const MOVE_TOL = 12                          // px: past this a press is a drag/scroll, not a tap
  const tapRef = useRef<{ downX: number; downY: number; hasDown: boolean; lastT: number; timer: number | null }>({ downX: 0, downY: 0, hasDown: false, lastT: 0, timer: null })
  const fxTimer = useRef<number | null>(null)
  const [seekFx, setSeekFx] = useState<{ key: number; dir: -1 | 1; amount: number } | null>(null)   // brief feedback

  const showSeekFx = (dir: -1 | 1) => {
    setSeekFx(prev => {
      const same = prev && prev.dir === dir
      return { key: (prev?.key ?? 0) + 1, dir, amount: same ? prev.amount + 10 : 10 }
    })
    if (fxTimer.current != null) window.clearTimeout(fxTimer.current)
    fxTimer.current = window.setTimeout(() => setSeekFx(null), 600)
  }

  const onPhonePointerDown = (e: PointerEvent<HTMLDivElement>) => {
    const s = tapRef.current
    s.hasDown = true; s.downX = e.clientX; s.downY = e.clientY
  }
  const onPhoneTap = (e: MouseEvent<HTMLDivElement>) => {
    const s = tapRef.current
    // Reject a press that dragged past the movement threshold (scroll/slide).
    if (s.hasDown && (Math.abs(e.clientX - s.downX) > MOVE_TOL || Math.abs(e.clientY - s.downY) > MOVE_TOL)) {
      s.hasDown = false
      return
    }
    s.hasDown = false
    const now = Date.now()
    const isDouble = now - s.lastT < DOUBLE_MS
    s.lastT = now
    if (isDouble) {
      if (s.timer != null) window.clearTimeout(s.timer); s.timer = null      // cancel the pending single-tap toggle
      const w = rootRef.current?.clientWidth || window.innerWidth
      const x = e.clientX
      if (x < w / 3) {                            // left third → back
        if (canControl && seekBridgeRef.current?.seekBy) { seekBridgeRef.current.seekBy(-10); showSeekFx(-1) }
        else toggleChrome()
      } else if (x > (w * 2) / 3) {               // right third → forward
        if (canControl && seekBridgeRef.current?.seekBy) { seekBridgeRef.current.seekBy(10); showSeekFx(1) }
        else toggleChrome()
      } else {                                    // middle third → toggle chrome
        toggleChrome()
      }
    } else {
      // Defer the single-tap toggle until the double-tap window closes so the
      // first tap of a double doesn't flash the chrome on/off.
      if (s.timer != null) window.clearTimeout(s.timer)
      s.timer = window.setTimeout(() => { s.timer = null; toggleChrome() }, DOUBLE_MS)
    }
  }
  useEffect(() => () => {
    if (tapRef.current.timer != null) window.clearTimeout(tapRef.current.timer)
    if (fxTimer.current != null) window.clearTimeout(fxTimer.current)
  }, [])

  // ── Immersive (fullscreen) ownership ──────────────────────────────────────
  // Element-FS platforms (Android/Chromium, iPad, desktop) report
  // document.fullscreenEnabled === true. iPhone Safari reports false and takes
  // the CSS faux-fullscreen path (Phase B): no webkitEnterFullscreen, no native
  // video takeover — we keep the whole party (chat, cameras, mic/cam/PTT,
  // controls, room code) mounted and just size the already-fixed stage to the
  // dynamic viewport so it fills under Safari's collapsing toolbars.
  const ELEMENT_FS = typeof document !== 'undefined' && document.fullscreenEnabled === true
  // The non-element-FS branch is iPhone Safari. Reuse the capability check as the
  // detector (no UA sniffing) — this is the same hinge Phase A branches on.
  const iosFaux = !ELEMENT_FS

  // State SOURCE for element-FS platforms: fullscreenchange keeps `immersive`
  // truthful, which also captures Esc / Android back-gesture / iOS "done" exits.
  useEffect(() => {
    if (!ELEMENT_FS) return
    const h = () => setImmersive(!!document.fullscreenElement)
    document.addEventListener('fullscreenchange', h)
    return () => document.removeEventListener('fullscreenchange', h)
  }, [ELEMENT_FS])

  // Re-poke controls when the device rotates so they settle then auto-hide.
  useEffect(() => {
    const h = () => poke()
    window.addEventListener('orientationchange', h)
    return () => window.removeEventListener('orientationchange', h)
  }, [])

  function enterImmersive() {
    if (ELEMENT_FS) {
      const p = document.documentElement.requestFullscreen?.()
      // Orientation lock is spec-gated on being in fullscreen, so lock only
      // AFTER requestFullscreen resolves; swallow rejection (desktop/unsupported).
      if (p?.then) p.then(() => { try { screen.orientation?.lock?.('landscape')?.catch?.(() => {}) } catch {} }).catch(() => {})
      // `immersive` is set by the fullscreenchange listener above.
    } else {
      // iOS CSS faux-fullscreen. The page is already fixed inset:0, so flip the
      // flag; the render branch below then sizes the stage to 100dvh/100dvw so
      // it fills the visible viewport. All overlays stay mounted — no native
      // video takeover. There is no fullscreenchange on this path, so this
      // setter (and exitImmersive's) is the single source of truth for iOS.
      setImmersive(true)
    }
    poke()
  }

  function exitImmersive() {
    if (ELEMENT_FS) {
      if (document.fullscreenElement) document.exitFullscreen?.()?.catch?.(() => {})
      try { screen.orientation?.unlock?.() } catch {}
      // `immersive` is cleared by the fullscreenchange listener above.
    } else {
      setImmersive(false)
    }
  }

  // Fill the persistent host frame, including its floating presentation.
  const rootStyle: CSSProperties = {
    position: 'absolute', top: 0, left: 0, right: 0,
    height: '100%',
    background: '#000', overflow: 'hidden', cursor: visible ? 'default' : 'none',
    // Kill the tap delay + double-tap-to-zoom (so double-tap-seek is snappy and
    // reliable) while leaving pan/pinch — and iOS edge back-swipe — untouched.
    touchAction: 'manipulation',
  }
  if (iosFaux && immersive) {
    // iOS faux-fullscreen: pin width to the dynamic viewport too so nothing
    // reflows against the layout viewport while immersive (Phase B).
    rootStyle.right = 'auto'
    rootStyle.width = '100dvw'
  }

  return (
    <div ref={rootRef}
      onMouseMove={phone ? undefined : poke}
      onClick={phone ? onPhoneTap : onSurfaceTap}
      onPointerDownCapture={phone ? onPhonePointerDown : undefined}
      style={rootStyle}>

      <div style={{ position: 'absolute', inset: 0 }}>
        <HlsPlayer
          onTitle={setMediaTitle}
          session={session} isHost={isHost} collaborativeControl={session.collaborativeControl}
          onSetPlaybackTracks={setPlaybackTracks}
          onSetSubtitlePreferences={setSubtitlePreferences}
          localSubtitleStreamIndex={localSubtitleSelection && localSubtitleSelection.itemId === session.mediaItemId ? localSubtitleSelection.index : null}
          subtitlePreferences={subtitlePreferences}
          peerPlayback={peerPlayback}
          showPeerPointers={showPeerPointers}
          micOn={lk.micOn} camOn={lk.camOn}
          onToggleMic={() => guardedToggle(() => lk.enableMic(!lk.micOn))}
          onToggleCam={() => guardedToggle(() => lk.enableCamera(!lk.camOn))}
          hideAllFeeds={hideAllFeeds} onToggleHideAllFeeds={() => setHideAllFeeds(v => !v)}
          onToggleLayout={() => setLayout(layoutMode === 'float' ? 'dock' : 'float')}
          hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
          onOpenChat={() => openChat(true)} onToggleChat={toggleChat} layoutMode={layoutMode}
          visible={visible} immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive}
          phone={phone} camStripOpen={camStripOpen}
          seekBridgeRef={seekBridgeRef}
          onHoldChrome={chrome.hold} onReleaseChrome={chrome.release} onPlayingChange={setPlaying}
        />
      </div>
      <RoomOverlay>
        {!hideAllFeeds && <CameraGrid {...cameraProps} chatOpen={chatOpen} controlsVisible={visible} micOn={lk.micOn} camOn={lk.camOn} onToggleMic={() => guardedToggle(() => lk.enableMic(!lk.micOn))} onToggleCam={() => guardedToggle(() => lk.enableCamera(!lk.camOn))} onToggleHideSelf={onToggleHideSelf} />}
      {/* Double-tap-to-seek feedback (Phase F): a soft ripple + "∓Ns" label on the
          tapped side. Decorative, non-interactive, and painted in the buffering
          band so the control bar / chat stay on top. Fades out ~600ms (frozen to
          a static, still-visible label under prefers-reduced-motion via .seek-fx). */}
      {phone && seekFx && (
        <div key={seekFx.key} className="seek-fx" aria-hidden style={{
          position: 'absolute', top: 0, bottom: 0, width: '38%',
          [seekFx.dir < 0 ? 'left' : 'right']: 0,
          zIndex: Z.buffering, pointerEvents: 'none', color: 'var(--text)',
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 10,
          animation: 'seekFx .6s ease-out both',
        }}>
          <div style={{ display: 'grid', placeItems: 'center', width: 56, height: 56, borderRadius: '50%', background: 'rgba(0,0,0,.42)', border: '1px solid rgba(255,255,255,.28)' }}>
            {seekFx.dir < 0
              ? <svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor"><path d="M11 6 5 12l6 6V6zm8 0-6 6 6 6V6z" /></svg>
              : <svg width="26" height="26" viewBox="0 0 24 24" fill="currentColor"><path d="M13 6l6 6-6 6V6zM5 6l6 6-6 6V6z" /></svg>}
          </div>
          <span style={{ fontSize: 15, fontWeight: 700, letterSpacing: '.01em', textShadow: '0 1px 4px rgba(0,0,0,.6)' }}>
            {seekFx.dir < 0 ? '−' : '+'}{seekFx.amount}s
          </span>
        </div>
      )}

      <Chat />

      <RoomControls
        stage="watching" mediaTitle={mediaTitle} visible={visible} phone={phone} onReconnect={lk.reconnect} onSetMic={on => guardedToggle(() => lk.enableMic(on))}
        micOn={lk.micOn} camOn={lk.camOn}
        onToggleMic={() => guardedToggle(() => lk.enableMic(!lk.micOn))}
        onToggleCam={() => guardedToggle(() => lk.enableCamera(!lk.camOn))}
        hideAllFeeds={hideAllFeeds} onToggleHideAllFeeds={() => setHideAllFeeds(value => !value)}
        onHoldChrome={chrome.hold} onReleaseChrome={chrome.release}
        onOpenChat={() => openChat(true)} chatOpen={chatOpen}
        layoutMode={layoutMode} onToggleLayout={() => setLayout(layoutMode === 'float' ? 'dock' : 'float')}
        hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
      />

      </RoomOverlay>
    </div>
  )
}

type HlsPlayerProps = Omit<PlayerProps, 'hlsUrl' | 'mediaItemId' | 'playback' | 'syncMode'> & {
  session: PartySession
  localSubtitleStreamIndex?: number | null
  onTitle?: (title: string) => void
}

function HlsPlayer({ session, onTitle, isHost, collaborativeControl, onSetPlaybackTracks, localSubtitleStreamIndex = null, ...rest }: HlsPlayerProps) {
  const { user } = useAuth()
  const [hlsUrl, setHlsUrl] = useState<{ itemId: string; url: string; saved?: SavedMedia } | null>(null)
  const [streamError, setStreamError] = useState('')
  const audioStreamIndex = session?.playback?.selectedAudioIndex
  const mediaSourceId = session?.playback?.mediaSourceId ?? session?.mediaSourceId ?? session?.mediaItemId
  useEffect(() => { onTitle?.(hlsUrl?.saved?.title ?? '') }, [hlsUrl?.saved?.title, onTitle])
  const playback = session.playback
    ? { ...session.playback, selectedSubtitleIndex: localSubtitleStreamIndex }
    : undefined

  useEffect(() => {
    const itemId = session?.mediaItemId
    setHlsUrl(current => current?.itemId === itemId ? current : null)
    setStreamError('')
    if (!itemId) return
    let cancelled = false
    let release = () => {}
    const resolve = async () => {
      if (!IS_NATIVE && OFFLINE_SUPPORTED) {
        try {
          const info = await infoFor(itemId, mediaSourceId)
          // Chromium cannot select arbitrary audio tracks in a static MP4.
          // Preserve shared track choice by falling back to HLS when needed.
          if (info.owner === user?.userId && (audioStreamIndex == null || audioStreamIndex === info.audioIndex)) {
            const saved = await cachePlayback(info)
            const source = await playbackSource(saved)
            release = source.release
            if (!cancelled) setHlsUrl({itemId,url:source.url,saved})
            else release()
            return
          }
        } catch { /* Unconverted titles / unsupported browsers retain HLS playback. */ }
      }
      const qs = new URLSearchParams({itemId,abr:'1'})
      if (mediaSourceId) qs.set('mediaSourceId',mediaSourceId)
      if (Number.isInteger(audioStreamIndex)) qs.set('audioStreamIndex',String(audioStreamIndex))
      const response = await fetch(`/api/library/hls-url?${qs}`,{credentials:'include'})
      const url = stringField(await apiJson(response),'url')
      if (!response.ok || !url) throw new Error('Could not load video. Reconnect and try again.')
      if (!cancelled) setHlsUrl({itemId,url})
    }
    void resolve().catch(error=>{if(!cancelled)setStreamError(error.message)})
    return () => { cancelled = true; release() }
  },[session?.mediaItemId,mediaSourceId,audioStreamIndex,user?.userId])

  if (!hlsUrl || hlsUrl.itemId !== session.mediaItemId) return (
    <div style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center', background: '#000' }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
        <div style={{ width: 36, height: 36, borderRadius: '50%', border: '3px solid var(--stroke2)', borderTopColor: 'var(--accent)', animation: 'spin .9s linear infinite' }} />
        <span style={{ color: 'var(--text3)', fontSize: 13 }}>{streamError || 'Loading video…'}</span>
      </div>
    </div>
  )

  const savedSubtitles = hlsUrl.saved ? localSubtitles(hlsUrl.saved) : []
  const subtitleStreams = (playback?.subtitleStreams ?? savedSubtitles).map(stream => ({
    ...stream,
    ...(savedSubtitles.find(saved => saved.index === stream.index) ?? {})
  }))
  return (
    <Player
      // A media item has its own HLS engine and text-track collection. Keying
      // the player prevents the previous item's engine from receiving a new
      // subtitle selection during the handoff.
      key={hlsUrl.itemId}
      hlsUrl={hlsUrl.url}
      mediaItemId={session.mediaItemId}
      playback={hlsUrl.saved ? { ...playback, offlineKey: hlsUrl.saved.key, mediaSourceId: hlsUrl.saved.sourceId, subtitleStreams } : playback}
      isHost={isHost}
      collaborativeControl={collaborativeControl}
      syncMode={session.syncMode}
      onSetPlaybackTracks={onSetPlaybackTracks}
      {...rest}
    />
  )
}
