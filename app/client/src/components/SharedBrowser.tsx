import { useCallback, useEffect, useRef, useState } from 'react'
import type { CSSProperties, KeyboardEvent, PointerEvent, ReactNode, WheelEvent } from 'react'
import { useParty } from '../context/PartyContext.tsx'
import { usePhone } from '../hooks/useIsMobile.ts'
import { Z } from '../watchLayers.ts'
import type { BrowserInputEvent, PartySession } from '../types.ts'

interface AttachableTrack {
  attach: (element: HTMLMediaElement) => unknown
  detach: (element: HTMLMediaElement) => unknown
}

function isAttachableTrack(value: unknown): value is AttachableTrack {
  return typeof value === 'object' && value !== null
    && 'attach' in value && typeof value.attach === 'function'
    && 'detach' in value && typeof value.detach === 'function'
}

/** DOM MouseEvent.button → X button number. */
const BUTTON = new Map([[0, 1], [1, 2], [2, 3]])

/** Keys xdotool names differently from the DOM. Anything else is sent as text. */
const KEYMAP: Record<string, string> = {
  Backspace: 'BackSpace', Enter: 'Return', Tab: 'Tab', Escape: 'Escape',
  ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right',
  Delete: 'Delete', Home: 'Home', End: 'End', PageUp: 'Prior', PageDown: 'Next',
  ' ': 'space',
}

const MOVE_INTERVAL_MS = 25   // ~40/s. Above this, xdotool becomes the bottleneck.

/**
 * The shared browser: a containerised Chromium published into the party's
 * LiveKit room, and (for the driver) the input surface that drives it.
 *
 * Not a video player — nothing here touches the Jellyfin sync engine. This is a
 * live stream: everyone receives the same frames, so there is no timeline to
 * agree on and nothing to seek.
 */
