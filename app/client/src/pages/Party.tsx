import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { CSSProperties, MouseEvent, PointerEvent, ReactNode } from 'react'
import { Rnd } from 'react-rnd'
import { useParty } from '../context/PartyContext.tsx'
import { useAuth } from '../context/AuthContext.tsx'
import { useSocket } from '../hooks/useSocket.ts'
import { useLiveKit } from '../hooks/useLiveKit.ts'
import type { LiveKitParticipantView } from '../hooks/useLiveKit.ts'
import { useHideSelf } from '../hooks/useHideSelf.ts'
import { navigate } from '../router.ts'
import Player from '../components/Player.tsx'
import type { PlayerProps } from '../components/Player.tsx'
import CameraGrid from '../components/CameraGrid.tsx'
import Dock from '../components/Dock.tsx'
import Chat from '../components/Chat.tsx'
import RoomControls from '../components/RoomControls.tsx'
import CameraTile from '../components/CameraTile.tsx'
import { glass } from '../glass.tsx'
import { mirror } from '../mirror.ts'
import { usePhone } from '../hooks/useIsMobile.ts'
import { Z } from '../watchLayers.ts'
import {
  AnalogToastStack,
  useAutoHideControls,
  useChatToasts,
  useDisplayPreferences,
} from '../analog/player/index.ts'
import MoviesStage from './MoviesStage.tsx'
import Lobby from './Lobby.tsx'
import type { ChatMessage, PartySession, SubtitlePreferences } from '../types.ts'
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

export default function Party({ partyId, isNew, itemId, initialTracks }: { partyId?: string; isNew?: boolean; itemId?: string; initialTracks?: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null } } = {}) {
  const { socket } = useSocket()
  const party = useParty()
  const { user } = useAuth()
  const {
    session, role, messages, layoutMode, chatOpen, chatRipple, alertMode,
    setLayout, toggleChat, openChat, closeChat, navigateBrowse, sendPointer, selectMedia, setPlaybackTracks, setSubtitlePreferences,
  } = party

  const lk = useLiveKit({ partyId: session?.id, enabled: role === 'host' || role === 'guest' })
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

  // ── LOBBY: everyone browses the library together, no title yet ───────────
  if (session.stage === 'lobby') {
    return (
      // No rotation transform: the lobby renders in the real (portrait or
      // landscape) coordinate space so safe areas and back-swipe/system gestures
      // behave normally. The embedded Library reflows for narrow portrait widths
      // on its own (icon-rail sidebar + fluid poster grid). Portrait phones get
      // the same non-rotating RotateHint the watch screen uses.
      <div style={{ position: 'fixed', inset: 0, background: '#000', overflow: 'hidden' }}>
        {/* The analog stage, not an embedded variant of it. It already reads
            the party from context — it publishes and follows session.browse.stack,
            gates driving on canDriveBrowse, and calls selectMedia on activation —
            so the lobby needs no props at all. The stack/onNavigate/onPickMedia/
            canDrive wiring the superseded Library needed here is now internal.

            Pointer mirroring is gone with it: the ghost cursor addressed a
            fraction of a freely-scrolling pane, and the stage has no such pane.
            The code pill and the "host is choosing" banner ride on the stage's
            own chrome rather than being injected through slots. */}
        <MoviesStage />
        <div style={{ position: 'absolute', top: 12, right: 12, zIndex: 2 }}>
          <CodePill code={session.id} count={participantCount} />
        </div>
        {!canDrive ? <ChoosingBanner host={session.hostName} /> : null}

        {layoutMode === 'float' && <CameraGrid {...cameraProps} />}
        {/* Chat: phones get the same dismissible slide-over sheet + scrim as the
            watch screen (cohesion); desktop keeps the docked panel. */}
        {chatOpen && (
          phone
            ? (
              <>
                <div onClick={(e) => { e.stopPropagation(); closeChat() }}
                  style={{ position: 'absolute', inset: 0, zIndex: Z.chatScrim, background: 'rgba(4,5,8,.5)', animation: 'scrimIn .2s ease both' }} />
                <ChatSheet />
              </>
            )
            : <Chat top={124} />
        )}

        <AVErrorBanner error={lk.error} />
        <LobbyAVBar lk={lk} chatOpen={chatOpen} onToggleChat={toggleChat} hideSelf={hideSelf} onToggleHideSelf={toggleHideSelf} />
        <RoomControls stage="lobby" top={74} />

        {phone && <RotateHint />}
      </div>
    )
  }

  // ── WATCHING: a title is selected, playback sync is live ─────────────────
  return (
    <WatchView
      session={session} isHost={isHost} cameraProps={cameraProps} lk={lk}
      chatOpen={chatOpen} chatRipple={chatRipple} alertMode={alertMode}
      messages={messages} selfUserId={user?.userId}
      layoutMode={layoutMode} setLayout={setLayout} openChat={openChat} closeChat={closeChat} toggleChat={toggleChat}
      setPlaybackTracks={setPlaybackTracks}
      setSubtitlePreferences={setSubtitlePreferences}
      hideSelf={hideSelf} onToggleHideSelf={toggleHideSelf}
    />
  )
}

