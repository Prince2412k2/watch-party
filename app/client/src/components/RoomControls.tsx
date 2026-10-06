import { useEffect, useRef, useState, type ReactNode } from 'react'
import { useParty } from '../context/PartyContext.tsx'
import { usePlayerPresentation } from './PlayerPresentation.tsx'
import { useAuth } from '../context/AuthContext.tsx'
import { AnIcon, type AnIconName } from '../analog/icons.tsx'
import Avatar from './Avatar.tsx'

export function RoomButton({
  label,
  icon,
  children,
  onClick,
  active,
  danger,
  disabled,
}: {
  label: string
  icon?: AnIconName
  children?: ReactNode
  onClick?: () => void
  active?: boolean
  danger?: boolean
  disabled?: boolean
}) {
  return (
    <button
      className="native-room-button"
      aria-label={label}
      title={label}
      aria-pressed={active}
      data-danger={danger}
      disabled={disabled}
      onClick={(event) => {
        event.stopPropagation()
        onClick?.()
      }}
    >
      {icon ? <AnIcon name={icon} size={20} /> : children}
    </button>
  )
}

export function DeviceGlyph({
  kind,
  off = false,
}: {
  kind: 'mic' | 'camera' | 'eye'
  off?: boolean
}) {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
    >
      {kind === 'mic' ? (
        <>
          <rect x="9" y="2" width="6" height="12" rx="3" />
          <path d="M5 10v2a7 7 0 0 0 14 0v-2m-7 9v3m-4 0h8" />
        </>
      ) : kind === 'camera' ? (
        <>
          <rect x="3" y="6" width="12" height="12" rx="2" />
          <path d="m15 10 6-4v12l-6-4" />
        </>
      ) : (
        <>
          <path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z" />
          <circle cx="12" cy="12" r="3" />
        </>
      )}
      {off && <path d="M3 3 21 21" />}
    </svg>
  )
}

export function DeviceRail({
  micOn,
  camOn,
  onToggleMic,
  onToggleCam,
  hideSelf,
  onToggleHideSelf,
  visible = true,
}: {
  micOn?: boolean
  camOn?: boolean
  onToggleMic?: () => unknown
  onToggleCam?: () => unknown
  hideSelf?: boolean
  onToggleHideSelf?: () => void
  visible?: boolean
}) {
  const [busy, setBusy] = useState<string>()
  const toggle = async (kind: string, action?: () => unknown) => {
    if (busy || !action) return
    setBusy(kind)
    try {
      await action()
    } finally {
      setBusy(undefined)
    }
  }
  if (!onToggleMic && !onToggleCam) return null
  return (
    <div
      className="native-device-rail"
      data-visible={visible}
      onClick={(event) => event.stopPropagation()}
    >
      {onToggleMic && (
        <RoomButton
          label={micOn ? 'Mute microphone' : 'Share microphone'}
          danger={!micOn}
          disabled={!!busy}
          onClick={() => {
            void toggle('mic', onToggleMic)
          }}
        >
          <DeviceGlyph kind="mic" off={!micOn} />
        </RoomButton>
      )}
      {onToggleCam && (
        <RoomButton
          label={camOn ? 'Turn camera off' : 'Share camera'}
          danger={!camOn}
          disabled={!!busy}
          onClick={() => {
            void toggle('cam', onToggleCam)
          }}
        >
          <DeviceGlyph kind="camera" off={!camOn} />
        </RoomButton>
      )}
      {onToggleHideSelf && (
        <RoomButton
          label={hideSelf ? 'Show my tile' : 'Hide my tile'}
          active={hideSelf}
          onClick={onToggleHideSelf}
        >
          <DeviceGlyph kind="eye" off={hideSelf} />
        </RoomButton>
      )}
    </div>
  )
}