export default function SharedBrowser({
  session, userId, isHost, videoTrack, audioTrack, visible = true,
}: {
  session: PartySession
  userId?: string
  isHost: boolean
  videoTrack: unknown | null
  audioTrack: unknown | null
  visible?: boolean
}) {
  const party = useParty()
  const phone = usePhone()
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const surfaceRef = useRef<HTMLDivElement | null>(null)
  const lastMove = useRef(0)
  const [fit, setFit] = useState<'contain' | 'actual'>('contain')
  const [scalePercent, setScalePercent] = useState(100)
  const [urlDraft, setUrlDraft] = useState('')

  const browser = session.browser ?? null
  // Control is server-enforced; this only decides what the UI offers. Phones are
  // view-only by design, so they never mount the input surface at all.
  const isDriver = !phone && !!userId && browser?.driverUserId === userId
  const driverName = browser?.driverUserId === session.hostId
    ? (session.hostName ?? 'The host')
    : session.guests?.find(guest => guest.userId === browser?.driverUserId)?.name ?? 'Someone'

  useEffect(() => {
    const element = videoRef.current
    if (isAttachableTrack(videoTrack) && element) {
      videoTrack.attach(element)
      return () => { videoTrack.detach(element) }
    }
  }, [videoTrack])

  useEffect(() => {
    const element = audioRef.current
    if (isAttachableTrack(audioTrack) && element) {
      audioTrack.attach(element)
      return () => { audioTrack.detach(element) }
    }
  }, [audioTrack])

  // ── geometry ───────────────────────────────────────────────────────────────

  /**
   * Where the image actually sits on screen.
   *
   * object-fit centres the image inside the element, and the image's size is NOT
   * the element's size. Assuming otherwise is what makes a remote click drift
   * further off the further it is from the centre — the bug the earlier attempt
   * shipped and had to fix twice.
   */
  const geometry = useCallback(() => {
    const video = videoRef.current
    if (!video) return null
    const vw = video.videoWidth
    const vh = video.videoHeight
    if (!vw || !vh) return null
    const rect = video.getBoundingClientRect()
    const scale = fit === 'actual' ? 1 : Math.min(rect.width / vw, rect.height / vh)
    const dw = vw * scale
    const dh = vh * scale
    return { vw, vh, scale, ox: rect.left + (rect.width - dw) / 2, oy: rect.top + (rect.height - dh) / 2 }
  }, [fit])

  // Displayed scale is the number that matters for sharpness: anything other
  // than 100% resamples every remote pixel, which reads as soft browser UI. The
  // cure is matching the window to the remote screen, not more bitrate.
  useEffect(() => {
    const update = () => {
      const geo = geometry()
      if (geo) setScalePercent(Math.round(geo.scale * 100))
    }
    update()
    const timer = window.setInterval(update, 1000)
    window.addEventListener('resize', update)
    return () => { window.clearInterval(timer); window.removeEventListener('resize', update) }
  }, [geometry])

  const toRemote = useCallback((clientX: number, clientY: number) => {
    const geo = geometry()
    if (!geo) return null
    const x = (clientX - geo.ox) / geo.scale
    const y = (clientY - geo.oy) / geo.scale
    if (x < 0 || y < 0 || x > geo.vw || y > geo.vh) return null   // in the letterbox
    return { x: Math.round(x), y: Math.round(y) }
  }, [geometry])

  // ── input ──────────────────────────────────────────────────────────────────

  const send = (event: BrowserInputEvent) => { if (isDriver) party.sendBrowserInput(event) }

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    surfaceRef.current?.focus()
    surfaceRef.current?.setPointerCapture(event.pointerId)
    const point = toRemote(event.clientX, event.clientY)
    if (point) send({ type: 'down', x: point.x, y: point.y, button: BUTTON.get(event.button) ?? 1 })
    event.preventDefault()
  }

  const onPointerUp = (event: PointerEvent<HTMLDivElement>) => {
    const point = toRemote(event.clientX, event.clientY)
    if (point) send({ type: 'up', x: point.x, y: point.y, button: BUTTON.get(event.button) ?? 1 })
    event.preventDefault()
  }

  const onPointerMove = (event: PointerEvent<HTMLDivElement>) => {
    const now = performance.now()
    if (now - lastMove.current < MOVE_INTERVAL_MS) return
    lastMove.current = now
    const point = toRemote(event.clientX, event.clientY)
    if (point) send({ type: 'move', x: point.x, y: point.y })
  }

  const onWheel = (event: WheelEvent<HTMLDivElement>) => {
    send({ type: 'scroll', dy: event.deltaY })
    event.preventDefault()
  }

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    const modifiers: string[] = []
    if (event.ctrlKey) modifiers.push('ctrl')
    if (event.altKey) modifiers.push('alt')
    if (event.shiftKey && event.key.length > 1) modifiers.push('shift')
    const named = KEYMAP[event.key] ?? (/^F\d{1,2}$/.test(event.key) ? event.key : null)
    if (named) {
      send({ type: 'key', key: [...modifiers, named].join('+') })
    } else if (event.key.length === 1) {
      // A modifier means this is a shortcut (ctrl+l), not text to type.
      if (modifiers.length > 0) send({ type: 'key', key: [...modifiers, event.key.toLowerCase()].join('+') })
      else send({ type: 'text', text: event.key })
    } else {
      return
    }
    event.preventDefault()
  }

  const submitUrl = () => {
    const url = urlDraft.trim()
    if (!url) return
    void party.navigateSharedBrowser(url)
    setUrlDraft('')
    surfaceRef.current?.focus()
  }

  // ── non-active states ──────────────────────────────────────────────────────

  if (!browser) return null

  if (browser.state === 'error') {
    return (
      <Centered>
        <Message
          title="The shared browser stopped"
          body={browser.error ?? 'Something went wrong with the shared browser.'}
        />
        {isHost && (
          <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
            <PrimaryButton onClick={() => { void party.startSharedBrowser(browser.url ?? undefined) }}>Try again</PrimaryButton>
            <PlainButton onClick={() => party.stopSharedBrowser()}>Back to the party</PlainButton>
          </div>
        )}
      </Centered>
    )
  }

  const waitingForFrames = browser.state === 'starting' || !videoTrack

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#000', overflow: 'hidden' }}>
      <video
        ref={videoRef}
        autoPlay
        playsInline
        muted
        style={{
          width: '100%', height: '100%', display: 'block', background: '#000',
          // contain never distorts; 'none' is 1:1 with the remote screen, centre-
          // cropped rather than shrunk, for when text sharpness matters more than
          // seeing the whole page.
          objectFit: fit === 'actual' ? 'none' : 'contain',
        }}
      />
      {/* LiveKit hands us a track; the element is ours, so audio needs its own. */}
      <audio ref={audioRef} autoPlay />

      {waitingForFrames && (
        <Centered>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
            <div style={{ width: 38, height: 38, borderRadius: '50%', border: '3px solid var(--stroke2)', borderTopColor: 'var(--accent)', animation: 'spin .9s linear infinite' }} />
            <span style={{ color: 'var(--text2)', fontSize: 13.5 }}>Starting the shared browser…</span>
          </div>
        </Centered>
      )}

      {/* The input surface. Mounted only for the driver, and it swallows every
          pointer event so the <video> element's own controls never see them.
          touch-action:none would otherwise let a drag pan the page instead. */}
      {isDriver && !waitingForFrames && (
        <div
          ref={surfaceRef}
          tabIndex={0}
          onPointerDown={onPointerDown}
          onPointerUp={onPointerUp}
          onPointerMove={onPointerMove}
          onWheel={onWheel}
          onKeyDown={onKeyDown}
          onContextMenu={event => event.preventDefault()}
          style={{ position: 'absolute', inset: 0, touchAction: 'none', cursor: 'crosshair', outline: 'none' }}
        />
      )}

      {/* Driver toolbar. The stream carries Chromium's own tab strip and address
          bar, so this is a convenience layer — typing a URL by injecting
          keystrokes into the remote address bar is fiddly, and back/forward as
          buttons beats remembering alt+Left. */}
      {isDriver && (
        <div style={{
          position: 'absolute', top: 'calc(var(--sa-t) + 8px)', left: '50%', transform: 'translateX(-50%)',
          zIndex: Z.controlBar, display: 'flex', alignItems: 'center', gap: 6,
          width: 'min(760px, calc(100vw - 32px))', padding: 6, borderRadius: 12,
          background: 'var(--glass)', border: '1px solid var(--stroke)', boxShadow: 'var(--shadow)',
          opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s',
        }}>
          <IconButton title="Back" onClick={() => send({ type: 'key', key: 'alt+Left' })}>←</IconButton>
          <IconButton title="Forward" onClick={() => send({ type: 'key', key: 'alt+Right' })}>→</IconButton>
          <IconButton title="Reload" onClick={() => send({ type: 'key', key: 'F5' })}>⟳</IconButton>
          <IconButton title="New tab" onClick={() => send({ type: 'key', key: 'ctrl+t' })}>+</IconButton>
          <input
            value={urlDraft}
            onChange={event => setUrlDraft(event.target.value)}
            // Keystrokes in this field are for this field. Without stopping
            // propagation they would also be forwarded to the remote browser.
            onKeyDown={event => {
              event.stopPropagation()
              if (event.key === 'Enter') submitUrl()
            }}
            placeholder="Type a URL and press Enter"
            spellCheck={false}
            style={{
              flex: 1, minWidth: 0, padding: '7px 10px', borderRadius: 8,
              background: 'var(--glass2)', border: '1px solid var(--stroke2)',
              color: 'var(--text)', fontSize: 13,
            }}
          />
          <IconButton
            title={fit === 'contain' ? `Fit to window (${scalePercent}% — resampled)` : '1:1 with the remote screen'}
            onClick={() => setFit(current => (current === 'contain' ? 'actual' : 'contain'))}
          >
            {fit === 'contain' ? 'fit' : '1:1'}
          </IconButton>
        </div>
      )}

      {/* Scale readout. Anything other than 100% means the image is resampled and
          text looks soft — worth saying, because the instinct is to blame the
          bitrate. Only shown when it is actually true. */}
      {!waitingForFrames && scalePercent !== 100 && visible && (
        <div style={{
          position: 'absolute', bottom: 'calc(var(--sa-b) + 12px)', left: 'calc(var(--sa-l) + 12px)', zIndex: Z.controlBar,
          padding: '5px 10px', borderRadius: 999, background: 'var(--glass)', border: '1px solid var(--stroke)',
          fontSize: 11.5, fontWeight: 600, color: 'var(--text3)',
        }}>
          {scalePercent}% — not 1:1, text will look soft
        </div>
      )}

      {/* The control to start audio lives in the party's A/V bar with mic and
          camera (see LobbyAVBar in Party.tsx), not here — browsers refuse audible
          autoplay, and the fix belongs next to the other sound controls rather
          than floating over the page on its own. */}

      <ControlBar
        session={session}
        userId={userId}
        isHost={isHost}
        phone={phone}
        isDriver={isDriver}
        driverName={driverName}
        visible={visible}
      />
    </div>
  )
}