/**
 * Camera / microphone / room failures, in front of the user.
 *
 * Rendered on EVERY stage — lobby and watch. It used to exist only
 * inside WatchView, so a denied camera permission in the lobby (where people
 * first switch their camera on, before any title is picked) flagged an error the
 * UI never showed: the button just did nothing. useLiveKit auto-dismisses the
 * message after ~4.5s. Opaque and high-contrast so it stays readable over a
 * bright frame.
 */
function AVErrorBanner({ error, top = 'calc(var(--sa-t) + 70px)' }: { error?: string | null; top?: string }) {
  if (!error) return null
  return (
    <div role="alert" style={{
      position: 'absolute', top, left: '50%', transform: 'translateX(-50%)', zIndex: Z.toast, maxWidth: '80vw',
      display: 'flex', alignItems: 'center', gap: 9, padding: '11px 16px', borderRadius: 12,
      background: 'rgba(224,101,94,.14)', border: '1px solid rgba(224,101,94,.4)', color: 'var(--text)',
      fontSize: 13.5, fontWeight: 600, boxShadow: '0 10px 30px rgba(0,0,0,.55)',
      animation: 'in .22s cubic-bezier(.2,0,.1,1)',
    }}>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="var(--red)" strokeWidth="2" style={{ flexShrink: 0 }}><circle cx="12" cy="12" r="10" /><path d="M12 8v4M12 16h.01" /></svg>
      {error}
    </div>
  )
}

// The column the desktop chat drawer occupies: its own `right: 12` inset, its
// `min(300px, …)` width, and 12px of clearance from the frame. The watch stage
// gives this up while chat is open rather than letting the drawer cover it.
const CHAT_DRAWER_W = 324

// A shared empty log, so an unsupplied `messages` prop does not hand the toast
// feed a new array identity on every render.
const NO_MESSAGES: ChatMessage[] = []

