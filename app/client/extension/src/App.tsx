import { useEffect, useRef, useState, type CSSProperties, type FormEvent, type ReactNode } from 'react'
import type { VideoTrack } from 'livekit-client'
import { useLiveKit, type LiveKitParticipantView } from '../../src/hooks/useLiveKit.ts'
import { bridge, canControl as mayControl, formatInvite, type Member } from './core.ts'
import { defaults, useRoom, type Settings } from './useRoom.ts'
import { useFloatingCameras } from './useFloatingCameras.tsx'
import { AnIcon } from '../../src/analog/icons.tsx'
import { rpc, localGet, localSet, sessionGet, sessionSet } from './platform.ts'

function Brand({ detail }: { detail?: string }) {
  return <div className="brand"><img src="brand.svg" width="26" height="26" alt="" /><div><strong>Watch Party</strong>{detail && <span>{detail}</span>}</div></div>
}
function MediaCover({ videoId }: { videoId: string | null }) {
  const [failed, setFailed] = useState(false)
  useEffect(() => setFailed(false), [videoId])
  return <div className="media-cover"><img className="media-fallback" src="brand.svg" alt="" />{videoId && !failed && <img className="media-thumb" src={`https://i.ytimg.com/vi/${videoId}/mqdefault.jpg`} alt="" onError={() => setFailed(true)} />}</div>
}

function Toggle({ label, value, onChange }: { label: string; value: boolean; onChange: (value: boolean) => void }) {
  return <label className="toggle"><span>{label}</span><input type="checkbox" checked={value} onChange={event => onChange(event.target.checked)} /></label>
}
function Field({ label, children }: { label: string; children: ReactNode }) {
  return <label className="field"><span>{label}</span>{children}</label>
}
function Tile({ participant, local, volume, onVolume }: { participant: LiveKitParticipantView; local: boolean; volume: number; onVolume: (value: number) => void }) {
  const ref = useRef<HTMLVideoElement>(null)
  const track = participant.videoTrack as VideoTrack | null
  useEffect(() => {
    const video = ref.current
    if (!track || !video) return
    track.attach(video)
    return () => { track.detach(video) }
  }, [track])
  return <article className={`camera-tile${participant.isSpeaking ? ' speaking' : ''}`}>
    <div className="camera-picture">{track ? <video ref={ref} autoPlay playsInline muted className={local ? 'mirrored' : ''} /> : <span className="avatar">{participant.name.slice(0, 1).toUpperCase()}</span>}</div>
    <span className="camera-name">{participant.name}{local ? ' (you)' : ''}</span>
    {!local && <label className="voice-volume"><span>{volume === 0 ? 'Muted' : 'Voice'}</span><input aria-label={`${participant.name} voice volume`} type="range" min="0" max="1" step=".05" value={volume} onChange={event => onVolume(Number(event.target.value))} /></label>}
  </article>
}

