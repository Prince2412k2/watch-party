import { useState } from 'react'
import { Rnd } from 'react-rnd'
import CameraTile from './CameraTile.jsx'

export default function CameraGrid({ localParticipant, participants, isHost, removedCameras, onRemove, hideSelf }) {
  const [hidden, setHidden] = useState(new Set())
  const [positions, setPositions] = useState({})
  const [hiddenMenuOpen, setHiddenMenuOpen] = useState(false)

  const localId = localParticipant?.identity
  const all = [
    // `hideSelf` is a purely-local render toggle — the camera keeps publishing,
    // we just drop our own tile from the grid to declutter our screen.
    ...(localParticipant && !hideSelf ? [{ ...localParticipant, isLocal: true }] : []),
    ...participants.filter(p => p.identity !== localId && !removedCameras.has(p.identity)),
  ]
    // Bug 5: only render tiles for feeds whose camera is actually ON. A missing
    // videoTrack means the participant isn't publishing camera — no blank/avatar
    // placeholder tile; they reappear automatically when they turn it back on.
    .filter(p => !!p.videoTrack)

  const visible = all.filter(p => !hidden.has(p.identity))
  // Bug 3: participants I've locally hidden but who are still present + live —
  // these are the ones an "unhide" control can bring back.
  const hiddenList = all.filter(p => hidden.has(p.identity))

  function hide(identity) { setHidden(s => new Set([...s, identity])) }
  function unhide(identity) { setHidden(s => { const n = new Set(s); n.delete(identity); return n }) }
  function showAll() { setHidden(new Set()); setHiddenMenuOpen(false) }

  function getPos(identity, i) {
    return positions[identity] ?? { x: 16 + i * 20, y: 80 + i * 20, width: 196, height: 148 }
  }

  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      {visible.map((p, i) => {
        const pos = getPos(p.identity, i)
        return (
          <Rnd
            key={p.identity}
            default={pos}
            minWidth={130} minHeight={96}
            bounds="parent"
            style={{ pointerEvents: 'all' }}
            onDragStop={(_, d) =>
              setPositions(prev => ({ ...prev, [p.identity]: { ...getPos(p.identity, i), x: d.x, y: d.y } }))}
            onResizeStop={(_, __, ref, ___, pos) =>
              setPositions(prev => ({
                ...prev,
                [p.identity]: { x: pos.x, y: pos.y, width: ref.offsetWidth, height: ref.offsetHeight },
              }))}
          >
            <div style={{
              width: '100%', height: '100%', borderRadius: 17,
              border: '1px solid rgba(255,255,255,.18)',
              boxShadow: '0 12px 34px rgba(0,0,0,.45)',
              overflow: 'hidden', position: 'relative',
            }}>
              <CameraTile
                participant={p}
                isLocal={p.isLocal}
                isHost={isHost}
                onHide={() => hide(p.identity)}
                onRemove={() => onRemove(p.identity)}
              />

              {/* Action buttons (top right) */}
              <div style={{
                position: 'absolute', top: 7, right: 7,
                display: 'flex', gap: 5,
              }}>
                {isHost && !p.isLocal && (
                  <button
                    onClick={() => onRemove(p.identity)}
                    title="Remove camera for everyone"
                    style={{
                      width: 24, height: 24, borderRadius: 7, border: 'none',
                      background: 'rgba(0,0,0,.5)', backdropFilter: 'blur(6px)',
                      color: 'var(--red)', display: 'grid', placeItems: 'center', cursor: 'pointer',
                    }}
                  >
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="m2 2 20 20M16 16H6a2 2 0 0 1-2-2V8m4-2h6a2 2 0 0 1 2 2v3M22 8l-4 4"/></svg>
                  </button>
                )}
                {!p.isLocal && (
                  <button
                    onClick={() => hide(p.identity)}
                    title="Hide for me"
                    style={{
                      width: 24, height: 24, borderRadius: 7, border: 'none',
                      background: 'rgba(0,0,0,.5)', backdropFilter: 'blur(6px)',
                      color: '#fff', display: 'grid', placeItems: 'center', cursor: 'pointer',
                    }}
                  >
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4"/></svg>
                  </button>
                )}
              </div>

              {/* Drag handle dots */}
              <div style={{
                position: 'absolute', top: 8, left: 9,
                display: 'flex', gap: 3, cursor: 'grab', pointerEvents: 'none',
              }}>
                {[0,1,2].map(k => (
                  <div key={k} style={{ width: 3, height: 3, borderRadius: '50%', background: 'rgba(255,255,255,.6)' }} />
                ))}
              </div>
            </div>
          </Rnd>
        )
      })}

      {/* Hidden cameras (bug 3): a "Hidden (N)" chip that opens a menu listing
          each locally-hidden participant with a per-person unhide, plus Show all.
          Hiding is local-only (remove = host-broadcast); this restores my view. */}
      {hiddenList.length > 0 && (
        <div style={{ position: 'absolute', left: 20, bottom: 110, pointerEvents: 'all' }}>
          {hiddenMenuOpen && (
            <div style={{
              position: 'absolute', left: 0, bottom: 'calc(100% + 8px)', minWidth: 200, maxWidth: 260,
              borderRadius: 14, overflow: 'hidden', background: 'var(--glass)',
              backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
              border: '1px solid var(--stroke)', boxShadow: 'var(--shadow-lg)',
              animation: 'up .18s ease both',
            }}>
              <div style={{ padding: '9px 13px', fontSize: 10.5, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--text3)', borderBottom: '1px solid var(--stroke)' }}>Hidden from you</div>
              {hiddenList.map(p => (
                <div key={p.identity} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 10px 8px 13px' }}>
                  <span style={{ flex: 1, fontSize: 13, fontWeight: 600, color: 'var(--text)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{p.name}{p.isLocal ? ' (you)' : ''}</span>
                  <button onClick={() => unhide(p.identity)} title="Unhide" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, border: 'none', background: 'var(--glass2)', color: 'var(--accent)', fontSize: 12, fontWeight: 600, cursor: 'pointer', padding: '5px 9px', borderRadius: 8 }}>
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>
                    Unhide
                  </button>
                </div>
              ))}
              {hiddenList.length > 1 && (
                <button onClick={showAll} style={{ width: '100%', textAlign: 'left', border: 'none', borderTop: '1px solid var(--stroke)', background: 'transparent', color: 'var(--accent)', fontSize: 12.5, fontWeight: 600, cursor: 'pointer', padding: '10px 13px' }}>Show all</button>
              )}
            </div>
          )}
          <button onClick={() => setHiddenMenuOpen(o => !o)} title="Show hidden cameras" style={{
            display: 'flex', alignItems: 'center', gap: 8, padding: '8px 13px', borderRadius: 13, cursor: 'pointer',
            background: 'var(--glass)', backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
            border: '1px solid var(--stroke)', boxShadow: 'var(--shadow)', color: 'var(--text2)',
          }}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m2 2 20 20M6.7 6.7C4.6 8 3 10 2 12c2 4 6 7 10 7 1.6 0 3.1-.4 4.5-1.1M9.9 4.2A10 10 0 0 1 12 4c4 0 8 3 10 8a16 16 0 0 1-2.3 3.4"/></svg>
            <span style={{ fontSize: 12.5, fontWeight: 600 }}>Hidden ({hiddenList.length})</span>
          </button>
        </div>
      )}
    </div>
  )
}