// The immersive watch screen: real fullscreen (whole container, feeds stay
// visible), and chrome that auto-hides after idle and returns on mouse move
// (desktop) or a tap (phone). See watchLayers.js for the z-index scale.
function WatchView({
  session, isHost, cameraProps, lk, chatOpen, chatRipple = 0, alertMode, layoutMode,
  messages = NO_MESSAGES, selfUserId,
  setLayout = () => {}, openChat = () => {}, closeChat = () => {}, toggleChat = () => {}, setPlaybackTracks = () => {}, setSubtitlePreferences = () => {}, hideSelf, onToggleHideSelf = () => {},
}: {
  session: PartySession
  isHost?: boolean
  cameraProps: CameraProps
  lk: LiveKitState
  chatOpen?: boolean
  chatRipple?: number
  alertMode?: 'focus' | 'on' | 'mute'
  messages?: ChatMessage[]
  selfUserId?: string
  layoutMode?: 'float' | 'dock'
  setLayout?: (mode: 'float' | 'dock') => void
  openChat?: (focus?: boolean) => void
  closeChat?: () => void
  toggleChat?: () => void
  setPlaybackTracks?: (tracks?: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null }) => void
  setSubtitlePreferences?: (preferences: SubtitlePreferences) => void
  hideSelf?: boolean
  onToggleHideSelf?: () => void
}) {
  const phone = usePhone()
  const rootRef = useRef<HTMLDivElement | null>(null)
  // Playback state, reported up by the player, purely so the chrome can obey
  // "controls hide after three seconds DURING PLAYBACK" — a paused frame keeps
  // its controls.
  const [playing, setPlaying] = useState(true)
  const chrome = useAutoHideControls({ playing })
  const visible = chrome.visible
  const displayPreferences = useDisplayPreferences()
  const toasts = useChatToasts({ messages, chatOpen, selfUserId })
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
  // shown it re-arms the idle timer. On desktop a click only wakes the chrome.
  const toggleChrome = () => chrome.toggle()
  const onSurfaceTap = () => chrome.note('tap')   // desktop click-to-wake

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
      const el = rootRef.current
      const p = el?.requestFullscreen?.()
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

  // The stage is always a fixed full-bleed layer sized to the DYNAMIC viewport
  // (`100dvh`) rather than the static layout viewport that `bottom:0`/`inset:0`
  // resolves against. On mobile browsers with collapsing toolbars (iOS Safari's
  // top/bottom chrome especially) `dvh` tracks the *visible* viewport, so the
  // stage — and every absolutely-positioned overlay anchored to its bottom edge
  // (the control bar, camera strip) — rides above Safari's bottom toolbar and
  // the home indicator instead of being clipped under them (Phase C, F6/G1).
  // On desktop `dvh == vh`, so this is a no-op there. This makes the NORMAL watch
  // stage robust, not just the immersive case (Phase B). overflow:hidden guards
  // against any dvw rounding overflow. Anchoring via top/left/right + an explicit
  // height (no `bottom`) is what lets `100dvh` win over the layout viewport.
  const rootStyle: CSSProperties = {
    position: 'fixed', top: 0, left: 0, right: 0,
    height: '100dvh', minHeight: '100dvh',
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
      <AVErrorBanner error={lk.error} />

      {/* On desktop the dock shrinks the video; on phones the video stays full-bleed
          and cameras float as a compact strip so the movie is never letterboxed. */}
      <div style={{
        position: 'absolute', inset: 0,
        marginLeft: (!phone && !hideAllFeeds && layoutMode === 'dock') ? 210 : 0,
        // "The movie stage yields enough horizontal space for the drawer rather
        // than being covered by it." The stage gives up the drawer's column
        // instead of the drawer being painted over the frame.
        marginRight: (!phone && chatOpen) ? CHAT_DRAWER_W : 0,
        transition: 'margin-left .3s cubic-bezier(.2,0,.1,1), margin-right .3s cubic-bezier(.2,0,.1,1)',
      }}>
        <HlsPlayer
          session={session} isHost={isHost} collaborativeControl={session.collaborativeControl}
          onSetPlaybackTracks={setPlaybackTracks}
          onSetSubtitlePreferences={setSubtitlePreferences}
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
        {/* Desktop camera layouts */}
        {!phone && !hideAllFeeds && layoutMode === 'float' && <CameraGrid {...cameraProps} />}
      </div>

      {!phone && !hideAllFeeds && layoutMode === 'dock' && (
        <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 210, zIndex: Z.cameraStrip }}>
          <Dock {...cameraProps} />
        </div>
      )}

      {/* Phone: compact, collapsible camera strip that sits above the bottom bar
          and can be hidden entirely so it never covers the movie. */}
      {phone && !hideAllFeeds && camStripOpen && <MobileCameraStrip {...cameraProps} visible={visible} />}

      {/* The desktop chat opener now lives in RoomControls' top-right cluster
          (alongside the watch-party menu), matching the redesigned player chrome.
          It replaced a right-edge tab that sat here — two chat buttons on one
          screen was worse than either alone. Press C still works (handled in
          Player). */}

      {/* Notification ripple from the right edge ('on' mode) */}
      {ripple > 0 && !chatOpen && (
        <div key={ripple} onAnimationEnd={() => setRipple(0)}
          style={{ position: 'absolute', top: 0, right: 0, bottom: 0, width: 6, zIndex: Z.chatEdge, pointerEvents: 'none',
            background: 'var(--text)', transformOrigin: 'right',
            animation: 'edgeRipple .9s ease-out forwards' }} />
      )}

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

      {/* Chat toasts. Anchored under the top-right room cluster, which is the
          one region of the stage that is not spoken for: the transport and the
          subtitles own the bottom, the chat toggle and the room menu own the
          top-right ABOVE this, floating camera tiles default to the top-left
          (and the phone camera popup to the bottom-right), and the desktop dock
          is a left column. Deliberately NOT tied to the auto-hide `visible`
          layer — a notification that only arrives when the controls happen to
          be up is not a notification. */}
      <AnalogToastStack
        view={toasts}
        preferences={displayPreferences}
        width={phone ? 232 : 280}
        style={{
          zIndex: Z.controlBar,
          top: phone ? 'calc(var(--sa-t) + 68px)' : 76,
          right: phone ? 'calc(var(--sa-r) + 8px)' : 14,
        }}
      />

      {/* Chat: persistent panel on desktop; dismissible slide-over sheet on phone
          (with a scrim) so it never permanently occludes the video or controls. */}
      {chatOpen && (
        phone
          ? (
            <>
              <div onClick={(e) => { e.stopPropagation(); closeChat() }}
                style={{ position: 'absolute', inset: 0, zIndex: Z.chatScrim, background: 'rgba(4,5,8,.5)', animation: 'scrimIn .2s ease both' }} />
              <ChatSheet />
            </>
          )
          : <Chat top={76} />
      )}

      <RoomControls
        stage="watching" visible={visible} phone={phone}
        onOpenChat={() => openChat(true)} chatOpen={chatOpen}
        layoutMode={layoutMode} onToggleLayout={() => setLayout(layoutMode === 'float' ? 'dock' : 'float')}
        hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
      />

      {/* Non-rotating "rotate your phone" hint. Shows only on a coarse-pointer
          phone held in portrait; hides itself in landscape and stays dismissed
          for the session once closed. Independent of the auto-hide `visible`
          layer so guidance is always present while portrait. */}
      {phone && <RotateHint />}
    </div>
  )
}

