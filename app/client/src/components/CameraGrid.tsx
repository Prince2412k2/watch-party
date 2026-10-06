import { useEffect, useRef, useState } from 'react'
import { Rnd } from 'react-rnd'
import CameraTile from './CameraTile.tsx'
import CollapsedFace from './CollapsedFace.tsx'
import { usePlayerPresentation } from './PlayerPresentation.tsx'
import { RoomButton, DeviceGlyph } from './RoomControls.tsx'
import { useParty } from '../context/PartyContext.tsx'

type CameraParticipant = {
  identity: string
  name?: string
  videoTrack?: unknown
  audioTrack?: unknown
  isLocal?: boolean
  isSpeaking?: boolean
}
type Frame = { x: number; y: number; width: number; collapsed?: boolean }

export default function CameraGrid({
  localParticipant,
  participants = [],
  removedCameras = new Set(),
  hideSelf,
  chatOpen,
  controlsVisible = true,
  isHost: _isHost,
  onRemove: _onRemove,
  micOn,
  camOn,
  onToggleMic,
  onToggleCam,
  onToggleHideSelf,
}: {
  localParticipant?: CameraParticipant | null
  participants?: CameraParticipant[]
  isHost?: boolean
  micOn?: boolean
  camOn?: boolean
  onToggleMic?: () => unknown
  onToggleCam?: () => unknown
  onToggleHideSelf?: () => void
  removedCameras?: Set<string>
  onRemove?: (id: string) => void
  hideSelf?: boolean
  chatOpen?: boolean
  controlsVisible?: boolean
} = {}) {
  const party = useParty()
  const presentation = usePlayerPresentation()
  const boundsRef = useRef<HTMLDivElement>(null)
  const [bounds, setBounds] = useState({ width: 0, height: 0 })
  const [frames, setFrames] = useState<Record<string, Frame>>({})
  const dragged = useRef(false)
  useEffect(() => {
    const element = boundsRef.current
    if (!element) return
    const resize = () =>
      setBounds({ width: element.clientWidth, height: element.clientHeight })
    resize()
    const observer = new ResizeObserver(resize)
    observer.observe(element)
    return () => observer.disconnect()
  }, [])
  const all = [
    ...(localParticipant && !hideSelf
      ? [{ ...localParticipant, isLocal: true }]
      : []),
    ...participants.filter(
      (p) =>
        p.identity !== localParticipant?.identity &&
        !removedCameras.has(p.identity)
    ),
  ].filter((p) => !!p.videoTrack)
  const tileWidth = Math.min(168, bounds.width, (bounds.height * 4) / 3)
  const tileHeight = (tileWidth * 3) / 4
  const capacity =
    Math.max(1, Math.floor((bounds.width + 8) / (tileWidth + 8))) *
    Math.max(1, Math.floor((bounds.height - 16) / (tileHeight + 8)))
  const overflow = all.length > capacity
  const update = (id: string, frame: Frame) =>
    setFrames((previous) => ({ ...previous, [id]: frame }))
  return (
    <div
      ref={boundsRef}
      className="native-camera-layer"
      data-controls={controlsVisible && !presentation.floating}
      data-chat={chatOpen ?? party.chatOpen}
    >
      <div
        className={overflow ? 'native-camera-overflow' : undefined}
        style={
          overflow
            ? { width: Math.max(60, tileWidth), height: '100%' }
            : { position: 'absolute', inset: 0 }
        }
      >
        <div
          style={
            overflow
              ? {
                  position: 'relative',
                  height: all.length * (tileHeight + 8),
                  width: '100%',
                }
              : { position: 'absolute', inset: 0 }
          }
        >
          {bounds.width > 0 &&
            all.map((participant, index) => {
              if (bounds.width < 44 || bounds.height < 44) return null
              const defaultWidth = Math.min(
                168,
                bounds.width,
                (bounds.height * 4) / 3
              )
              const rows = Math.max(
                1,
                Math.floor(
                  (bounds.height - 24 + 8) / ((defaultWidth * 3) / 4 + 8)
                )
              )
              const frame = frames[participant.identity] ?? {
                x:
                  bounds.width -
                  defaultWidth -
                  12 -
                  Math.floor(index / rows) * (defaultWidth + 8),
                y:
                  bounds.height -
                  12 -
                  (((index % rows) + 1) * defaultWidth * 3) / 4 -
                  (index % rows) * 8,
                width: defaultWidth,
              }
              const collapsed =
                frame.collapsed || bounds.width < 112 || bounds.height < 84
              const width = collapsed
                ? Math.min(60, bounds.width, bounds.height)
                : Math.min(frame.width, bounds.width, (bounds.height * 4) / 3)
              const height = collapsed
                ? Math.min(60, bounds.width, bounds.height)
                : (width * 3) / 4
              const x = Math.max(0, Math.min(frame.x, bounds.width - width))
              const y = Math.max(0, Math.min(frame.y, bounds.height - height))
              const toggle = () =>
                update(participant.identity, {
                  ...frame,
                  x,
                  y,
                  collapsed: !frame.collapsed,
                })
              const snap = (value: number, max: number) =>
                value < 30
                  ? Math.min(12, max)
                  : value > max - 30
                    ? Math.max(0, max - 12)
                    : value
              return (
                <Rnd
                  key={participant.identity}
                  size={{ width, height }}
                  position={
                    overflow ? { x: 0, y: index * (tileHeight + 8) } : { x, y }
                  }
                  disableDragging={overflow}
                  bounds="parent"
                  lockAspectRatio={collapsed ? 1 : 4 / 3}
                  minWidth={Math.min(
                    collapsed ? Math.min(60, bounds.width, bounds.height) : 112,
                    bounds.width,
                    (bounds.height * 4) / 3
                  )}
                  maxWidth={Math.min(bounds.width, (bounds.height * 4) / 3)}
                  enableResizing={
                    collapsed || overflow ? false : { bottomRight: true }
                  }
                  cancel="button"
                  className={`native-camera${collapsed ? ' is-collapsed' : ''}`}
                  data-speaking={!!participant.isSpeaking}
                  onDragStart={() => {
                    dragged.current = false
                  }}
                  onDrag={() => {
                    dragged.current = true
                  }}
                  onDragStop={(_, data) =>
                    update(participant.identity, {
                      ...frame,
                      x: snap(data.x, bounds.width - width),
                      y: snap(data.y, bounds.height - height),
                    })
                  }
                  onResizeStop={(_, __, element, ___, position) =>
                    update(participant.identity, {
                      ...frame,
                      ...position,
                      width: element.offsetWidth,
                    })
                  }
                >
                  <div
                    className="native-camera-picture"
                    onClick={(event) => {
                      event.stopPropagation()
                      if (collapsed && !dragged.current) toggle()
                    }}
                  >
                    <div
                      style={{
                        position: 'absolute',
                        inset: 0,
                        opacity: collapsed ? 0 : 1,
                      }}
                    >
                      <CameraTile
                        participant={participant}
                        isLocal={participant.isLocal}
                      />
                    </div>
                    {collapsed ? (
                      <>
                        <CollapsedFace
                          identity={participant.identity}
                          name={participant.name}
                        />
                        <button
                          className="native-camera-expand"
                          aria-label={`Expand ${participant.name || 'camera'}`}
                          onClick={(event) => {
                            event.stopPropagation()
                            toggle()
                          }}
                        />
                      </>
                    ) : (
                      <button
                        className="native-camera-collapse"
                        aria-label={`Collapse ${participant.name || 'camera'}`}
                        onClick={(event) => {
                          event.stopPropagation()
                          toggle()
                        }}
                      >
                        −
                      </button>
                    )}
                    {!collapsed && participant.isLocal && (
                      <div className="native-camera-local-actions">
                        {onToggleMic && (
                          <RoomButton
                            label={
                              micOn
                                ? 'Mute my microphone'
                                : 'Enable my microphone'
                            }
                            onClick={() => {
                              void onToggleMic()
                            }}
                          >
                            <DeviceGlyph kind="mic" off={!micOn} />
                          </RoomButton>
                        )}
                        {onToggleCam && (
                          <RoomButton
                            label={
                              camOn ? 'Stop my camera' : 'Enable my camera'
                            }
                            onClick={() => {
                              void onToggleCam()
                            }}
                          >
                            <DeviceGlyph kind="camera" off={!camOn} />
                          </RoomButton>
                        )}
                        {onToggleHideSelf && (
                          <RoomButton
                            label="Hide my camera tile"
                            onClick={onToggleHideSelf}
                          >
                            <DeviceGlyph kind="eye" />
                          </RoomButton>
                        )}
                      </div>
                    )}
                  </div>
                </Rnd>
              )
            })}
        </div>
      </div>
    </div>
  )
}
