import { useEffect, useRef, useState } from 'react'
import { Room, RoomEvent, Track } from 'livekit-client'

export function useLiveKit({ partyId, enabled = true }) {
  const roomRef = useRef(null)
  const [participants, setParticipants] = useState([]) // [{ identity, name, videoTrack, audioTrack, isSpeaking }]
  const [localParticipant, setLocalParticipant] = useState(null)
  const [camOn, setCamOn] = useState(false)
  const [micOn, setMicOn] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    if (!partyId || !enabled) return

    let room
    let cancelled = false

    async function connect() {
      try {
        const res = await fetch(`/api/livekit/token?partyId=${partyId}`, { credentials: 'include' })
        if (!res.ok) throw new Error('Failed to get LiveKit token')
        const { token, url } = await res.json()

        room = new Room({ adaptiveStream: true, dynacast: true })
        roomRef.current = room

        function refresh() {
          if (cancelled) return
          const parts = [...room.remoteParticipants.values()].map(p => ({
            identity: p.identity,
            name: p.name || p.identity,
            videoTrack: p.getTrackPublication(Track.Source.Camera)?.track ?? null,
            audioTrack: p.getTrackPublication(Track.Source.Microphone)?.track ?? null,
            isSpeaking: p.isSpeaking,
          }))
          setParticipants(parts)
          setLocalParticipant({
            identity: room.localParticipant.identity,
            name: room.localParticipant.name || room.localParticipant.identity,
            videoTrack: room.localParticipant.getTrackPublication(Track.Source.Camera)?.track ?? null,
            audioTrack: room.localParticipant.getTrackPublication(Track.Source.Microphone)?.track ?? null,
            isSpeaking: room.localParticipant.isSpeaking,
          })
        }

        room
          .on(RoomEvent.ParticipantConnected, refresh)
          .on(RoomEvent.ParticipantDisconnected, refresh)
          .on(RoomEvent.TrackPublished, refresh)
          .on(RoomEvent.TrackUnpublished, refresh)
          .on(RoomEvent.TrackSubscribed, refresh)
          .on(RoomEvent.TrackUnsubscribed, refresh)
          .on(RoomEvent.ActiveSpeakersChanged, refresh)
          .on(RoomEvent.LocalTrackPublished, refresh)
          .on(RoomEvent.LocalTrackUnpublished, refresh)

        await room.connect(url, token)
        refresh()
      } catch (err) {
        if (!cancelled) setError(err.message)
      }
    }

    connect()
    return () => {
      cancelled = true
      room?.disconnect()
      roomRef.current = null
    }
  }, [partyId, enabled])

  function mediaError(kind, err) {
    // getUserMedia only works in a secure context (https or localhost).
    if (!window.isSecureContext) {
      return `${kind} needs a secure (HTTPS) connection — open the site over https.`
    }
    return err?.message || `Could not access ${kind.toLowerCase()}.`
  }

  async function enableCamera(on) {
    if (!roomRef.current) return setError('Not connected to the room yet.')
    try {
      await roomRef.current.localParticipant.setCameraEnabled(on)
      setCamOn(on)
      setError(null)
    } catch (err) {
      setError(mediaError('Camera', err))
    }
  }

  async function enableMic(on) {
    if (!roomRef.current) return setError('Not connected to the room yet.')
    try {
      await roomRef.current.localParticipant.setMicrophoneEnabled(on)
      setMicOn(on)
      setError(null)
    } catch (err) {
      setError(mediaError('Microphone', err))
    }
  }

  return { participants, localParticipant, camOn, micOn, enableCamera, enableMic, error }
}
