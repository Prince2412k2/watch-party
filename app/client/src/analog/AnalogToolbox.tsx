import { useEffect, useRef, useState, type FormEvent, type ReactNode } from 'react'
import QRCode from 'qrcode'
import Avatar from '../components/Avatar.tsx'
import { useParty } from '../context/PartyContext.tsx'
import { useMemberAvatar } from '../hooks/useMemberAvatar.ts'
import type { AvatarConfig } from '../lib/avatar.ts'
import type { PartyUser } from '../types.ts'
import { AnIcon, type AnIconName } from './icons.tsx'
import { cueEnabled, setCueEnabled } from './cue.ts'

/**
 * A corner control that expands into an inline toolbox — never a dashboard,
 * never a permanent sidebar.
 *
 * Profile takes the upper-right corner and Watch Party the lower-right. The
 * expanded panel is width- and height-capped and the lower-right one is offset
 * by the measured nav height (see AnalogStage), so neither covers the shelf that
 * owns focus nor competes with the bottom modes.
 */

export interface AnalogToolboxProps {
  corner: 'top-right' | 'bottom-right'
  label: string
  icon: AnIconName
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Renders the control as a live room rather than an idle action. */
  live?: boolean
  badge?: number
  showLabel?: boolean
  children: ReactNode
}

export function AnalogToolbox({
  corner,
  label,
  icon,
  open,
  onOpenChange,
  live = false,
  badge = 0,
  showLabel = true,
  children,
}: AnalogToolboxProps) {
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onPointerDown = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) onOpenChange(false)
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onOpenChange(false)
    }
    document.addEventListener('pointerdown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [open, onOpenChange])

  return (
    <div className="an-toolbox" data-corner={corner} ref={rootRef}>
      {open ? (
        <div className="an-toolbox-panel" role="dialog" aria-label={label}>
          {children}
        </div>
      ) : null}
      <button
        type="button"
        className={`an-toolbox-button${live ? ' is-live' : ''}`}
        aria-expanded={open}
        aria-label={label}
        onClick={() => onOpenChange(!open)}
      >
        {live ? <span className="an-live-dot" aria-hidden /> : <AnIcon name={icon} size={16} />}
        {showLabel ? <span>{label}</span> : null}
        {badge > 0 ? <span className="an-nav-badge is-alert">{badge}</span> : null}
      </button>
    </div>
  )
}

// ── profile ─────────────────────────────────────────────────────────────────

export interface AnalogProfileToolboxProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  userId?: string
  name?: string
  avatar?: AvatarConfig | null
  onEditProfile: () => void
  onSignOut: () => void
}

export function AnalogProfileToolbox({
  open,
  onOpenChange,
  userId,
  name,
  avatar,
  onEditProfile,
  onSignOut,
}: AnalogProfileToolboxProps) {
  // "Optional subtle interface sound … always user-controllable." The detent
  // cue's only switch lives here.
  const [sound, setSound] = useState(cueEnabled)

  return (
    <AnalogToolbox corner="top-right" label="Profile" icon="user" open={open} onOpenChange={onOpenChange} showLabel={false}>
      <small>Signed in as</small>
      <h2>{name || 'Profile'}</h2>
      <div className="an-toolbox-row" style={{ marginTop: 12 }}>
        {userId ? <Avatar userId={userId} name={name} config={avatar} size={30} circle /> : null}
        <span>{name || 'Profile'}</span>
      </div>
      <button
        type="button"
        className="an-toolbox-action"
        onClick={() => {
          setCueEnabled(!sound)
          setSound(!sound)
        }}
        aria-pressed={sound}
      >
        <AnIcon name={sound ? 'sound' : 'mute'} size={16} />
        Interface sound
        <small className="an-host-tag">{sound ? 'ON' : 'OFF'}</small>
      </button>
      <button type="button" className="an-toolbox-action" onClick={onEditProfile}>
        <AnIcon name="user" size={16} />
        Edit profile
      </button>
      <button type="button" className="an-toolbox-action" onClick={onSignOut}>
        <AnIcon name="logout" size={16} />
        Sign out
      </button>
    </AnalogToolbox>
  )
}

