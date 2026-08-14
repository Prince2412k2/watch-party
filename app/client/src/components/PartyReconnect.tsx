import { useEffect, useState } from 'react'
import '../analog/partyReconnect.css'
import Avatar from './Avatar.tsx'
import { useParty } from '../context/PartyContext.tsx'
import { useSocket } from '../hooks/useSocket.ts'
import { artworkSrc } from '../analog/artwork.ts'
import { orderFaces, reconnectLabel, shouldShowReconnect } from '../analog/partyReconnect.ts'
import { navigate } from '../router.ts'

/**
 * What a party looks like while its connection is being got back.
 *
 * A drop used to be silent: chat stopped arriving, playback stopped following
 * the host, and nothing on screen said why. Socket.IO reconnects its transport
 * by itself and PartyContext re-resumes the session when it does — so the
 * retrying was already happening. What was missing was anyone being told, and
 * a way to stop waiting and leave.
 *
 * Mounted above the router, inside PartyProvider, so it covers the lobby and
 * the watch screen alike — the same place the desktop client puts it.
 *
 * Playback is not stopped. The film keeps running underneath, which is what
 * makes minimising worth having: it hands the picture back while the retrying
 * carries on behind a corner pill.
 */
export default function PartyReconnect() {
  const { session, leaveParty } = useParty()
  const { connected } = useSocket()
  const [minimised, setMinimised] = useState(false)
  const [attempt, setAttempt] = useState(0)

  const lost = shouldShowReconnect(Boolean(session), connected)

  // Count how long this has been going on, on the same curve the desktop client
  // retries on. Socket.IO owns the actual dialling.
  useEffect(() => {
    if (!lost) {
      setAttempt(0)
      setMinimised(false)
      return
    }
    const timer = window.setInterval(() => setAttempt(a => a + 1), 5000)
    return () => window.clearInterval(timer)
  }, [lost])

  // Escape minimises, matching the player. Nothing here closes on Escape: the
  // only way out of a party is the leave control, which says what it does.
  useEffect(() => {
    if (!lost || minimised) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setMinimised(true)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [lost, minimised])

  if (!lost || !session) return null

  const label = reconnectLabel(attempt)

  if (minimised) {
    return (
      <button
        type="button"
        className="an-reconnect-pill"
        onClick={() => setMinimised(false)}
        title="Back to the party"
      >
        <i aria-hidden />
        <span>{label}</span>
      </button>
    )
  }

  const faces = orderFaces(session.guests ?? [], session.hostId)
  // The app's own artwork path, so this poster comes from the same proxy (and
  // the same cache) as every other one on screen.
  const poster = artworkSrc({
    kind: 'series',
    itemId: session.mediaItemId ?? null,
    imageTag: null,
    label: null,
  })

  const leave = () => {
    leaveParty()
    navigate('/movies')
  }

  return (
    <div className="an-reconnect" role="dialog" aria-label="Reconnecting to the party">
      <div className="an-reconnect-room">
        {poster ? <img className="an-reconnect-poster" src={poster} alt="" /> : null}
        <div className="an-reconnect-status">
          <i aria-hidden />
          <span>{label}</span>
        </div>
        {faces.length > 0 ? (
          <div className="an-reconnect-faces">
            {faces.map(person => (
              <div key={person.userId} className="an-reconnect-face">
                <div
                  className={person.userId === session.hostId ? 'is-host' : undefined}
                >
                  <Avatar
                    userId={person.userId}
                    name={person.name}
                    config={person.avatar}
                    size={44}
                    circle
                  />
                </div>
                <span>{person.name}</span>
                {person.userId === session.hostId ? <small>Host</small> : null}
              </div>
            ))}
          </div>
        ) : null}
      </div>

      <div className="an-reconnect-corner">
        <button
          type="button"
          onClick={() => setMinimised(true)}
          title="Keep trying in the background"
        >
          Minimise
        </button>
        {/* The only control here that ends anything — which is why it says so
            rather than reading as a way to dismiss the message. */}
        <button type="button" className="is-danger" onClick={leave}>
          Leave the party
        </button>
      </div>
    </div>
  )
}