/**
 * Who is driving, and how to change that.
 *
 * Phones get a sentence rather than a button: control is desktop-only, and an
 * affordance that does nothing is worse than none.
 */
function ControlBar({
  session, userId, isHost, phone, isDriver, driverName, visible,
}: {
  session: PartySession
  userId?: string
  isHost: boolean
  phone: boolean
  isDriver: boolean
  driverName: string
  visible: boolean
}) {
  const party = useParty()
  const browser = session.browser
  if (!browser) return null
  const requests = browser.requests ?? []
  const hasRequested = requests.some(request => request.userId === userId)

  return (
    // Right-aligned and lifted clear of the party's centred A/V bar, which sits
    // at the bottom of this same stage.
    <div style={{
      position: 'absolute', bottom: 'calc(var(--sa-b) + 86px)', right: 'calc(var(--sa-r) + 12px)',
      zIndex: Z.controlBar, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 8,
      opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s',
    }}>
      {/* Host: pending control requests, with the decision attached. */}
      {isHost && requests.length > 0 && (
        <div style={{
          width: 'min(280px, calc(100vw - 24px))', borderRadius: 14, overflow: 'hidden',
          background: 'var(--glass)', border: '1px solid var(--stroke)', boxShadow: 'var(--shadow)',
        }}>
          <div style={{ padding: '9px 13px', borderBottom: '1px solid var(--stroke)', fontSize: 11.5, fontWeight: 700, letterSpacing: '.06em', textTransform: 'uppercase', color: 'var(--text2)' }}>
            Wants to drive · {requests.length}
          </div>
          {requests.map(request => (
            <div key={request.userId} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 10px' }}>
              <span style={{ flex: 1, fontSize: 13, fontWeight: 600, color: 'var(--text)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{request.name}</span>
              <button onClick={() => party.denyBrowserControl(request.userId)} title="Decline" style={smallButton('var(--red)')}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4"><path d="M18 6 6 18M6 6l12 12" /></svg>
              </button>
              <button onClick={() => party.grantBrowserControl(request.userId)} title="Give control" style={{ ...smallButton('var(--on-accent)'), background: 'var(--accent)' }}>
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.8"><path d="M20 6 9 17l-5-5" /></svg>
              </button>
            </div>
          ))}
        </div>
      )}

      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px 6px 12px', borderRadius: 999,
        background: 'var(--glass)', border: '1px solid var(--stroke)', boxShadow: 'var(--shadow)',
      }}>
        <span style={{ fontSize: 12, color: 'var(--text3)' }}>
          {isDriver ? 'You are driving' : `${driverName} is driving`}
        </span>

        {phone
          // Deliberate: phones are view-only. Say so instead of offering a
          // button that cannot work.
          ? <span style={{ fontSize: 11.5, color: 'var(--text3)', opacity: .8 }}>· control needs a computer</span>
          : (
            <>
              {!isDriver && !isHost && (
                <PlainButton disabled={hasRequested} onClick={() => party.requestBrowserControl()}>
                  {hasRequested ? 'Asked…' : 'Ask to drive'}
                </PlainButton>
              )}
              {isHost && !isDriver && (
                <PlainButton onClick={() => party.reclaimBrowserControl()}>Take control</PlainButton>
              )}
            </>
          )}

        {isHost && (
          <PlainButton danger onClick={() => party.stopSharedBrowser()}>Close browser</PlainButton>
        )}
      </div>
    </div>
  )
}

