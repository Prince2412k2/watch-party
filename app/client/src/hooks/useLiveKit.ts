import { useCallback, useEffect, useRef, useState } from 'react'
import { Room, RoomEvent, Track } from 'livekit-client'
import { isObject } from '../guards.ts'
import { apiJson } from '../types/guards.ts'
import { createLifecycleRun, isAbortError } from './liveKitLifecycle.ts'
import { mediaErrorMessage } from '../lib/mediaError.ts'

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
  // Browsers refuse audible playback without a gesture, and a surface that
  // starts streaming on its own has not had one. Tracked so the UI can offer a
  // button instead of leaving a silent stream that looks broken.
  const [audioBlocked, setAudioBlocked] = useState(false)
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

    // One owner token for this whole connect attempt. Everything the attempt
    // creates belongs to the run, so a teardown mid-await (unmount, party
    // switch, `enabled` flip) aborts the token request and disconnects the room
    // instead of leaving a live session nobody owns — and a losing attempt can
    // never overwrite the winner's roomRef. See liveKitLifecycle.ts.
    const run = createLifecycleRun<Room>({
      // Disconnecting a room that never finished connecting can reject; that is
      // still a successful teardown, not something to report.
      dispose: room => { Promise.resolve(room.disconnect()).catch(() => {}) },
    })

    async function connect() {
      try {
        const res = await fetch(`/api/livekit/token?partyId=${partyId}`, { credentials: 'include', signal: run.signal })
        if (!res.ok) throw new Error('Failed to get LiveKit token')
        const payload = await apiJson(res)
        if (run.cancelled) return
        if (!isLiveKitConnection(payload)) throw new Error('LiveKit returned invalid connection details')
        const { token, url, iceServers } = payload

        const room = new Room({
          adaptiveStream: true,
          dynacast: true,
          ...(iceServers ? { rtcConfig: { iceServers } } : {}),
        })
        // Torn down while the token was in flight: adopt() disposes the room it
        // was handed and we touch nothing else — no connect, no roomRef write.
        if (!run.adopt(room)) return
        roomRef.current = room

        function refresh() {
          if (run.cancelled) return
          const remotes = [...room.remoteParticipants.values()]

          const parts = remotes
            .map(p => ({
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
          .on(RoomEvent.AudioPlaybackStatusChanged, () => {
            if (!run.cancelled) setAudioBlocked(!room.canPlaybackAudio)
          })

        await room.connect(url, token)
        // Cancelled during connect: run.cancel() has already disconnected this
        // room, so publishing its state would describe a dead session.
        if (run.cancelled) return
        setAudioBlocked(!room.canPlaybackAudio)
        refresh()
      } catch (err) {
        // An aborted token request is our own teardown, not a failure to report.
        if (run.cancelled || isAbortError(err)) return
        flagError(err instanceof Error ? err.message : String(err))
      }
    }

    connect()
    return () => {
      const owned = run.resource
      run.cancel()
      // Only clear the ref if it still points at THIS run's room; a newer run
      // may already own it.
      if (roomRef.current === owned) roomRef.current = null
      // A new party means a new room: nothing about the old one's participants
      // or our own publish state survives the switch.
      setParticipants([])
      setLocalParticipant(null)
      setCamOn(false)
      setMicOn(false)
      setAudioBlocked(false)
    }
  }, [partyId, enabled, flagError])

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

  function mediaError(kind: 'Camera' | 'Microphone', err: unknown) {
    return mediaErrorMessage(kind, err, { secureContext: window.isSecureContext })
  }

  // Both return whether the device actually changed state, so a caller that
  // wraps the toggle (the player's authoring guard) can tell a real failure from
  // a no-op instead of assuming success.
  async function enableCamera(on: boolean): Promise<boolean> {
    const room = roomRef.current
    if (!room) { flagError('Not connected to the room yet.'); return false }
    try {
      await room.localParticipant.setCameraEnabled(on)
      setCamOn(on)
      flagError(null)
      return true
    } catch (err) {
      flagError(mediaError('Camera', err))
      return false
    }
  }

  async function enableMic(on: boolean): Promise<boolean> {
    const room = roomRef.current
    if (!room) { flagError('Not connected to the room yet.'); return false }
    try {
      await room.localParticipant.setMicrophoneEnabled(on, MIC_CAPTURE)
      setMicOn(on)
      flagError(null)
      return true
    } catch (err) {
      flagError(mediaError('Microphone', err))
      return false
    }
  }

  // Must be called from a real user gesture — that is the whole point of it.
  // Resolves either way; a rejection just means the browser still refuses.
  async function startAudio() {
    if (!roomRef.current) return
    try {
      await roomRef.current.startAudio()
      setAudioBlocked(!roomRef.current.canPlaybackAudio)
    } catch {
      setAudioBlocked(true)
    }
  }

  return {
    participants, localParticipant, camOn, micOn, enableCamera, enableMic, error,
    audioBlocked, startAudio,
    // Lets a wrapper around enableCamera/enableMic (the player's authoring
    // guard) push its own failure into the SAME visible banner instead of
    // dropping it on the floor.
    reportError: flagError,
  }
}

interface LiveKitConnection {
  token: string
  url: string
  iceServers?: RTCIceServer[]
}

function isIceServer(value: unknown): value is RTCIceServer {
  if (!isObject(value)) return false
  const urlsValid = typeof value.urls === 'string' ||
    (Array.isArray(value.urls) && value.urls.length > 0 && value.urls.every(url => typeof url === 'string'))
  return urlsValid && (value.username === undefined || typeof value.username === 'string') &&
    (value.credential === undefined || typeof value.credential === 'string')
}

function isLiveKitConnection(value: unknown): value is LiveKitConnection {
  return isObject(value) && typeof value.token === 'string' && value.token.length > 0 &&
    typeof value.url === 'string' && /^wss?:\/\//.test(value.url) &&
    (value.iceServers === undefined || (Array.isArray(value.iceServers) && value.iceServers.every(isIceServer)))
}
