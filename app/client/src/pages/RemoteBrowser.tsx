import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { useParty } from '../context/PartyContext'
import { useAuth } from '../context/AuthContext'
import { useSocket } from '../hooks/useSocket'
import { navigate } from '../router'
import { glass } from '../glass'
import CameraGrid from '../components/CameraGrid'
import Dock from '../components/Dock'
import Chat from '../components/Chat'
import NekoScreen from '../components/NekoScreen'
import { ChatSheet } from './Party'
import type { CameraProps, LiveKitState } from './Party'
import { Z } from '../watchLayers'
import type { PartySession } from '../types'
import { apiJson, stringField } from '../types/guards'

// Renders the party's shared Neko browser via our own client (NekoScreen)
// speaking Neko's WS+WebRTC protocol directly, authenticated with a per-user
// session token — not Neko's bundled client (which only supports
// URL-password auth). Watchparty's own floating cameras and chat sit on top
// of it, same as the watch screen. The heavy lifting (auth, container
// lifecycle, proxying) all lives server-side — this page just mints a
// viewer session + token, and surfaces control hand-off through the
// existing socket-emit + ack pattern the rest of PartyContext uses.
export default function RemoteBrowser({
  session, isHost, cameraProps, lk, layoutMode, setLayout = () => {},
  chatOpen, openChat = () => {}, closeChat = () => {}, chatRipple = 0, phone,
}: {
  session: PartySession
  isHost?: boolean
  cameraProps?: CameraProps
  lk?: LiveKitState
  layoutMode?: 'float' | 'dock'
  setLayout?: (mode: 'float' | 'dock') => void
  chatOpen?: boolean
  openChat?: (focus?: boolean) => void
  closeChat?: () => void
  chatRipple?: number
  phone?: boolean
}) {
  const party = useParty()
  const { user } = useAuth()
  const { socket } = useSocket()
  const { controllerUserId, getControl, requestControl, assignControl, revokeControl, stopBrowser } = party
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading')
  const [error, setError] = useState<string | null>(null)
  const [actionMsg, setActionMsg] = useState<string | null>(null)
  const [token, setToken] = useState<string | null>(null)
  const mountedRef = useRef(true)

  useEffect(() => {
    mountedRef.current = true
    return () => { mountedRef.current = false }
  }, [])

  useEffect(() => {
    let cancelled = false
    setStatus('loading')
    setError(null)
    fetch(`/api/party/${session.id}/browser/session`, { method: 'POST', credentials: 'include' })
      .then(async (r) => {
        if (!r.ok) {
          const body = await r.json().catch(() => null)
          throw new Error(stringField(body, 'error') || `request failed (${r.status})`)
        }
        return apiJson(r)
      })
      .then((body) => {
        if (cancelled) return
        const sessionToken = stringField(body, 'token')
        if (!sessionToken) throw new Error('shared browser session response was missing a token')
        setToken(sessionToken)
        setStatus('ready')
      })
      .catch((err) => {
        if (cancelled) return
        setError(err?.message || 'Could not connect to the shared browser')
        setStatus('error')
      })
    return () => { cancelled = true }
  }, [session.id])

  // Hydrate authoritative control state on mount and on every reconnect —
  // cached 'browser:control' broadcasts can predate this client.
  useEffect(() => {
    getControl().catch(() => {})
    const onConnect = () => { getControl().catch(() => {}) }
    socket.on('connect', onConnect)
    return () => { socket.off('connect', onConnect) }
  }, [socket]) // eslint-disable-line react-hooks/exhaustive-deps

  function flash(msg: string) {
    setActionMsg(msg)
    setTimeout(() => { if (mountedRef.current) setActionMsg(null) }, 3500)
  }

  async function onRequestControl() {
    const res = await requestControl()
    if (res.error === 'held') flash('Someone else already has control')
    else if (res.error === 'viewer not connected') flash('Your browser session isn’t ready yet — wait a moment and try again')
    else if (res.error) flash(res.error)
  }

  async function onAssign(userId: string) {
    const res = await assignControl(userId)
    if (res.error === 'viewer not connected') flash('That viewer hasn’t connected to the browser yet')
    else if (res.error) flash(res.error)
  }

  async function onRevoke() {
    const res = await revokeControl()
    if (res.error) flash(res.error)
  }

  const isController = controllerUserId != null
  const canStop = isHost // controller-gated stop is enforced server-side; we always show it to the host
  async function onStop() {
    const res = await stopBrowser()
    if (res.error) flash(res.error)
  }

  const showCameraGrid = !!cameraProps && layoutMode === 'float'
  const showDock = !!cameraProps && !phone && layoutMode === 'dock'

  return (
    <div style={{ position: 'fixed', inset: 0, background: '#000' }}>
      {status === 'loading' && (
        <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center' }}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
            <div style={{ width: 36, height: 36, borderRadius: '50%', border: '3px solid var(--stroke2)', borderTopColor: 'var(--accent)', animation: 'spin .9s linear infinite' }} />
            <span style={{ color: 'var(--text3)', fontSize: 13 }}>Connecting to the shared browser…</span>
          </div>
        </div>
      )}

      {status === 'error' && (
        <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', padding: 24 }}>
          <div style={{ maxWidth: 360, textAlign: 'center' }}>
            <div style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-.02em', marginBottom: 8, color: 'var(--text)' }}>Couldn't start the shared browser</div>
            <p style={{ fontSize: 14, color: 'var(--text2)', lineHeight: 1.55, marginBottom: 20 }}>{error}</p>
            {isHost && (
              <button onClick={onStop} style={{
                padding: '11px 20px', border: 'none', borderRadius: 10, background: 'var(--accent)', color: 'var(--on-accent)',
                fontSize: 14, fontWeight: 700, cursor: 'pointer',
              }}>Back to lobby</button>
            )}
          </div>
        </div>
      )}

      {status === 'ready' && token && (
        <div style={{ position: 'absolute', inset: 0, marginLeft: showDock ? 210 : 0, transition: 'margin-left .3s cubic-bezier(.2,0,.1,1)' }}>
          <NekoScreen
            wsUrl={`${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}/neko/api/ws`}
            token={token}
            canControl={!!user && controllerUserId === user.userId}
            onError={(err) => { setError(err.message); setStatus('error') }}
          />
          {showCameraGrid && <CameraGrid {...cameraProps!} />}
        </div>
      )}

      {showDock && (
        <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 210, zIndex: Z.cameraStrip }}>
          <Dock {...cameraProps!} />
        </div>
      )}

      {/* Chat: same behavior as the watch screen — dismissible slide-over sheet
          with a scrim on phones, docked panel on desktop. */}
      {chatOpen && (
        phone
          ? (
            <>
              <div onClick={(e) => { e.stopPropagation(); closeChat() }}
                style={{ position: 'absolute', inset: 0, zIndex: Z.chatScrim, background: 'rgba(4,5,8,.5)', animation: 'scrimIn .2s ease both' }} />
              <ChatSheet />
            </>
          )
          : <Chat top={76} />
      )}

      {/* Control bar: controller status, request/assign/revoke, stop. */}
      <div style={{
        position: 'absolute', top: 12, left: 12, right: 12, zIndex: 10,
        display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap',
      }}>
        <ControllerPill controllerUserId={controllerUserId} session={session} />

        {!isController && (
          <Chip onClick={onRequestControl}>Request control</Chip>
        )}

        {isHost && (
          <>
            <RosterAssign session={session} onAssign={onAssign} controllerUserId={controllerUserId} />
            {controllerUserId && <Chip onClick={onRevoke}>Revoke control</Chip>}
          </>
        )}

        <div style={{ flex: 1 }} />

        {cameraProps && !phone && (
          <Chip onClick={() => setLayout(layoutMode === 'float' ? 'dock' : 'float')}>
            {layoutMode === 'float' ? 'Dock cameras' : 'Float cameras'}
          </Chip>
        )}
        <Chip onClick={() => (chatOpen ? closeChat() : openChat())}>{chatOpen ? 'Close chat' : 'Chat'}</Chip>

        {canStop && <Chip onClick={onStop} danger>Stop browser</Chip>}
      </div>

      {/* Notification ripple from the right edge, same treatment as the watch
          screen — a quick visual nudge when a chat message lands while closed. */}
      {chatRipple > 0 && !chatOpen && (
        <div key={chatRipple}
          style={{ position: 'absolute', top: 0, right: 0, bottom: 0, width: 6, zIndex: Z.chatEdge, pointerEvents: 'none',
            background: 'var(--text)', transformOrigin: 'right',
            animation: 'edgeRipple .9s ease-out forwards' }} />
      )}

      {actionMsg && (
        <div style={{
          position: 'absolute', bottom: 20, left: '50%', transform: 'translateX(-50%)', zIndex: 10,
          padding: '10px 18px', borderRadius: 999, ...glass('medium'),
          color: 'var(--text)', fontSize: 13.5, fontWeight: 600,
        }}>
          {actionMsg}
        </div>
      )}
    </div>
  )
}

