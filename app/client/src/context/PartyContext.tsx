import { createContext, useContext, useEffect, useReducer, useRef } from 'react'
import type { ReactNode } from 'react'
import { useSocket } from '../hooks/useSocket'
import { navigate } from '../router'
import { mirror } from '../mirror'
import type { BrowseEntry, MirrorPoint, PartyContextValue, PartySession, PartyUser, ToastRecord } from '../types'
import { isChatMessage, isMirrorPoint, isObject, isPartyBrowse, isPartySession, isPartyUser } from '../guards'

const PartyContext = createContext<PartyContextValue | null>(null)

interface PartyState {
  session: PartySession | null
  role: PartyContextValue['role']
  messages: PartyContextValue['messages']
  layoutMode: PartyContextValue['layoutMode']
  chatOpen: boolean
  chatFocusToken: number
  chatRipple: number
  alertMode: PartyContextValue['alertMode']
  toasts: ToastRecord[]
}

type PartyAction =
  | { type: 'SET_SESSION'; session: PartySession; role: PartyContextValue['role'] }
  | { type: 'SET_ROLE'; role: PartyContextValue['role'] }
  | { type: 'UPDATE_SESSION'; patch: Partial<PartySession> }
  | { type: 'PUSH_MESSAGE'; msg: PartyContextValue['messages'][number] }
  | { type: 'SET_MESSAGES'; msgs: PartyContextValue['messages'] }
  | { type: 'SET_LAYOUT'; mode: PartyContextValue['layoutMode'] }
  | { type: 'TOGGLE_CHAT' }
  | { type: 'OPEN_CHAT'; focus?: boolean }
  | { type: 'CLOSE_CHAT' }
  | { type: 'SET_ALERT_MODE'; mode: PartyContextValue['alertMode'] }
  | { type: 'RIPPLE' }
  | { type: 'ADD_TOAST'; toast: ToastRecord }
  | { type: 'REMOVE_TOAST'; id: number }
  | { type: 'USER_JOINED'; user: PartyUser }
  | { type: 'USER_LEFT'; userId: string }
  | { type: 'HOST_CHANGED'; hostId: string }
  | { type: 'WAITING_USER'; user: PartyUser }
  | { type: 'CLEAR' }

const initialState: PartyState = {
  session: null,
  role: null,
  messages: [],
  layoutMode: 'float',
  chatOpen: false,
  chatFocusToken: 0,
  chatRipple: 0,
  alertMode: 'focus',
  toasts: [],
}

function reducer(state: PartyState, action: PartyAction): PartyState {
  switch (action.type) {
    case 'SET_SESSION':
      return { ...state, session: action.session, role: action.role }
    case 'SET_ROLE':
      return { ...state, role: action.role }
    case 'UPDATE_SESSION':
      return { ...state, session: state.session ? { ...state.session, ...action.patch } : null }
    case 'PUSH_MESSAGE':
      return { ...state, messages: [...state.messages, action.msg] }
    case 'SET_MESSAGES':
      return { ...state, messages: action.msgs }
    case 'SET_LAYOUT':
      return { ...state, layoutMode: action.mode }
    case 'TOGGLE_CHAT':
      return { ...state, chatOpen: !state.chatOpen, chatFocusToken: state.chatFocusToken + 1 }
    case 'OPEN_CHAT':
      return { ...state, chatOpen: true, chatFocusToken: state.chatFocusToken + (action.focus ? 1 : 0) }
    case 'CLOSE_CHAT':
      return { ...state, chatOpen: false }
    case 'SET_ALERT_MODE':
      return { ...state, alertMode: action.mode }
    case 'RIPPLE':
      return { ...state, chatRipple: state.chatRipple + 1 }
    case 'ADD_TOAST':
      return { ...state, toasts: [...state.toasts, action.toast] }
    case 'REMOVE_TOAST':
      return { ...state, toasts: state.toasts.filter(t => t.id !== action.id) }
    case 'USER_JOINED': {
      const guests = state.session
        ? [...(state.session.guests ?? []), { userId: action.user.userId, name: action.user.name }]
        : []
      return { ...state, session: state.session ? { ...state.session, guests } : null }
    }
    case 'USER_LEFT': {
      const guests = (state.session?.guests ?? []).filter(g => g.userId !== action.userId)
      return { ...state, session: state.session ? { ...state.session, guests } : null }
    }
    case 'HOST_CHANGED':
      return { ...state, session: state.session ? { ...state.session, hostId: action.hostId } : null }
    case 'WAITING_USER': {
      const current = state.session?.waiting ?? []
      if (current.some(w => w.userId === action.user.userId)) return state
      const waiting = [...current, action.user]
      return { ...state, session: state.session ? { ...state.session, waiting } : null }
    }
    case 'CLEAR':
      return initialState
    default:
      return state
  }
}

