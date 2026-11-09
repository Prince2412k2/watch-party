import { useEffect, useRef, useState, type CSSProperties, type FormEvent, type ReactNode } from 'react'
import type { VideoTrack } from 'livekit-client'
import { useLiveKit, type LiveKitParticipantView } from '../../src/hooks/useLiveKit.ts'
import { bridge, canControl as mayControl, formatInvite, type Member } from './core.ts'
import { defaults, useRoom, type Settings } from './useRoom.ts'
import { useFloatingCameras } from './useFloatingCameras.tsx'
import { useFloatingPanels } from './useFloatingPanels.tsx'
import { AnIcon } from '../../src/analog/icons.tsx'
import { rpc, localGet, localSet, sessionGet, sessionSet } from './platform.ts'

function Brand() {
  return <div className="brand"><img src="brand.svg" width="22" height="22" alt="" /><strong>Watch Party</strong></div>
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
function Glyph({ name }: { name: 'camera' | 'mic' | 'chat' | 'pause' }) {
  const paths = { camera: 'M3 6h12v12H3zM15 10l6-4v12l-6-4', mic: 'M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0zM5 10v2a7 7 0 0 0 14 0v-2M12 19v3M8 22h8', chat: 'M4 4h16v12H9l-5 4z', pause: 'M8 5v14M16 5v14' }
  return <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[name]} /></svg>
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
  const [invite, setInvite] = useState('')
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const [avBusy, setAVBusy] = useState(false)
  const [copied, setCopied] = useState(false)
  const [optionsOpen, setOptionsOpen] = useState(false)
  const [chatVisible, setChatVisible] = useState(true)
  const [avVisible, setAVVisible] = useState(true)
  const [unread, setUnread] = useState(0)
  const lastMessage = useRef('')
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [volumes, setVolumes] = useState<Record<string, number>>({})
  const bottom = useRef<HTMLDivElement>(null)
  const restoredAV = useRef('')
  const isHost = !!session && session.hostId === connection?.user.userId
  const canControl = !!session && mayControl(session, connection?.user.userId)
  const mismatched = !!session && !!player && player.url !== session.externalMedia.url
  useEffect(() => { setCopied(false); setOptionsOpen(false); setDraft(''); setUnread(0); setVolumes({}) }, [session?.id])
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
    if (chatVisible || !latest) {
      setUnread(0)
      bottom.current?.scrollIntoView({ block: 'end' })
    } else if (key !== lastMessage.current && latest.userId !== connection?.user.userId) setUnread(value => value + 1)
    lastMessage.current = key
  }, [room.messages, chatVisible, connection?.user.userId])
  useEffect(() => {
    if (!copied) return
    const timer = setTimeout(() => setCopied(false), 1800)
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
  useEffect(() => { if (media.localParticipant) void media.switchDevice('videoinput', settings.cameraId) }, [media.localParticipant?.identity, settings.cameraId])
  useEffect(() => { if (media.localParticipant) void media.switchDevice('audioinput', settings.micId) }, [media.localParticipant?.identity, settings.micId])
  useEffect(() => { if (media.localParticipant && settings.speakerId) void media.switchDevice('audiooutput', settings.speakerId) }, [media.localParticipant?.identity, settings.speakerId])
  useEffect(() => { for (const participant of media.participants) media.setParticipantVolume(participant.identity, volumes[participant.identity] ?? settings.voiceVolume) }, [media.participants, settings.voiceVolume, volumes])
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
    if (!session || !connection || avBusy) return
    setAVBusy(true)
    try {
      const camera = kind === 'camera' ? !media.camOn : media.camOn
      const mic = kind === 'mic' ? !media.micOn : media.micOn
      const changed = kind === 'camera' ? await media.enableCamera(camera) : await media.enableMic(mic)
      if (changed) await sessionSet({ [`av-${session.id}-${connection.user.userId}`]: { camera, mic } })
    } catch (error) { room.setError(error instanceof Error ? error.message : 'Could not change device.') }
    finally { setAVBusy(false) }
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
    if (text) await act(async () => { await room.request('chat:message', { text }); setDraft('') })
  }
  const members: Member[] = session ? [{ userId: session.hostId, name: session.hostName }, ...session.guests.filter(guest => guest.userId !== session.hostId)] : []
  const participants = [...(settings.showSelf && media.localParticipant ? [media.localParticipant] : []), ...media.participants]
  const tileParticipants = members.filter(member => settings.showSelf || member.userId !== connection?.user.userId).map(member => participants.find(participant => participant.identity === member.userId) ?? { identity: member.userId, name: member.name, videoTrack: null, audioTrack: null, isSpeaking: false })
  const floatingCameras = useFloatingCameras(settings.hideCameras ? [] : tileParticipants.map(participant => ({ id: participant.identity, name: participant.name, speaking: participant.isSpeaking })), settings.tileSize, id => {
    const participant = tileParticipants.find(participant => participant.identity === id)
    return participant ? <Tile participant={participant} local={participant.identity === connection?.user.userId} volume={volumes[id] ?? settings.voiceVolume} onVolume={value => setVolumes(previous => ({ ...previous, [id]: value }))} /> : null
  })
  const floatingPanels = useFloatingPanels(!!session, id => <main className="independent-content" style={{ '--chat-size': `${settings.chatSize}px` } as CSSProperties}>
    {id === 'chat' ? <section className="chat-panel" aria-label="Party chat">
      <div className="messages" role="log" aria-live="polite">{!room.messages.length && <p className="chat-empty">No messages yet</p>}{room.messages.map((message, index) => <article className={`message${message.userId === connection?.user.userId ? ' own' : ''}`} key={`${message.timestamp}-${index}`}><header><strong>{message.userId === connection?.user.userId ? 'You' : message.name}</strong><time>{new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</time></header><p>{message.text}</p></article>)}<div ref={bottom} /></div>
      <form className="chat-compose" onSubmit={send}><label className="sr-only" htmlFor="chat-draft">Message</label><input id="chat-draft" placeholder="Message" value={draft} maxLength={2000} onChange={event => setDraft(event.target.value)} autoComplete="off" /><button aria-label="Send" title="Send" disabled={busy || !draft.trim() || !room.connected}><AnIcon name="enter" size={18} /></button></form>
    </section> : <>
      <div className="av-buttons">
        <button className={`icon-button${!media.micOn ? ' device-off' : ''}`} disabled={!media.connected || avBusy} aria-label={media.micOn ? 'Mic on' : 'Mic off'} title={media.micOn ? 'Mute microphone' : 'Unmute microphone'} aria-pressed={media.micOn} onClick={() => void toggleAV('mic')}><Glyph name="mic" /></button>
        <button className={`icon-button${!media.camOn ? ' device-off' : ''}`} disabled={!media.connected || avBusy} aria-label={media.camOn ? 'Camera on' : 'Camera off'} title={media.camOn ? 'Turn camera off' : 'Turn camera on'} aria-pressed={media.camOn} onClick={() => void toggleAV('camera')}><Glyph name="camera" /></button>
        <button className="icon-button" aria-label={settings.hideCameras ? 'Show feeds' : 'Hide feeds'} title={settings.hideCameras ? 'Show feeds' : 'Hide feeds'} aria-pressed={!settings.hideCameras} onClick={() => update('hideCameras', !settings.hideCameras)}><AnIcon name="users" size={19} /></button>
      </div>
      {!media.connected && <p className="hint">Connecting… <button onClick={media.reconnect}>Retry</button></p>}
      {media.audioBlocked && <button className="primary" onClick={() => void media.startAudio()}>Enable room audio</button>}
      {media.error && <p className="notice" role="alert">{media.error}</p>}
      <details className="device-settings"><summary>Devices</summary>
        {([['cameraId', 'videoinput', 'Camera'], ['micId', 'audioinput', 'Microphone'], ['speakerId', 'audiooutput', 'Speakers']] as const).map(([key, kind, name]) => <Field key={key} label={name}><select value={settings[key]} onChange={event => update(key, event.target.value)}><option value="">System default</option>{devices.filter(device => device.kind === kind).map((device, index) => <option key={device.deviceId || index} value={device.deviceId}>{device.label || `${name} ${index + 1}`}</option>)}</select></Field>)}
        <Field label="Voice volume"><input type="range" min="0" max="1" step=".05" value={settings.voiceVolume} onChange={event => { update('voiceVolume', Number(event.target.value)); setVolumes({}) }} /></Field>
        <Toggle label="Show my camera" value={settings.showSelf} onChange={value => update('showSelf', value)} />
        <button onClick={() => void refreshDevices()}>Refresh devices</button><button onClick={media.reconnect}>Reconnect</button>
      </details>
    </>}
  </main>, (id, visible) => { if (id === 'chat') setChatVisible(visible); if (id === 'av') setAVVisible(visible) })

  const openSettings = () => void rpc('open-settings').catch(error => room.setError(error.message))
  const connectionLabel = !room.loaded ? 'Connecting' : room.startupError ? 'Disconnected' : room.ownsTab ? room.connected ? 'Connected' : room.error ? 'Disconnected' : 'Connecting' : room.serverStatus
  const status = <span className={`connection-status${connectionLabel === 'Connected' ? ' online' : ''}`} role="status"><i className="connection-dot" />{connectionLabel}</span>
  const header = <header className="room-header"><Brand /><div className="header-actions">{status}<button className="connection-settings" aria-label="Connection settings" title="Connection settings" onClick={openSettings}><AnIcon name="settings" size={16} /></button></div></header>
  if (!room.loaded || !connection || !session) return <main className="launch">
    {header}
    {room.loaded && <>
      {connection?.user.isAdmin && <button className="primary wide" disabled={busy || connectionLabel !== 'Connected'} onClick={() => void act(room.create)}>{busy ? 'Creating…' : 'Create code'}</button>}
      <form className="join-form" onSubmit={event => { event.preventDefault(); void act(() => room.join(invite)) }}><input aria-label="Invite code" placeholder="Code" value={invite} onChange={event => setInvite(event.target.value.toUpperCase())} maxLength={20} disabled={!setup?.server || !!room.startupError} required /><button disabled={busy || !setup?.server || !!room.startupError}>{busy ? 'Joining…' : 'Join'}</button></form>
    </>}
    {(room.startupError || room.error) && <p className="launch-error" role="alert">{room.startupError || room.error}</p>}{room.startupError && <button onClick={room.retryStartup}>Retry</button>}
  </main>

  return <main className="app">
    {floatingCameras}{floatingPanels}{header}<h1 className="sr-only">Room {session.id}</h1>
    {(room.error || media.error) && <div className="notice" role="alert">{room.error || media.error}<button onClick={() => { room.setError(''); media.reportError(null) }} aria-label="Dismiss message">Dismiss</button></div>}
    <div className="invite-strip" aria-label="Invite code"><strong>{formatInvite(session.inviteCode)}</strong><button className={copied ? 'is-copied' : ''} onClick={() => void act(async () => { await navigator.clipboard.writeText(formatInvite(session.inviteCode)); setCopied(true) })}><AnIcon name={copied ? 'check' : 'copy'} size={16} /><span aria-live="polite">{copied ? 'Copied' : 'Copy'}</span></button></div>
    <div className="now-playing"><MediaCover videoId={session.externalMedia.videoId} /><div className="media-copy"><strong>{session.externalMedia.title || 'YouTube'}</strong><span>{mismatched ? 'Syncing shared page…' : player?.ad ? 'Waiting for ad…' : !session.externalMedia.videoId ? 'Browsing together' : session.schedule.phase === 'stalled' ? 'Waiting for a viewer…' : Math.abs(room.drift) < .3 ? 'In sync' : `${Math.abs(room.drift).toFixed(1)}s ${room.drift > 0 ? 'behind' : 'ahead'}`}</span></div></div>
    <nav className="party-tray" aria-label="Party controls">
      <button className="primary" aria-label={session.schedule.phase === 'playing' ? 'Pause room' : 'Play room'} title={canControl ? session.schedule.phase === 'playing' ? 'Pause room' : 'Play room' : 'View only'} disabled={!canControl || mismatched || busy || !room.connected || !session.externalMedia.videoId} onClick={() => void room.command(session.schedule.phase === 'playing' ? 'pause' : 'play')}>{session.schedule.phase === 'playing' ? <Glyph name="pause" /> : <AnIcon name="play" size={17} />}</button>
      <button className="icon-button" aria-label="Chat" title="Chat" aria-pressed={chatVisible} onClick={() => bridge({ type: 'toggle-panel', id: 'chat' })}><Glyph name="chat" />{unread > 0 && <span className="unread-badge">{unread > 9 ? '9+' : unread}</span>}</button>
      <button className="icon-button" aria-label="Camera & mic" title="Camera & mic" aria-pressed={avVisible} onClick={() => bridge({ type: 'toggle-panel', id: 'av' })}><Glyph name="camera" /></button>
      <button className="icon-button" aria-label="Party settings" title="Party settings" aria-expanded={optionsOpen} onClick={() => setOptionsOpen(value => !value)}><AnIcon name="settings" size={18} /></button>
    </nav>
    <section className="faces" aria-label={`People (${members.length})`}>{members.map(member => <details className="member-menu" key={member.userId}><summary className={`member-avatar${member.userId === session.hostId ? ' host' : ''}`} title={member.name} aria-label={`${member.name} actions`}>{member.name.slice(0, 1).toUpperCase()}</summary><div className="member-actions"><strong>{member.name}{member.userId === connection.user.userId ? ' (you)' : ''}</strong><small>{member.userId === session.hostId ? 'Host' : session.controllers.includes(member.userId) ? 'Can control' : 'Viewer'}</small>{isHost && member.userId !== connection.user.userId && <><button disabled={busy} aria-pressed={session.controllers.includes(member.userId)} onClick={() => void act(() => room.request('party:setController', { userId: member.userId, enabled: !session.controllers.includes(member.userId) }))}>{session.controllers.includes(member.userId) ? 'Revoke control' : 'Give control'}</button><button className="danger" disabled={busy} onClick={() => void act(() => room.request('party:kick', { userId: member.userId }))}>Remove</button></>}</div></details>)}</section>
    {isHost && session.waiting.map(member => <div key={member.userId}><span className="hint">{member.name}</span><button disabled={busy} onClick={() => void act(() => room.request('party:approve', { userId: member.userId }))}>Allow</button><button disabled={busy} onClick={() => void act(() => room.request('party:reject', { userId: member.userId }))}>Decline</button></div>)}
    {optionsOpen && <section className="party-options" aria-label="Party settings">
      <Field label="Playback speed"><select disabled={!canControl} value={session.externalMedia.playbackRate} onChange={event => void room.command('rate', undefined, Number(event.target.value))}>{[.25, .5, .75, 1, 1.25, 1.5, 1.75, 2].map(rate => <option key={rate} value={rate}>{rate}×</option>)}</select></Field>
      {isHost && <Field label="Buffering"><select value={session.syncMode} onChange={event => void act(() => room.request('party:setSyncMode', { mode: event.target.value }))}><option value="hopping">Lead — keep playing</option><option value="dragging">Follow — wait for everyone</option></select></Field>}
      <Toggle label="Gentle sync correction" value={settings.gentle} onChange={value => update('gentle', value)} /><Field label={`Sync tolerance · ${settings.tolerance.toFixed(2)}s`}><input type="range" min=".1" max="1" step=".05" value={settings.tolerance} onChange={event => update('tolerance', Number(event.target.value))} /></Field>
      <Field label="YouTube volume"><input type="range" min="0" max="1" step=".05" value={player?.volume ?? 1} onChange={event => bridge({ type: 'volume', videoId: player?.videoId, volume: Number(event.target.value) })} /></Field>
      <Field label="Dock"><select value={settings.dock} onChange={event => update('dock', event.target.value as Settings['dock'])}><option value="right">Right</option><option value="left">Left</option></select></Field>
      <Field label="Opacity"><input type="range" min=".5" max="1" step=".05" value={settings.opacity} onChange={event => update('opacity', Number(event.target.value))} /></Field>
      <Field label="Camera width"><input type="range" min="112" max="480" step="8" value={settings.tileSize} onChange={event => update('tileSize', Number(event.target.value))} /></Field>
      <Field label="Chat text size"><input type="range" min="12" max="20" step="1" value={settings.chatSize} onChange={event => update('chatSize', Number(event.target.value))} /></Field><button onClick={() => setSettings(defaults)}>Reset settings</button>
    </section>}
    <footer className="room-footer"><span className="footer-identity">{connection.user.name} · {isHost ? 'Host' : canControl ? 'Can control' : 'Viewer'}</span><button className="icon-button danger" aria-label={isHost ? 'End party' : 'Leave party'} title={isHost ? 'End party' : 'Leave party'} disabled={busy} onClick={() => void act(room.leave)}><AnIcon name="logout" size={18} /></button></footer>
  </main>
}
