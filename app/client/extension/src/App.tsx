import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import type { VideoTrack } from 'livekit-client'
import { useLiveKit, type LiveKitParticipantView } from '../../src/hooks/useLiveKit.ts'
import { bridge, canControl as mayControl, formatInvite, type Member } from './core.ts'
import { defaults, useRoom, type Settings } from './useRoom.ts'
import { useFloatingCameras } from './useFloatingCameras.tsx'
import { useFloatingPanels } from './useFloatingPanels.tsx'
import { AnIcon } from '../../src/analog/icons.tsx'
import { rpc, localGet, localSet, sessionGet, sessionSet } from './platform.ts'
import Avatar from '../../src/components/Avatar.tsx'
import Chat from './Chat.tsx'
import { createAvatar } from '@humation/core'
import { assets, effectiveConfig } from '../../src/lib/avatar.ts'

const avatarImages = new Map<string, string>()
function avatarImage(member: Member) {
  const key = `${member.userId}:${JSON.stringify(member.avatar)}`
  if (!avatarImages.has(key)) {
    if (avatarImages.size > 200) avatarImages.clear()
    avatarImages.set(key, `data:image/svg+xml,${encodeURIComponent(createAvatar(assets, effectiveConfig(member.userId, member.avatar)).toString())}`)
  }
  return avatarImages.get(key)
}

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
function Tile({ participant, member, local, volume, onVolume }: { participant: LiveKitParticipantView; member?: Member; local: boolean; volume: number; onVolume: (value: number) => void }) {
  const ref = useRef<HTMLVideoElement>(null)
  const track = participant.videoTrack as VideoTrack | null
  useEffect(() => {
    const video = ref.current
    if (!track || !video) return
    track.attach(video)
    return () => { track.detach(video) }
  }, [track])
  return <article className={`camera-tile${participant.isSpeaking ? ' speaking' : ''}`}>
    <div className="camera-picture">{track ? <video ref={ref} autoPlay playsInline muted className={local ? 'mirrored' : ''} /> : <Avatar userId={participant.identity} name={participant.name} config={member?.avatar} size={64} circle />}</div>
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
  const [busy, setBusy] = useState(false)
  const [avBusy, setAVBusy] = useState(false)
  const [copied, setCopied] = useState(false)
  const [optionsOpen, setOptionsOpen] = useState(false)
  const [chatVisible, setChatVisible] = useState(false)
  const [unread, setUnread] = useState(0)
  const readIncoming = useRef(0)
  const [devices, setDevices] = useState<MediaDeviceInfo[]>([])
  const [volumes, setVolumes] = useState<Record<string, number>>({})
  const restoredAV = useRef('')
  const isHost = !!session && session.hostId === connection?.user.userId
  const canControl = !!session && mayControl(session, connection?.user.userId)
  const mismatched = !!session && !!player && player.url !== session.externalMedia.url
  useEffect(() => { setCopied(false); setOptionsOpen(false); setUnread(0); setVolumes({}) }, [session?.id])
  useEffect(() => { bridge({ type: 'panel-mode', active: !!session }) }, [session?.id])
  useEffect(() => {
    const dismiss = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      if (optionsOpen) setOptionsOpen(false)
      else bridge({ type: 'close-controls' })
    }
    window.addEventListener('keydown', dismiss)
    return () => window.removeEventListener('keydown', dismiss)
  }, [optionsOpen])
  useEffect(() => {
    void localGet<{ settings?: Partial<Settings> }>('settings').then(({ settings }) => { setSettings({ ...defaults, ...settings }); setSettingsLoaded(true) }).catch(() => setSettingsLoaded(true))
  }, [])
  useEffect(() => {
    if (settingsLoaded) void localSet({ settings }).catch(() => {})
    bridge({ type: 'layout', dock: settings.dock, opacity: settings.opacity })
  }, [settings, settingsLoaded])
  useEffect(() => {
    const delta = Math.max(0, room.incomingCount - readIncoming.current)
    readIncoming.current = room.incomingCount
    if (chatVisible || !session) setUnread(0)
    else if (delta) setUnread(value => value + delta)
  }, [room.incomingCount, chatVisible, session?.id])
  useEffect(() => { bridge({ type: 'chat-unread', count: unread }) }, [unread, chatVisible])
  useEffect(() => {
    let lastActivity = 0
    const wake = () => { if (Date.now() - lastActivity < 80) return; lastActivity = Date.now(); bridge({ type: 'activity' }) }
    for (const type of ['pointermove', 'pointerdown', 'keydown', 'input']) window.addEventListener(type, wake, { passive: true })
    return () => { for (const type of ['pointermove', 'pointerdown', 'keydown', 'input']) window.removeEventListener(type, wake) }
  }, [])
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
  const members: Member[] = session ? [{ userId: session.hostId, name: session.hostName, avatar: session.hostAvatar }, ...session.guests.filter(guest => guest.userId !== session.hostId)] : []
  const participants = [...(settings.showSelf && media.localParticipant ? [media.localParticipant] : []), ...media.participants]
  const tileParticipants = members.filter(member => settings.showSelf || member.userId !== connection?.user.userId).map(member => participants.find(participant => participant.identity === member.userId) ?? { identity: member.userId, name: member.name, videoTrack: null, audioTrack: null, isSpeaking: false })
  const floatingCameras = useFloatingCameras(settings.hideCameras ? [] : tileParticipants.map(participant => ({ id: participant.identity, name: participant.name, speaking: participant.isSpeaking, avatar: avatarImage(members.find(member => member.userId === participant.identity) ?? { userId: participant.identity, name: participant.name }) })), settings.tileSize, id => {
    const participant = tileParticipants.find(participant => participant.identity === id)
    return participant ? <Tile participant={participant} member={members.find(member => member.userId === id)} local={participant.identity === connection?.user.userId} volume={volumes[id] ?? settings.voiceVolume} onVolume={value => setVolumes(previous => ({ ...previous, [id]: value }))} /> : null
  })
  const floatingPanels = useFloatingPanels(!!session, id => <main className={`independent-content ${id}-content`} style={{ '--chat-size': `${settings.chatSize}px` } as CSSProperties}>
    {id === 'chat' ? <Chat key={session?.id} messages={room.messages} members={members} ownId={connection?.user.userId} connected={room.connected} onSend={content => room.request('chat:message', content)} onError={room.setError} onClose={() => bridge({ type: 'toggle-panel', id: 'chat' })} /> : id === 'status' ? <button className={`watch-status${room.connected ? ' online' : ''}`} title={room.connected ? `${members.length} people in your party` : 'Reconnecting to your party'} onClick={() => bridge({ type: 'open-controls' })}><i className="connection-dot" /><AnIcon name="link" size={14} /><span>{members.length}</span><span className="sr-only">{room.connected ? 'Connected' : 'Reconnecting'}</span></button> : <>
      <div className="av-buttons">
        <button className="icon-button" aria-label={session?.schedule.phase === 'playing' ? 'Pause room' : 'Play room'} title={canControl ? session?.schedule.phase === 'playing' ? 'Pause room' : 'Play room' : 'Playback is controlled by the host'} disabled={!canControl || mismatched || busy || !room.connected || !session?.externalMedia.videoId} onClick={() => void room.command(session?.schedule.phase === 'playing' ? 'pause' : 'play')}>{session?.schedule.phase === 'playing' ? <Glyph name="pause" /> : <AnIcon name="play" size={17} />}</button>
        <button className={`icon-button${!media.micOn ? ' device-off' : ''}`} disabled={!media.connected || avBusy} aria-label={media.micOn ? 'Mic on' : 'Mic off'} title={media.micOn ? 'Mute microphone' : 'Unmute microphone'} aria-pressed={media.micOn} onClick={() => void toggleAV('mic')}><Glyph name="mic" /></button>
        <button className={`icon-button${!media.camOn ? ' device-off' : ''}`} disabled={!media.connected || avBusy} aria-label={media.camOn ? 'Camera on' : 'Camera off'} title={media.camOn ? 'Turn camera off' : 'Turn camera on'} aria-pressed={media.camOn} onClick={() => void toggleAV('camera')}><Glyph name="camera" /></button>
        <button className="icon-button" aria-label="Toggle fullscreen" title="Toggle fullscreen" onClick={() => bridge({ type: 'fullscreen' })}><img src="expand.svg" width="18" height="18" alt="" /></button>
      </div>
    </>}
  </main>, (id, visible) => { if (id === 'chat') setChatVisible(visible) })

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
    {floatingCameras}{floatingPanels}<h1 className="sr-only">Room {session.id}</h1>
    <header className="panel-heading">
      {optionsOpen && <button className="icon-button" aria-label="Back to party" onClick={() => setOptionsOpen(false)}><AnIcon name="back" /></button>}
      <div><h2>{optionsOpen ? 'Preferences' : 'Your party'}</h2><span>{optionsOpen ? 'Make yourself comfortable' : `${members.length} watching together`}</span></div>
      {!optionsOpen && <button className="icon-button" aria-label="Party settings" title="Party settings" onClick={() => setOptionsOpen(true)}><AnIcon name="settings" size={18} /></button>}
      <button className="icon-button" aria-label="Close party controls" title="Close party controls" onClick={() => bridge({ type: 'close-controls' })}><AnIcon name="x" size={17} /></button>
    </header>
    {(room.error || media.error) && <div className="notice" role="alert">{room.error || media.error}<button onClick={() => { room.setError(''); media.reportError(null) }} aria-label="Dismiss message">Dismiss</button></div>}
    <div className="panel-body">
      {!optionsOpen ? <>
        <div className="now-playing"><MediaCover videoId={session.externalMedia.videoId} /><div className="media-copy"><strong>{session.externalMedia.title || 'YouTube'}</strong><span>{mismatched ? 'Syncing shared page…' : player?.ad ? 'Waiting for ad…' : !session.externalMedia.videoId ? 'Browsing together' : session.schedule.phase === 'stalled' ? 'Waiting for a viewer…' : Math.abs(room.drift) < .3 ? 'In sync' : `${Math.abs(room.drift).toFixed(1)}s ${room.drift > 0 ? 'behind' : 'ahead'}`}</span></div></div>
        <section className="people-list" aria-label={`People (${members.length})`}>{members.map(member => <details className="member-menu" key={member.userId}>
          <summary aria-label={`${member.name} actions`}><Avatar userId={member.userId} name={member.name} config={member.avatar} size={30} circle /><span className="member-copy"><strong>{member.userId === connection.user.userId ? `${member.name} (you)` : member.name}</strong><small>{member.userId === session.hostId ? 'Host' : session.controllers.includes(member.userId) ? 'Playback control' : 'Watching'}</small></span><AnIcon name="back" size={14} /></summary>
          <div className="member-actions">{isHost && member.userId !== connection.user.userId ? <><button disabled={busy} aria-pressed={session.controllers.includes(member.userId)} onClick={() => void act(() => room.request('party:setController', { userId: member.userId, enabled: !session.controllers.includes(member.userId) }))}>{session.controllers.includes(member.userId) ? 'Revoke control' : 'Give control'}</button><button disabled={busy} onClick={() => void act(() => room.request('party:transferHost', { userId: member.userId }))}>Make host</button><button className="danger" disabled={busy} onClick={() => void act(() => room.request('party:kick', { userId: member.userId }))}>Remove</button></> : <p className="hint">{member.userId === session.hostId ? 'The host manages this party.' : 'Watching with you.'}</p>}</div>
        </details>)}</section>
        <Field label="Sync mode"><select disabled={!isHost || busy} value={session.syncMode} onChange={event => void act(() => room.request('party:setSyncMode', { mode: event.target.value }))}><option value="hopping">Keep playing</option><option value="dragging">Wait for everyone</option></select></Field>
        <div className="invite-strip"><div><span>Invite a friend</span><strong>{formatInvite(session.inviteCode)}</strong></div><button title="Copy invite code" aria-label="Copy invite code" className="icon-button" onClick={() => void act(async () => { await navigator.clipboard.writeText(formatInvite(session.inviteCode)); setCopied(true) })}><AnIcon name={copied ? 'check' : 'copy'} size={17} /></button><span className="sr-only" role="status">{copied ? 'Invite code copied' : ''}</span></div>
        {isHost && session.waiting.map(member => <div className="waiting-person" key={member.userId}><span>{member.name} wants to join</span><button disabled={busy} onClick={() => void act(() => room.request('party:approve', { userId: member.userId }))}>Allow</button><button disabled={busy} onClick={() => void act(() => room.request('party:reject', { userId: member.userId }))}>Decline</button></div>)}
      </> : <section className="party-options" aria-label="Party settings">
        <details className="settings-group" open><summary>Camera & sound</summary>
          {([['cameraId', 'videoinput', 'Camera'], ['micId', 'audioinput', 'Microphone'], ['speakerId', 'audiooutput', 'Speakers']] as const).map(([key, kind, name]) => <Field key={key} label={name}><select value={settings[key]} onChange={event => update(key, event.target.value)}><option value="">System default</option>{devices.filter(device => device.kind === kind).map((device, index) => <option key={device.deviceId || index} value={device.deviceId}>{device.label || `${name} ${index + 1}`}</option>)}</select></Field>)}
          <Field label="Voice volume"><input type="range" min="0" max="1" step=".05" value={settings.voiceVolume} onChange={event => { update('voiceVolume', Number(event.target.value)); setVolumes({}) }} /></Field>
          <Toggle label="Show my feed" value={settings.showSelf} onChange={value => update('showSelf', value)} /><Toggle label="Hide all feeds" value={settings.hideCameras} onChange={value => update('hideCameras', value)} />
          <div className="settings-actions"><button onClick={() => void refreshDevices()}>Refresh devices</button><button onClick={media.reconnect}>Reconnect audio</button></div>
        </details>
        <details className="settings-group"><summary>Playback</summary>
          <Field label="Speed"><select disabled={!canControl} value={session.externalMedia.playbackRate} onChange={event => void room.command('rate', undefined, Number(event.target.value))}>{[.25, .5, .75, 1, 1.25, 1.5, 1.75, 2].map(rate => <option key={rate} value={rate}>{rate}×</option>)}</select></Field>
          {isHost && <Toggle label="Everyone can control playback" value={session.collaborativeControl} onChange={value => void act(() => room.request('party:setCollaborative', { enabled: value }))} />}
          <Toggle label="Gentle sync correction" value={settings.gentle} onChange={value => update('gentle', value)} /><Field label={`Sync tolerance · ${settings.tolerance.toFixed(2)}s`}><input type="range" min=".1" max="1" step=".05" value={settings.tolerance} onChange={event => update('tolerance', Number(event.target.value))} /></Field>
          <Field label="YouTube volume"><input type="range" min="0" max="1" step=".05" value={player?.volume ?? 1} onChange={event => bridge({ type: 'volume', videoId: player?.videoId, volume: Number(event.target.value) })} /></Field>
        </details>
        <details className="settings-group"><summary>Display</summary>
          <Field label="Dock"><select value={settings.dock} onChange={event => update('dock', event.target.value as Settings['dock'])}><option value="right">Right</option><option value="left">Left</option></select></Field>
          <Field label="Opacity"><input type="range" min=".5" max="1" step=".05" value={settings.opacity} onChange={event => update('opacity', Number(event.target.value))} /></Field>
          <Field label="Feed size"><input type="range" min="112" max="480" step="8" value={settings.tileSize} onChange={event => update('tileSize', Number(event.target.value))} /></Field>
          <Field label="Chat text size"><input type="range" min="12" max="20" step="1" value={settings.chatSize} onChange={event => update('chatSize', Number(event.target.value))} /></Field>
        </details>
        <div className="settings-actions"><button onClick={openSettings}>Connection settings</button><button onClick={() => setSettings(defaults)}>Reset</button></div>
      </section>}
      {media.audioBlocked && <button className="primary wide" onClick={() => void media.startAudio()}>Enable room audio</button>}
    </div>
    <footer className="room-footer"><span className={`connection-status${room.connected ? ' online' : ''}`}><i className="connection-dot" />{room.connected ? 'Connected' : 'Reconnecting…'}</span><button className="leave-button" disabled={busy} onClick={() => void act(room.leave)}><AnIcon name="power" size={14} />{isHost ? 'End party' : 'Leave party'}</button></footer>
  </main>
}
