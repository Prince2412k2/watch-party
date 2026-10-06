import { useAuth } from '../context/AuthContext.tsx'
import { useParty } from '../context/PartyContext.tsx'
import {
  AnalogToastStack,
  useChatToasts,
  useDisplayPreferences,
} from '../analog/player/index.ts'
import { useRoomConnection } from './PlayerPresentation.tsx'

/** Room feedback survives transitions between the movie, floating frame and lobby. */
export default function RoomFeedback() {
  const party = useParty()
  const { user } = useAuth()
  const connection = useRoomConnection()
  const preferences = useDisplayPreferences()
  const toasts = useChatToasts({
    messages: party.messages,
    chatOpen: party.chatOpen,
    selfUserId: user?.userId,
  })
  return (
    <>
      <AnalogToastStack
        view={toasts}
        preferences={preferences}
        style={{
          zIndex: 60,
          top: 'calc(var(--sa-t) + 68px)',
          left: 'calc(var(--sa-l) + 12px)',
        }}
      />
      {(connection.error || connection.audioBlocked) && (
        <div className="native-room-feedback">
          {connection.error && <p role="alert">{connection.error}</p>}
          {connection.audioBlocked && (
            <button
              onClick={() => {
                void connection.startAudio()
              }}
            >
              Tap to hear the room
            </button>
          )}
        </div>
      )}
    </>
  )
}
