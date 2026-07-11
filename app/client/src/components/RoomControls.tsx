import { useEffect, useState } from 'react'
import QRCode from 'qrcode'
import { useParty } from '../context/PartyContext'
import { navigate } from '../router'

const MONO = "'JetBrains Mono', ui-monospace, monospace"
function initials(name = '') {
  return name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2) || '?'
}

/**
 * Room chrome: icon-only Host / Leave buttons (flat surfaces), the host modal,
 * toasts, and a join-request sidebar with accept/reject. `visible` fades the
 * top cluster with the auto-hide layer; the join sidebar stays put (it's a
 * notification), and toasts/modal are never hidden.
 */
export default function RoomControls({ stage, top = 18, visible = true, phone = false, onOpenChat, chatOpen = false }) {
  const party = useParty()
  const {
    session, role, toasts,
    approveUser, rejectUser, kickUser, transferHost,
    setCollaborative, setSyncMode, backToLobby, endParty,
  } = party

  const [open, setOpen] = useState(false)
  const [copyLabel, setCopyLabel] = useState('Copy link')
  const [confirmEnd, setConfirmEnd] = useState(false)
  if (!session) return null

  const isHost = role === 'host'
  const watching = stage === 'watching'
  const waiting = session.waiting ?? []
  const participantCount = 1 + (session.guests?.length ?? 0)

  function copyLink() {
    navigator.clipboard.writeText(`${window.location.origin}/party/${session.id}`)
    setCopyLabel('Copied!')
    setTimeout(() => setCopyLabel('Copy link'), 2000)
  }

  function leaveRoom() {
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
  const elevatedPanel = {
    background: 'var(--bg)',
    border: '1px solid var(--stroke)',
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
        <button onClick={leaveRoom} title="Back" aria-label="Back" style={iconBtn(true)} onMouseEnter={e => { e.currentTarget.style.color = 'var(--red)' }} onMouseLeave={e => { e.currentTarget.style.color = 'var(--red)' }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="m15 18-6-6 6-6" /><path d="M9 12h12" /></svg>
        </button>
        {isHost && (
          <button onClick={() => setOpen(true)} title="Host controls" aria-label="Host controls" style={{ ...iconBtn(), position: 'relative' }} onMouseEnter={e => { e.currentTarget.style.color = 'var(--text)' }} onMouseLeave={e => { e.currentTarget.style.color = 'var(--text2)' }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" /></svg>
            {waiting.length > 0 && (
              <span style={{ position: 'absolute', top: phone ? 3 : -2, right: phone ? 3 : -2, minWidth: 16, height: 16, padding: '0 5px', borderRadius: 999, background: 'var(--red)', color: 'var(--text)', fontSize: 10, fontWeight: 700, display: 'grid', placeItems: 'center' }}>{waiting.length}</span>
            )}
          </button>
        )}
      </div>

      {/* Top-right icon cluster (fades with auto-hide) */}
      <div style={{ position: 'absolute', top: phone ? 'calc(var(--sa-t) + 8px)' : top, right: phone ? 'calc(var(--sa-r) + 8px)' : 18, zIndex: 40, display: 'flex', alignItems: 'center', gap: phone ? 8 : 10, opacity: visible ? 1 : 0, pointerEvents: visible ? 'auto' : 'none', transition: 'opacity .25s' }}>
        {phone && watching && onOpenChat && (
          <button onClick={(e) => { e.stopPropagation(); onOpenChat() }} title="Chat" aria-label="Chat" style={{ ...iconBtn(), width: 44, height: 44, color: chatOpen ? 'var(--text)' : 'var(--text2)' }}>
            <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" /></svg>
          </button>
        )}
      </div>

      {/* Join-request sidebar (host only) — stays visible; it's a notification */}
      {isHost && waiting.length > 0 && (
        <div style={{ ...flatPanel, position: 'absolute', top: phone ? 'calc(var(--sa-t) + 60px)' : top + 54, right: phone ? 'calc(var(--sa-r) + 8px)' : 12, zIndex: 41, width: 'min(268px, calc(100vw - 24px))', borderRadius: 16, overflow: 'hidden', animation: 'up .25s cubic-bezier(.2,0,.1,1)' }}>
          <div style={{ padding: '11px 15px', borderBottom: '1px solid var(--stroke)', fontSize: 12, fontWeight: 700, letterSpacing: '.06em', textTransform: 'uppercase', color: 'var(--text2)' }}>
            Wants to join · {waiting.length}
          </div>
          {waiting.map(w => (
            <div key={w.userId} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px' }}>
              <div style={{ width: 32, height: 32, borderRadius: '50%', background: 'var(--stroke2)', display: 'grid', placeItems: 'center', color: 'var(--text)', fontSize: 12, fontWeight: 700, flexShrink: 0 }}>{initials(w.name)}</div>
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

      {/* Host modal */}
      {open && (
        <>
          <div onClick={() => setOpen(false)} style={{ position: 'absolute', inset: 0, zIndex: 50, background: 'rgba(0,0,0,.72)' }} />
          <div style={{ ...elevatedPanel, position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', zIndex: 51, width: 420, maxWidth: 'calc(100vw - 28px)', maxHeight: 'min(680px, calc(100vh - 40px))', display: 'flex', flexDirection: 'column', borderRadius: 14, overflow: 'hidden', color: 'var(--text)' }}>
            <div style={{ padding: '18px 22px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', borderBottom: '1px solid var(--stroke)' }}>
              <span style={{ fontSize: 17, fontWeight: 700, letterSpacing: '-.02em' }}>Host controls</span>
              <button onClick={() => setOpen(false)} style={{ width: 28, height: 28, borderRadius: 8, border: 'none', background: 'transparent', color: 'var(--text2)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M18 6 6 18M6 6l12 12" /></svg>
              </button>
            </div>

            <div style={{ overflowY: 'auto', padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 24 }}>
              <div>
                <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--text3)', marginBottom: 12 }}>In the party · {participantCount}</div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '6px 0' }}>
                    <div style={{ width: 34, height: 34, borderRadius: '50%', background: 'var(--stroke2)', display: 'grid', placeItems: 'center', color: 'var(--text)', fontSize: 13, fontWeight: 700, flexShrink: 0 }}>{initials(session.hostName || 'Host')}</div>
                    <span style={{ flex: 1, fontSize: 14, fontWeight: 600 }}>{session.hostName || 'Host'}</span>
                    <span style={{ padding: '2px 7px', borderRadius: 6, background: 'var(--glass2)', color: 'var(--text)', fontSize: 10, fontWeight: 700, letterSpacing: '.04em' }}>HOST</span>
                  </div>
                  {session.guests?.map(g => (
                    <div key={g.userId} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '6px 0' }}>
                      <div style={{ width: 34, height: 34, borderRadius: '50%', background: 'var(--stroke2)', display: 'grid', placeItems: 'center', color: 'var(--text)', fontSize: 13, fontWeight: 700, flexShrink: 0 }}>{initials(g.name)}</div>
                      <span style={{ flex: 1, fontSize: 14, fontWeight: 600 }}>{g.name}</span>
                      {isHost && (
                        <>
                          <button onClick={() => transferHost(g.userId)} title="Make host" style={{ width: 32, height: 32, borderRadius: 9, border: 'none', background: 'transparent', color: 'var(--text3)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m3 11 2-7 4 4 3-5 3 5 4-4 2 7z" /><path d="M3 11h18v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /></svg>
                          </button>
                          <button onClick={() => kickUser(g.userId)} title="Kick" style={{ width: 32, height: 32, borderRadius: 9, border: 'none', background: 'transparent', color: 'var(--red)', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M16 17l5-5-5-5M21 12H9M13 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h8" /></svg>
                          </button>
                        </>
                      )}
                    </div>
                  ))}
                </div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '16px 0 4px', borderTop: '1px solid var(--stroke)' }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 14.5, fontWeight: 600 }}>Collaborative control</div>
                  <div style={{ fontSize: 12.5, color: 'var(--text3)', marginTop: 2 }}>Let guests browse, play, pause &amp; seek</div>
                </div>
                <button onClick={() => setCollaborative(!session.collaborativeControl)} style={{ width: 44, height: 26, borderRadius: 13, border: '1px solid var(--stroke2)', cursor: 'pointer', padding: 3, flexShrink: 0, background: session.collaborativeControl ? 'var(--stroke2)' : 'transparent', transition: 'background .2s', display: 'flex', alignItems: 'center', justifyContent: session.collaborativeControl ? 'flex-end' : 'flex-start' }}>
                  <span style={{ width: 18, height: 18, borderRadius: '50%', background: 'var(--text)', display: 'block' }} />
                </button>
              </div>

              {watching && (
                <div style={{ padding: '16px 0 4px', borderTop: '1px solid var(--stroke)' }}>
                  <div style={{ fontSize: 14.5, fontWeight: 600 }}>Sync mode</div>
                  <div style={{ fontSize: 12.5, color: 'var(--text3)', margin: '2px 0 12px' }}>
                    {(session.syncMode ?? 'hopping') === 'dragging' ? 'Everyone waits for the slowest viewer' : 'Host never waits; slow viewers catch up'}
                  </div>
                  <div style={{ display: 'flex', gap: 6, background: 'var(--glass2)', border: '1px solid var(--stroke)', borderRadius: 10, padding: 4 }}>
                    {[{ id: 'hopping', label: 'Hopping' }, { id: 'dragging', label: 'Dragging' }].map(m => {
                      const active = (session.syncMode ?? 'hopping') === m.id
                      return <button key={m.id} onClick={() => setSyncMode(m.id)} style={{ flex: 1, padding: '9px 0', borderRadius: 8, border: 'none', cursor: 'pointer', fontSize: 13, fontWeight: active ? 700 : 600, background: active ? 'var(--accent)' : 'transparent', color: active ? 'var(--on-accent)' : 'var(--text2)', transition: 'background .15s, color .15s' }}>{m.label}</button>
                    })}
                  </div>
                </div>
              )}

              {watching && isHost && (
                <button onClick={() => { backToLobby(); setOpen(false) }} style={{ padding: '11px 0', borderRadius: 10, border: '1px solid var(--stroke2)', background: 'var(--glass2)', color: 'var(--text)', fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>← Pick something else</button>
              )}

              <div style={{ paddingTop: 4 }}>
                <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--text3)', marginBottom: 12 }}>Share this code</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                  <JoinQR url={`${window.location.origin}/party/${session.id}`} />
                  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 10, minWidth: 0 }}>
                    <span style={{ fontFamily: MONO, fontSize: 24, fontWeight: 600, letterSpacing: '.14em', color: 'var(--text)' }}>{session.id}</span>
                    <button onClick={copyLink} style={{ padding: '10px 16px', borderRadius: 10, border: 'none', background: 'var(--accent)', color: 'var(--on-accent)', fontSize: 13, fontWeight: 700, cursor: 'pointer' }}>{copyLabel}</button>
                  </div>
                </div>
              </div>

              {isHost && (
                <div style={{ paddingTop: 4, borderTop: '1px solid var(--stroke)', paddingBottom: 2 }}>
                  <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--red)', margin: '16px 0 10px' }}>Danger zone</div>
                  <button onClick={() => setConfirmEnd(true)} style={{
                    width: '100%', padding: '11px 0', borderRadius: 10, border: '1px solid rgba(224,101,94,.35)',
                    background: 'rgba(224,101,94,.12)', color: 'var(--red)', fontSize: 13.5, fontWeight: 700, cursor: 'pointer',
                  }}>End party for everyone</button>
                </div>
              )}
            </div>
          </div>
        </>
      )}

      {/* End-party confirmation — this is instant and permanent, distinct from
          just leaving/closing the tab (which still goes through the grace-period
          host-disconnect path). Every guest gets kicked back to login/lobby. */}
      {confirmEnd && (
        <>
          <div onClick={() => setConfirmEnd(false)} style={{ position: 'absolute', inset: 0, zIndex: 52, background: 'rgba(0,0,0,.72)' }} />
          <div style={{ ...elevatedPanel, position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', zIndex: 53, width: 360, maxWidth: '90vw', borderRadius: 14, padding: 22, color: 'var(--text)' }}>
            <div style={{ fontSize: 17, fontWeight: 700, letterSpacing: '-.01em', marginBottom: 8 }}>End party for everyone?</div>
            <p style={{ fontSize: 13.5, color: 'var(--text2)', lineHeight: 1.5, margin: '0 0 20px' }}>
              Everyone in the party will be disconnected immediately and returned to the lobby. This can't be undone.
            </p>
            <div style={{ display: 'flex', gap: 10 }}>
              <button onClick={() => setConfirmEnd(false)} style={{ flex: 1, height: 44, borderRadius: 10, border: '1px solid var(--stroke2)', background: 'var(--glass2)', color: 'var(--text)', fontSize: 13.5, fontWeight: 700, cursor: 'pointer' }}>Cancel</button>
              <button onClick={() => { setConfirmEnd(false); setOpen(false); endParty() }} style={{ flex: 1, height: 44, borderRadius: 10, border: 'none', background: 'var(--red)', color: 'var(--text)', fontSize: 13.5, fontWeight: 700, cursor: 'pointer' }}>End party</button>
            </div>
          </div>
        </>
      )}
    </>
  )
}

// Self-contained QR code encoding the join URL — no network calls (the
// 'qrcode' package renders entirely client-side as inline SVG), framed in a
// small rounded white card so it stays scannable against the dark UI.
function JoinQR({ url, size = 108 }) {
  const [svg, setSvg] = useState(null)
  useEffect(() => {
    let live = true
    QRCode.toString(url, { type: 'svg', margin: 1, width: size, color: { dark: '#0a0a0c', light: '#ffffff' } })
      .then(s => { if (live) setSvg(s) })
      .catch(() => {})
    return () => { live = false }
  }, [url, size])

  return (
    <div style={{ flexShrink: 0, width: size + 20, height: size + 20, borderRadius: 14, background: '#fff', display: 'grid', placeItems: 'center' }}>
      {svg
        ? <div style={{ width: size, height: size }} dangerouslySetInnerHTML={{ __html: svg }} />
        : <div style={{ width: size, height: size, borderRadius: 8, background: 'rgba(0,0,0,.06)' }} />}
    </div>
  )
}
