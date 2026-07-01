import { useEffect, useRef, useState } from 'react'
import { useParty } from '../context/PartyContext.jsx'
import { useAuth } from '../context/AuthContext.jsx'
import { useSocket } from '../hooks/useSocket.js'
import { useLiveKit } from '../hooks/useLiveKit.js'
import { navigate } from '../router.js'
import Player from '../components/Player.jsx'
import CameraGrid from '../components/CameraGrid.jsx'
import Dock from '../components/Dock.jsx'
import Chat from '../components/Chat.jsx'
import Lobby from './Lobby.jsx'

const COLORS = ['#0A84FF','#FF9F0A','#30D158','#BF5AF2','#FF6482','#64D2FF']
function colorFor(name = '') {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffffffff
  return COLORS[Math.abs(h) % COLORS.length]
}
function initials(name = '') {
  return name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2) || '?'
}

export default function Party({ partyId, isNew, itemId }) {
  const { user } = useAuth()
  const { socket } = useSocket()
  const party = useParty()
  const { session, role, layoutMode, chatOpen, toasts, setLayout, setCollaborative, kickUser, transferHost, removeCamera, toggleChat } = party

  const lk = useLiveKit({ partyId: session?.id ?? null, enabled: role === 'host' || role === 'guest' })
  const [removedCameras, setRemovedCameras] = useState(new Set())
  const [hostPanelOpen, setHostPanelOpen] = useState(false)
  const [copyLabel, setCopyLabel] = useState('Copy link')

  const joinedRef = useRef(false)
  useEffect(() => {
    // Guard against StrictMode's double-invoke (would create/join twice)
    if (joinedRef.current) return
    joinedRef.current = true
    if (isNew && itemId) {
      party.createParty(itemId)
        .then(id => window.history.replaceState({}, '', `/party/${id}`))
        .catch(() => navigate('/library'))
    } else if (partyId) {
      party.joinParty(partyId).catch(() => navigate('/library'))
    }
  }, []) // eslint-disable-line

  useEffect(() => {
    const handler = ({ userId }) => setRemovedCameras(prev => new Set([...prev, userId]))
    socket.on('camera:removed', handler)
    return () => socket.off('camera:removed', handler)
  }, [socket])

  function copyLink() {
    navigator.clipboard.writeText(`${window.location.origin}/party/${session.id}`)
    setCopyLabel('Copied!')
    setTimeout(() => setCopyLabel('Copy link'), 2000)
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
  const participantCount = 1 + (session.guests?.length ?? 0)
  const waitingCount = session.waiting?.length ?? 0
  const hasWaiting = waitingCount > 0

  const cameraProps = {
    localParticipant: lk.localParticipant,
    participants: lk.participants,
    isHost,
    removedCameras,
    onRemove: (identity) => {
      removeCamera(identity)
      setRemovedCameras(prev => new Set([...prev, identity]))
    },
  }

  return (
    <div style={{ position: 'fixed', inset: 0, background: '#000', overflow: 'hidden' }}>
      {/* Toasts */}
      <div style={{
        position: 'absolute', top: 18, left: '50%', transform: 'translateX(-50%)',
        zIndex: 60, display: 'flex', flexDirection: 'column', gap: 8,
        alignItems: 'center', pointerEvents: 'none',
      }}>
        {toasts.map(t => (
          <div key={t.id} style={{
            display: 'flex', alignItems: 'center', gap: 9,
            padding: '10px 16px', borderRadius: 13,
            background: 'var(--glass)',
            backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
            border: '1px solid var(--stroke)',
            boxShadow: 'var(--shadow)',
            animation: 'in .22s cubic-bezier(.2,0,.1,1)',
          }}>
            <span style={{
              width: 7, height: 7, borderRadius: '50%',
              background: t.level === 'success' ? 'var(--green)' : t.level === 'warning' ? '#FF9F0A' : t.level === 'error' ? 'var(--red)' : 'var(--accent)',
              flexShrink: 0,
            }} />
            <span style={{ fontSize: 13.5, fontWeight: 600 }}>{t.msg}</span>
          </div>
        ))}
      </div>

      {/* LiveKit / media error */}
      {lk.error && (
        <div style={{
          position: 'absolute', bottom: 18, left: '50%', transform: 'translateX(-50%)',
          zIndex: 60, maxWidth: '80vw',
          display: 'flex', alignItems: 'center', gap: 9,
          padding: '10px 16px', borderRadius: 12,
          background: 'rgba(255,69,58,.14)', border: '1px solid rgba(255,69,58,.3)',
          color: '#FF8A80', fontSize: 13, fontWeight: 600,
        }}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><path d="M12 8v4M12 16h.01"/></svg>
          {lk.error}
        </div>
      )}

      {/* Video fill */}
      <div style={{
        position: 'absolute', inset: 0,
        marginLeft: layoutMode === 'dock' ? 210 : 0,
        transition: 'margin-left .3s cubic-bezier(.2,0,.1,1)',
      }}>
        <HlsPlayer
          session={session} isHost={isHost}
          collaborativeControl={session.collaborativeControl}
          micOn={lk.micOn} camOn={lk.camOn}
          onToggleMic={() => lk.enableMic(!lk.micOn)}
          onToggleCam={() => lk.enableCamera(!lk.camOn)}
          onToggleLayout={() => setLayout(layoutMode === 'float' ? 'dock' : 'float')}
          onToggleChat={toggleChat}
          chatOpen={chatOpen}
          layoutMode={layoutMode}
        />

        {/* Float cameras overlay */}
        {layoutMode === 'float' && <CameraGrid {...cameraProps} />}

        {/* Chat overlay */}
        {chatOpen && <Chat />}
      </div>

      {/* Dock strip */}
      {layoutMode === 'dock' && (
        <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 210, zIndex: 10 }}>
          <Dock {...cameraProps} />
        </div>
      )}

      {/* Top-left media info */}
      <div style={{
        position: 'absolute', top: 18, left: layoutMode === 'dock' ? 228 : 20,
        zIndex: 16, display: 'flex', alignItems: 'center', gap: 11,
        padding: '9px 14px 9px 9px', borderRadius: 16,
        background: 'var(--glass)',
        backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
        border: '1px solid var(--stroke)',
        boxShadow: 'var(--shadow), inset 0 1px 0 var(--hi)',
        transition: 'left .3s cubic-bezier(.2,0,.1,1)',
      }}>
        <div style={{ width: 28, height: 40, borderRadius: 6, background: '#1c1428', flexShrink: 0 }} />
        <div>
          <div style={{ fontSize: 13.5, fontWeight: 600, lineHeight: 1.15 }}>
            {session.mediaItemId ? 'Now watching' : 'Watchparty'}
          </div>
          <div style={{ fontSize: 11.5, color: 'var(--text3)', marginTop: 1 }}>
            Code: <span style={{ fontFamily: 'monospace', letterSpacing: '.05em' }}>{session.id}</span>
          </div>
        </div>
        <div style={{ width: 1, height: 22, background: 'var(--stroke)', margin: '0 4px' }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{
            width: 7, height: 7, borderRadius: '50%', background: 'var(--red)',
            boxShadow: '0 0 7px var(--red)',
            animation: 'pulse 2s ease-in-out infinite',
          }} />
          <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--text2)' }}>
            {participantCount} watching
          </span>
        </div>
      </div>

      {/* Top-right controls */}
      <div style={{
        position: 'absolute', top: 18, right: 18, zIndex: 16,
        display: 'flex', alignItems: 'center', gap: 10,
      }}>
        {isHost && (
          <button onClick={() => setHostPanelOpen(true)} style={{
            position: 'relative', display: 'flex', alignItems: 'center', gap: 8,
            padding: '10px 15px', borderRadius: 14,
            background: 'var(--glass)',
            backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
            border: '1px solid var(--stroke)',
            boxShadow: 'var(--shadow), inset 0 1px 0 var(--hi)',
            color: 'var(--text)', fontSize: 13.5, fontWeight: 600, cursor: 'pointer',
          }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>
            Host controls
            {hasWaiting && (
              <span style={{
                position: 'absolute', top: -7, right: -7,
                minWidth: 20, height: 20, padding: '0 5px', borderRadius: 10,
                background: 'var(--red)', color: '#fff', fontSize: 11, fontWeight: 700,
                display: 'grid', placeItems: 'center',
                boxShadow: '0 2px 8px rgba(0,0,0,.4)',
                border: '2px solid #000',
              }}>{waitingCount}</span>
            )}
          </button>
        )}
        <button onClick={() => navigate('/library')} style={{
          display: 'flex', alignItems: 'center', gap: 7, padding: '10px 15px', borderRadius: 14,
          background: 'var(--glass)',
          backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
          border: '1px solid var(--stroke)',
          boxShadow: 'var(--shadow), inset 0 1px 0 var(--hi)',
          color: 'var(--red)', fontSize: 13.5, fontWeight: 600, cursor: 'pointer',
        }}>Leave</button>
      </div>

      {/* Host Panel Modal */}
      {hostPanelOpen && (
        <>
          <div
            onClick={() => setHostPanelOpen(false)}
            style={{
              position: 'absolute', inset: 0, zIndex: 30,
              background: 'rgba(6,8,15,.5)',
              backdropFilter: 'blur(3px)', WebkitBackdropFilter: 'blur(3px)',
            }}
          />
          <div style={{
            position: 'absolute', top: '50%', left: '50%',
            transform: 'translate(-50%,-50%)',
            zIndex: 31, width: 440, maxWidth: '92vw', maxHeight: '85vh',
            display: 'flex', flexDirection: 'column', borderRadius: 26,
            background: 'rgba(10,12,20,.92)',
            backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
            border: '1px solid var(--stroke)',
            boxShadow: 'var(--shadow-lg), inset 0 1px 0 var(--hi)',
            overflow: 'hidden',
            animation: 'in .25s cubic-bezier(.2,0,.1,1)',
          }}>
            {/* Modal header */}
            <div style={{
              padding: '18px 22px', display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              borderBottom: '1px solid var(--stroke)', flexShrink: 0,
            }}>
              <span style={{ fontSize: 17, fontWeight: 700, letterSpacing: '-0.02em' }}>Host controls</span>
              <button onClick={() => setHostPanelOpen(false)} style={{
                width: 28, height: 28, borderRadius: 9, border: 'none',
                background: 'var(--glass2)', color: 'var(--text2)',
                display: 'grid', placeItems: 'center', cursor: 'pointer',
              }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M18 6 6 18M6 6l12 12"/></svg>
              </button>
            </div>

            <div style={{ overflowY: 'auto', padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 24 }}>
              {/* Waiting */}
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
                  <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--text3)' }}>Waiting to join</span>
                  {hasWaiting && (
                    <span style={{
                      minWidth: 18, height: 18, padding: '0 5px', borderRadius: 9,
                      background: 'var(--red)', color: '#fff', fontSize: 11, fontWeight: 700,
                      display: 'grid', placeItems: 'center',
                    }}>{waitingCount}</span>
                  )}
                </div>
                {hasWaiting ? (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                    {session.waiting.map(w => (
                      <div key={w.userId} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '6px 0' }}>
                        <div style={{
                          width: 34, height: 34, borderRadius: '50%',
                          background: colorFor(w.name),
                          display: 'grid', placeItems: 'center',
                          color: '#fff', fontSize: 13, fontWeight: 700, flexShrink: 0,
                        }}>{initials(w.name)}</div>
                        <span style={{ flex: 1, fontSize: 14, fontWeight: 600 }}>{w.name}</span>
                        <button onClick={() => party.rejectUser(w.userId)} style={{
                          width: 34, height: 34, borderRadius: 10, border: 'none',
                          background: 'transparent', color: 'var(--red)',
                          display: 'grid', placeItems: 'center', cursor: 'pointer',
                        }}>
                          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M18 6 6 18M6 6l12 12"/></svg>
                        </button>
                        <button onClick={() => party.approveUser(w.userId)} style={{
                          display: 'flex', alignItems: 'center', gap: 6,
                          padding: '8px 13px', borderRadius: 10, border: 'none',
                          background: 'var(--green)', color: '#04130a',
                          fontSize: 13, fontWeight: 700, cursor: 'pointer',
                        }}>
                          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6"><path d="M20 6 9 17l-5-5"/></svg>
                          Approve
                        </button>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div style={{ color: 'var(--text3)', fontSize: 13, padding: '6px 0' }}>No one waiting</div>
                )}
              </div>

              {/* Participants */}
              <div>
                <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--text3)', marginBottom: 12 }}>
                  In the party · {participantCount}
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {/* Host */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '6px 0' }}>
                    <div style={{
                      width: 34, height: 34, borderRadius: '50%',
                      background: colorFor(session.hostName || 'Host'),
                      display: 'grid', placeItems: 'center',
                      color: '#fff', fontSize: 13, fontWeight: 700, flexShrink: 0,
                    }}>{initials(session.hostName || 'Host')}</div>
                    <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ fontSize: 14, fontWeight: 600 }}>{session.hostName || 'Host'}</span>
                      <span style={{
                        padding: '2px 7px', borderRadius: 6,
                        background: 'var(--accent-soft)', color: 'var(--accent)',
                        fontSize: 10, fontWeight: 700, letterSpacing: '.04em',
                      }}>HOST</span>
                    </div>
                  </div>
                  {session.guests?.map(g => (
                    <div key={g.userId} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '6px 0' }}>
                      <div style={{
                        width: 34, height: 34, borderRadius: '50%',
                        background: colorFor(g.name),
                        display: 'grid', placeItems: 'center',
                        color: '#fff', fontSize: 13, fontWeight: 700, flexShrink: 0,
                      }}>{initials(g.name)}</div>
                      <span style={{ flex: 1, fontSize: 14, fontWeight: 600 }}>{g.name}</span>
                      <button onClick={() => transferHost(g.userId)} title="Make host" style={{
                        width: 32, height: 32, borderRadius: 9, border: 'none',
                        background: 'transparent', color: 'var(--text3)',
                        display: 'grid', placeItems: 'center', cursor: 'pointer',
                      }}>
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m3 11 2-7 4 4 3-5 3 5 4-4 2 7z"/><path d="M3 11h18v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>
                      </button>
                      <button onClick={() => removeCamera(g.userId)} title="Remove camera" style={{
                        width: 32, height: 32, borderRadius: 9, border: 'none',
                        background: 'transparent', color: 'var(--text3)',
                        display: 'grid', placeItems: 'center', cursor: 'pointer',
                      }}>
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M16 16H4a2 2 0 0 1-2-2V8m4-2h8a2 2 0 0 1 2 2v3l4-2v8"/></svg>
                      </button>
                      <button onClick={() => kickUser(g.userId)} title="Kick" style={{
                        width: 32, height: 32, borderRadius: 9, border: 'none',
                        background: 'transparent', color: 'var(--red)',
                        display: 'grid', placeItems: 'center', cursor: 'pointer',
                      }}>
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M16 17l5-5-5-5M21 12H9M13 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h8"/></svg>
                      </button>
                    </div>
                  ))}
                </div>
              </div>

              {/* Collaborative */}
              <div style={{
                display: 'flex', alignItems: 'center', gap: 14,
                padding: '16px 0 4px', borderTop: '1px solid var(--stroke)',
              }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 14.5, fontWeight: 600 }}>Collaborative control</div>
                  <div style={{ fontSize: 12.5, color: 'var(--text3)', marginTop: 2 }}>Let guests play, pause &amp; seek</div>
                </div>
                <button
                  onClick={() => setCollaborative(!session.collaborativeControl)}
                  style={{
                    width: 44, height: 26, borderRadius: 13, border: 'none', cursor: 'pointer', padding: 3,
                    background: session.collaborativeControl ? 'var(--accent)' : 'rgba(255,255,255,.15)',
                    transition: 'background .2s', flexShrink: 0, display: 'flex',
                    alignItems: 'center',
                    justifyContent: session.collaborativeControl ? 'flex-end' : 'flex-start',
                  }}
                >
                  <span style={{ width: 20, height: 20, borderRadius: '50%', background: '#fff', display: 'block', boxShadow: '0 1px 4px rgba(0,0,0,.4)' }} />
                </button>
              </div>

              {/* Invite link */}
              <div>
                <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--text3)', marginBottom: 12 }}>
                  Invite link
                </div>
                <div style={{ display: 'flex', gap: 9 }}>
                  <div style={{
                    flex: 1, padding: '11px 12px', fontSize: 12.5, color: 'var(--text2)',
                    fontFamily: 'ui-monospace, monospace',
                    whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                    borderRadius: 11, background: 'var(--glass2)', border: '1px solid var(--stroke)',
                  }}>
                    {window.location.origin}/party/{session.id}
                  </div>
                  <button onClick={copyLink} style={{
                    display: 'flex', alignItems: 'center', gap: 7,
                    padding: '0 15px', borderRadius: 11, border: 'none',
                    background: 'var(--accent)', color: '#fff',
                    fontSize: 13, fontWeight: 600, cursor: 'pointer', flexShrink: 0,
                    transition: 'background .15s',
                  }}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                    {copyLabel}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  )
}

