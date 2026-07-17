import { useEffect, useRef, useState } from 'react'
import type { CSSProperties, MouseEvent, PointerEvent, ReactNode } from 'react'
import { useParty } from '../context/PartyContext'
import { useSocket } from '../hooks/useSocket'
import { useLiveKit } from '../hooks/useLiveKit'
import type { LiveKitParticipantView } from '../hooks/useLiveKit'
import { useHideSelf } from '../hooks/useHideSelf'
import { usePushToTalk } from '../hooks/usePushToTalk'
import { navigate } from '../router'
import Player from '../components/Player'
import type { PlayerProps } from '../components/Player'
import CameraGrid from '../components/CameraGrid'
import Dock from '../components/Dock'
import Chat from '../components/Chat'
import RoomControls from '../components/RoomControls'
import CameraTile from '../components/CameraTile'
import { glass } from '../glass'
import { mirror } from '../mirror'
import { usePhone } from '../hooks/useIsMobile'
import { Z } from '../watchLayers'
import Library from './Library'
import Lobby from './Lobby'
import type { PartySession } from '../types'
import { apiJson, stringField } from '../types/guards'

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
  guardToggle: (action: () => void | Promise<void>) => Promise<void>
}

export default function Party({ partyId, isNew, itemId, initialTracks }: { partyId?: string; isNew?: boolean; itemId?: string; initialTracks?: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null } } = {}) {
  const { socket } = useSocket()
  const party = useParty()
  const {
    session, role, layoutMode, chatOpen, chatRipple, alertMode,
    setLayout, toggleChat, openChat, closeChat, navigateBrowse, sendPointer, selectMedia, setPlaybackTracks,
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

  const joinedRef = useRef(false)
  useEffect(() => {
    // Guard against StrictMode's double-invoke (would create/join twice)
    if (joinedRef.current) return
    joinedRef.current = true
    if (isNew) {
      // itemId → room preloaded with a title; no itemId → empty lobby room
      const create = itemId ? party.createParty(itemId, initialTracks) : party.createRoom()
      create
        .then(id => window.history.replaceState({}, '', `/party/${id}`))
        .catch(() => navigate('/library'))
    } else if (partyId) {
      party.joinParty(partyId).catch(err => setJoinError(err?.message || 'not found'))
    }
  }, []) // eslint-disable-line

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
        <Library
          embedded
          stack={session.browse?.stack ?? []}
          onNavigate={navigateBrowse}
          onPickMedia={(item: { Id: string }, tracks) => selectMedia(item.Id, tracks)}
          canDrive={canDrive}
          onPointer={canDrive ? sendPointer : undefined}
          mirrorSubscribe={!canDrive ? mirror.subscribe : undefined}
          driverName={session.hostName}
          headerRight={<CodePill code={session.id} count={participantCount} />}
          banner={!canDrive ? <ChoosingBanner host={session.hostName} /> : null}
        />

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
      layoutMode={layoutMode} setLayout={setLayout} openChat={openChat} closeChat={closeChat}
      setPlaybackTracks={setPlaybackTracks}
      hideSelf={hideSelf} onToggleHideSelf={toggleHideSelf}
    />
  )
}