export function PartyProvider({ children, userId }: { children?: ReactNode; userId?: string } = {}) {
  const [state, dispatch] = useReducer(reducer, initialState)
  const { socket } = useSocket()
  const stateRef = useRef<PartyState>(initialState)
  stateRef.current = state

  useEffect(() => {
    function toast(msg: string, level = 'info') {
      const id = Date.now()
      dispatch({ type: 'ADD_TOAST', toast: { id, msg, level } })
      setTimeout(() => dispatch({ type: 'REMOVE_TOAST', id }), 4000)
    }

    socket.on('party:state', (value: unknown) => {
      if (!isPartySession(value)) return
      const sess = value
      const role = sess.hostId === userId ? 'host' : 'guest'
      dispatch({ type: 'SET_SESSION', session: sess, role })
    })

    socket.on('party:waiting', (value: unknown) => {
      if (!isPartyUser(value)) return
      const user = value
      dispatch({ type: 'WAITING_USER', user })
      toast(`${user.name} wants to join`, 'warning')
    })

    socket.on('party:approved', (value: unknown) => {
      if (!isObject(value) || !isPartySession(value.session)) return
      const sess = value.session
      dispatch({ type: 'SET_SESSION', session: sess, role: 'guest' })
    })

    socket.on('party:rejected', () => {
      navigate('/library')
      toast('The host declined your request')
    })

    socket.on('party:kicked', () => {
      dispatch({ type: 'CLEAR' })
      navigate('/library')
      toast('You were removed from the party')
    })

    // party:ended — the host deliberately ended the session for everyone
    // (distinct from a host disconnect, which grants a grace period + promotes
    // a guest instead). Broadcast to guests only; the host navigates locally
    // from endParty()'s own ack.
    socket.on('party:ended', () => {
      dispatch({ type: 'CLEAR' })
      navigate('/library')
      toast('The host ended the party')
    })

    socket.on('user:joined', (value: unknown) => {
      if (!isPartyUser(value)) return
      const user = value
      dispatch({ type: 'USER_JOINED', user })
      toast(`${user.name} joined`)
    })

    socket.on('user:left', (value: unknown) => {
      if (!isObject(value) || typeof value.userId !== 'string' || typeof value.name !== 'string') return
      const { userId: uid, name } = value
      dispatch({ type: 'USER_LEFT', userId: uid })
      toast(`${name} left`)
    })

    socket.on('host:changed', (value: unknown) => {
      if (!isObject(value) || typeof value.hostId !== 'string') return
      const { hostId } = value
      dispatch({ type: 'HOST_CHANGED', hostId })
      if (hostId === userId) {
        dispatch({ type: 'SET_ROLE', role: 'host' })
        toast('You are now the host', 'success')
      }
    })

    socket.on('browse:state', (browse: unknown) => {
      if (!isPartyBrowse(browse)) return
      dispatch({ type: 'UPDATE_SESSION', patch: { browse } })
    })

    // Host's live scroll/cursor → mirror store (kept out of React state; applied
    // imperatively by followers so we don't re-render 60×/sec).
    socket.on('browse:pointer', (p: unknown) => { if (isMirrorPoint(p)) mirror.set(p) })

    socket.on('chat:message', (value: unknown) => {
      if (!isChatMessage(value)) return
      const msg = value
      dispatch({ type: 'PUSH_MESSAGE', msg })
      const st = stateRef.current
      if (msg.userId === userId || st.chatOpen) return
      if (st.alertMode === 'focus') dispatch({ type: 'OPEN_CHAT', focus: true })
      else if (st.alertMode === 'on') dispatch({ type: 'RIPPLE' })
    })

    socket.on('chat:history', (value: unknown) => {
      if (!Array.isArray(value)) return
      dispatch({ type: 'SET_MESSAGES', msgs: value.filter(isChatMessage) })
    })

    return () => {
      socket.off('party:state')
      socket.off('party:waiting')
      socket.off('party:approved')
      socket.off('party:rejected')
      socket.off('party:kicked')
      socket.off('party:ended')
      socket.off('user:joined')
      socket.off('user:left')
      socket.off('host:changed')
      socket.off('browse:state')
      socket.off('browse:pointer')
      socket.off('chat:message')
      socket.off('chat:history')
    }
  }, [socket, userId])

  // Socket.IO reconnects its transport automatically, but a new server-side
  // socket is not a member of the party room. Re-assert membership after every
  // reconnect so chat and sync broadcasts resume while the independently-held
  // LiveKit call remains uninterrupted. The first page connection is ignored:
  // createParty/joinParty owns that initial handshake.
  useEffect(() => {
    let hasConnected = socket.connected
    const onConnect = () => {
      if (!hasConnected) {
        hasConnected = true
        return
      }
      const current = stateRef.current
      const partyId = current.session?.id
      if (!partyId || (current.role !== 'host' && current.role !== 'guest')) return
      socket.emit('party:join', { partyId }, (value: unknown) => {
        if (!isObject(value)) return
        if (typeof value.error === 'string') {
          dispatch({ type: 'CLEAR' })
          navigate('/library')
          return
        }
        if (value.status === 'joined' && isPartySession(value.session)) {
          const role = value.session.hostId === userId ? 'host' : 'guest'
          dispatch({ type: 'SET_SESSION', session: value.session, role })
        }
      })
    }
    socket.on('connect', onConnect)
    return () => { socket.off('connect', onConnect) }
  }, [socket, userId])

  // Actions
  function createParty(mediaItemId: string, tracks: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null } = {}): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      socket.emit('party:create', { mediaItemId, ...tracks }, (value: unknown) => {
        if (!isObject(value)) return reject(new Error('Party creation failed'))
        if (typeof value.error === 'string') return reject(new Error(value.error))
        if (!isPartySession(value.session) || typeof value.partyId !== 'string') return reject(new Error('Party creation failed'))
        dispatch({ type: 'SET_SESSION', session: value.session, role: 'host' })
        resolve(value.partyId)
      })
    })
  }

  // Create an empty room (lobby stage — no title yet). Returns partyId.
  function createRoom(): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      socket.emit('party:create', {}, (value: unknown) => {
        if (!isObject(value)) return reject(new Error('Room creation failed'))
        if (typeof value.error === 'string') return reject(new Error(value.error))
        if (!isPartySession(value.session) || typeof value.partyId !== 'string') return reject(new Error('Room creation failed'))
        dispatch({ type: 'SET_SESSION', session: value.session, role: 'host' })
        resolve(value.partyId)
      })
    })
  }

  // Drive the shared library browsing (host, or any guest when collaborative).
  function navigateBrowse(stack: BrowseEntry[]) {
    dispatch({ type: 'UPDATE_SESSION', patch: { browse: { stack } } })
    socket.emit('browse:navigate', { stack })
  }

  // Broadcast the driver's live scroll fraction + cursor to the room (throttled
  // by the caller via rAF). Fire-and-forget; the server relays to followers.
  function sendPointer(p: MirrorPoint) {
    socket.emit('browse:pointer', p)
  }

  // Pick a title from the lobby → everyone transitions into the player.
  function selectMedia(mediaItemId: string, tracks: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null } = {}) {
    socket.emit('party:selectMedia', { mediaItemId, ...tracks })
  }

  // Stop the movie, return the room to shared browsing.
  function backToLobby() {
    socket.emit('party:backToLobby', {})
  }

  function joinParty(partyId: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      socket.emit('party:join', { partyId }, (value: unknown) => {
        if (!isObject(value)) return reject(new Error('Invalid join response'))
        if (typeof value.error === 'string') return reject(new Error(value.error))
        if (value.status === 'joined' && isPartySession(value.session)) {
          const role = value.session.hostId === userId ? 'host' : 'guest'
          dispatch({ type: 'SET_SESSION', session: value.session, role })
        } else {
          dispatch({ type: 'SET_ROLE', role: 'waiting' })
        }
        resolve(typeof value.status === 'string' ? value.status : 'waiting')
      })
    })
  }

  function approveUser(targetUserId: string) {
    socket.emit('party:approve', { userId: targetUserId })
    const waiting = (stateRef.current.session?.waiting ?? []).filter(w => w.userId !== targetUserId)
    dispatch({ type: 'UPDATE_SESSION', patch: { waiting } })
  }

  function rejectUser(targetUserId: string) {
    socket.emit('party:reject', { userId: targetUserId })
    const waiting = (stateRef.current.session?.waiting ?? []).filter(w => w.userId !== targetUserId)
    dispatch({ type: 'UPDATE_SESSION', patch: { waiting } })
  }

  function kickUser(targetUserId: string) {
    socket.emit('party:kick', { userId: targetUserId })
  }

  // Host-only, deliberate teardown — ends the session for everyone right now.
  // Navigates the host's own client immediately rather than waiting on the
  // 'party:ended' broadcast (which is sent to guests only).
  function endParty(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      socket.emit('party:end', {}, (value: unknown) => {
        if (isObject(value) && typeof value.error === 'string') return reject(new Error(value.error))
        dispatch({ type: 'CLEAR' })
        navigate('/library')
        resolve()
      })
    })
  }

  function transferHost(targetUserId: string) {
    socket.emit('party:transferHost', { userId: targetUserId })
  }

  function setCollaborative(enabled: boolean) {
    socket.emit('party:setCollaborative', { enabled })
  }

  function setSyncMode(mode: string) {
    socket.emit('party:setSyncMode', { mode })
  }

  function setPlaybackTracks({ audioStreamIndex = null, subtitleStreamIndex = null }: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null } = {}) {
    socket.emit('party:setPlaybackTracks', { audioStreamIndex, subtitleStreamIndex })
  }

  function sendMessage(text: string) {
    socket.emit('chat:message', { text })
  }

  function removeCamera(targetUserId: string) {
    socket.emit('camera:remove', { userId: targetUserId })
  }

  function setLayout(mode: 'float' | 'dock') {
    dispatch({ type: 'SET_LAYOUT', mode })
  }

  function toggleChat() {
    dispatch({ type: 'TOGGLE_CHAT' })
  }
  function openChat(focus = true) {
    dispatch({ type: 'OPEN_CHAT', focus })
  }
  function closeChat() {
    dispatch({ type: 'CLOSE_CHAT' })
  }
  function setAlertMode(mode: PartyContextValue['alertMode']) {
    dispatch({ type: 'SET_ALERT_MODE', mode })
  }

  return (
    <PartyContext.Provider value={{
      ...state,
      createParty, createRoom, joinParty,
      navigateBrowse, sendPointer, selectMedia, backToLobby,
      approveUser, rejectUser, kickUser, transferHost, endParty,
      setCollaborative, setSyncMode, sendMessage, removeCamera,
      setPlaybackTracks,
      setLayout, toggleChat, openChat, closeChat, setAlertMode,
    }}>
      {children}
    </PartyContext.Provider>
  )
}

export function useParty() {
  const value = useContext(PartyContext)
  if (!value) throw new Error('useParty must be used within PartyProvider')
  return value
}