function ControllerPill({ controllerUserId, session }: { controllerUserId: string | null; session: PartySession }) {
  const name = !controllerUserId
    ? 'No one has control'
    : controllerUserId === session.hostId
      ? `${session.hostName || 'Host'} has control`
      : `${session.guests?.find(g => g.userId === controllerUserId)?.name || 'A viewer'} has control`
  return (
    <div style={{ ...glass('light'), padding: '8px 14px', borderRadius: 999, fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>
      {name}
    </div>
  )
}

function Chip({ onClick, children, danger }: { onClick?: () => void; children?: ReactNode; danger?: boolean }) {
  return (
    <button onClick={onClick} style={{
      ...glass('light'), padding: '8px 14px', borderRadius: 999, cursor: 'pointer',
      fontSize: 13, fontWeight: 700, color: danger ? 'var(--red)' : 'var(--text)', border: 'none',
    }}>{children}</button>
  )
}

// Host-only roster dropdown to hand control to a specific member. The server
// is the source of truth on whether a target has an active mapped Neko
// session — if not, assignControl() resolves {error:'viewer not connected'}
// which the caller surfaces as a toast. We don't attempt to pre-filter the
// roster client-side since that state isn't surfaced to the web client.
function RosterAssign({ session, onAssign, controllerUserId }: {
  session: PartySession
  onAssign: (userId: string) => void
  controllerUserId: string | null
}) {
  const members = [
    { userId: session.hostId, name: session.hostName || 'Host' },
    ...(session.guests ?? []),
  ]
  return (
    <select
      defaultValue=""
      onChange={(e) => { const v = e.target.value; if (v) onAssign(v); e.target.value = '' }}
      style={{
        ...glass('light'), padding: '8px 12px', borderRadius: 999, fontSize: 13, fontWeight: 600,
        color: 'var(--text)', border: 'none', cursor: 'pointer',
      }}
    >
      <option value="" disabled>Give control to…</option>
      {members.map(m => (
        <option key={m.userId} value={m.userId} disabled={m.userId === controllerUserId}>
          {m.name}{m.userId === controllerUserId ? ' (current)' : ''}
        </option>
      ))}
    </select>
  )
}
