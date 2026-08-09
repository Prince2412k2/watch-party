// The lower-right watch-party control.
//
// "Watch Party is a compact control in the lower-right corner. Activating it
// also expands an inline toolbox. The expanded surface must not cover primary
// content or compete with the bottom navigation. […] Outside a party, the
// toolbox offers Create and Join. Once connected, it changes to room controls
// with End/Leave, Start Browser, and Show QR Code. Host-only actions must be
// visibly distinct from controls available to every participant."
//
// It expands in place into a rail of icon buttons, with one sheet underneath
// for whichever toggle is on — the QR, the roster, or the code field. There is
// no heading, no description and no button text: `cornerWidgets.ts` decides
// which controls exist and what each one is called, and this file only draws
// them and wires them to PartyContext.
//
// The room's own id is the single piece of writing on the surface, and only
// while the QR is showing. It is not a label for a control; it is the thing
// people read to each other, and the QR beside it is the same string in a form
// a phone camera can take.

import { useEffect, useReducer, useRef, useState, type FormEvent } from 'react'
import QRCode from 'qrcode'
import Avatar from '../components/Avatar.tsx'
import { useParty } from '../context/PartyContext.tsx'
import { useMemberAvatar } from '../hooks/useMemberAvatar.ts'
import { analogTokens } from '../design/analogTokens.ts'
import { AnIcon, AnIconButton } from './icons.tsx'
import {
  closedWidget,
  inviteUrl,
  isJoinCode,
  normalizeJoinCode,
  partyWidgetView,
  widgetNext,
  type IconControl,
  type RosterEntry,
} from './cornerWidgets.ts'

const WIDGET_ID = 'an-party-widget'
const COPIED_MS = 1400
const QR_PX = 116

/** Client-side, so an invite still appears on a connection that cannot fetch. */
function PartyQr({ url }: { url: string }) {
  const [svg, setSvg] = useState('')
  useEffect(() => {
    let live = true
    QRCode.toString(url, {
      type: 'svg',
      margin: 0,
      width: QR_PX,
      color: { dark: analogTokens.color.stageGround, light: analogTokens.color.ink },
    })
      .then((markup) => {
        if (live) setSvg(markup)
      })
      .catch(() => {
        if (live) setSvg('')
      })
    return () => {
      live = false
    }
  }, [url])

  return (
    <div className="an-widget-qr" style={{ width: QR_PX, height: QR_PX }}>
      {svg ? <div aria-hidden dangerouslySetInnerHTML={{ __html: svg }} /> : null}
    </div>
  )
}

function RosterRow({ entry, onAction }: { entry: RosterEntry; onAction: (control: IconControl) => void }) {
  const avatar = useMemberAvatar(entry.userId)
  const who = entry.waiting
    ? `${entry.name}, waiting to join`
    : entry.host
      ? `${entry.name}, host`
      : entry.name

  return (
    <div className="an-roster-row" data-waiting={entry.waiting ? 'true' : undefined}>
      <span
        className="an-roster-avatar"
        data-host={entry.host ? 'true' : undefined}
        role="img"
        aria-label={who}
        title={who}
      >
        <Avatar userId={entry.userId} name={entry.name} config={avatar} size={26} circle />
      </span>
      {entry.actions.map((action) => (
        <AnIconButton key={action.id} control={action} onPress={() => onAction(action)} size={14} />
      ))}
    </div>
  )
}

