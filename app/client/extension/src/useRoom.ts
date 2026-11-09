import { useCallback, useEffect, useRef, useState } from 'react'
import { io, type Socket } from 'socket.io-client'
import { acceptsSchedule, type SyncSchedule } from '../../src/sync/syncCore.ts'
import { bridge, canControl, isPlayerState, isSession, playbackPlan, timelinePosition, TICKS, type Connection, type Message, type PlayerState, type Session, type Setup } from './core.ts'
import { rpc, localGet, sessionSet, sessionRemove, observeStorage } from './platform.ts'

export interface Settings { gentle: boolean; tolerance: number; followVideo: boolean; showSelf: boolean; tileSize: number; opacity: number; dock: 'left' | 'right'; chatSize: number; hideCameras: boolean; voiceVolume: number; cameraId: string; micId: string; speakerId: string }
export const defaults: Settings = { gentle: true, tolerance: .25, followVideo: true, showSelf: true, tileSize: 168, opacity: 1, dock: 'right', chatSize: 14, hideCameras: false, voiceVolume: .8, cameraId: '', micId: '', speakerId: '' }

export function useRoom(settings: Settings) {
  const [connection, setConnection] = useState<Connection | null>(null)
  const [setup, setSetup] = useState<Setup | null>(null)
  const [loaded, setLoaded] = useState(false)
  const [startupError, setStartupError] = useState('')
  const [serverStatus, setServerStatus] = useState('Connecting')
  const [startupRevision, setStartupRevision] = useState(0)
  const [connected, setConnected] = useState(false)
  const [ownsTab, setOwnsTab] = useState(false)
  const [session, setSession] = useState<Session | null>(null)
  const [waiting, setWaiting] = useState(false)
  const [messages, setMessages] = useState<Message[]>([])
  const [player, setPlayer] = useState<PlayerState | null>(null)
  const [error, setError] = useState('')
  const [drift, setDrift] = useState(0)
  const socket = useRef<Socket | null>(null)
  const state = useRef({ connection, session, player, settings })
  state.current = { connection, session, player, settings }
  const schedule = useRef<SyncSchedule | null>(null)
  const force = useRef(false)
  const clock = useRef({ offset: 0, rtt: Infinity, ready: false })
  const pendingUntil = useRef(0)
  const tabId = useRef<number | null>(null)
  const lastStall = useRef('')
  const followingUrl = useRef('')
  const restored = useRef<{ id: string; canControl?: boolean } | null>(null)
  const publishingUrl = useRef('')
  const navigating = useRef<Promise<void> | null>(null)

  const request = useCallback((event: string, payload: Record<string, unknown> = {}): Promise<Record<string, any>> => new Promise((resolve, reject) => {
    if (!socket.current?.connected) { reject(new Error('Reconnecting to Watch Party…')); return }
    socket.current.timeout(8000).emit(event, payload, (timeout: Error | null, result: Record<string, any> = {}) => {
      if (timeout) reject(new Error('The server did not respond. Please retry.'))
      else if (result.error) reject(new Error(result.error))
      else resolve(result)
    })
  }), [])

  const accept = useCallback((next: unknown) => {
    if (!isSession(next)) return false
    const previous = state.current.session
    const ownId = state.current.connection?.user.userId
    const ownPage = state.current.player?.url
    const returningController = !previous && restored.current?.id === next.id && restored.current.canControl
    if (ownPage !== next.externalMedia.url && ((previous && previous.externalMedia.url !== next.externalMedia.url) || (!previous && next.hostId !== ownId && !returningController))) followingUrl.current = next.externalMedia.url
    if (previous?.id !== next.id) { schedule.current = null; bridge({ type: 'open' }) }
    state.current.session = next
    setSession(next); setWaiting(false)
    const current = schedule.current
    if (!current || acceptsSchedule(current.mediaGeneration, current.version ?? -1, next.schedule)) {
      schedule.current = next.schedule
      force.current = true
    }
    lastStall.current = ''
    void rpc('party-state', { partyId: next.id, inviteCode: next.inviteCode, canControl: canControl(next, ownId) }).catch(error => setError(error.message))
    void rpc('room-ready', { partyId: next.id }).catch(() => {})
    return true
  }, [])

  useEffect(() => {
    let cancelled = false
    setLoaded(false)
    setStartupError('')
    setError('')
    void rpc<{ connection?: Connection; setup?: Setup; activeParty?: { id: string; tabId: number; canControl?: boolean }; tabId: number | null; follow: string }>('bootstrap', {}, 5000).then(stored => {
      if (cancelled) return
      tabId.current = stored.tabId
      restored.current = stored.activeParty ?? null
      setOwnsTab(!!stored.activeParty && stored.activeParty.tabId === stored.tabId)
      followingUrl.current = stored.follow
      setSetup(stored.setup ?? (stored.connection ? { server: stored.connection.server, name: stored.connection.user.name } : null))
      setConnection(stored.connection ?? null)
      void rpc('status', {}, 10_000).then(status => {
        if (cancelled) return
        setServerStatus(status.connected ? 'Connected' : 'Not configured')
        if (status.connection) setConnection(previous => JSON.stringify(previous) === JSON.stringify(status.connection) ? previous : status.connection)
      }).catch(error => { if (!cancelled) { setServerStatus('Disconnected'); setError(error.message) } })
    }).catch(error => { if (!cancelled) { setStartupError(error.message); setServerStatus('Disconnected') } }).finally(() => { if (!cancelled) setLoaded(true) })
    const changed = (changes: Record<string, chrome.storage.StorageChange>, area: string) => {
      if (area === 'local' && changes.connection) setConnection((changes.connection.newValue as Connection | undefined) ?? null)
      if (area === 'local' && changes.setup) {
        setSetup((changes.setup.newValue as Setup | undefined) ?? null)
        void rpc('status', {}, 10_000).then(status => { setServerStatus(status.connected ? 'Connected' : 'Not configured'); if (status.connected) setError('') }).catch(error => { setServerStatus('Disconnected'); setError(error.message) })
      }
      if (area === 'local' && changes.activeParty) {
        const active = changes.activeParty.newValue as { id: string; tabId: number; userId: string; server: string } | null
        const owner = !!active && active.tabId === tabId.current
        setOwnsTab(owner)
        if (!owner) { followingUrl.current = ''; socket.current?.disconnect(); return }
        if (active.id === state.current.session?.id) { void rpc('room-ready', { partyId: active.id }).catch(() => {}); return }
        if (socket.current?.connected) void request('party:join', { partyId: active.id }).then(result => { if (result.status === 'waiting') setWaiting(true); else accept(result.session) }).catch(error => setError(error.message))
      }
    }
    const stop = observeStorage(changed)
    return () => { cancelled = true; stop() }
  }, [startupRevision, accept, request])

  useEffect(() => {
    if (!connection || !ownsTab) return
    const transport = io(connection.server, { transports: ['websocket'], auth: { extensionToken: connection.token }, reconnectionDelayMax: 5000 })
    socket.current = transport
    let alive = true
    const clearRoom = () => {
      if (!alive) return
      const partyId = state.current.session?.id ?? restored.current?.id
      restored.current = null
      state.current.session = null; followingUrl.current = ''; setSession(null); setWaiting(false); setMessages([])
      schedule.current = null
      if (partyId) void rpc('clear-party', { partyId }).catch(() => {})
    }
    transport.on('connect', () => {
      setConnected(true); setError(''); clock.current = { offset: 0, rtt: Infinity, ready: false }
      void localGet<{ activeParty?: { id: string; tabId: number; server: string; userId: string } }>('activeParty').then(({ activeParty }) => {
        if (!alive || activeParty?.tabId !== tabId.current || activeParty?.server !== connection.server || activeParty?.userId !== connection.user.userId) return
        restored.current = activeParty
        transport.emit('party:join', { partyId: activeParty.id }, (result: Record<string, any>) => {
          if (!alive) return
          if (result.error) { clearRoom(); setError(result.error) }
          else if (result.status === 'waiting') setWaiting(true)
          else accept(result.session)
        })
      }).catch(error => setError(error.message))
    })
    transport.on('disconnect', reason => {
      setConnected(false); clock.current.ready = false
      if (reason === 'io server disconnect') { clearRoom(); setError('Sign in again.') }
    })
    transport.on('connect_error', error => setError(error.message || 'Could not connect to your Watch Party server'))
    transport.on('party:state', accept)
    transport.on('party:approved', ({ session }) => {
      accept(session)
      transport.emit('party:resume', {}, (result: Record<string, any>) => { if (alive) accept(result.session) })
    })
    for (const event of ['party:ended', 'party:kicked', 'party:rejected', 'party:left']) transport.on(event, () => {
      clearRoom(); setError(event === 'party:ended' ? 'The host ended the party.' : event === 'party:rejected' ? 'The host declined your request.' : event === 'party:kicked' ? 'You were removed from the party.' : '')
    })
    transport.on('user:joined', member => setSession(current => current && !current.guests.some(guest => guest.userId === member.userId) && member.userId !== current.hostId ? { ...current, guests: [...current.guests, member], waiting: current.waiting.filter(waiter => waiter.userId !== member.userId) } : current))
    transport.on('user:left', ({ userId }) => setSession(current => current ? { ...current, guests: current.guests.filter(guest => guest.userId !== userId) } : current))
    transport.on('host:changed', ({ hostId }) => setSession(current => current ? { ...current, hostId, hostName: current.guests.find(guest => guest.userId === hostId)?.name ?? current.hostName } : current))
    transport.on('chat:history', history => { if (Array.isArray(history)) setMessages(history.slice(-200)) })
    transport.on('chat:message', message => { if (typeof message?.text === 'string') setMessages(current => [...current.slice(-199), message]) })
    transport.on('sync:schedule', (next: SyncSchedule) => {
      if (!Number.isFinite(next?.positionTicks)) return
      const current = schedule.current
      if (current && !acceptsSchedule(current.mediaGeneration, current.version ?? -1, next)) return
      force.current = true
      schedule.current = next
      setSession(current => current ? { ...current, schedule: next } : current)
    })
    const ping = () => {
      if (!transport.connected) return
      const start = Date.now()
      transport.timeout(3000).emit('clock:ping', start, (error: Error | null, serverTime: number) => {
        if (error || !alive || !Number.isFinite(serverTime)) return
        const end = Date.now(), rtt = end - start
        if (rtt < clock.current.rtt + 50 || !clock.current.ready) clock.current = { offset: serverTime - (start + end) / 2, rtt, ready: true }
      })
    }
    transport.on('connect', ping)
    const timer = setInterval(ping, 3000)
    return () => { alive = false; clearInterval(timer); transport.disconnect(); socket.current = null; setConnected(false); state.current.session = null; setSession(null); setWaiting(false); setMessages([]); schedule.current = null }
  }, [connection, ownsTab, accept])

  const command = useCallback(async (action: string, position?: number, rate?: number) => {
    const current = state.current
    const room = current.session
    if (!room || !current.player || current.player.videoId !== room.externalMedia.videoId) return
    if (!canControl(room, current.connection?.user.userId)) { force.current = true; return }
    pendingUntil.current = Date.now() + 1500
    try {
      if (action === 'rate') await request('party:setExternalPlaybackRate', { rate })
      else await request(`sync:${action}`, { positionTicks: Math.round((position ?? current.player.position) * TICKS), commandId: crypto.randomUUID(), mediaGeneration: schedule.current?.mediaGeneration })
      setError('')
    } catch (error) {
      setError(error instanceof Error ? error.message : 'Playback command failed')
      socket.current?.emit('sync:hello')
    } finally { pendingUntil.current = 0 }
  }, [request])

  useEffect(() => {
    const receive = (event: MessageEvent) => {
      if (!event.isTrusted || event.source !== window.parent || event.origin !== 'https://www.youtube.com' || event.data?.source !== 'watchparty-youtube') return
      const data = event.data
      if (isPlayerState(data)) {
        const snapshot = { ...data, observedAt: Date.now() }
        state.current.player = snapshot; setPlayer(snapshot)
      }
      else if (data.type === 'error') setError(String(data.message).slice(0, 300))
      else if (data.type === 'intent' && data.videoId === state.current.session?.externalMedia.videoId && ['play', 'pause', 'seek', 'rate'].includes(data.action) && Number.isFinite(data.position)) void command(data.action, data.position, data.rate)
    }
    window.addEventListener('message', receive)
    bridge({ type: 'hello' })
    return () => window.removeEventListener('message', receive)
  }, [command])

  const followRoom = useCallback(async () => {
    if (navigating.current) return navigating.current
    const current = state.current.session
    const target = current?.externalMedia.url
    if (!target || !socket.current?.connected) return
    navigating.current = (async () => {
      followingUrl.current = target
      await request('party:navigating')
      await sessionSet({ [`follow-${tabId.current}`]: target })
      if (state.current.session?.id === current.id && state.current.session.externalMedia.url === target) await rpc('navigate-party', { partyId: current.id, url: target })
    })().finally(() => { navigating.current = null })
    return navigating.current
  }, [request])

  useEffect(() => {
    if (!session || !player || !connection || !connected) return
    if (player.url === session.externalMedia.url) {
      followingUrl.current = ''
      void sessionRemove(`follow-${tabId.current}`).catch(() => {})
      return
    }
    if (followingUrl.current || !canControl(session, connection.user.userId)) {
      const follow = () => { void followRoom().catch(error => setError(error.message)) }
      follow()
      const retry = setInterval(follow, 2500)
      return () => clearInterval(retry)
    }
    const url = player.url
    if (publishingUrl.current === url) return
    const timer = setTimeout(() => {
      publishingUrl.current = url
      const latest = state.current.player
      if (latest?.url !== url) { publishingUrl.current = ''; return }
      void request('party:selectExternalMedia', { provider: 'youtube', url, title: latest.title, position: latest.ad ? 0 : latest.position })
        .catch(error => setError(error.message))
        .finally(() => { publishingUrl.current = '' })
    }, 350)
    return () => clearTimeout(timer)
  }, [session?.id, session?.externalMedia.url, session?.controllers.join(','), session?.collaborativeControl, player?.url, connected, connection?.user.userId, followRoom, request])

  useEffect(() => {
    let heartbeat = 0
    const timer = setInterval(() => {
      const { session, player, connection, settings } = state.current
      const timeline = schedule.current
      if (!session || !player || !connection || !timeline || !socket.current?.connected) return
      if (!session.externalMedia.videoId) return
      const matched = player.videoId === session.externalMedia.videoId
      const stalled = !matched || player.ad || (!player.ready && player.buffered < .5)
      const ad = player.ad && matched
      const stallKey = `${timeline.mediaGeneration}:${stalled}:${ad}`
      if (stallKey !== lastStall.current) {
        socket.current.emit('sync:stall', { stalled, ad, mediaGeneration: timeline.mediaGeneration })
        lastStall.current = stallKey
      }
      if (!matched || !clock.current.ready) return
      const now = Date.now() + clock.current.offset
      const estimated = { ...player, position: player.position + (!player.paused && player.ready && !player.ad && !player.seeking ? Math.max(0, Date.now() - (player.observedAt ?? Date.now())) / 1000 * player.rate : 0) }
      if (++heartbeat % 4 === 0) {
        const drift = timelinePosition(timeline, now) - estimated.position
        setDrift(drift)
        socket.current.emit('sync:report', { position: estimated.position, drift, rate: player.rate, mediaGeneration: timeline.mediaGeneration, stalled })
      }
      if (Date.now() < pendingUntil.current) return
      const plan = playbackPlan({ schedule: timeline, player: estimated, now, baseRate: session.externalMedia.playbackRate, force: force.current, gentle: settings.gentle, tolerance: settings.tolerance, hostLead: session.hostId === connection.user.userId && session.syncMode === 'hopping' })
      if (plan) { bridge({ type: 'apply', videoId: session.externalMedia.videoId, ...plan }); force.current = false }
    }, 250)
    return () => clearInterval(timer)
  }, [])

  async function create() {
    if (!state.current.connection?.user.isAdmin) throw new Error('Sign in as admin in the extension setup to create party codes.')
    await rpc('create-party', {}, 30_000)
  }
  async function join(code: string) {
    await rpc('join-party', { code }, 30_000)
  }
  async function leave() {
    await rpc('disconnect-party', {}, 25_000)
    schedule.current = null; state.current.session = null; setSession(null); setWaiting(false); setMessages([])
  }
  async function refresh() {
    const result = await request('party:resume')
    accept(result.session)
  }
  return { connection, setup, loaded, startupError, retryStartup: () => setStartupRevision(value => value + 1), serverStatus, connected, ownsTab, session, waiting, messages, player, error, setError, drift, request, command, create, join, leave, refresh, followRoom }
}