// Portrait detection for the phone UI. Never rotates anything — it only reports
// orientation so RotateHint can guide the user to turn the phone.
function usePortrait() {
  const [portrait, setPortrait] = useState(
    () => typeof window !== 'undefined' && window.matchMedia('(orientation: portrait)').matches
  )
  useEffect(() => {
    const mq = window.matchMedia('(orientation: portrait)')
    const on = () => setPortrait(mq.matches)
    on()
    mq.addEventListener('change', on)
    return () => mq.removeEventListener('change', on)
  }, [])
  return portrait
}

// A small, centered glass chip that suggests rotating to landscape for a
// full-bleed 16:9 view. Shared by the lobby and the watch screen. It does NOT
// rotate the DOM (this replaced the old lobby rotate hack) — no transform:rotate,
// so safe areas, gestures and the real Fullscreen API keep behaving normally.
// Shown only in portrait on a phone; auto-hides in landscape; dismissible (whole
// chip taps to close) and stays dismissed for the session. Rendered at
// Z.rotateHint, cushioned off the notch/home indicator via --sa-*.
function RotateHint() {
  const portrait = usePortrait()
  const [dismissed, setDismissed] = useState(false)
  if (!portrait || dismissed) return null
  return (
    <button
      onClick={(e) => { e.stopPropagation(); setDismissed(true) }}
      aria-label="Rotate your phone for the best view. Tap to dismiss."
      style={{
        position: 'absolute', zIndex: Z.rotateHint,
        left: '50%', top: '50%', transform: 'translate(-50%,-50%)',
        maxWidth: 'calc(100vw - var(--sa-l) - var(--sa-r) - 32px)',
        marginTop: 'calc((var(--sa-t) - var(--sa-b)) / 2)', // stay centered within the safe area
        display: 'inline-flex', alignItems: 'center', gap: 9,
        padding: '9px 12px 9px 15px', borderRadius: 999, cursor: 'pointer',
        background: 'rgba(0,0,0,.72)', border: '1px solid rgba(255,255,255,.16)',
        color: 'var(--text)', fontSize: 12, fontWeight: 600, textAlign: 'left',
        boxShadow: '0 10px 32px rgba(0,0,0,.5)',
      }}
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ flexShrink: 0 }}>
        <path d="M3 12a9 9 0 0 1 15-6.7L21 8M21 3v5h-5" />
      </svg>
      <span>Rotate your phone for the best view</span>
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" style={{ flexShrink: 0, opacity: .75 }}>
        <path d="M18 6 6 18M6 6l12 12" />
      </svg>
    </button>
  )
}

