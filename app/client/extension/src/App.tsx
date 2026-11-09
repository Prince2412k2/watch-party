import { useEffect, useRef, useState, type CSSProperties, type FormEvent, type ReactNode } from 'react'
import type { VideoTrack } from 'livekit-client'
import { useLiveKit, type LiveKitParticipantView } from '../../src/hooks/useLiveKit.ts'
import { bridge, type Member } from './core.ts'
import { defaults, useRoom, type Settings } from './useRoom.ts'

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
  const { connection, session, player } = room
  const media = useLiveKit({ partyId: session?.id, enabled: !!session && room.connected, tokenEndpoint: connection ? `${connection.server}/api/extension/livekit-token` : '/api/extension/livekit-token', authToken: connection?.token })
  const [tab, setTab] = useState<'chat' | 'people' | 'settings'>('chat')
  const [invite, setInvite] = useState('')
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [volumes, setVolumes] = useState<Record<string, number>>({})
  const bottom = useRef<HTMLDivElement>(null)
  const navigating = useRef('')
  const isHost = !!session && session.hostId === connection?.user.userId
  const canControl = isHost || !!session?.collaborativeControl
  const mismatched = !!session && player?.videoId !== session.externalMedia.videoId

  useEffect(() => {
    void chrome.storage.local.get<{ settings?: Partial<Settings> }>('settings').then(({ settings }) => { setSettings({ ...defaults, ...settings }); setSettingsLoaded(true) }).catch(() => setSettingsLoaded(true))
  }, [])
  useEffect(() => {
    if (settingsLoaded) void chrome.storage.local.set({ settings })
    bridge({ type: 'layout', dock: settings.dock, opacity: settings.opacity })
  }, [settings, settingsLoaded])
  useEffect(() => { if (tab === 'chat') bottom.current?.scrollIntoView({ block: 'end' }) }, [room.messages.length, tab])
  useEffect(() => {
    if (!session || !player || !mismatched || isHost || !settings.followVideo) { if (!mismatched) navigating.current = ''; return }
    if (navigating.current === session.externalMedia.videoId) return
    navigating.current = session.externalMedia.videoId
    bridge({ type: 'navigate', videoId: session.externalMedia.videoId })
  }, [session?.externalMedia.videoId, player?.available, mismatched, isHost, settings.followVideo])

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

  if (!room.loaded) return <main className="empty"><p>Loading Watch Party…</p></main>
  if (!connection) return <main className="empty"><p className="eyebrow">YOUTUBE, TOGETHER</p><h1>Bring your people.</h1><p>Pair this browser with your Watch Party server using the extension’s toolbar popup.</p><p>In Watch Party, open <strong>/extension</strong> to generate your pairing code.</p></main>

  return <main className="app" style={{ '--chat-size': `${settings.chatSize}px`, '--tile-size': `${settings.tileSize}px` } as CSSProperties}>
    <header className="room-header"><div><p className="eyebrow">{room.connected ? 'CONNECTED' : 'RECONNECTING'}</p><h1>{session ? `Room ${session.id}` : 'Watch together'}</h1></div><span className={`connection-dot${room.connected ? ' online' : ''}`} title={room.connected ? 'Connected' : 'Disconnected'} /></header>
    {(room.error || media.error) && <div className="notice" role="alert">{room.error || media.error}<button onClick={() => { room.setError(''); media.reportError(null) }} aria-label="Dismiss message">Dismiss</button></div>}
    {!session ? <div className="setup">
      <p className="current-title">{player?.available ? player.title : 'Open a YouTube video to start a party.'}</p>
      {player?.live && <p className="notice">Live streams are not supported in this first version.</p>}
      {room.waiting ? <><h2>Waiting for the host</h2><p>Your request is in. The host needs to let you into the room.</p><button onClick={() => void act(room.leave)} disabled={busy}>Cancel request</button></> : <>
        <button className="primary" disabled={busy || !room.connected || !player?.available || player.live} onClick={() => void act(room.create)}>Start a YouTube party</button>
        <div className="divider">or join your friends</div>
        <form onSubmit={event => { event.preventDefault(); void act(() => room.join(invite)) }}><Field label="Room code"><input value={invite} onChange={event => setInvite(event.target.value.toUpperCase())} placeholder="8-character code" maxLength={8} pattern="[A-Fa-f0-9]{8}" required /></Field><button disabled={busy || !room.connected}>Request to join</button></form>
      </>}
      <a href={`${connection.server}/extension`} target="_blank" rel="noreferrer">Manage paired browsers</a>
    </div> : <>
      <div className="now-playing"><strong>{session.externalMedia.title || 'YouTube video'}</strong><span>{session.schedule.phase === 'stalled' ? 'Waiting for a viewer or ad…' : session.schedule.phase === 'playing' ? 'Playing together' : 'Paused'} · {Math.abs(room.drift) < .3 ? 'In sync' : `${Math.abs(room.drift).toFixed(1)}s ${room.drift > 0 ? 'behind' : 'ahead'}`}</span></div>
      {mismatched && <div className="notice"><p>You’re on a different video.</p><button onClick={() => bridge({ type: 'navigate', videoId: session.externalMedia.videoId })}>Open room video</button>{canControl && player?.available && !player.live && <button onClick={() => void act(() => room.request('party:selectExternalMedia', { provider: 'youtube', videoId: player.videoId, title: player.title }))}>Watch this video instead</button>}</div>}
      {player?.ad && <p className="notice">YouTube is showing an ad. Timeline corrections are paused until it ends.</p>}
      <div className="playback-buttons"><button disabled={!canControl || mismatched || busy || !room.connected} onClick={() => void room.command(session.schedule.phase === 'playing' ? 'pause' : 'play')}>{session.schedule.phase === 'playing' ? 'Pause room' : 'Play room'}</button><button onClick={() => void act(() => navigator.clipboard.writeText(session.id))}>Copy code</button></div>
      <div className="av-buttons"><button disabled={!media.connected} aria-pressed={media.camOn} onClick={() => void media.enableCamera(!media.camOn)}>{media.camOn ? 'Camera on' : 'Camera off'}</button><button disabled={!media.connected} aria-pressed={media.micOn} onClick={() => void media.enableMic(!media.micOn)}>{media.micOn ? 'Mic on' : 'Mic off'}</button><button aria-pressed={!settings.hideCameras} onClick={() => update('hideCameras', !settings.hideCameras)}>{settings.hideCameras ? 'Show feeds' : 'Hide feeds'}</button></div>
      {!media.connected && <p className="hint">Connecting voice & cameras… <button onClick={media.reconnect}>Retry connection</button></p>}
      {media.audioBlocked && <button className="primary" onClick={() => void media.startAudio()}>Enable room audio</button>}
      {!settings.hideCameras && <section className="camera-grid" aria-label="Participant video feeds">{tileParticipants.map(participant => <Tile key={participant.identity} participant={participant} local={participant.identity === connection.user.userId} volume={volumes[participant.identity] ?? settings.voiceVolume} onVolume={value => setVolumes(previous => ({ ...previous, [participant.identity]: value }))} />)}</section>}
      <nav className="tabs" aria-label="Room panels">{(['chat', 'people', 'settings'] as const).map(name => <button key={name} aria-current={tab === name ? 'page' : undefined} onClick={() => setTab(name)}>{name === 'people' ? `People (${members.length})` : name === 'chat' ? 'Chat' : 'Settings'}</button>)}</nav>
      {tab === 'chat' && <section className="chat-panel" aria-label="Party chat"><div className="messages" role="log" aria-live="polite">{room.messages.length ? room.messages.map((message, index) => <article className={`message${message.userId === connection.user.userId ? ' own' : ''}`} key={`${message.timestamp}-${index}`}><div><strong>{message.name}</strong><time>{new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</time></div><p>{message.text}</p></article>) : <p className="hint">Say hello. Your messages stay in this party.</p>}<div ref={bottom} /></div><form className="chat-compose" onSubmit={send}><label className="sr-only" htmlFor="chat-draft">Message the room</label><input id="chat-draft" placeholder="Message the room…" value={draft} maxLength={2000} onChange={event => setDraft(event.target.value)} autoComplete="off" /><button disabled={busy || !draft.trim() || !room.connected}>Send</button></form></section>}
      {tab === 'people' && <section className="panel-scroll"><p className="hint">{isHost ? 'You’re hosting. Approve friends and manage the room.' : `${session.hostName} is hosting.`}</p>
        {isHost && session.waiting.length > 0 && <div><h2>Waiting to join</h2>{session.waiting.map(member => <div className="member" key={member.userId}><strong>{member.name}</strong><div className="row"><button disabled={busy} onClick={() => void act(() => room.request('party:approve', { userId: member.userId }))}>Allow</button><button disabled={busy} onClick={() => void act(async () => { await room.request('party:reject', { userId: member.userId }); await room.refresh() })}>Decline</button></div></div>)}</div>}
        {members.map(member => <div className="member" key={member.userId}><strong>{member.name}{member.userId === connection.user.userId ? ' (you)' : ''}<small>{member.userId === session.hostId ? 'Host' : 'Viewer'}</small></strong>{isHost && member.userId !== connection.user.userId && <div className="row"><button disabled={busy} onClick={() => void act(() => room.request('party:transferHost', { userId: member.userId }))}>Make host</button><button disabled={busy} onClick={() => void act(() => room.request('party:kick', { userId: member.userId }))}>Remove</button></div>}</div>)}
      </section>}
      {tab === 'settings' && <section className="panel-scroll settings">
        <details open><summary>Playback & sync</summary><p className="hint">Quality, captions, and volume remain available in YouTube’s player.</p>
          <Field label="Room playback speed"><select disabled={!canControl} value={session.externalMedia.playbackRate} onChange={event => void room.command('rate', undefined, Number(event.target.value))}>{[.25, .5, .75, 1, 1.25, 1.5, 1.75, 2].map(rate => <option key={rate} value={rate}>{rate}×</option>)}</select></Field>
          {isHost && <><Field label="Buffering behavior"><select value={session.syncMode} onChange={event => void act(() => room.request('party:setSyncMode', { mode: event.target.value }))}><option value="hopping">Lead: keep going when guests buffer</option><option value="dragging">Follow: wait for everyone</option></select></Field><Toggle label="Everyone can play, pause, seek & change videos" value={session.collaborativeControl} onChange={enabled => void act(() => room.request('party:setCollaborative', { enabled }))} /></>}
          <Toggle label="Gently adjust speed to correct drift" value={settings.gentle} onChange={value => update('gentle', value)} /><Field label={`Sync tolerance: ${settings.tolerance.toFixed(2)} seconds`}><input type="range" min=".1" max="1" step=".05" value={settings.tolerance} onChange={event => update('tolerance', Number(event.target.value))} /></Field><Toggle label="Automatically follow the host to a new video" value={settings.followVideo} onChange={value => update('followVideo', value)} />
          <Field label="Your YouTube volume"><input type="range" min="0" max="1" step=".05" value={player?.volume ?? 1} onChange={event => bridge({ type: 'volume', videoId: player?.videoId, volume: Number(event.target.value) })} /></Field>
        </details>
        <details><summary>Camera, microphone & voice</summary><p className="hint">Camera and microphone start off. Echo cancellation, noise suppression, and automatic gain are enabled.</p><button onClick={() => void refreshDevices()}>Refresh devices</button>
          {([['cameraId', 'videoinput', 'Camera'], ['micId', 'audioinput', 'Microphone'], ['speakerId', 'audiooutput', 'Speakers']] as const).map(([key, kind, name]) => <Field key={key} label={name}><select value={settings[key]} onChange={event => update(key, event.target.value)}><option value="">System default</option>{devices.filter(device => device.kind === kind).map((device, index) => <option key={device.deviceId || index} value={device.deviceId}>{device.label || `${name} ${index + 1}`}</option>)}</select></Field>)}
          <Field label={`Default participant volume: ${Math.round(settings.voiceVolume * 100)}%`}><input type="range" min="0" max="1" step=".05" value={settings.voiceVolume} onChange={event => { update('voiceVolume', Number(event.target.value)); setVolumes({}) }} /></Field><Toggle label="Show my own camera tile" value={settings.showSelf} onChange={value => update('showSelf', value)} /><button onClick={media.reconnect}>Reconnect voice & cameras</button>
        </details>
        <details><summary>Overlay & chat</summary><p className="hint">Drag the top bar to move the overlay. Drag its lower corner to resize it. It stays visible in YouTube fullscreen.</p><Field label="Dock"><select value={settings.dock} onChange={event => update('dock', event.target.value as Settings['dock'])}><option value="right">Right</option><option value="left">Left</option></select></Field><Field label={`Overlay opacity: ${Math.round(settings.opacity * 100)}%`}><input type="range" min=".5" max="1" step=".05" value={settings.opacity} onChange={event => update('opacity', Number(event.target.value))} /></Field><Field label="Camera tile size"><input type="range" min="90" max="240" step="10" value={settings.tileSize} onChange={event => update('tileSize', Number(event.target.value))} /></Field><Field label="Chat text size"><input type="range" min="12" max="20" step="1" value={settings.chatSize} onChange={event => update('chatSize', Number(event.target.value))} /></Field><button onClick={() => setSettings(defaults)}>Reset personal settings</button></details>
      </section>}
      <footer className="room-footer"><span>{connection.user.name}</span><button className="danger" disabled={busy} onClick={() => void act(room.leave)}>{isHost ? 'End party' : 'Leave party'}</button></footer>
    </>}
  </main>
}