/* ── small shared bits ───────────────────────────────────────────────────── */

function smallButton(color: string): CSSProperties {
  return {
    width: 30, height: 30, borderRadius: 8, border: 'none', background: 'var(--glass2)',
    color, display: 'grid', placeItems: 'center', cursor: 'pointer', flexShrink: 0,
  }
}

function IconButton({ title, onClick, children }: { title: string; onClick: () => void; children: ReactNode }) {
  return (
    <button onClick={event => { event.stopPropagation(); onClick() }} title={title} style={{
      minWidth: 32, height: 32, padding: '0 9px', borderRadius: 8, cursor: 'pointer',
      background: 'var(--glass2)', border: '1px solid var(--stroke2)', color: 'var(--text2)',
      fontSize: 13, fontWeight: 600, flexShrink: 0,
    }}>{children}</button>
  )
}

function PlainButton({ onClick, children, danger = false, disabled = false }: {
  onClick: () => void
  children: ReactNode
  danger?: boolean
  disabled?: boolean
}) {
  return (
    <button onClick={event => { event.stopPropagation(); onClick() }} disabled={disabled} style={{
      padding: '6px 12px', borderRadius: 999, cursor: disabled ? 'default' : 'pointer',
      background: 'var(--glass2)', border: '1px solid var(--stroke2)',
      color: danger ? 'var(--red)' : 'var(--text)', fontSize: 12.5, fontWeight: 600,
      opacity: disabled ? .55 : 1, flexShrink: 0,
    }}>{children}</button>
  )
}

function PrimaryButton({ onClick, children }: { onClick: () => void; children: ReactNode }) {
  return (
    <button onClick={event => { event.stopPropagation(); onClick() }} style={{
      padding: '10px 20px', borderRadius: 10, border: 'none', cursor: 'pointer',
      background: 'var(--accent)', color: 'var(--on-accent)', fontSize: 13.5, fontWeight: 700,
    }}>{children}</button>
  )
}

function Centered({ children }: { children: ReactNode }) {
  return (
    <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', background: '#000', padding: 24 }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>{children}</div>
    </div>
  )
}

function Message({ title, body }: { title: string; body: string }) {
  return (
    <div style={{ maxWidth: 380, textAlign: 'center' }}>
      <div style={{ fontSize: 19, fontWeight: 800, letterSpacing: '-.02em', marginBottom: 8, color: 'var(--text)' }}>{title}</div>
      <p style={{ fontSize: 13.5, color: 'var(--text2)', lineHeight: 1.55, margin: 0 }}>{body}</p>
    </div>
  )
}
