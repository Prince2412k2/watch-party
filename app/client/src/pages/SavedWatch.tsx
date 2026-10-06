import { useEffect, useRef, useState } from 'react'
import Player, { type PlayerProps } from '../components/Player.tsx'
import RoomControls, {
  DeviceRail,
  RoomButton
} from '../components/RoomControls.tsx'
import {
  RoomOverlay,
  usePlayerPresentation,
  useRoomConnection
} from '../components/PlayerPresentation.tsx'
import CameraGrid from '../components/CameraGrid.tsx'
import Chat from '../components/Chat.tsx'
import { useParty } from '../context/PartyContext.tsx'
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
  const presentation = usePlayerPresentation()
  const [hideSelf, setHideSelf] = useState(false)
  const [roomId, setRoomId] = useState<string>()
  const sharing = !!roomId && party.session?.id === roomId
  const lk = useRoomConnection()
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
  useEffect(() => {
    if (!party.chatOpen) return
    chrome.hold('chat')
    return () => chrome.release('chat')
  }, [party.chatOpen, chrome.hold, chrome.release])
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
    hideSelf: hideSelf || !lk.camOn,
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
        position: 'absolute',
        inset: 0,
        height: '100%',
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
          visible={chrome.visible && !presentation.floating}
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
      <RoomOverlay>
        {sharing ? (
          <>
            <RoomControls
              stage="watching"
              mediaTitle={record?.title}
              phone={phone}
              visible={chrome.visible && !presentation.floating}
              micOn={lk.micOn}
              camOn={lk.camOn}
              onToggleMic={() => toggleShare('microphone')}
              onToggleCam={() => toggleShare('camera')}
              hideSelf={hideSelf}
              onToggleHideSelf={() => setHideSelf((value) => !value)}
              onReconnect={lk.reconnect}
              onSetMic={(on) =>
                seekBridge.current?.guardToggle(() => lk.enableMic(on)) ??
                lk.enableMic(on)
              }
              onOpenChat={() => party.openChat(true)}
              chatOpen={party.chatOpen}
              onHoldChrome={chrome.hold}
              onReleaseChrome={chrome.release}
            />
            <CameraGrid
              {...cameraProps}
              chatOpen={party.chatOpen}
              controlsVisible={chrome.visible && !presentation.floating}
              micOn={lk.micOn}
              camOn={lk.camOn}
              onToggleMic={() => toggleShare('microphone')}
              onToggleCam={() => toggleShare('camera')}
              onToggleHideSelf={() => setHideSelf(true)}
            />
            <Chat />
          </>
        ) : (
          <>
            {!presentation.floating && (
              <div
                className="native-player-title"
                data-visible={chrome.visible}
              >
                <RoomButton
                  label="Minimize movie"
                  icon="back"
                  onClick={presentation.minimize}
                />
                <span>{record?.title || 'Saved movies'}</span>
              </div>
            )}
            {navigator.onLine && !user?.offline && (
              <DeviceRail
                micOn={lk.micOn}
                camOn={lk.camOn}
                onToggleMic={() => toggleShare('microphone')}
                onToggleCam={() => toggleShare('camera')}
                visible={chrome.visible && !presentation.floating}
              />
            )}
          </>
        )}
      </RoomOverlay>
      {error && (
        <p role="alert" style={{ color: 'white', padding: 60 }}>
          {error}
        </p>
      )}
    </div>
  )
}
