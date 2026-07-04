import { useEffect, useRef } from 'react'

const COLORS = ['#0A84FF','#FF9F0A','#30D158','#BF5AF2','#FF6482','#64D2FF']
function colorFor(name = '') {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffffffff
  return COLORS[Math.abs(h) % COLORS.length]
}

function initials(name = '') {
  return name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2) || '?'
}

export default function CameraTile({ participant, isLocal, isHost, onHide, onRemove }) {
  const videoRef = useRef(null)
  const audioRef = useRef(null)
  const hasVideo = !!participant.videoTrack

  useEffect(() => {
    if (participant.videoTrack && videoRef.current) {
      participant.videoTrack.attach(videoRef.current)
      return () => participant.videoTrack.detach(videoRef.current)
    }
  }, [participant.videoTrack])

  useEffect(() => {
    if (participant.audioTrack && audioRef.current && !isLocal) {
      participant.audioTrack.attach(audioRef.current)
      return () => participant.audioTrack.detach(audioRef.current)
    }
  }, [participant.audioTrack, isLocal])

  const color = colorFor(participant.name)
  const ini = initials(participant.name)
  const speaking = participant.isSpeaking
  const muted = !participant.audioTrack

  return (
    <div style={{
      position: 'absolute', inset: 0, borderRadius: 17, overflow: 'hidden',
    }}>
      {/* Video or avatar */}
      {hasVideo
        ? <video ref={videoRef} autoPlay muted={isLocal} playsInline style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        : (
          <div style={{
            width: '100%', height: '100%',
            background: `color-mix(in srgb, ${color} 45%, #0c1322)`,
            display: 'grid', placeItems: 'center',
          }}>
            <span style={{ fontSize: 28, fontWeight: 700, color: 'rgba(255,255,255,.3)' }}>{ini}</span>
          </div>
        )
      }
      {!isLocal && <audio ref={audioRef} autoPlay />}

      {/* Gradient overlay */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(180deg, rgba(0,0,0,.25) 0%, transparent 30%, transparent 60%, rgba(0,0,0,.55))',
      }} />

      {/* Speaking ring */}
      {speaking && (
        <div style={{
          position: 'absolute', inset: -2, borderRadius: 19,
          border: '2px solid var(--green)',
          boxShadow: '0 0 0 3px rgba(48,209,88,.2)',
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
          <div className="speak-bars"><span/><span/><span/></div>
        )}
        <span style={{
          fontSize: 12, fontWeight: 600, color: '#fff',
          textShadow: '0 1px 4px rgba(0,0,0,.7)',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{participant.name}{isLocal ? ' (you)' : ''}</span>
      </div>
    </div>
  )
}

export { colorFor, initials }
