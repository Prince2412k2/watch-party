import { useParty } from '../context/PartyContext'

// Host-only panel: approve/reject guests waiting to join
export default function WaitingRoom() {
  const { session, approveUser, rejectUser } = useParty()
  const waiting = session?.waiting ?? []

  if (waiting.length === 0) return null

  return (
    <div data-component="waiting-room" style={{
      background: 'var(--glass)', border: '1px solid var(--stroke)', borderRadius: 'var(--r-lg)',
      padding: 16, display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <h3 data-badge={waiting.length} style={{
        margin: 0, fontSize: 13.5, fontWeight: 700, color: 'var(--text)',
      }}>
        Waiting to join ({waiting.length})
      </h3>
      {waiting.map(w => (
        <div key={w.userId} data-waiting-user style={{
          display: 'flex', alignItems: 'center', gap: 10, padding: '8px 4px',
          borderTop: '1px solid var(--stroke)',
        }}>
          <span style={{ flex: 1, fontSize: 14, color: 'var(--text)', fontWeight: 500 }}>{w.name}</span>
          <button onClick={() => approveUser(w.userId)} style={{
            padding: '6px 14px', borderRadius: 999, border: 'none', cursor: 'pointer',
            background: 'var(--accent)', color: 'var(--on-accent)', fontSize: 13, fontWeight: 700,
          }}>Approve</button>
          <button onClick={() => rejectUser(w.userId)} style={{
            padding: '6px 14px', borderRadius: 999, cursor: 'pointer',
            background: 'transparent', border: '1px solid var(--stroke2)', color: 'var(--text2)', fontSize: 13, fontWeight: 600,
          }}>Reject</button>
        </div>
      ))}
    </div>
  )
}
