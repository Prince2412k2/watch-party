import { useParty } from '../context/PartyContext.jsx'

// Host-only panel: approve/reject guests waiting to join
export default function WaitingRoom() {
  const { session, approveUser, rejectUser } = useParty()
  const waiting = session?.waiting ?? []

  if (waiting.length === 0) return null

  return (
    <div data-component="waiting-room">
      <h3 data-badge={waiting.length}>Waiting to join ({waiting.length})</h3>
      {waiting.map(w => (
        <div key={w.userId} data-waiting-user>
          <span>{w.name}</span>
          <button onClick={() => approveUser(w.userId)}>Approve</button>
          <button onClick={() => rejectUser(w.userId)}>Reject</button>
        </div>
      ))}
    </div>
  )
}