// Phone chat as a right-side slide-over sheet. Wraps the existing <Chat> so all
// chat behavior (alerts, focus, send, Esc) is preserved; only the framing differs.
function ChatSheet() {
  return (
    <div onClick={(e) => e.stopPropagation()} style={{
      position: 'absolute', zIndex: Z.chat,
      top: 'calc(var(--sa-t) + 8px)', bottom: 'calc(var(--sa-b) + 8px)',
      right: 'calc(var(--sa-r) + 8px)', width: 'min(340px, calc(100vw - var(--sa-l) - var(--sa-r) - 16px))',
      animation: 'sheetIn .26s cubic-bezier(.2,.8,.2,1)',
    }}>
      <Chat mobileSheet />
    </div>
  )
}

const CAM_POPUP_DEFAULT_W = 196
const CAM_POPUP_DEFAULT_H = 116
const CAM_POPUP_MARGIN = 10
const CAM_POPUP_MIN_W = 132
const CAM_POPUP_MIN_H = 76

// Phone camera popup: the "pop-up screen of people" the redesign asked for —
// a single floating, draggable, resizable window (react-rnd, same library the
// desktop CameraGrid already uses) instead of a strip pinned full-width above
// the bar. One <Rnd> frame holds every tile so multiple participants still
// read as ONE floating element; inside, tiles lay out as a compact horizontal
// mini-strip (this is a small-group watch party, not a conferencing grid) that
// scrolls if more people join than fit — the user can just resize the frame
// wider/taller instead. `camStripOpen` is no longer a manual toggle: it's
// derived from whether there's a camera actually on (mine or a remote
// participant's), so turning your camera on is the only tap needed to see it
// — a separate show/hide button used to make that a two-step action, which
// read as "I have to turn on my camera from two places." Respects the
// Phase-2.1 hide-self flag (localParticipant is dropped upstream).
function MobileCameraStrip({
  localParticipant, participants = [], isHost, removedCameras = new Set(), onRemove = () => {}, hideSelf, visible,
}: {
  localParticipant?: { identity: string; isLocal?: boolean } | null
  participants?: Array<{ identity: string; videoTrack?: unknown; isLocal?: boolean }>
  isHost?: boolean
  removedCameras?: Set<string>
  onRemove?: (identity: string) => void
  hideSelf?: boolean
  visible?: boolean
} = {}) {
  const localId = localParticipant?.identity
  const all = [
    ...(localParticipant && !hideSelf ? [{ ...localParticipant, isLocal: true }] : []),
    ...participants.filter(p => p.identity !== localId && !removedCameras.has(p.identity)),
  ]
    // Bug 5: only tiles for cameras that are actually ON (no avatar placeholders).
    .filter(p => !!p.videoTrack)

  const boundsRef = useRef<HTMLDivElement | null>(null)
  const [defaultFrame, setDefaultFrame] = useState<{ x: number; y: number; width: number; height: number } | null>(null)

  // Compute a sensible default position/size once, from the ACTUAL measured
  // bounds box below (which already excludes the safe areas and the bar) —
  // not a guess from window size — so the popup never opens overlapping the
  // bar or off a notch/home-indicator edge. Default corner: bottom-right. The
  // top-left (room code chip) and top-right (chat/host/leave cluster) corners
  // are already spoken for; bottom-right sits over the movie but clear of
  // both. Local, uncontrolled state — no persistence across sessions, and a
  // remount (closing and reopening the popup) just recomputes this again.
  useLayoutEffect(() => {
    const el = boundsRef.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    const width = Math.min(CAM_POPUP_DEFAULT_W, Math.max(CAM_POPUP_MIN_W, rect.width - CAM_POPUP_MARGIN * 2))
    const height = Math.min(CAM_POPUP_DEFAULT_H, Math.max(CAM_POPUP_MIN_H, rect.height - CAM_POPUP_MARGIN * 2))
    setDefaultFrame({
      width, height,
      x: Math.max(0, rect.width - width - CAM_POPUP_MARGIN),
      y: Math.max(0, rect.height - height - CAM_POPUP_MARGIN),
    })
  }, [])

  return (
    <div ref={boundsRef} style={{
      position: 'absolute', zIndex: Z.cameraStrip,
      top: 'calc(var(--sa-t) + 8px)', left: 'calc(var(--sa-l) + 8px)', right: 'calc(var(--sa-r) + 8px)',
      // Same clearance the old strip used: sit above the bottom bar when chrome
      // is shown; drop to the safe-area edge when it hides. Clearance derives
      // from the bar's REAL measured height (published as --watch-bar-h by
      // MobileBottomBar) so it tracks any change to the bar's contents. This is
      // the drag/resize BOUNDS box (react-rnd's bounds="parent" reads this
      // element's real rect) — the frame itself can be parked anywhere inside
      // it, but never dragged/resized outside it.
      bottom: visible ? 'calc(var(--sa-b) + 8px + var(--watch-bar-h, 56px) + 8px)' : 'calc(var(--sa-b) + 8px)',
      transition: 'bottom .25s cubic-bezier(.2,0,.1,1)',
      pointerEvents: 'none',
    }}>
      {defaultFrame && (
        <Rnd
          default={defaultFrame}
          bounds="parent"
          minWidth={CAM_POPUP_MIN_W}
          minHeight={CAM_POPUP_MIN_H}
          style={{ pointerEvents: 'auto' }}
          onClick={(e: MouseEvent) => e.stopPropagation()}
        >
          <div style={{
            width: '100%', height: '100%', borderRadius: 16, overflow: 'hidden', position: 'relative',
            background: 'rgba(10,10,14,.72)', border: '1px solid rgba(255,255,255,.16)',
            boxShadow: '0 12px 32px rgba(0,0,0,.5)',
            animation: 'in .2s cubic-bezier(.2,0,.1,1) both',
          }}>
            {all.length === 0 && (
              <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', fontSize: 12.5, color: 'rgba(255,255,255,.55)' }}>No cameras</div>
            )}
            <div style={{ width: '100%', height: '100%', display: 'flex', gap: 6, padding: 6, overflowX: 'auto', overflowY: 'hidden' }}>
              {all.map(p => (
                <div key={p.identity} style={{
                  position: 'relative', height: '100%', flexShrink: 0,
                  width: all.length === 1 ? '100%' : undefined,
                  aspectRatio: all.length === 1 ? undefined : '4/3',
                  minWidth: all.length === 1 ? undefined : 64,
                  borderRadius: 10, overflow: 'hidden', border: '1px solid rgba(255,255,255,.16)',
                }}>
                  <CameraTile participant={p} isLocal={p.isLocal} isHost={isHost} onRemove={() => onRemove(p.identity)} />
                </div>
              ))}
            </div>
            {/* Drag affordance — same corner-dots hint the desktop CameraGrid's
                per-tile Rnd frames use. Purely visual, non-interactive; the
                frame itself is draggable from anywhere on it. */}
            <div aria-hidden style={{ position: 'absolute', top: 7, left: 8, display: 'flex', gap: 3, pointerEvents: 'none' }}>
              {[0, 1, 2].map(k => <div key={k} style={{ width: 3, height: 3, borderRadius: '50%', background: 'rgba(255,255,255,.5)' }} />)}
            </div>
          </div>
        </Rnd>
      )}
    </div>
  )
}

