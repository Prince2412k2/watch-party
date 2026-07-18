import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import QRCode from 'qrcode'
import { useParty } from '../context/PartyContext'
import { navigate } from '../router'
import type { PartyUser } from '../types'

type WebTab = 'movies' | 'series' | 'discover' | 'downloads'
type Theme = 'light' | 'dark' | 'balanced'

type IconName = 'film' | 'tv' | 'compass' | 'download' | 'users' | 'plus' | 'enter' | 'logout' | 'x' | 'check' | 'copy' | 'play' | 'sun' | 'moon' | 'blend'

const paths: Record<IconName, string> = {
  film: 'M4 4h16v16H4zM4 8h16M4 16h16M8 4v16M16 4v16',
  tv: 'M3 6h18v12H3zM8 21h8M12 18v3',
  compass: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM16.2 7.8l-2.9 6.5-6.5 2.9 2.9-6.5z',
  download: 'M12 3v12m0 0 4-4m-4 4-4-4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2',
  users: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm13 10v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
  plus: 'M12 5v14M5 12h14',
  enter: 'M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M3 12h12m0 0-4-4m4 4-4 4',
  logout: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
  x: 'M18 6 6 18M6 6l12 12',
  check: 'M20 6 9 17l-5-5',
  copy: 'M8 8h11v11H8zM5 16H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h11a1 1 0 0 1 1 1v1',
  play: 'M8 5v14l11-7z',
  sun: 'M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z',
  moon: 'M20 15.3A8.5 8.5 0 0 1 8.7 4 8.5 8.5 0 1 0 20 15.3z',
  blend: 'M12 3a9 9 0 1 0 0 18V3zm0 0a9 9 0 0 1 0 18',
}

const tabs: Array<{ id: WebTab; label: string; href: string; icon: IconName }> = [
  { id: 'movies', label: 'Movies', href: '/movies', icon: 'film' },
  { id: 'series', label: 'Shows', href: '/series', icon: 'tv' },
  { id: 'discover', label: 'Discover', href: '/discover', icon: 'compass' },
  { id: 'downloads', label: 'Downloads', href: '/downloads', icon: 'download' },
]

function Icon({ name, size = 19, fill = 'none' }: { name: IconName; size?: number; fill?: string }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d={paths[name]} /></svg>
}

function initials(name = '') {
  return name.split(/\s+/).map(word => word[0]).join('').toUpperCase().slice(0, 2) || '?'
}

function ThemeSwitch({ theme, onChange }: { theme: Theme; onChange: (theme: Theme) => void }) {
  const options: Array<{ id: Theme; label: string; icon: IconName }> = [
    { id: 'light', label: 'Light mode', icon: 'sun' },
    { id: 'balanced', label: 'Balanced mode', icon: 'blend' },
    { id: 'dark', label: 'Dark mode', icon: 'moon' },
  ]
  return (
    <div className="web-theme-switch" aria-label="Appearance">
      {options.map(option => (
        <button key={option.id} className={theme === option.id ? 'is-active' : ''} onClick={() => onChange(option.id)} aria-label={option.label} title={option.label}>
          <Icon name={option.icon} size={16} />
        </button>
      ))}
    </div>
  )
}

function ProfileMenu({ profileInitials, profileName, logout, theme, onThemeChange }: { profileInitials?: string; profileName?: string; logout?: () => void | Promise<void>; theme: Theme; onThemeChange: (theme: Theme) => void }) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const close = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false)
    }
    document.addEventListener('pointerdown', close)
    return () => document.removeEventListener('pointerdown', close)
  }, [open])

  return (
    <div className="web-profile" ref={rootRef}>
      <button className="web-avatar" onClick={() => setOpen(value => !value)} aria-label="Open profile menu" aria-expanded={open}>{profileInitials || '?'}</button>
      {open ? (
        <div className="web-profile-menu">
          <div><span>Signed in as</span><strong>{profileName || 'Profile'}</strong></div>
          <ThemeSwitch theme={theme} onChange={onThemeChange} />
          <button onClick={() => logout?.()}><Icon name="logout" size={16} />Sign out</button>
        </div>
      ) : null}
    </div>
  )
}

