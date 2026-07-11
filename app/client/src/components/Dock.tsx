import { useState } from 'react'
import CameraTile from './CameraTile'

export default function Dock({ localParticipant, participants, isHost, removedCameras, onRemove, hideSelf }: any = {}) {
  const [hidden, setHidden] = useState(new Set())

  const localId = localParticipant?.identity
  const all = [
    // `hideSelf`: local render-only drop of our own tile (camera keeps publishing).
    ...(localParticipant && !hideSelf ? [{ ...localParticipant, isLocal: true }] : []),
    ...participants.filter(p => p.identity !== localId && !removedCameras.has(p.identity)),
  ]

  function hide(identity) { setHidden(s => new Set([...s, identity])) }

  return (
    <div style={{
      position: 'absolute', left: 18, top: 76, bottom: 108, width: 180,
      zIndex: 15, borderRadius: 16, padding: 10,
      background: 'var(--glass)',
      border: '1px solid var(--stroke)',
      boxShadow: 'var(--shadow)',
      overflowY: 'auto',
      display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      {all.filter(p => !hidden.has(p.identity)).map(p => (
        <div key={p.identity} style={{
          position: 'relative', width: '100%', aspectRatio: '4/3',
          borderRadius: 12, overflow: 'hidden', flexShrink: 0,
          border: '1px solid var(--stroke)',
        }}>
          <CameraTile
            participant={p}
            isLocal={p.isLocal}
            isHost={isHost}
            onHide={() => hide(p.identity)}
            onRemove={() => onRemove(p.identity)}
          />
        </div>
      ))}
      {all.filter(p => !hidden.has(p.identity)).length === 0 && (
        <div style={{ color: 'var(--text3)', fontSize: 12, textAlign: 'center', padding: '20px 0' }}>
          No cameras
        </div>
      )}
    </div>
  )
}