/* ── Lobby chrome bits ─────────────────────────────────────────────────── */
function CodePill({ code, count }: { code?: string; count?: number } = {}) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12, padding: '7px 8px 7px 14px', borderRadius: 999,
      background: 'var(--glass2)', border: '1px solid var(--stroke)',
    }}>
      <span style={{ fontSize: 13, color: 'var(--text3)' }}>Code</span>
      <span style={{ fontSize: 14, fontWeight: 700, letterSpacing: '.1em', fontFamily: 'JetBrains Mono, ui-monospace, monospace', color: 'var(--text)' }}>{code}</span>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '4px 10px', borderRadius: 999, background: 'var(--glass2)', fontSize: 12.5, fontWeight: 600, color: 'var(--text)' }}>
        <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--text)' }} />
        {count}
      </span>
    </div>
  )
}

function ChoosingBanner({ host }: { host?: string } = {}) {
  return (
    <div style={{
      maxWidth: 1240, margin: '14px auto 0', padding: '10px 16px', borderRadius: 10,
      display: 'flex', alignItems: 'center', gap: 10,
      background: 'var(--glass2)', border: '1px solid var(--stroke2)', color: 'var(--text2)', fontSize: 13.5, fontWeight: 600,
    }}>
      <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--text)', animation: 'pulse 2s ease-in-out infinite' }} />
      {host || 'The host'} is choosing what to watch…
    </div>
  )
}