export default function RoomControls({
  stage,
  mediaTitle,
  visible = true,
  onOpenChat,
  chatOpen,
  micOn,
  camOn,
  onToggleMic,
  onToggleCam,
  hideSelf,
  onToggleHideSelf,
  onReconnect,
  onHoldChrome,
  onReleaseChrome,
  onSetMic,
}: {
  stage?: string
  mediaTitle?: string
  visible?: boolean
  phone?: boolean
  top?: number
  onOpenChat?: () => void
  chatOpen?: boolean
  micOn?: boolean
  camOn?: boolean
  onToggleMic?: () => unknown
  onToggleCam?: () => unknown
  hideSelf?: boolean
  onToggleHideSelf?: () => void
  onSetMic?: (enabled: boolean) => unknown
  onReconnect?: () => void
  onHoldChrome?: (reason: string) => void
  onReleaseChrome?: (reason: string) => void
  hideAllFeeds?: boolean
  onToggleHideAllFeeds?: () => void
  layoutMode?: 'float' | 'dock'
  onToggleLayout?: () => void
}) {
  const party = useParty()
  const { user } = useAuth()
  const presentation = usePlayerPresentation()
  const [tray, setTray] = useState(false)
  const [panel, setPanel] = useState(false)
  const [person, setPerson] = useState<string>()
  const [confirmEnd, setConfirmEnd] = useState(false)
  const [error, setError] = useState('')
  const [copied, setCopied] = useState(false)
  const [busy, setBusy] = useState(false)
  const dialog = useRef<HTMLDialogElement>(null)
  const trayRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (panel) dialog.current?.showModal()
    else dialog.current?.close()
  }, [panel])
  useEffect(() => {
    if (!tray && !panel) return
    onHoldChrome?.('partyControls')
    return () => onReleaseChrome?.('partyControls')
  }, [tray, panel, onHoldChrome, onReleaseChrome])
  useEffect(() => {
    if (!tray) return
    const outside = (event: PointerEvent) => {
      if (!trayRef.current?.contains(event.target as Node)) setTray(false)
    }
    document.addEventListener('pointerdown', outside)
    return () => document.removeEventListener('pointerdown', outside)
  }, [tray])
  useEffect(() => {
    const menu = (event: MouseEvent) => {
      if (
        event.shiftKey ||
        !(event.target as HTMLElement).closest('.player-host-content')
      )
        return
      event.preventDefault()
      setPanel(true)
    }
    document.addEventListener('contextmenu', menu)
    return () => document.removeEventListener('contextmenu', menu)
  }, [])
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined
    let origin: { x: number; y: number } | undefined
    const cancel = () => {
      clearTimeout(timer)
      origin = undefined
    }
    const down = (event: PointerEvent) => {
      const target = event.target as HTMLElement
      if (
        event.pointerType !== 'touch' ||
        !target.closest('.player-host-content') ||
        target.closest('button,input,[role="slider"],.player-float-surface')
      )
        return
      origin = { x: event.clientX, y: event.clientY }
      timer = setTimeout(() => {
        setPanel(true)
        origin = undefined
      }, 550)
    }
    const move = (event: PointerEvent) => {
      if (
        origin &&
        Math.hypot(event.clientX - origin.x, event.clientY - origin.y) > 10
      )
        cancel()
    }
    document.addEventListener('pointerdown', down)
    document.addEventListener('pointermove', move)
    document.addEventListener('pointerup', cancel)
    document.addEventListener('pointercancel', cancel)
    return () => {
      cancel()
      document.removeEventListener('pointerdown', down)
      document.removeEventListener('pointermove', move)
      document.removeEventListener('pointerup', cancel)
      document.removeEventListener('pointercancel', cancel)
    }
  }, [])
  const keyActions = useRef({
    micOn,
    onSetMic,
    floating: presentation.floating,
    toggleChat: party.toggleChat,
  })
  keyActions.current = {
    micOn,
    onSetMic,
    floating: presentation.floating,
    toggleChat: party.toggleChat,
  }
  useEffect(() => {
    let held = false
    let starting: Promise<unknown> | undefined
    const release = () => {
      if (!held) return
      held = false
      void starting
        ?.then(() => keyActions.current.onSetMic?.(false))
        .catch(() => {})
    }
    const down = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null
      if (target?.closest('input,textarea,dialog,[contenteditable="true"]'))
        return
      const actions = keyActions.current
      if (
        (event.ctrlKey || event.metaKey) &&
        event.key.toLowerCase() === 'c' &&
        !window.getSelection()?.toString()
      ) {
        event.preventDefault()
        event.stopImmediatePropagation()
        actions.toggleChat()
        return
      }
      if (
        event.key.toLowerCase() !== 't' ||
        event.repeat ||
        event.ctrlKey ||
        event.metaKey ||
        actions.floating ||
        !actions.onSetMic
      )
        return
      event.preventDefault()
      if (!actions.micOn) {
        held = true
        starting = Promise.resolve()
          .then(() => actions.onSetMic?.(true))
          .catch(() => {})
      }
    }
    const up = (event: KeyboardEvent) => {
      if (event.key.toLowerCase() === 't') release()
    }
    window.addEventListener('keydown', down, true)
    window.addEventListener('keyup', up)
    window.addEventListener('blur', release)
    return () => {
      window.removeEventListener('keydown', down, true)
      window.removeEventListener('keyup', up)
      window.removeEventListener('blur', release)
      release()
    }
  }, [])
  const waiting = party.session?.waiting ?? []
  useEffect(() => {
    if (waiting.length) setTray(true)
  }, [waiting.length])
  if (!party.session) return null
  const session = party.session
  const host = party.role === 'host'
  const watching = stage === 'watching'
  const shown = visible || presentation.floating || !watching || tray || panel
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(
        `${location.origin}/party/${session.id}`
      )
      setCopied(true)
    } catch {
      setError('Could not copy the invite. You can select the room code below.')
    }
  }
  const leave = async () => {
    setBusy(true)
    try {
      await party.exitParty()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not leave')
    } finally {
      setBusy(false)
    }
  }
  const end = async () => {
    setBusy(true)
    try {
      await party.endParty()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not end party')
    } finally {
      setBusy(false)
    }
  }
  const people = [
    { userId: session.hostId, name: session.hostName || 'Host' },
    ...(session.guests ?? []),
  ]
  return (
    <>
      {watching && !presentation.floating && (
        <div className="native-player-title" data-visible={shown}>
          <RoomButton
            label="Minimize movie"
            icon="back"
            onClick={presentation.minimize}
          />
          <span>{mediaTitle}</span>
        </div>
      )}
      <DeviceRail
        micOn={micOn}
        camOn={camOn}
        onToggleMic={onToggleMic}
        onToggleCam={onToggleCam}
        hideSelf={hideSelf}
        onToggleHideSelf={onToggleHideSelf}
        visible={shown}
      />
      <div
        className="native-party-tray"
        ref={trayRef}
        data-visible={shown}
        data-floating={presentation.floating}
        data-watching={watching}
      >
        {tray && (
          <div className="native-party-actions">
            <RoomButton
              label={host ? 'End party' : 'Leave party'}
              icon={host ? 'power' : 'logout'}
              danger
              disabled={busy}
              onClick={() =>
                host ? (setPanel(true), setConfirmEnd(true)) : void leave()
              }
            />
            {host && (
              <RoomButton
                label={copied ? 'Invite copied' : 'Copy invite'}
                icon={copied ? 'check' : 'link'}
                onClick={() => {
                  void copy()
                }}
              />
            )}
            <RoomButton
              label="Watch party controls"
              icon="settings"
              onClick={() => {
                setTray(false)
                setPanel(true)
              }}
            />
          </div>
        )}
        <button
          className="native-popcorn"
          aria-label="Watch party"
          aria-expanded={tray}
          onClick={() => setTray((value) => !value)}
        >
          <img src="/popcorn.png" alt="" />
          {waiting.length > 0 && <span>{waiting.length}</span>}
        </button>
      </div>
      {onOpenChat && (
        <div
          className="native-chat-button"
          data-visible={shown}
          data-floating={presentation.floating}
        >
          <RoomButton label="Chat" active={chatOpen} onClick={onOpenChat}>
            <svg
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.7"
            >
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z" />
            </svg>
          </RoomButton>
        </div>
      )}
      {host && waiting.length > 0 && (
        <div className="native-join-requests">
          {waiting.map((person) => (
            <div key={person.userId}>
              <Avatar
                userId={person.userId}
                name={person.name}
                size={38}
                circle
              />
              <span>
                {person.name}
                <small>wants to join</small>
              </span>
              <RoomButton
                label={`Reject ${person.name}`}
                icon="x"
                danger
                onClick={() => party.rejectUser(person.userId)}
              />
              <RoomButton
                label={`Approve ${person.name}`}
                icon="check"
                onClick={() => party.approveUser(person.userId)}
              />
            </div>
          ))}
        </div>
      )}
      <dialog
        ref={dialog}
        className="native-party-panel"
        aria-label="Watch party controls"
        onCancel={() => setPanel(false)}
        onClose={() => {
          setPanel(false)
          setConfirmEnd(false)
          setPerson(undefined)
        }}
      >
        <div className="native-panel-close">
          <RoomButton
            label="Close party controls"
            icon="x"
            onClick={() => setPanel(false)}
          />
        </div>
        <div className="native-party-faces">
          {people.map((p) => (
            <button
              key={p.userId}
              className="native-party-face"
              data-host={p.userId === session.hostId}
              title={`${p.name}${p.userId === session.hostId ? ' · host' : ''}`}
              aria-label={`${p.name}${p.userId === session.hostId ? ' · host' : ''}`}
              onClick={() =>
                setPerson(p.userId === person ? undefined : p.userId)
              }
            >
              <Avatar userId={p.userId} name={p.name} size={40} circle />
            </button>
          ))}
        </div>
        {person && (
          <div className="native-person-menu">
            <span>
              {people.find((p) => p.userId === person)?.name}
              {person === user?.userId ? ' · You' : ''}
            </span>
            {host && person !== session.hostId && (
              <>
                <button
                  onClick={() => {
                    party.transferHost(person)
                    setPerson(undefined)
                  }}
                >
                  Make host
                </button>
                <button
                  onClick={() => {
                    party.kickUser(person)
                    setPerson(undefined)
                  }}
                >
                  Remove from party
                </button>
              </>
            )}
          </div>
        )}
        {host && (
          <>
            <div className="native-sync-modes">
              {(['dragging', 'hopping'] as const).map((mode) => (
                <button
                  key={mode}
                  aria-pressed={session.syncMode === mode}
                  onClick={() => party.setSyncMode(mode)}
                >
                  {mode === 'dragging' ? 'Follow' : 'Lead'}
                </button>
              ))}
            </div>
            <p>
              {session.syncMode === 'dragging'
                ? 'Wait for viewers who are buffering.'
                : 'Keep playing while viewers catch up.'}
            </p>
          </>
        )}
        <div className="native-party-tools">
          {onReconnect && (
            <RoomButton
              label="Reconnect my video and audio"
              icon="update"
              onClick={onReconnect}
            />
          )}
          <RoomButton
            label={copied ? 'Invite copied' : 'Copy invite'}
            icon={copied ? 'check' : 'link'}
            onClick={() => {
              void copy()
            }}
          />
          <RoomButton
            label="Viewer timeline pointers"
            icon="tracks"
            active={party.showPeerPointers}
            onClick={party.togglePeerPointers}
          />
          {host && (
            <RoomButton
              label="Allow guests to control playback"
              icon={session.collaborativeControl ? 'unlock' : 'lock'}
              active={session.collaborativeControl}
              onClick={() =>
                party.setCollaborative(!session.collaborativeControl)
              }
            />
          )}
          <RoomButton
            label={host ? 'End party for everyone' : 'Leave party'}
            icon={host ? 'power' : 'logout'}
            danger
            onClick={() => (host ? setConfirmEnd(true) : void leave())}
          />
        </div>
        <code>{session.id}</code>
        {confirmEnd && (
          <div className="native-end-confirm">
            <p>End party for everyone?</p>
            <button onClick={() => setConfirmEnd(false)}>Cancel</button>
            <button
              disabled={busy}
              onClick={() => {
                void end()
              }}
            >
              End party
            </button>
          </div>
        )}
        {error && <p role="alert">{error}</p>}
      </dialog>
      <div className="native-room-toasts" role="status">
        {party.toasts.map((t) => (
          <div key={t.id}>{t.msg}</div>
        ))}
      </div>
    </>
  )
}