// The immersive watch screen: real fullscreen (whole container, feeds stay
// visible), and chrome that auto-hides after idle and returns on mouse move
// (desktop) or a tap (phone). See watchLayers.js for the z-index scale.
function WatchView({
  session, isHost, cameraProps, lk, chatOpen, chatRipple = 0, alertMode, layoutMode,
  setLayout = () => {}, openChat = () => {}, closeChat = () => {}, setPlaybackTracks = () => {}, hideSelf, onToggleHideSelf = () => {},
}: {
  session: PartySession
  isHost?: boolean
  cameraProps: CameraProps
  lk: LiveKitState
  chatOpen?: boolean
  chatRipple?: number
  alertMode?: 'focus' | 'on' | 'mute'
  layoutMode?: 'float' | 'dock'
  setLayout?: (mode: 'float' | 'dock') => void
  openChat?: (focus?: boolean) => void
  closeChat?: () => void
  setPlaybackTracks?: (tracks?: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null }) => void
  hideSelf?: boolean
  onToggleHideSelf?: () => void
}) {
  const phone = usePhone()
  const rootRef = useRef<HTMLDivElement | null>(null)
  const hideTimer = useRef<number | null>(null)
  const [visible, setVisible] = useState(true)
  // Single "are we in the app's fullscreen presentation?" state. Derived from
  // whichever mechanism the platform supports (element FS today; iOS faux-FS in
  // Phase B). Drives the button icon, orientation lock, and the control-layer poke.
  const [immersive, setImmersive] = useState(false)
  const [ripple, setRipple] = useState(0)
  // Cameras start collapsed on phones so they never cover the movie by default.
  const [camStripOpen, setCamStripOpen] = useState(false)

  // ── Audio interaction model ──────────────────────────────────────────────
  // Default-mute-on-movie-start: WatchView mounts exactly when the session
  // enters the watching stage, so muting once here (on mount) fires exactly on
  // that lobby→watching transition and never fights later manual unmutes. If
  // the mic is already off (the common case) this is a harmless no-op. Going
  // back to the lobby unmounts WatchView, so re-entering re-arms this.
  useEffect(() => {
    if (lk.micOn) lk.enableMic(false)
  }, []) // eslint-disable-line

  // Push-to-talk: hold T (desktop) / press-and-hold the talk button (phone) to
  // momentarily open the mic; release returns to muted. No-op if the user has
  // manually unmuted. Works even while the video has focus (window listeners).
  const ptt = usePushToTalk({ micOn: lk.micOn, enableMic: lk.enableMic })

  // Edge ripple when a message arrives in 'on' alert mode
  useEffect(() => {
    if (chatRipple > 0 && alertMode === 'on' && !chatOpen) setRipple(r => r + 1)
  }, [chatRipple]) // eslint-disable-line

  const poke = () => {
    setVisible(true)
    if (hideTimer.current != null) window.clearTimeout(hideTimer.current)
    hideTimer.current = window.setTimeout(() => setVisible(false), 3000)
  }
  useEffect(() => { poke(); return () => { if (hideTimer.current != null) window.clearTimeout(hideTimer.current) } }, [])

  // On phones a tap on the video TOGGLES the control layer (show → hide); when
  // shown it re-arms the idle timer. On desktop a click only wakes the chrome.
  const toggleChrome = () => {
    if (visible) { setVisible(false); if (hideTimer.current != null) window.clearTimeout(hideTimer.current) }
    else poke()
  }
  const onSurfaceTap = () => poke()   // desktop click-to-wake

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
  const guardedToggle = (fn: () => void) => {
    const g = seekBridgeRef.current?.guardToggle
    return g ? g(fn) : fn()
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
      {lk.error && (
        // Bug 8: opaque, high-contrast banner (was a see-through red wash that was
        // hard to read over a bright frame). useLiveKit auto-dismisses it ~4.5s.
        <div role="alert" style={{
          position: 'absolute', top: 'calc(var(--sa-t) + 70px)', left: '50%', transform: 'translateX(-50%)', zIndex: Z.toast, maxWidth: '80vw',
          display: 'flex', alignItems: 'center', gap: 9, padding: '11px 16px', borderRadius: 12,
          background: 'rgba(224,101,94,.14)', border: '1px solid rgba(224,101,94,.4)', color: 'var(--text)',
          fontSize: 13.5, fontWeight: 600, boxShadow: '0 10px 30px rgba(0,0,0,.55)',
          animation: 'in .22s cubic-bezier(.2,0,.1,1)',
        }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="var(--red)" strokeWidth="2" style={{ flexShrink: 0 }}><circle cx="12" cy="12" r="10" /><path d="M12 8v4M12 16h.01" /></svg>
          {lk.error}
        </div>
      )}

      {/* On desktop the dock shrinks the video; on phones the video stays full-bleed
          and cameras float as a compact strip so the movie is never letterboxed. */}
      <div style={{ position: 'absolute', inset: 0, marginLeft: (!phone && layoutMode === 'dock') ? 210 : 0, transition: 'margin-left .3s cubic-bezier(.2,0,.1,1)' }}>
        <HlsPlayer
          session={session} isHost={isHost} collaborativeControl={session.collaborativeControl}
          onSetPlaybackTracks={setPlaybackTracks}
          micOn={lk.micOn} camOn={lk.camOn}
          onToggleMic={() => guardedToggle(() => lk.enableMic(!lk.micOn))}
          onToggleCam={() => guardedToggle(() => lk.enableCamera(!lk.camOn))}
          talking={ptt.talking} onTalkStart={ptt.start} onTalkEnd={ptt.stop}
          onToggleLayout={() => setLayout(layoutMode === 'float' ? 'dock' : 'float')}
          hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
          onOpenChat={() => openChat(true)} layoutMode={layoutMode}
          visible={visible} immersive={immersive} enterImmersive={enterImmersive} exitImmersive={exitImmersive}
          phone={phone} camStripOpen={camStripOpen} onToggleCamStrip={() => setCamStripOpen(o => !o)}
          seekBridgeRef={seekBridgeRef}
        />
        {/* Desktop camera layouts */}
        {!phone && layoutMode === 'float' && <CameraGrid {...cameraProps} />}
      </div>

      {!phone && layoutMode === 'dock' && (
        <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 210, zIndex: Z.cameraStrip }}>
          <Dock {...cameraProps} />
        </div>
      )}

      {/* Phone: compact, collapsible camera strip that sits above the bottom bar
          and can be hidden entirely so it never covers the movie. */}
      {phone && camStripOpen && <MobileCameraStrip {...cameraProps} visible={visible} />}

      {/* Desktop chat opener (bug 1): an explicit, visible tab you CLICK — no more
          proximity/hover open from a full-height invisible edge zone. Press C also
          works (handled in Player). Fades with the auto-hide chrome. */}
      {!phone && !chatOpen && (
        <button onClick={(e) => { e.stopPropagation(); openChat(true) }} title="Open chat (C)" aria-label="Open chat"
          style={{
            position: 'absolute', top: '50%', right: 0, transform: 'translateY(-50%)',
            zIndex: Z.chatEdge, width: 30, height: 62, borderRadius: '13px 0 0 13px',
            display: 'grid', placeItems: 'center', cursor: 'pointer', color: '#fff',
            ...glass('medium'), borderRight: 'none',
            opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s',
          }}>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" /></svg>
        </button>
      )}

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

      <RoomControls stage="watching" visible={visible} phone={phone} onOpenChat={() => openChat(true)} chatOpen={chatOpen} />

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

// Phone camera strip: a single horizontal row of compact tiles, bottom-anchored
// just above the control bar, dismissed via the bar's camera toggle. Respects
// the Phase-2.1 hide-self flag (localParticipant is dropped upstream).
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
  return (
    <div onClick={(e) => e.stopPropagation()} style={{
      position: 'absolute', zIndex: Z.cameraStrip,
      left: 'calc(var(--sa-l) + 8px)', right: 'calc(var(--sa-r) + 8px)',
      // Sit above the bottom control bar when chrome is shown; slide down to the
      // safe-area edge when it hides. Clearance derives from the bar's REAL
      // measured height (published as --watch-bar-h by MobileBottomBar) so it
      // tracks any change to the bar's contents: bar bottom is (--sa-b + 8px),
      // plus the bar height, plus an 8px gap above it. Falls back to 56px (→ the
      // old 72px total) before the bar has measured.
      bottom: visible ? 'calc(var(--sa-b) + 8px + var(--watch-bar-h, 56px) + 8px)' : 'calc(var(--sa-b) + 8px)',
      transition: 'bottom .25s cubic-bezier(.2,0,.1,1)',
      display: 'flex', gap: 8, overflowX: 'auto', padding: 2, pointerEvents: 'auto',
    }}>
      {all.length === 0 && (
        <div style={{ ...glass('light'), borderRadius: 12, padding: '10px 14px', fontSize: 12.5, color: 'rgba(255,255,255,.6)' }}>No cameras</div>
      )}
      {all.map(p => (
        <div key={p.identity} style={{
          position: 'relative', width: 108, aspectRatio: '4/3', flexShrink: 0,
          borderRadius: 13, overflow: 'hidden', border: '1px solid rgba(255,255,255,.18)',
          boxShadow: '0 8px 24px rgba(0,0,0,.45)',
        }}>
          <CameraTile participant={p} isLocal={p.isLocal} isHost={isHost} onRemove={() => onRemove(p.identity)} />
        </div>
      ))}
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
      isHost={isHost}
      collaborativeControl={collaborativeControl}
      syncMode={session.syncMode}
      onSetPlaybackTracks={onSetPlaybackTracks}
      {...rest}
    />
  )
}