// Bitrate ladder (bps). null = no cap (best quality). A guest that can't keep
// up steps down a rung so it can actually stay in sync.
const BITRATE_LADDER = [null, 3_000_000, 1_500_000, 700_000]

function HlsPlayer({ session, isHost, collaborativeControl, ...rest }) {
  const [hlsUrl, setHlsUrl] = useState(null)
  const [tier, setTier] = useState(0)
  const shiftAt = useRef(0)

  useEffect(() => {
    if (!session?.mediaItemId) return
    const cap = BITRATE_LADDER[tier]
    const q = cap ? `&maxBitrate=${cap}` : ''
    fetch(`/api/library/hls-url?itemId=${session.mediaItemId}${q}`, { credentials: 'include' })
      .then(r => r.ok ? r.json() : null)
      .then(d => { if (d?.url) setHlsUrl(d.url) })
  }, [session?.mediaItemId, tier])

  // The host drives quality; only guests downshift to keep up.
  function onStruggle() {
    if (isHost) return
    const now = Date.now()
    if (now - shiftAt.current < 8000) return          // don't thrash
    setTier(t => {
      if (t >= BITRATE_LADDER.length - 1) return t     // already lowest
      shiftAt.current = now
      return t + 1
    })
  }

  if (!hlsUrl) return (
    <div style={{
      width: '100%', height: '100%', display: 'grid', placeItems: 'center',
      background: '#000',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
        <div style={{ width: 36, height: 36, borderRadius: '50%', border: '3px solid var(--stroke2)', borderTopColor: 'var(--accent)', animation: 'spin .9s linear infinite' }} />
        <span style={{ color: 'var(--text3)', fontSize: 13 }}>Loading video…</span>
      </div>
    </div>
  )

  return <Player hlsUrl={hlsUrl} isHost={isHost} collaborativeControl={collaborativeControl} onStruggle={onStruggle} {...rest} />
}