export default function App() {
  const [settings, setSettings] = useState<Settings>(defaults)
  const [settingsLoaded, setSettingsLoaded] = useState(false)
  const room = useRoom(settings)
  const { connection, session, player, setup } = room
  const media = useLiveKit({ partyId: session?.id, enabled: !!session && room.connected, tokenEndpoint: connection ? `${connection.server}/api/extension/livekit-token` : '/api/extension/livekit-token', authToken: connection?.token })
  const [tab, setTab] = useState<'chat' | 'people' | 'settings'>('chat')
  const [invite, setInvite] = useState('')
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const [copied, setCopied] = useState(false)
  const [inviteOpen, setInviteOpen] = useState(false)
  const [unread, setUnread] = useState(0)
  const lastMessage = useRef('')
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [volumes, setVolumes] = useState<Record<string, number>>({})
  const bottom = useRef<HTMLDivElement>(null)
  const restoredAV = useRef('')
  const isHost = !!session && session.hostId === connection?.user.userId
  const canControl = !!session && mayControl(session, connection?.user.userId)
  const mismatched = !!session && player?.videoId !== session.externalMedia.videoId
  useEffect(() => { setInviteOpen(!!session && isHost); setCopied(false) }, [session?.id])
  useEffect(() => { bridge({ type: 'panel-mode', active: !!session }) }, [session?.id])

  useEffect(() => {
    void localGet<{ settings?: Partial<Settings> }>('settings').then(({ settings }) => { setSettings({ ...defaults, ...settings }); setSettingsLoaded(true) }).catch(() => setSettingsLoaded(true))
  }, [])
  useEffect(() => {
    if (settingsLoaded) void localSet({ settings }).catch(() => {})
    bridge({ type: 'layout', dock: settings.dock, opacity: settings.opacity })
  }, [settings, settingsLoaded])
  useEffect(() => {
    const latest = room.messages[room.messages.length - 1]
    const key = latest ? `${latest.timestamp}:${latest.userId}:${latest.text}` : ''
    if (tab === 'chat' || !latest) {
      setUnread(0)
      if (tab === 'chat') bottom.current?.scrollIntoView({ block: 'end' })
    } else if (key !== lastMessage.current && latest.userId !== connection?.user.userId) setUnread(value => value + 1)
    lastMessage.current = key
  }, [room.messages, tab, connection?.user.userId])
  useEffect(() => {
    if (!copied) return
    const timer = setTimeout(() => { setCopied(false); setInviteOpen(false) }, 1800)
    return () => clearTimeout(timer)
  }, [copied])

  async function refreshDevices() {
    try { setDevices(await navigator.mediaDevices.enumerateDevices()) }
    catch { room.setError('Your browser could not list camera and microphone devices.') }
  }
  useEffect(() => {
    void refreshDevices()
    navigator.mediaDevices?.addEventListener('devicechange', refreshDevices)
    return () => navigator.mediaDevices?.removeEventListener('devicechange', refreshDevices)
  }, [media.camOn, media.micOn])
  useEffect(() => {
    if (!media.localParticipant) return
    void media.switchDevice('videoinput', settings.cameraId)
  }, [media.localParticipant?.identity, settings.cameraId])
  useEffect(() => {
    if (!media.localParticipant) return
    void media.switchDevice('audioinput', settings.micId)
  }, [media.localParticipant?.identity, settings.micId])
  useEffect(() => {
    if (!media.localParticipant) return
    if (settings.speakerId) void media.switchDevice('audiooutput', settings.speakerId)
  }, [media.localParticipant?.identity, settings.speakerId])
  useEffect(() => {
    for (const participant of media.participants) media.setParticipantVolume(participant.identity, volumes[participant.identity] ?? settings.voiceVolume)
  }, [media.participants, settings.voiceVolume, volumes])
  useEffect(() => {
    if (!session || !connection || !media.connected) { restoredAV.current = ''; return }
    if (restoredAV.current === session.id) return
    const partyId = session.id
    restoredAV.current = partyId
    let cancelled = false
    void sessionGet<{ [key: string]: { camera: boolean; mic: boolean } }>(`av-${partyId}-${connection.user.userId}`).then(value => {
      if (cancelled) return
      const previous = value[`av-${partyId}-${connection.user.userId}`]
      if (previous?.camera) void media.enableCamera(true)
      if (previous?.mic) void media.enableMic(true)
    }).catch(() => {})
    return () => { cancelled = true }
  }, [session?.id, connection?.user.userId, media.connected])

  async function toggleAV(kind: 'camera' | 'mic') {
    if (!session || !connection) return
    const camera = kind === 'camera' ? !media.camOn : media.camOn
    const mic = kind === 'mic' ? !media.micOn : media.micOn
    const changed = kind === 'camera' ? await media.enableCamera(camera) : await media.enableMic(mic)
    if (changed) await sessionSet({ [`av-${session.id}-${connection.user.userId}`]: { camera, mic } })
  }

  function update<K extends keyof Settings>(key: K, value: Settings[K]) { setSettings(previous => ({ ...previous, [key]: value })) }
  async function act(action: () => Promise<unknown>) {
    setBusy(true); room.setError('')
    try { await action() }
    catch (error) { room.setError(error instanceof Error ? error.message : 'Something went wrong. Please retry.') }
    finally { setBusy(false) }
  }
  async function send(event: FormEvent) {
    event.preventDefault()
    const text = draft.trim()
    if (!text) return
    await act(async () => { await room.request('chat:message', { text }); setDraft('') })
  }
  const members: Member[] = session ? [{ userId: session.hostId, name: session.hostName }, ...session.guests.filter(guest => guest.userId !== session.hostId)] : []
  const participants = [...(settings.showSelf && media.localParticipant ? [media.localParticipant] : []), ...media.participants]
  const tileParticipants = members.filter(member => settings.showSelf || member.userId !== connection?.user.userId).map(member => participants.find(participant => participant.identity === member.userId) ?? { identity: member.userId, name: member.name, videoTrack: null, audioTrack: null, isSpeaking: false })
  const floatingCameras = useFloatingCameras(settings.hideCameras ? [] : tileParticipants.map(participant => ({ id: participant.identity, name: participant.name, speaking: participant.isSpeaking })), settings.tileSize, id => {
    const participant = tileParticipants.find(participant => participant.identity === id)
    return participant ? <Tile participant={participant} local={participant.identity === connection?.user.userId} volume={volumes[id] ?? settings.voiceVolume} onVolume={value => setVolumes(previous => ({ ...previous, [id]: value }))} /> : null
  })

  const openSettings = () => void rpc('open-settings').catch(error => room.setError(error.message))
  const connectionLabel = !room.loaded ? 'Connecting' : room.startupError ? 'Disconnected' : connection ? room.connected ? 'Connected' : room.error ? 'Disconnected' : 'Connecting' : room.serverStatus
  if (!room.loaded || !connection || !session) return <main className="launch"><header className="room-header"><Brand /><div className="header-actions"><span className={`connection-status${connectionLabel === 'Connected' ? ' online' : ''}`} role="status"><i className="connection-dot" />{connectionLabel}</span><button className="connection-settings" aria-label="Connection settings" title="Settings" onClick={openSettings}><AnIcon name="settings" size={18} /></button></div></header>{room.loaded && (connection?.user.isAdmin ? <button className="primary wide" disabled={busy || !room.connected} onClick={() => void act(room.create)}>{busy ? 'Creating…' : 'Create code'}</button> : <form className="join-form" onSubmit={event => { event.preventDefault(); void act(() => room.join(invite)) }}><input aria-label="Invite code" placeholder="Code" value={invite} onChange={event => setInvite(event.target.value.toUpperCase())} maxLength={20} disabled={!setup?.server || !!room.startupError} required /><button className="primary" disabled={busy || !setup?.server || !!room.startupError}>{busy ? 'Joining…' : 'Join'}</button></form>)}{(room.startupError || room.error) && <p className="launch-error" role="alert">{room.startupError || room.error}</p>}{room.startupError && <button onClick={room.retryStartup}>Retry</button>}</main>

  return <main className="app" style={{ '--chat-size': `${settings.chatSize}px`, '--tile-size': `${settings.tileSize}px` } as CSSProperties}>
    {floatingCameras}
    <header className="room-header"><div><Brand /><h1 className="sr-only">Room {session.id}</h1></div><div className="header-actions"><span className={`connection-status${room.connected ? ' online' : ''}`}><i className="connection-dot" />{room.connected ? 'Connected' : 'Disconnected'}</span><button className="invite-trigger" aria-expanded={inviteOpen} aria-controls="room-invite" onClick={() => setInviteOpen(value => !value)}>Code</button><button className="connection-settings" aria-label="Connection settings" title="Settings" onClick={openSettings}><AnIcon name="settings" size={18} /></button></div></header>
    {(room.error || media.error) && <div className="notice" role="alert">{room.error || media.error}<button onClick={() => { room.setError(''); media.reportError(null) }} aria-label="Dismiss message">Dismiss</button></div>}
    <>
      <div className="now-playing"><MediaCover videoId={session.externalMedia.videoId} /><div className="media-copy"><small>{session.externalMedia.videoId ? 'NOW WATCHING' : 'BROWSING TOGETHER'}</small><strong>{session.externalMedia.title || 'YouTube'}</strong><span><i className={session.schedule.phase === 'playing' ? 'playback-dot' : 'playback-dot paused'} />{!session.externalMedia.videoId ? 'Everyone follows this page' : <>{session.schedule.phase === 'stalled' ? 'Waiting for a viewer or ad…' : session.schedule.phase === 'playing' ? 'Playing together' : 'Paused'}<b>·</b>{Math.abs(room.drift) < .3 ? 'In sync' : `${Math.abs(room.drift).toFixed(1)}s ${room.drift > 0 ? 'behind' : 'ahead'}`}</>}</span></div></div>
      {mismatched && <div className="notice"><p>{canControl ? 'Sharing your YouTube navigation with the room…' : 'Following the host’s YouTube page…'}</p><button onClick={() => void room.followRoom()}>Open shared page</button></div>}
      {player?.ad && <p className="notice">YouTube is showing an ad. Timeline corrections are paused until it ends.</p>}
      <section className="invite-card" id="room-invite" aria-label="Invite code" hidden={!inviteOpen}><div className="invite-strip"><strong>{formatInvite(session.inviteCode)}</strong><button className={copied ? 'is-copied' : ''} onClick={() => void act(async () => { await navigator.clipboard.writeText(formatInvite(session.inviteCode)); setCopied(true) })}><AnIcon name={copied ? 'check' : 'copy'} size={16} /><span aria-live="polite">{copied ? 'Copied' : 'Copy'}</span></button></div></section>
      <div className="playback-buttons"><button disabled={!canControl || mismatched || busy || !room.connected || !session.externalMedia.videoId} onClick={() => void room.command(session.schedule.phase === 'playing' ? 'pause' : 'play')}>{session.schedule.phase === 'playing' ? 'Pause room' : 'Play room'}</button><span className="hint">{canControl ? 'Control enabled' : 'View only'}</span></div>
      <div className="av-buttons"><button disabled={!media.connected} aria-pressed={media.camOn} onClick={() => void toggleAV('camera')}><AnIcon name="tv" size={17} /><span>{media.camOn ? 'Camera on' : 'Camera off'}</span></button><button disabled={!media.connected} aria-pressed={media.micOn} onClick={() => void toggleAV('mic')}><AnIcon name={media.micOn ? 'sound' : 'mute'} size={17} /><span>{media.micOn ? 'Mic on' : 'Mic off'}</span></button><button aria-pressed={!settings.hideCameras} onClick={() => update('hideCameras', !settings.hideCameras)}><AnIcon name="users" size={17} /><span>{settings.hideCameras ? 'Show feeds' : 'Hide feeds'}</span></button></div>
      {!media.connected && <p className="hint">Connecting voice & cameras… <button onClick={media.reconnect}>Retry connection</button></p>}
      {media.audioBlocked && <button className="primary" onClick={() => void media.startAudio()}>Enable room audio</button>}
      {!settings.hideCameras && <div className="floating-summary"><span className="mini-avatars" aria-hidden="true">{members.slice(0, 4).map(member => <i key={member.userId}>{member.name.slice(0, 1).toUpperCase()}</i>)}</span><span>{tileParticipants.length}</span></div>}
      <nav className="tabs" aria-label="Room panels">{(['chat', 'people', 'settings'] as const).map(name => <button key={name} aria-label={name === 'people' ? `People (${members.length})` : name === 'chat' ? 'Chat' : 'Settings'} aria-current={tab === name ? 'page' : undefined} onClick={() => setTab(name)}>{name === 'people' ? `People (${members.length})` : name === 'chat' ? 'Chat' : 'Settings'}{name === 'chat' && unread > 0 && <span className="unread-badge" aria-hidden="true">{unread > 9 ? '9+' : unread}</span>}</button>)}</nav>
      {tab === 'chat' && <section className="chat-panel" aria-label="Party chat"><div className="messages" role="log" aria-live="polite">{room.messages.map((message, index) => <article className={`message${message.userId === connection.user.userId ? ' own' : ''}`} key={`${message.timestamp}-${index}`}><span className="message-avatar" aria-hidden="true">{message.name.slice(0, 1).toUpperCase()}</span><div className="message-content"><header><strong>{message.userId === connection.user.userId ? 'You' : message.name}</strong><time>{new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</time></header><p>{message.text}</p></div></article>)}<div ref={bottom} /></div><form className="chat-compose" onSubmit={send}><label className="sr-only" htmlFor="chat-draft">Message</label><input id="chat-draft" placeholder="Message" value={draft} maxLength={2000} onChange={event => setDraft(event.target.value)} autoComplete="off" /><button aria-label="Send" title="Send" disabled={busy || !draft.trim() || !room.connected}><AnIcon name="enter" size={18} /></button></form></section>}
      {tab === 'people' && <section className="panel-scroll"><div className="panel-heading"><h2>People</h2><span>{members.length}</span></div>
        {isHost && session.waiting.length > 0 && <div><h2>Waiting to join</h2>{session.waiting.map(member => <div className="member" key={member.userId}><strong>{member.name}</strong><div className="row"><button disabled={busy} onClick={() => void act(() => room.request('party:approve', { userId: member.userId }))}>Allow</button><button disabled={busy} onClick={() => void act(async () => { await room.request('party:reject', { userId: member.userId }); await room.refresh() })}>Decline</button></div></div>)}</div>}
        {members.map(member => <div className="member" key={member.userId}><span className="member-avatar" aria-hidden="true">{member.name.slice(0, 1).toUpperCase()}</span><strong>{member.name}{member.userId === connection.user.userId ? ' (you)' : ''}<small className={session.controllers.includes(member.userId) ? 'controller-label' : ''}>{member.userId === session.hostId ? 'Host' : session.controllers.includes(member.userId) ? 'Can control' : 'Viewer'}</small></strong>{isHost && member.userId !== connection.user.userId && <div className="row"><button disabled={busy} aria-pressed={session.controllers.includes(member.userId)} onClick={() => void act(() => room.request('party:setController', { userId: member.userId, enabled: !session.controllers.includes(member.userId) }))}>{session.controllers.includes(member.userId) ? 'Revoke control' : 'Give control'}</button><button className="remove-member" disabled={busy} onClick={() => void act(() => room.request('party:kick', { userId: member.userId }))}>Remove</button></div>}</div>)}
      </section>}
      {tab === 'settings' && <section className="panel-scroll settings">
        <details open><summary>Playback & sync</summary><p className="hint">Quality, captions, and volume remain available in YouTube’s player.</p>
          <Field label="Room playback speed"><select disabled={!canControl} value={session.externalMedia.playbackRate} onChange={event => void room.command('rate', undefined, Number(event.target.value))}>{[.25, .5, .75, 1, 1.25, 1.5, 1.75, 2].map(rate => <option key={rate} value={rate}>{rate}×</option>)}</select></Field>
          {isHost && <Field label="Buffering behavior"><select value={session.syncMode} onChange={event => void act(() => room.request('party:setSyncMode', { mode: event.target.value }))}><option value="hopping">Lead: keep going when guests buffer</option><option value="dragging">Follow: wait for everyone</option></select></Field>}
          <Toggle label="Gently adjust speed to correct drift" value={settings.gentle} onChange={value => update('gentle', value)} /><Field label={`Sync tolerance: ${settings.tolerance.toFixed(2)} seconds`}><input type="range" min=".1" max="1" step=".05" value={settings.tolerance} onChange={event => update('tolerance', Number(event.target.value))} /></Field>
          <Field label="Your YouTube volume"><input type="range" min="0" max="1" step=".05" value={player?.volume ?? 1} onChange={event => bridge({ type: 'volume', videoId: player?.videoId, volume: Number(event.target.value) })} /></Field>
        </details>
        <details><summary>Camera, microphone & voice</summary><p className="hint">Camera and microphone start off. Echo cancellation, noise suppression, and automatic gain are enabled.</p><button onClick={() => void refreshDevices()}>Refresh devices</button>
          {([['cameraId', 'videoinput', 'Camera'], ['micId', 'audioinput', 'Microphone'], ['speakerId', 'audiooutput', 'Speakers']] as const).map(([key, kind, name]) => <Field key={key} label={name}><select value={settings[key]} onChange={event => update(key, event.target.value)}><option value="">System default</option>{devices.filter(device => device.kind === kind).map((device, index) => <option key={device.deviceId || index} value={device.deviceId}>{device.label || `${name} ${index + 1}`}</option>)}</select></Field>)}
          <Field label={`Default participant volume: ${Math.round(settings.voiceVolume * 100)}%`}><input type="range" min="0" max="1" step=".05" value={settings.voiceVolume} onChange={event => { update('voiceVolume', Number(event.target.value)); setVolumes({}) }} /></Field><Toggle label="Show my own camera tile" value={settings.showSelf} onChange={value => update('showSelf', value)} /><button onClick={media.reconnect}>Reconnect voice & cameras</button>
        </details>
        <details><summary>Overlay & chat</summary><p className="hint">Drag the top bar to move the overlay. Drag its lower corner to resize it. It stays visible in YouTube fullscreen.</p><Field label="Dock"><select value={settings.dock} onChange={event => update('dock', event.target.value as Settings['dock'])}><option value="right">Right</option><option value="left">Left</option></select></Field><Field label={`Overlay opacity: ${Math.round(settings.opacity * 100)}%`}><input type="range" min=".5" max="1" step=".05" value={settings.opacity} onChange={event => update('opacity', Number(event.target.value))} /></Field><Field label="Default floating camera width"><input type="range" min="112" max="480" step="8" value={settings.tileSize} onChange={event => update('tileSize', Number(event.target.value))} /></Field><Field label="Chat text size"><input type="range" min="12" max="20" step="1" value={settings.chatSize} onChange={event => update('chatSize', Number(event.target.value))} /></Field><button onClick={() => setSettings(defaults)}>Reset personal settings</button></details>
      </section>}
      <footer className="room-footer"><span className="footer-identity"><i aria-hidden="true">{connection.user.name.slice(0, 1).toUpperCase()}</i><span>{connection.user.name}<small>{isHost ? 'Host' : canControl ? 'Guest · can control' : 'Guest'}</small></span></span><button className="danger" disabled={busy} onClick={() => void act(room.leave)}><AnIcon name="logout" size={14} />{isHost ? 'End party' : 'Leave party'}</button></footer>
    </>
  </main>
}
