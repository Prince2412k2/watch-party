import { useEffect, useRef, useState } from 'react'
import Player from '../components/Player.tsx'
import { useAuth } from '../context/AuthContext.tsx'
import {
  getMedia,
  localSubtitles,
  localUrl,
  ready,
  type SavedMedia
} from '../offline/client.ts'
import { navigate } from '../router.ts'
import {
  DEFAULT_SUBTITLE_PREFERENCES,
  type SubtitlePreferences
} from '../types.ts'
import { useAutoHideControls } from '../analog/player/index.ts'
export default function SavedWatch({ mediaKey }: { mediaKey: string }) {
  const { user } = useAuth()
  const [record, setRecord] = useState<SavedMedia | null>(null)
  const [error, setError] = useState('')
  const [subtitle, setSubtitle] = useState(-1)
  const [preferences, setPreferences] = useState<SubtitlePreferences>(
    DEFAULT_SUBTITLE_PREFERENCES
  )
  const [playing, setPlaying] = useState(false)
  const [immersive, setImmersive] = useState(false)
  const stage = useRef<HTMLDivElement>(null)
  const chrome = useAutoHideControls({ playing })
  useEffect(() => {
    const changed = () => setImmersive(Boolean(document.fullscreenElement))
    document.addEventListener('fullscreenchange', changed)
    return () => document.removeEventListener('fullscreenchange', changed)
  }, [])
  useEffect(() => {
    let active = true
    setRecord(null)
    setError('')
    setSubtitle(-1)
    void ready()
      .then(() => getMedia(mediaKey))
      .then((file) => {
        if (!file || file.owner !== user?.userId)
          throw new Error('Saved movie not found')
        if (active) setRecord(file)
      })
      .catch((err) => {
        if (active) setError(err.message)
      })
    return () => {
      active = false
    }
  }, [mediaKey, user?.userId])
  return (
    <div
      ref={stage}
      style={{ position: 'fixed', inset: 0, background: '#000' }}
      onPointerMove={() => chrome.note()}
      onClick={() => chrome.note()}
    >
      {record && (
        <Player
          standalone
          hlsUrl={localUrl(record)}
          mediaItemId={record.itemId}
          visible={chrome.visible}
          immersive={immersive}
          onPlayingChange={setPlaying}
          onHoldChrome={chrome.hold}
          onReleaseChrome={chrome.release}
          playback={{
            offlineKey: record.key,
            mediaSourceId: record.sourceId,
            selectedAudioIndex: record.audioIndex,
            subtitleStreams: localSubtitles(record),
            selectedSubtitleIndex: subtitle
          }}
          subtitlePreferences={preferences}
          onSetSubtitlePreferences={setPreferences}
          onSetPlaybackTracks={(tracks) => {
            if (tracks.subtitleStreamIndex != null)
              setSubtitle(tracks.subtitleStreamIndex)
          }}
          enterImmersive={() => {
            void stage.current?.requestFullscreen?.().catch(() => {})
          }}
          exitImmersive={() => {
            void document.exitFullscreen?.().catch(() => {})
          }}
        />
      )}
      <button
        onClick={() => navigate('/saved')}
        style={{
          position: 'absolute',
          top: 'max(16px,env(safe-area-inset-top))',
          left: 16,
          zIndex: 50,
          color: 'white',
          background: 'transparent',
          border: 0,
          padding: 12,
          display: chrome.visible ? 'block' : 'none'
        }}
      >
        ← {record?.title || 'Saved movies'}
      </button>
      {error && (
        <p role="alert" style={{ color: 'white', padding: 60 }}>
          {error}
        </p>
      )}
    </div>
  )
}