function PartyQr({ url }: { url: string }) {
  const [src, setSrc] = useState('')
  useEffect(() => {
    let active = true
    QRCode.toDataURL(url, { width: 112, margin: 1 }).then(image => { if (active) setSrc(image) })
    return () => { active = false }
  }, [url])
  return src ? <img src={src} width="112" height="112" alt="Party invite QR code" /> : <div className="party-qr-placeholder" />
}

function Person({ user, host, actions }: { user: PartyUser; host?: boolean; actions?: ReactNode }) {
  return (
    <div className="party-person">
      <span className="party-person-avatar">{initials(user.name)}</span>
      <span>{user.name}</span>
      {host ? <small>Host</small> : null}
      {actions}
    </div>
  )
}

function WebPartyWidget({ open = true, onClose, onStartParty, onJoinParty, starting = false }: {
  open?: boolean
  onClose?: () => void
  onStartParty?: () => void
  onJoinParty?: () => void
  starting?: boolean
} = {}) {
  const { session, role, approveUser, rejectUser, kickUser, endParty } = useParty()
  const [copied, setCopied] = useState(false)
  if (!open) return null

  if (!session) {
    return (
      <div className="party-card party-card-empty" role="dialog" aria-label="Watch party options">
        <div className="party-card-header"><div><small>WATCH TOGETHER</small><h2>Start a watch party</h2></div><button className="party-icon-button" onClick={onClose} aria-label="Close"><Icon name="x" size={18} /></button></div>
        <p>Invite friends, browse together, and keep every screen in sync.</p>
        <button className="party-primary-action" onClick={onStartParty} disabled={starting}><Icon name="plus" size={18} />{starting ? 'Starting…' : 'Start a party'}</button>
        <button className="party-secondary-action" onClick={onJoinParty}><Icon name="enter" size={18} />Join with a code</button>
      </div>
    )
  }

  const isHost = role === 'host'
  const guests = session.guests ?? []
  const waiting = session.waiting ?? []
  const joinUrl = `${window.location.origin}/party/${session.id}`

  function copyLink() {
    navigator.clipboard.writeText(joinUrl).then(() => {
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1400)
    })
  }

  return (
    <aside className="party-card" aria-label="Watch party">
      <div className="party-card-header"><div><small>LIVE ROOM</small><h2>Watch party</h2></div><button className="party-icon-button" onClick={onClose} aria-label="Close"><Icon name="x" size={18} /></button></div>
      <div className="party-invite">
        <PartyQr url={joinUrl} />
        <div><span>ROOM CODE</span><strong>{session.id}</strong><button onClick={copyLink}><Icon name={copied ? 'check' : 'copy'} size={15} />{copied ? 'Copied' : 'Copy invite'}</button></div>
      </div>
      <div className="party-people">
        <Person host user={{ userId: session.hostId, name: session.hostName || 'Host' }} />
        {guests.map(guest => <Person key={guest.userId} user={guest} actions={isHost ? <button className="party-person-action" onClick={() => kickUser(guest.userId)} aria-label={`Remove ${guest.name}`}><Icon name="x" size={14} /></button> : undefined} />)}
      </div>
      {isHost && waiting.length ? <div className="party-waiting"><strong>Waiting to join</strong>{waiting.map(person => <Person key={person.userId} user={person} actions={<div className="party-person-actions"><button onClick={() => rejectUser(person.userId)} aria-label={`Reject ${person.name}`}><Icon name="x" size={14} /></button><button onClick={() => approveUser(person.userId)} aria-label={`Accept ${person.name}`}><Icon name="check" size={14} /></button></div>} />)}</div> : null}
      {isHost ? <button className="party-end" onClick={() => { if (window.confirm('End this party for everyone?')) void endParty() }}>End party</button> : null}
    </aside>
  )
}

function JoinDialog({ onClose, onJoin }: { onClose: () => void; onJoin: (code: string) => Promise<unknown> }) {
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [joining, setJoining] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => { inputRef.current?.focus() }, [])

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    const partyId = code.trim().toUpperCase()
    if (!/^[0-9A-F]{8}$/.test(partyId)) {
      setError('Enter the 8-character party code')
      return
    }
    setJoining(true)
    setError('')
    try {
      await onJoin(partyId)
      onClose()
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Could not join party')
    } finally {
      setJoining(false)
    }
  }

  return (
    <div className="web-dialog-scrim" onClick={onClose}>
      <form className="web-dialog" onSubmit={submit} onClick={event => event.stopPropagation()}>
        <div className="party-card-header"><div><small>ROOM CODE</small><h2>Join a party</h2></div><button type="button" className="party-icon-button" onClick={onClose} aria-label="Close"><Icon name="x" size={18} /></button></div>
        <label htmlFor="party-code">Party code</label>
        <input id="party-code" ref={inputRef} value={code} maxLength={8} placeholder="A1B2C3D4" onChange={event => { setCode(event.target.value); setError('') }} />
        {error ? <div className="web-dialog-error" role="alert">{error}</div> : null}
        <button className="party-primary-action" type="submit" disabled={joining}>{joining ? 'Joining…' : 'Join party'}</button>
      </form>
    </div>
  )
}

