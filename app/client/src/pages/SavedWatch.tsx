import { useEffect, useRef, useState } from 'react'
import Player, { type PlayerProps } from '../components/Player.tsx'
import RoomControls from '../components/RoomControls.tsx'
import CameraGrid from '../components/CameraGrid.tsx'
import Chat from '../components/Chat.tsx'
import { MobileCameraStrip, ChatSheet } from './Party.tsx'
import { useParty } from '../context/PartyContext.tsx'
import { useLiveKit } from '../hooks/useLiveKit.ts'
import { useSocket } from '../hooks/useSocket.ts'
import { usePhone } from '../hooks/useIsMobile.ts'
import { useAuth } from '../context/AuthContext.tsx'
import {
  getMedia,
  localSubtitles,
  playbackSource,
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
  const party = useParty()
  const { socket } = useSocket()
  const phone = usePhone()
  const [roomId, setRoomId] = useState<string>()
  const sharing = !!roomId && party.session?.id === roomId
  const lk = useLiveKit({ partyId: roomId, enabled: sharing })
  const seekBridge =
    useRef<NonNullable<PlayerProps['seekBridgeRef']>['current']>(null)
  const joining = useRef(false)
  const [pendingShare, setPendingShare] = useState<'camera' | 'microphone'>()
  const removedCameras = useRef(new Set<string>())
  const [record, setRecord] = useState<SavedMedia | null>(null)
  const [url, setUrl] = useState('')
  const [error, setError] = useState('')
  const [subtitle, setSubtitle] = useState(-1)
  const [preferences, setPreferences] = useState<SubtitlePreferences>(
    DEFAULT_SUBTITLE_PREFERENCES
  )
  const [playing, setPlaying] = useState(false)
  const stage = useRef<HTMLDivElement>(null)
  const chrome = useAutoHideControls({ playing })
  const toggleShare = async (kind: 'camera' | 'microphone') => {
    if (!record || joining.current) return
    if (sharing) {
      const toggle = () =>
        kind === 'camera' ? lk.enableCamera(!lk.camOn) : lk.enableMic(!lk.micOn)
      try {
        await (seekBridge.current?.guardToggle(toggle) ?? toggle())
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Could not share media')
      }
      return
    }
    joining.current = true
    setError('')
    try {
      const video =
        stage.current?.querySelector<HTMLVideoElement>('.watch-video')
      const id = await party.createParty(record.itemId, {
        mediaSourceId: record.sourceId,
        audioStreamIndex: record.audioIndex,
        resumePositionTicks: Math.round((video?.currentTime ?? 0) * 10_000_000)
      })
      // Room creation can take seconds. Publish the CURRENT position and pause
      // state before attaching sync; keep the same mounted video and URL.
      await new Promise<void>((resolve, reject) => {
        socket.timeout(10000).emit(
          video?.paused ? 'sync:pause' : 'sync:play',
          {
            positionTicks: Math.round((video?.currentTime ?? 0) * 10_000_000)
          },
          (timeout: Error | null, result: { error?: string }) => {
            if (timeout || result?.error)
              reject(timeout || new Error(result.error))
            else resolve()
          }
        )
      })
      setRoomId(id)
      setPendingShare(kind)
    } catch (err) {
      setError(
        err instanceof Error ? err.message : 'Could not start the watch party'
      )
    } finally {
      joining.current = false
    }
  }
  useEffect(() => {
    if (!pendingShare || !lk.localParticipant) return
    setPendingShare(undefined)
    const toggle = () =>
      pendingShare === 'camera' ? lk.enableCamera(true) : lk.enableMic(true)
    void (seekBridge.current?.guardToggle(toggle) ?? toggle()).catch((err) =>
      setError(err.message)
    )
  }, [pendingShare, lk.localParticipant])
  useEffect(() => {
    // An explicit new-title/lobby selection belongs to the regular room route.
    if (
      sharing &&
      party.session &&
      (party.session.stage !== 'watching' ||
        party.session.mediaItemId !== record?.itemId)
    )
      navigate(`/party/${roomId}`)
  }, [
    sharing,
    party.session?.stage,
    party.session?.mediaItemId,
    record?.itemId,
    roomId
  ])
  const cameraProps = {
    localParticipant: lk.localParticipant,
    participants: lk.participants,
    isHost: party.role === 'host',
    removedCameras: removedCameras.current,
    hideSelf: !lk.camOn,
    onRemove: (identity: string) => party.removeCamera(identity)
  }
  useEffect(() => {
    let active = true
    let release = () => {}
    setRecord(null)
    setError('')
    setSubtitle(-1)
    void ready()
      .then(() => getMedia(mediaKey))
      .then(async (file) => {
        if (!file || file.owner !== user?.userId)
          throw new Error('Saved movie not found')
        const source = await playbackSource(file)
        release = source.release
        if (active) {
          setUrl(source.url)
          setRecord(file)
        } else release()
      })
      .catch((err) => {
        if (active) setError(err.message)
      })
    return () => {
      active = false
      release()
    }
  }, [mediaKey, user?.userId])
  return (
    <div
      ref={stage}
      style={{
        position: 'fixed',
        inset: '0 0 auto',
        height: 'var(--app-vh, 100dvh)',
        overflow: 'hidden',
        background: '#000'
      }}
      onPointerMove={(event) => {
        if (event.pointerType === 'mouse') chrome.note()
      }}
      onClick={() => chrome.toggle()}
    >
      {record && (
        <Player
          standalone={!sharing}
          phone={phone}
          isHost={sharing && party.role === 'host'}
          collaborativeControl={sharing && party.session?.collaborativeControl}
          syncMode={sharing ? party.session?.syncMode : undefined}
          seekBridgeRef={seekBridge}
          camOn={lk.camOn}
          micOn={lk.micOn}
          hlsUrl={url}
          mediaItemId={record.itemId}
          visible={chrome.visible}
          onToggleCam={
            navigator.onLine && !user?.offline
              ? () => {
                  void toggleShare('camera')
                }
              : undefined
          }
          onToggleMic={
            navigator.onLine && !user?.offline
              ? () => {
                  void toggleShare('microphone')
                }
              : undefined
          }
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
        />
      )}
      {sharing && (
        <>
          <RoomControls
            stage="watching"
            mediaTitle={record?.title}
            phone={phone}
            visible={chrome.visible}
            onOpenChat={() => party.openChat(true)}
            chatOpen={party.chatOpen}
            onHoldChrome={chrome.hold}
            onReleaseChrome={chrome.release}
          />
          {(lk.camOn || lk.participants.some((p) => !!p.videoTrack)) &&
            (phone ? (
              <MobileCameraStrip {...cameraProps} visible={chrome.visible} />
            ) : (
              <CameraGrid {...cameraProps} />
            ))}
          {party.chatOpen && (phone ? <ChatSheet /> : <Chat top={76} />)}
        </>
      )}
      {!sharing && (
        <button
          onClick={(event) => {
            event.stopPropagation()
            navigate('/saved')
          }}
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
      )}
      {(error || lk.error) && (
        <p role="alert" style={{ color: 'white', padding: 60 }}>
          {error || lk.error}
        </p>
      )}
    </div>
  )
}