// ── watch party ─────────────────────────────────────────────────────────────

function PartyPerson({ user, host }: { user: PartyUser; host?: boolean }) {
  const avatar = useMemberAvatar(user.userId)
  return (
    <div className="an-toolbox-row">
      <Avatar userId={user.userId} name={user.name} config={avatar} size={24} circle />
      <span>{user.name}</span>
      {host ? <small>Host</small> : null}
    </div>
  )
}

function PartyQr({ url }: { url: string }) {
  const [src, setSrc] = useState('')
  useEffect(() => {
    let active = true
    QRCode.toDataURL(url, { width: 132, margin: 1 }).then((image) => {
      if (active) setSrc(image)
    })
    return () => {
      active = false
    }
  }, [url])
  return (
    <div className="an-toolbox-qr">
      {src ? <img src={src} width="132" height="132" alt="Party invite QR code" /> : null}
    </div>
  )
}

export interface AnalogPartyToolboxProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function AnalogPartyToolbox({ open, onOpenChange }: AnalogPartyToolboxProps) {
  const {
    session,
    role,
    createRoom,
    joinParty,
    leaveParty,
    endParty,
    approveUser,
    rejectUser,
    startSharedBrowser,
    stopSharedBrowser,
  } = useParty()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [code, setCode] = useState('')
  const [joining, setJoining] = useState(false)
  const [showQr, setShowQr] = useState(false)
  const [copied, setCopied] = useState(false)

  const isHost = role === 'host'
  const waiting = session?.waiting ?? []
  const guests = session?.guests ?? []

  async function create() {
    if (session || busy) return
    setBusy(true)
    setError('')
    try {
      await createRoom()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not start party')
    } finally {
      setBusy(false)
    }
  }

  async function join(event: FormEvent) {
    event.preventDefault()
    const partyId = code.trim().toUpperCase()
    if (!/^[0-9A-F]{8}$/.test(partyId)) {
      setError('Enter the 8-character party code')
      return
    }
    setBusy(true)
    setError('')
    try {
      await joinParty(partyId)
      setJoining(false)
      setCode('')
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not join party')
    } finally {
      setBusy(false)
    }
  }

  const inviteUrl = session ? `${window.location.origin}/party/${session.id}` : ''
  const canOpenBrowser = isHost && session?.browserAvailable === true && session.stage !== 'browser'

