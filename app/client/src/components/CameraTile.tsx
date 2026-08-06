import { useEffect, useRef } from 'react'
import Avatar from './Avatar.tsx'
import { useMemberAvatar } from '../hooks/useMemberAvatar.ts'

interface AttachableTrack {
  attach: (element: HTMLMediaElement) => unknown
  detach: (element: HTMLMediaElement) => unknown
}

interface CameraParticipant {
  /** LiveKit identity, which is the Jellyfin user id — so it seeds the avatar. */
  identity: string
  name?: string
  videoTrack?: unknown
  audioTrack?: unknown
  isSpeaking?: boolean
}

function isAttachableTrack(value: unknown): value is AttachableTrack {
  return typeof value === 'object' && value !== null
    && 'attach' in value && typeof value.attach === 'function'
    && 'detach' in value && typeof value.detach === 'function'
}

interface CameraTileProps {
  participant: CameraParticipant
  isLocal?: boolean
  isHost?: boolean
  onHide?: () => void
  onRemove?: () => void
}

export default function CameraTile({ participant, isLocal }: CameraTileProps) {
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const hasVideo = isAttachableTrack(participant.videoTrack)
  const avatar = useMemberAvatar(participant.identity)

  useEffect(() => {
    const track = participant.videoTrack
    const element = videoRef.current
    if (isAttachableTrack(track) && element) {
      track.attach(element)
      return () => { track.detach(element) }
    }
  }, [participant.videoTrack])

  useEffect(() => {
    const track = participant.audioTrack
    const element = audioRef.current
    if (isAttachableTrack(track) && element && !isLocal) {
      track.attach(element)
      return () => { track.detach(element) }
    }
  }, [participant.audioTrack, isLocal])

  const speaking = participant.isSpeaking
  const muted = !participant.audioTrack

  return (
    <div style={{
      position: 'absolute', inset: 0, borderRadius: 12, overflow: 'hidden',
    }}>
      {/* Live video always wins; the avatar is what a camera-off tile shows. */}
      {hasVideo
        ? <video ref={videoRef} autoPlay muted={isLocal} playsInline style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        : (
          <div style={{
            width: '100%', height: '100%',
            background: 'var(--glass2, rgba(255,255,255,.04))',
            display: 'grid', placeItems: 'center',
          }}>
            <Avatar
              userId={participant.identity}
              name={participant.name}
              config={avatar}
              // Fills the tile at whatever aspect ratio it has, the way footage would.
              size="100%"
              style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            />
          </div>
        )
      }
      {!isLocal && <audio ref={audioRef} autoPlay />}

      {/* Black-alpha legibility scrim (the one allowed gradient) so the name
          row stays readable over any footage */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(180deg, rgba(0,0,0,.2) 0%, transparent 30%, transparent 60%, rgba(0,0,0,.55) 100%)',
        pointerEvents: 'none',
      }} />

      {/* Active-speaker indicator: a single thin muted-red ring, not a boxed
          colored border around the whole tile */}
      {speaking && (
        <div style={{
          position: 'absolute', inset: 0, borderRadius: 12,
          boxShadow: 'inset 0 0 0 2px var(--live)',
          pointerEvents: 'none',
        }} />
      )}

      {/* Bottom bar */}
      <div style={{
        position: 'absolute', left: 9, bottom: 8, right: 9,
        display: 'flex', alignItems: 'center', gap: 5, pointerEvents: 'none',
      }}>
        {muted && (
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--red)" strokeWidth="2"><path d="m2 2 20 20M9 9v3a3 3 0 0 0 5.1 2.1M12 2a3 3 0 0 1 3 3v6"/><path d="M19 10v2a7 7 0 0 1-.7 3"/></svg>
        )}
        {speaking && (
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 2, height: 10 }}>
            {[0, 1, 2].map(i => (
              <span key={i} style={{
                width: 2.5, height: '100%', borderRadius: 2, background: 'var(--text)',
                opacity: .85, transformOrigin: 'bottom', animation: `bar .6s ease-in-out ${i * .2}s infinite`,
              }} />
            ))}
          </div>
        )}
        <span style={{
          fontSize: 12, fontWeight: 600, color: 'var(--text)',
          textShadow: '0 1px 4px rgba(0,0,0,.7)',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{participant.name}{isLocal ? ' (you)' : ''}</span>
      </div>
    </div>
  )
}