// The party's own controls: mic, camera, self-view and chat. Used by the lobby,
// which has no player bar to put them in.
function LobbyAVBar({ lk, chatOpen, onToggleChat, hideSelf, onToggleHideSelf }: {
  lk: LiveKitState
  chatOpen?: boolean
  onToggleChat?: () => void
  hideSelf?: boolean
  onToggleHideSelf?: () => void
}) {
  const Btn = ({ on, danger = false, onClick, title, children }: {
    on?: boolean
    danger?: boolean
    onClick?: () => void
    title?: string
    children?: ReactNode
  }) => (
    <button onClick={onClick} title={title} style={{
      ...glass('light'), width: 48, height: 48, borderRadius: 16, cursor: 'pointer',
      display: 'grid', placeItems: 'center',
      color: danger ? 'var(--red)' : 'var(--text)',
      ...(on ? { backgroundColor: 'var(--glass2)' } : {}),
    }}>{children}</button>
  )
  return (
    <div style={{
      position: 'absolute', bottom: 'calc(var(--sa-b) + 22px)', left: '50%', transform: 'translateX(-50%)', zIndex: 40,
      display: 'flex', gap: 10,
    }}>
      <Btn on={lk.micOn} onClick={() => lk.enableMic(!lk.micOn)} title="Microphone">
        {lk.micOn
          ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M12 2a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z" /><path d="M19 10v1a7 7 0 0 1-14 0v-1M12 18v4" /></svg>
          : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M9 9v2a3 3 0 0 0 5.12 2.12M15 9.34V5a3 3 0 0 0-5.94-.6M19 10v1a7 7 0 0 1-.11 1.23M12 18.5A7 7 0 0 1 5 11v-1M12 18v4" /></svg>}
      </Btn>
      <Btn on={lk.camOn} onClick={() => lk.enableCamera(!lk.camOn)} title="Camera">
        {lk.camOn
          ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M23 7l-7 5 7 5V7z" /><rect x="1" y="5" width="15" height="14" rx="2" /></svg>
          : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M16 16H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h1m4-1h4a2 2 0 0 1 2 2v3l4-2v8" /></svg>}
      </Btn>
      <Btn on={hideSelf} onClick={onToggleHideSelf} title={hideSelf ? 'Show my camera to me' : 'Hide my camera from me'}>
        {hideSelf
          ? <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4" /></svg>
          : <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z" /><circle cx="12" cy="12" r="3" /></svg>}
      </Btn>
      <Btn on={chatOpen} onClick={onToggleChat} title="Chat">
        <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" /></svg>
      </Btn>
    </div>
  )
}

type HlsPlayerProps = Omit<PlayerProps, 'hlsUrl' | 'mediaItemId' | 'playback' | 'syncMode'> & {
  session: PartySession
}

function HlsPlayer({ session, isHost, collaborativeControl, onSetPlaybackTracks, ...rest }: HlsPlayerProps) {
  const [hlsUrl, setHlsUrl] = useState<{ itemId: string; url: string } | null>(null)
  const audioStreamIndex = session?.playback?.selectedAudioIndex
  const subtitleStreamIndex = session?.playback?.selectedSubtitleIndex
  const mediaSourceId = session?.playback?.mediaSourceId ?? session?.mediaSourceId ?? session?.mediaItemId

  // Phase 1.2: fetch the ADAPTIVE (ABR) master playlist ONCE per media item.
  // The URL carries no bitrate pin, so hls.js loads a multi-variant ladder and
  // adapts by bandwidth. Quality changes are now level switches inside hls.js
  // (see Player → useQualityLevels) — they never re-fetch or swap <HlsVideo src>,
  // so this effect intentionally does NOT depend on the selected quality.
  useEffect(() => {
    const itemId = session?.mediaItemId
    // Never render the prior title while the new playlist is resolving. Apart
    // from showing the wrong movie briefly, that kept the old HLS track list
    // alive while the settings menu was already using the new session metadata.
    setHlsUrl(null)
    if (!itemId) return
    let cancelled = false
    const qs = new URLSearchParams({ itemId, abr: '1' })
    if (mediaSourceId) qs.set('mediaSourceId', mediaSourceId)
    if (Number.isInteger(audioStreamIndex)) qs.set('audioStreamIndex', String(audioStreamIndex))
    if (Number.isInteger(subtitleStreamIndex)) qs.set('subtitleStreamIndex', String(subtitleStreamIndex))
    fetch(`/api/library/hls-url?${qs}`, { credentials: 'include' })
      .then(r => r.ok ? apiJson(r) : null)
      .then(d => {
        const url = stringField(d, 'url')
        if (url && !cancelled) setHlsUrl({ itemId, url })
      })
      .catch(() => {})
    return () => { cancelled = true }
  // Track indices are intentionally excluded from deps: audio/subtitle switching
  // is handled client-side via hls.audioTrack / hls.subtitleTrack (no src reload).
  // The initial URL still carries the session's starting indices for the first load.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.mediaItemId, mediaSourceId])

  if (!hlsUrl || hlsUrl.itemId !== session.mediaItemId) return (
    <div style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center', background: '#000' }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
        <div style={{ width: 36, height: 36, borderRadius: '50%', border: '3px solid var(--stroke2)', borderTopColor: 'var(--accent)', animation: 'spin .9s linear infinite' }} />
        <span style={{ color: 'var(--text3)', fontSize: 13 }}>Loading video…</span>
      </div>
    </div>
  )

  return (
    <Player
      // A media item has its own HLS engine and text-track collection. Keying
      // the player prevents the previous item's engine from receiving a new
      // subtitle selection during the handoff.
      key={hlsUrl.itemId}
      hlsUrl={hlsUrl.url}
      mediaItemId={session.mediaItemId}
      playback={session.playback ?? undefined}
      subtitlePreferences={session.subtitlePreferences}
      isHost={isHost}
      collaborativeControl={collaborativeControl}
      syncMode={session.syncMode}
      onSetPlaybackTracks={onSetPlaybackTracks}
      {...rest}
    />
  )
}