  return (
    <AnalogToolbox
      corner="bottom-right"
      label={session ? `${1 + guests.length} in party` : 'Watch party'}
      icon="users"
      open={open}
      onOpenChange={onOpenChange}
      live={session != null}
      badge={isHost ? waiting.length : 0}
    >
      {!session ? (
        <>
          <small>Watch together</small>
          <h2>Start a watch party</h2>
          <p>Invite friends, browse together, and keep every screen in sync.</p>
          {joining ? (
            <form onSubmit={join}>
              <label className="an-toolbox-row" htmlFor="an-party-code">
                Party code
              </label>
              <input
                id="an-party-code"
                className="an-toolbox-code"
                autoFocus
                value={code}
                maxLength={8}
                placeholder="A1B2C3D4"
                onChange={(event) => {
                  setCode(event.target.value)
                  setError('')
                }}
              />
              <button type="submit" className="an-toolbox-action is-primary" disabled={busy}>
                <AnIcon name="enter" size={16} />
                {busy ? 'Joining…' : 'Join party'}
              </button>
              <button type="button" className="an-toolbox-action" onClick={() => setJoining(false)}>
                <AnIcon name="x" size={16} />
                Cancel
              </button>
            </form>
          ) : (
            <>
              <button type="button" className="an-toolbox-action is-primary" onClick={create} disabled={busy}>
                <AnIcon name="plus" size={16} />
                {busy ? 'Starting…' : 'Create a party'}
              </button>
              <button type="button" className="an-toolbox-action" onClick={() => setJoining(true)}>
                <AnIcon name="enter" size={16} />
                Join with a code
              </button>
            </>
          )}
        </>
      ) : (
        <>
          <small>Live room</small>
          <h2>Watch party</h2>
          <div className="an-toolbox-code">
            {session.id}
            <button
              type="button"
              className="an-toolbox-action"
              style={{ width: 'auto', marginTop: 0, marginLeft: 'auto' }}
              onClick={() => {
                navigator.clipboard.writeText(inviteUrl).then(() => {
                  setCopied(true)
                  window.setTimeout(() => setCopied(false), 1400)
                })
              }}
            >
              <AnIcon name={copied ? 'check' : 'copy'} size={15} />
              {copied ? 'Copied' : 'Copy'}
            </button>
          </div>

          <div className="an-toolbox-rows">
            <PartyPerson host user={{ userId: session.hostId, name: session.hostName || 'Host' }} />
            {guests.map((guest) => (
              <PartyPerson key={guest.userId} user={guest} />
            ))}
          </div>

          {isHost && waiting.length > 0 ? (
            <div className="an-toolbox-rows">
              {waiting.map((person) => (
                <div className="an-toolbox-row" key={person.userId}>
                  <span>{person.name}</span>
                  <button
                    type="button"
                    className="an-toolbox-action is-host-only"
                    style={{ width: 'auto', marginTop: 0, marginLeft: 'auto' }}
                    onClick={() => rejectUser(person.userId)}
                    aria-label={`Reject ${person.name}`}
                  >
                    <AnIcon name="x" size={14} />
                  </button>
                  <button
                    type="button"
                    className="an-toolbox-action is-host-only"
                    style={{ width: 'auto', marginTop: 0 }}
                    onClick={() => approveUser(person.userId)}
                    aria-label={`Accept ${person.name}`}
                  >
                    <AnIcon name="check" size={14} />
                  </button>
                </div>
              ))}
            </div>
          ) : null}

          <button type="button" className="an-toolbox-action" onClick={() => setShowQr((value) => !value)} aria-pressed={showQr}>
            <AnIcon name="qr" size={16} />
            {showQr ? 'Hide QR code' : 'Show QR code'}
          </button>
          {showQr ? <PartyQr url={inviteUrl} /> : null}

          {/* Host-only actions carry a dashed edge AND a HOST tag — visibly
              distinct from what every participant can reach. */}
          {canOpenBrowser ? (
            <button
              type="button"
              className="an-toolbox-action is-host-only"
              onClick={() => {
                onOpenChange(false)
                void startSharedBrowser()
              }}
            >
              <AnIcon name="globe" size={16} />
              Start browser
              <span className="an-host-tag">HOST</span>
            </button>
          ) : null}
          {isHost && session.stage === 'browser' ? (
            <button
              type="button"
              className="an-toolbox-action is-host-only"
              onClick={() => {
                onOpenChange(false)
                stopSharedBrowser()
              }}
            >
              <AnIcon name="x" size={16} />
              Close browser
              <span className="an-host-tag">HOST</span>
            </button>
          ) : null}

          {isHost ? (
            <button
              type="button"
              className="an-toolbox-action is-danger is-host-only"
              onClick={() => {
                if (window.confirm('End this party for everyone?')) void endParty()
              }}
            >
              <AnIcon name="x" size={16} />
              End party
              <span className="an-host-tag">HOST</span>
            </button>
          ) : (
            <button type="button" className="an-toolbox-action is-danger" onClick={() => leaveParty()}>
              <AnIcon name="logout" size={16} />
              Leave party
            </button>
          )}
        </>
      )}
      {error ? (
        <div className="an-toolbox-error" role="alert">
          {error}
        </div>
      ) : null}
    </AnalogToolbox>
  )
}