export function AnalogPartyWidget() {
  const {
    session,
    role,
    createRoom,
    joinParty,
    leaveParty,
    endParty,
    approveUser,
    rejectUser,
    kickUser,
    transferHost,
    setCollaborative,
  } = useParty()

  const [widget, dispatch] = useReducer(widgetNext, closedWidget)
  const [joining, setJoining] = useState(false)
  const [code, setCode] = useState('')
  const [showQr, setShowQr] = useState(false)
  const [showRoster, setShowRoster] = useState(false)
  const [copied, setCopied] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const rootRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)

  const view = partyWidgetView({ session, role, joining, showQr, showRoster, copied, busy })
  const invite = session ? inviteUrl(window.location.origin, session.id) : ''
  const pending = view.alerts

  useEffect(() => {
    if (!widget.open) return
    const onPointerDown = (event: PointerEvent) => {
      dispatch({ type: rootRef.current?.contains(event.target as Node) ? 'pointerInside' : 'pointerOutside' })
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') dispatch({ type: 'escape' })
    }
    document.addEventListener('pointerdown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [widget.open])

  useEffect(() => {
    if (!widget.open && widget.returnFocus) triggerRef.current?.focus()
  }, [widget])

  // Someone knocking is the one thing that opens this widget by itself — and it
  // opens the roster with it, because the badge alone would leave the host a
  // count with nothing to press.
  useEffect(() => {
    if (pending > 0) {
      dispatch({ type: 'open' })
      setShowRoster(true)
    }
  }, [pending])

  // Leaving or being removed from a room must not leave the previous room's
  // sheets showing over an idle widget.
  useEffect(() => {
    if (session) return
    setShowQr(false)
    setShowRoster(false)
    setCopied(false)
  }, [session?.id])

  async function create() {
    if (session || busy) return
    setBusy(true)
    setError('')
    try {
      await createRoom()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not start the party')
    } finally {
      setBusy(false)
    }
  }

  async function join() {
    if (busy) return
    if (!isJoinCode(code)) {
      setError('That is not an 8-character party code')
      return
    }
    setBusy(true)
    setError('')
    try {
      await joinParty(normalizeJoinCode(code))
      setJoining(false)
      setCode('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not join that party')
    } finally {
      setBusy(false)
    }
  }

  function copyInvite() {
    navigator.clipboard.writeText(invite).then(
      () => {
        setCopied(true)
        window.setTimeout(() => setCopied(false), COPIED_MS)
      },
      () => setError('Could not copy the invite link'),
    )
  }

  function run(control: IconControl) {
    const [action, targetUserId] = control.id.split(':')
    // Everything that answers inside the widget is sticky; everything that
    // takes you somewhere else closes it on the way.
    switch (action) {
      case 'create':
        dispatch({ type: 'action', sticky: true })
        void create()
        return
      case 'join':
        dispatch({ type: 'action', sticky: true })
        setError('')
        setJoining(true)
        return
      case 'joinCancel':
        dispatch({ type: 'action', sticky: true })
        setJoining(false)
        setCode('')
        setError('')
        return
      case 'joinSubmit':
        dispatch({ type: 'action', sticky: true })
        void join()
        return
      case 'qr':
        dispatch({ type: 'action', sticky: true })
        setShowQr((value) => !value)
        return
      case 'copy':
        dispatch({ type: 'action', sticky: true })
        copyInvite()
        return
      case 'roster':
        dispatch({ type: 'action', sticky: true })
        setShowRoster((value) => !value)
        return
      case 'collaborative':
        dispatch({ type: 'action', sticky: true })
        setCollaborative(session?.collaborativeControl !== true)
        return
      case 'end':
        if (!window.confirm('End this party for everyone?')) return
        dispatch({ type: 'action' })
        void endParty()
        return
      case 'leave':
        dispatch({ type: 'action' })
        leaveParty()
        return
      case 'approve':
        dispatch({ type: 'action', sticky: true })
        approveUser(targetUserId)
        return
      case 'reject':
        dispatch({ type: 'action', sticky: true })
        rejectUser(targetUserId)
        return
      case 'promote':
        dispatch({ type: 'action', sticky: true })
        transferHost(targetUserId)
        return
      case 'kick':
        dispatch({ type: 'action', sticky: true })
        kickUser(targetUserId)
        return
    }
  }

  function submitCode(event: FormEvent) {
    event.preventDefault()
    void join()
  }

  return (
    <div className="an-corner" data-corner="bottom-right" ref={rootRef}>
      <button
        ref={triggerRef}
        type="button"
        className={`an-corner-trigger${view.live ? ' is-live' : ''}`}
        aria-label={view.triggerLabel}
        aria-expanded={widget.open}
        aria-controls={WIDGET_ID}
        onClick={() => dispatch({ type: 'toggle' })}
      >
        <AnIcon name="users" size={16} />
        {pending > 0 ? <span className="an-corner-badge">{pending}</span> : null}
      </button>

      {widget.open ? (
        <div className="an-widget" id={WIDGET_ID} role="group" aria-label="Watch party controls">
          <div className="an-widget-rail">
            {view.controls.map((control) => (
              <AnIconButton key={control.id} control={control} onPress={() => run(control)} />
            ))}
          </div>

          {view.mode === 'joining' ? (
            <form className="an-widget-sheet" onSubmit={submitCode}>
              {/* Implicit submission: Enter in the only field here runs the same
                  join the rail's button does, so the code can be typed and
                  entered without reaching for the mouse. */}
              <input
                className="an-widget-code"
                aria-label="Party code or invite link"
                placeholder="A1B2C3D4"
                autoFocus
                autoCapitalize="characters"
                autoCorrect="off"
                spellCheck={false}
                maxLength={64}
                value={code}
                onChange={(event) => {
                  setCode(event.target.value)
                  setError('')
                }}
              />
            </form>
          ) : null}

          {showQr && session ? (
            <div className="an-widget-sheet">
              <PartyQr url={invite} />
              <span className="an-widget-id">{session.id}</span>
            </div>
          ) : null}

          {showRoster && view.roster.length > 0 ? (
            <div className="an-widget-sheet">
              <div className="an-roster">
                {view.roster.map((entry) => (
                  <RosterRow key={entry.userId} entry={entry} onAction={run} />
                ))}
              </div>
            </div>
          ) : null}

          {error ? (
            <p className="an-corner-error" role="alert">
              {error}
            </p>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}
