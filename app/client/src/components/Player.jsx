import { useEffect, useRef, useState } from 'react'
import { createPlayer } from '@videojs/react'
import { VideoSkin, videoFeatures } from '@videojs/react/video'
import { HlsVideo } from '@videojs/react/media/hls-video'
import '@videojs/react/video/skin.css'
import { useSyncPlay } from '../hooks/useSyncPlay.js'

const VPlayer = createPlayer({ features: videoFeatures })

export default function Player({
  hlsUrl, isHost, collaborativeControl, onStruggle,
  onToggleMic, onToggleCam, micOn, camOn,
  onToggleLayout, onToggleChat, chatOpen, layoutMode,
}) {
  const canControl = isHost || collaborativeControl

  return (
    <VPlayer.Provider>
      {/* isolate so the skin's internal z-indexed layers don't paint over the
          camera tiles / chat that render as siblings of this player */}
      <div style={{ position: 'relative', width: '100%', height: '100%', background: '#000', isolation: 'isolate' }}>
        {/* Skin is interactive only for controllers; guests can't drive transport */}
        <VideoSkin style={{ width: '100%', height: '100%', pointerEvents: canControl ? 'auto' : 'none' }}>
          {/* Guests start muted so synced play() autoplays without a gesture;
              they can unmute from the AV controls. */}
          <HlsVideo src={hlsUrl} playsInline preload="auto" muted={!canControl} style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
        </VideoSkin>

        {/* Route all playback through SyncPlay */}
        <SyncBridge isHost={isHost} collaborativeControl={collaborativeControl} onStruggle={onStruggle} />

        {!canControl && (
          <div style={{
            position: 'absolute', bottom: 18, left: '50%', transform: 'translateX(-50%)',
            zIndex: 20, display: 'flex', alignItems: 'center', gap: 7,
            padding: '7px 13px', borderRadius: 999,
            background: 'rgba(18,20,26,.86)', backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
            border: '1px solid var(--stroke)', color: 'var(--text2)',
            fontSize: 12.5, fontWeight: 600, pointerEvents: 'none',
          }}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>
            Host controls playback
          </div>
        )}

        {/* App AV controls — separate from video transport */}
        <AVControls
          micOn={micOn} camOn={camOn}
          onToggleMic={onToggleMic} onToggleCam={onToggleCam}
          onToggleLayout={onToggleLayout} layoutMode={layoutMode}
          onToggleChat={onToggleChat} chatOpen={chatOpen}
        />
      </div>
    </VPlayer.Provider>
  )
}

// ── Bridges the videojs Media instance into our SyncPlay protocol ────────────
function SyncBridge({ isHost, collaborativeControl, onStruggle }) {
  const media = VPlayer.useMedia()
  const mediaRef = useRef(null)
  mediaRef.current = media

  const {
    canControl, applyingRef, notifyUserSeeking,
    requestPlay, requestPause, requestSeek,
    TICKS_PER_SECOND,
  } = useSyncPlay({ playerRef: mediaRef, isHost, collaborativeControl, onStruggle })

  const seekTimer = useRef(null)
  const [buffering, setBuffering] = useState(false)

  // "Catching up…" for guests reflects a real stall only. We turn it on when the
  // player actually stalls ('waiting') and clear it as soon as time advances
  // again — a plain seek while playing must NOT leave the overlay stuck.
  useEffect(() => {
    if (!media || isHost) return
    const on = () => setBuffering(true)
    const off = () => setBuffering(false)
    media.addEventListener('waiting', on)
    media.addEventListener('stalled', on)
    media.addEventListener('playing', off)
    media.addEventListener('timeupdate', off)
    return () => {
      media.removeEventListener('waiting', on)
      media.removeEventListener('stalled', on)
      media.removeEventListener('playing', off)
      media.removeEventListener('timeupdate', off)
    }
  }, [media, isHost])

  // Translate this controller's UI actions into schedule-change requests.
  // Programmatic (control-loop) changes are suppressed via applyingRef.
  useEffect(() => {
    if (!media) return
    const ticks = () => Math.round((media.currentTime || 0) * TICKS_PER_SECOND)

    const onPlay   = () => { if (!applyingRef.current && canControl) requestPlay(ticks()) }
    const onPause  = () => { if (!applyingRef.current && canControl) requestPause(ticks()) }
    // Scrub start → tell the loop to stop correcting so it doesn't snap us back.
    const onSeeking = () => { if (!applyingRef.current && canControl) notifyUserSeeking() }
    // A scrubber drag fires many 'seeked' events — author only the settled one.
    const onSeeked = () => {
      if (applyingRef.current || !canControl) return
      clearTimeout(seekTimer.current)
      seekTimer.current = setTimeout(() => requestSeek(ticks()), 200)
    }

    media.addEventListener('play', onPlay)
    media.addEventListener('pause', onPause)
    media.addEventListener('seeking', onSeeking)
    media.addEventListener('seeked', onSeeked)
    return () => {
      clearTimeout(seekTimer.current)
      media.removeEventListener('play', onPlay)
      media.removeEventListener('pause', onPause)
      media.removeEventListener('seeking', onSeeking)
      media.removeEventListener('seeked', onSeeked)
    }
  }, [media, canControl, applyingRef, notifyUserSeeking, requestPlay, requestPause, requestSeek, TICKS_PER_SECOND])

  if (!buffering) return null
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 25, display: 'grid', placeItems: 'center',
      background: 'rgba(6,8,15,.55)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
        <div style={{
          width: 44, height: 44, borderRadius: '50%',
          border: '3px solid var(--stroke2)', borderTopColor: 'var(--accent)',
          animation: 'spin .9s linear infinite',
        }} />
        <span style={{ fontSize: 14, fontWeight: 600, color: 'var(--text)' }}>Catching up…</span>
      </div>
    </div>
  )
}