export function WebShell({ children, active, initials: profileInitials, profileName, logout }: {
  children: ReactNode
  active?: WebTab
  initials?: string
  profileName?: string
  logout?: () => void | Promise<void>
}) {
  const { session, role, createRoom, joinParty, shareView } = useParty()
  const [theme, setTheme] = useState<Theme>(() => {
    const saved = localStorage.getItem('watchparty-theme')
    return saved === 'light' || saved === 'dark' || saved === 'balanced' ? saved : 'light'
  })
  const [partyOpen, setPartyOpen] = useState(false)
  const [joinOpen, setJoinOpen] = useState(false)
  const [starting, setStarting] = useState(false)
  const [startError, setStartError] = useState('')
  const partyRef = useRef<HTMLDivElement>(null)
  const waitingCount = session?.waiting?.length ?? 0

  useEffect(() => {
    localStorage.setItem('watchparty-theme', theme)
  }, [theme])

  useEffect(() => {
    if (role === 'host' && waitingCount > 0) setPartyOpen(true)
  }, [role, waitingCount])

  useEffect(() => {
    if (!session || role !== 'host' || !active) return
    shareView({ tab: active, screen: 'grid' })
  }, [session?.id, role, active])

  useEffect(() => {
    if (!partyOpen) return
    const close = (event: PointerEvent) => {
      if (!partyRef.current?.contains(event.target as Node)) setPartyOpen(false)
    }
    document.addEventListener('pointerdown', close)
    return () => document.removeEventListener('pointerdown', close)
  }, [partyOpen])

  async function startParty() {
    if (session || starting) return
    setStarting(true)
    setStartError('')
    try {
      await createRoom()
      setPartyOpen(true)
    } catch (reason) {
      setStartError(reason instanceof Error ? reason.message : 'Could not start party')
    } finally {
      setStarting(false)
    }
  }

  return (
    <div className="web-app" data-theme={theme}>
      <div className="web-ambient" aria-hidden />
      <div className="web-stage">
        <ProfileMenu profileInitials={profileInitials} profileName={profileName} logout={logout} theme={theme} onThemeChange={setTheme} />

        <main className="web-main" aria-label={session && role === 'guest' ? 'Shared host view' : undefined} style={{ pointerEvents: session && role === 'guest' ? 'none' : 'auto' }}>{children}</main>

        <nav className="web-bottom-nav" aria-label="Primary">
          {tabs.map(tab => <button key={tab.id} className={active === tab.id ? 'is-active' : ''} aria-current={active === tab.id ? 'page' : undefined} onClick={() => navigate(tab.href)}><Icon name={tab.icon} size={18} /><span>{tab.label}</span></button>)}
        </nav>

        <div className="web-party-float" ref={partyRef}>
          {partyOpen ? <WebPartyWidget open onClose={() => setPartyOpen(false)} onStartParty={startParty} onJoinParty={() => setJoinOpen(true)} starting={starting} /> : null}
          <button className={`web-party-button${session ? ' is-live' : ''}`} onClick={() => setPartyOpen(open => !open)} aria-expanded={partyOpen} aria-label="Watch party">
            <img className="web-party-icon" src="/popcorn.png" alt="" />
            <span>{session ? `${1 + (session.guests?.length ?? 0)} in party` : 'Watch party'}</span>
            {waitingCount > 0 ? <b>{waitingCount}</b> : null}
          </button>
        </div>
      </div>
      {startError ? <div className="web-toast" role="alert">{startError}</div> : null}
      {joinOpen ? <JoinDialog onClose={() => setJoinOpen(false)} onJoin={joinParty} /> : null}
    </div>
  )
}
