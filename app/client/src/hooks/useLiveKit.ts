import { useCallback, useEffect, useRef, useState } from 'react'
import { Room, RoomEvent, Track } from 'livekit-client'

export interface LiveKitParticipantView {
  identity: string
  name: string
  videoTrack: unknown | null
  audioTrack: unknown | null
  isSpeaking: boolean
}

export function useLiveKit({ partyId, enabled = true }: { partyId?: string; enabled?: boolean } = {}) {
  const roomRef = useRef<Room | null>(null)
  const [participants, setParticipants] = useState<LiveKitParticipantView[]>([])
  const [localParticipant, setLocalParticipant] = useState<LiveKitParticipantView | null>(null)
  const [camOn, setCamOn] = useState(false)
  const [micOn, setMicOn] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const errorTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Surface a transient error banner that dismisses itself after ~4.5s so a
  // one-off camera/mic hiccup doesn't leave a permanent bar over the movie.
  // Passing null clears it (and any pending timer) immediately.
  const flagError = useCallback((msg: string | null) => {
    if (errorTimer.current) clearTimeout(errorTimer.current)
    setError(msg ?? null)
    if (msg) errorTimer.current = setTimeout(() => setError(null), 4500)
  }, [])
  useEffect(() => () => { if (errorTimer.current) clearTimeout(errorTimer.current) }, [])

  useEffect(() => {
    if (!partyId || !enabled) return

    let room: Room | null = null
    let cancelled = false

    async function connect() {
      try {
        const res = await fetch(`/api/livekit/token?partyId=${partyId}`, { credentials: 'include' })
        if (!res.ok) throw new Error('Failed to get LiveKit token')
        const { token, url, iceServers } = await res.json()

        room = new Room({
          adaptiveStream: true,
          dynacast: true,
          ...(iceServers ? { rtcConfig: { iceServers } } : {}),
        })
        roomRef.current = room

        function refresh() {
          if (cancelled) return
          if (!room) return
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
        if (!cancelled) flagError(err instanceof Error ? err.message : String(err))
      }
    }

    connect()
    return () => {
      cancelled = true
      room?.disconnect()
      roomRef.current = null
    }
  }, [partyId, enabled])

  // WebRTC audio processing applied to the PUBLISHED mic track. Echo
  // cancellation is the backstop against the "mic picks up movie audio → echo"
  // loop for anyone listening on speakers; noise suppression + auto gain keep
  // levels clean. Passed as AudioCaptureOptions (getUserMedia constraints) so
  // they're baked into the LocalAudioTrack LiveKit actually creates + publishes,
  // not merely requested at some higher layer.
  const MIC_CAPTURE = {
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
  }

  function mediaError(kind: string, err: unknown) {
    // getUserMedia only works in a secure context (https or localhost).
    if (!window.isSecureContext) {
      return `${kind} needs a secure (HTTPS) connection — open the site over https.`
    }
    return err instanceof Error ? err.message : `Could not access ${kind.toLowerCase()}.`
  }

  async function enableCamera(on: boolean) {
    if (!roomRef.current) return flagError('Not connected to the room yet.')
    try {
      await roomRef.current.localParticipant.setCameraEnabled(on)
      setCamOn(on)
      flagError(null)
    } catch (err) {
      flagError(mediaError('Camera', err))
    }
  }

  async function enableMic(on: boolean) {
    if (!roomRef.current) return flagError('Not connected to the room yet.')
    try {
      await roomRef.current.localParticipant.setMicrophoneEnabled(on, MIC_CAPTURE)
      setMicOn(on)
      flagError(null)
    } catch (err) {
      flagError(mediaError('Microphone', err))
    }
  }

  return { participants, localParticipant, camOn, micOn, enableCamera, enableMic, error }
}
