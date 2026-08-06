import { useEffect, useState } from 'react'
import { useParty } from '../context/PartyContext.tsx'
import { navigate } from '../router.ts'
import type { PartyUser } from '../types.ts'
import PartyPanel, { MONO } from './PartyPanel.tsx'
import Avatar from './Avatar.tsx'

/**
 * Room chrome: icon-only Host / Leave buttons (flat surfaces), toasts, and a
 * join-request sidebar with accept/reject. `visible` fades the top cluster with
 * the auto-hide layer; the join sidebar stays put (it's a notification), and
 * toasts are never hidden. The party panel itself lives in `PartyPanel`.
 */
export default function RoomControls({
  stage, top = 18, visible = true, phone = false, onOpenChat, chatOpen = false,
  layoutMode, onToggleLayout, hideSelf, onToggleHideSelf,
}: {
  stage?: string
  top?: number
  visible?: boolean
  phone?: boolean
  onOpenChat?: () => void
  chatOpen?: boolean
  layoutMode?: 'float' | 'dock'
  onToggleLayout?: () => void
  hideSelf?: boolean
  onToggleHideSelf?: () => void
} = {}) {
  const { session, role, toasts, approveUser, rejectUser, endParty } = useParty()

  const [open, setOpen] = useState(false)

  useEffect(() => {
    if (phone || !session) return
    const openPartyMenu = (event: globalThis.MouseEvent) => {
      if (event.shiftKey) return
      event.preventDefault()
      setOpen(true)
    }
    window.addEventListener('contextmenu', openPartyMenu)
    return () => window.removeEventListener('contextmenu', openPartyMenu)
  }, [phone, session?.id])

  if (!session) return null
  const currentSession = session

  const isHost = role === 'host'
  const watching = stage === 'watching'
  const waiting = currentSession.waiting ?? []
  const participantCount = 1 + (currentSession.guests?.length ?? 0)

  async function leaveRoom() {
    // Back from a host-owned room is a real teardown, not just browser
    // navigation. Otherwise the app-wide socket remains in the room and guests
    // keep playing because the server never observes a disconnect.
    if (isHost) {
      await endParty()
      return
    }
    if (window.history.length > 1) {
      window.history.back()
      return
    }
    navigate('/library')
  }

  const flatPanel = {
    background: 'var(--glass)',
    border: '1px solid var(--stroke)',
    boxShadow: 'var(--shadow)',
  }
  const iconBtn = (danger = false) => ({
    width: phone ? 44 : 34, height: phone ? 44 : 34, borderRadius: 8, display: 'grid', placeItems: 'center',
    cursor: 'pointer', color: danger ? 'var(--red)' : 'var(--text2)', transition: 'color .15s',
    background: 'transparent', border: 'none', flexShrink: 0,
  })

  return (
    <>
      {/* Toasts */}
      <div style={{ position: 'absolute', top: 18, left: '50%', transform: 'translateX(-50%)', zIndex: 60, display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'center', pointerEvents: 'none' }}>
        {toasts.map(t => (
          <div key={t.id} style={{ ...flatPanel, display: 'flex', alignItems: 'center', gap: 9, padding: '10px 16px', borderRadius: 12, animation: 'in .22s cubic-bezier(.2,0,.1,1)' }}>
            <span style={{ width: 6, height: 6, borderRadius: '50%', flexShrink: 0, background: (t.level === 'success') ? 'var(--green)' : (t.level === 'warning' || t.level === 'error') ? 'var(--red)' : 'var(--text3)' }} />
            <span style={{ fontSize: 13.5, fontWeight: 600, color: 'var(--text)' }}>{t.msg}</span>
          </div>
        ))}
      </div>

      {/* Phone: compact top bar with room code + participant count (top-left,
          clear of the notch via safe-area). Pairs with the top-right cluster. */}
      {phone && watching && (
        <div style={{
          position: 'absolute', top: 'calc(var(--sa-t) + 8px)', left: 'calc(var(--sa-l) + 8px)', zIndex: 40,
          display: 'flex', alignItems: 'center', gap: 8, padding: '7px 8px 7px 13px', borderRadius: 999,
          ...flatPanel, opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s',
        }}>
          <span style={{ fontSize: 11.5, color: 'var(--text3)' }}>Code</span>
          <span style={{ fontFamily: MONO, fontSize: 13, fontWeight: 600, letterSpacing: '.1em', color: 'var(--text)' }}>{session.id}</span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '3px 8px', borderRadius: 999, background: 'var(--glass2)', fontSize: 11.5, fontWeight: 600, color: 'var(--text)' }}>
            <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--text)' }} />{participantCount}
          </span>
        </div>
      )}

      {/* Top-left room controls (fades with auto-hide) */}
      <div style={{ position: 'absolute', top: phone ? 'calc(var(--sa-t) + 58px)' : top, left: phone ? 'calc(var(--sa-l) + 8px)' : 14, zIndex: 40, display: 'flex', alignItems: 'center', gap: phone ? 8 : 4, opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s' }}>
        <button onClick={() => { void leaveRoom() }} title="Back" aria-label="Back" style={iconBtn(true)} onMouseEnter={e => { e.currentTarget.style.color = 'var(--red)' }} onMouseLeave={e => { e.currentTarget.style.color = 'var(--red)' }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="m15 18-6-6 6-6" /><path d="M9 12h12" /></svg>
        </button>
      </div>

      {/* Top-right room cluster: chat + the watch-party menu. Rendered on BOTH
          desktop and phone now. Desktop used to reach this menu only via a right
          click on the player, which nobody could discover; the right-click
          shortcut is still wired above for anyone used to it. */}
      <div style={{
        position: 'absolute',
        top: phone ? 'calc(var(--sa-t) + 8px)' : top,
        right: phone ? 'calc(var(--sa-r) + 8px)' : 14,
        zIndex: 40, display: 'flex', alignItems: 'center', gap: phone ? 8 : 6,
        opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none',
        transform: visible ? 'translateY(0)' : 'translateY(-6px)', transition: 'opacity .25s, transform .25s',
      }}>
        {/* No shared-browser control here. The movie screen is for watching the
            thing you already chose; starting a browser is a "what shall we watch"
            decision and lives in the popcorn widget (WebShell) instead. */}
        {watching && onOpenChat ? (
          <button onClick={(event) => { event.stopPropagation(); onOpenChat() }} title="Chat" aria-label="Chat" style={{ ...iconBtn(), width: phone ? 44 : 38, height: phone ? 44 : 38, color: chatOpen ? 'var(--text)' : 'var(--text2)' }}>
            <svg width={phone ? 19 : 18} height={phone ? 19 : 18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" /></svg>
          </button>
        ) : null}
        <button onClick={(event) => { event.stopPropagation(); setOpen(value => !value) }} title="Watch party" aria-label="Watch party" aria-expanded={open} style={{ position: 'relative', minWidth: phone ? 52 : 38, height: phone ? 52 : 38, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: 0, borderRadius: phone ? 18 : 10, border: phone ? '1px solid rgba(255,255,255,.14)' : 'none', color: phone ? '#f5f4f0' : 'var(--text2)', background: phone ? '#202126' : 'transparent', boxShadow: phone ? '0 15px 38px rgba(0,0,0,.38)' : 'none', cursor: 'pointer' }}>
          <svg width={phone ? 20 : 18} height={phone ? 20 : 18} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" /></svg>
          {waiting.length > 0 ? <span style={{ position: 'absolute', top: -5, right: -5, minWidth: phone ? 20 : 17, height: phone ? 20 : 17, padding: '0 5px', borderRadius: 10, display: 'grid', placeItems: 'center', color: '#fff', background: 'var(--red)', fontSize: 10, fontWeight: 800 }}>{waiting.length}</span> : null}
        </button>
      </div>

      {/* Join-request sidebar (host only) — stays visible; it's a notification */}
      {isHost && waiting.length > 0 && (
        <div style={{ ...flatPanel, position: 'absolute', top: phone ? 'calc(var(--sa-t) + 60px)' : top + 54, right: phone ? 'calc(var(--sa-r) + 8px)' : 12, zIndex: 41, width: 'min(268px, calc(100vw - 24px))', borderRadius: 16, overflow: 'hidden', animation: 'up .25s cubic-bezier(.2,0,.1,1)' }}>
          <div style={{ padding: '11px 15px', borderBottom: '1px solid var(--stroke)', fontSize: 12, fontWeight: 700, letterSpacing: '.06em', textTransform: 'uppercase', color: 'var(--text2)' }}>
            Wants to join · {waiting.length}
          </div>
          {waiting.map((w: PartyUser) => (
            <div key={w.userId} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px' }}>
              {/* The requester's profile is already on their waiting-list entry,
                  so their face costs nothing extra here. */}
              <Avatar userId={w.userId} name={w.name} config={w.avatar} size={32} circle style={{ border: '1px solid var(--stroke2)' }} />
              <span style={{ flex: 1, fontSize: 13.5, fontWeight: 600, color: 'var(--text)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{w.name}</span>
              <button onClick={() => rejectUser(w.userId)} title="Reject" style={{ width: 32, height: 32, borderRadius: 9, border: 'none', background: 'var(--glass2)', color: 'var(--red)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4"><path d="M18 6 6 18M6 6l12 12" /></svg>
              </button>
              <button onClick={() => approveUser(w.userId)} title="Accept" style={{ width: 32, height: 32, borderRadius: 9, border: 'none', background: 'var(--accent)', color: 'var(--on-accent)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.8"><path d="M20 6 9 17l-5-5" /></svg>
              </button>
            </div>
          ))}
        </div>
      )}

      {open ? (
        <PartyPanel
          phone={phone} watching={watching} top={top}
          onClose={() => setOpen(false)}
          layoutMode={layoutMode} onToggleLayout={onToggleLayout}
          hideSelf={hideSelf} onToggleHideSelf={onToggleHideSelf}
        />
      ) : null}
    </>
  )
}