// ── Mic / Cam / Layout / Chat — pinned to the right edge, clear of the skin ──
function AVControls({ micOn, camOn, onToggleMic, onToggleCam, onToggleLayout, layoutMode, onToggleChat, chatOpen }) {
  const media = VPlayer.useMedia()
  const [soundOff, setSoundOff] = useState(true)

  useEffect(() => {
    if (!media) return
    const sync = () => setSoundOff(media.muted || media.volume === 0)
    sync()
    media.addEventListener('volumechange', sync)
    return () => media.removeEventListener('volumechange', sync)
  }, [media])

  function toggleSound() {
    if (!media) return
    const next = !(media.muted || media.volume === 0)
    media.muted = next
    if (!next && media.volume === 0) media.volume = 1
  }

  const btn = (active = false, danger = false) => ({
    display: 'grid', placeItems: 'center', width: 40, height: 40, borderRadius: 12,
    border: 'none', background: 'transparent', cursor: 'pointer',
    color: danger ? 'var(--red)' : active ? 'var(--accent)' : 'var(--text2)',
    transition: 'color .15s, background .15s',
  })
  return (
    <div style={{
      position: 'absolute', right: 16, top: '50%', transform: 'translateY(-50%)',
      zIndex: 18, display: 'flex', flexDirection: 'column', gap: 4, padding: 5,
      borderRadius: 16, background: 'rgba(18,20,26,.82)',
      backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
      border: '1px solid var(--stroke)', boxShadow: '0 8px 28px rgba(0,0,0,.5)',
    }}>
      <button onClick={toggleSound} style={btn(false, soundOff)} title={soundOff ? 'Unmute video' : 'Mute video'}>
        {soundOff
          ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M11 5 6 9H2v6h4l5 4zM22 9l-6 6M16 9l6 6"/></svg>
          : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M11 5 6 9H2v6h4l5 4zM15.5 8.5a5 5 0 0 1 0 7M19 5a9 9 0 0 1 0 14"/></svg>
        }
      </button>
      <div style={{ height: 1, background: 'var(--stroke)', margin: '2px 6px' }} />
      <button onClick={onToggleMic} style={btn(false, !micOn)} title={micOn ? 'Mute mic' : 'Unmute mic'}>
        {micOn
          ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></svg>
          : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M9 9v3a3 3 0 0 0 5.1 2.1M15 9.3V5a3 3 0 0 0-5.7-1.3M19 10v2a7 7 0 0 1-.7 3M12 19v3"/></svg>
        }
      </button>
      <button onClick={onToggleCam} style={btn(false, !camOn)} title={camOn ? 'Camera off' : 'Camera on'}>
        {camOn
          ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="2" y="6" width="14" height="12" rx="2"/><path d="m16 10 6-3v10l-6-3"/></svg>
          : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m2 2 20 20M16 16H4a2 2 0 0 1-2-2V8m4-2h8a2 2 0 0 1 2 2v3l4-2v8"/></svg>
        }
      </button>
      <div style={{ height: 1, background: 'var(--stroke)', margin: '2px 6px' }} />
      <button onClick={onToggleLayout} style={btn()} title="Toggle layout">
        {layoutMode === 'float'
          ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="3" y="3" width="18" height="18" rx="2"/><rect x="13" y="12" width="6" height="6" rx="1" fill="currentColor" stroke="none"/></svg>
          : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="3" y="3" width="6" height="18" rx="1.5"/><rect x="11" y="3" width="10" height="18" rx="1.5"/></svg>
        }
      </button>
      <button onClick={onToggleChat} style={btn(chatOpen)} title="Chat">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
      </button>
    </div>
  )
}
