import { createContext, useContext, useEffect, useReducer, useRef } from 'react'
import { useSocket } from '../hooks/useSocket.js'
import { navigate } from '../router.js'
import { mirror } from '../mirror.js'

const PartyContext = createContext(null)

const initialState = {
  session: null,       // publicSession from server
  role: null,          // 'host' | 'guest' | 'waiting'
  messages: [],
  layoutMode: 'float', // 'float' | 'dock'
  chatOpen: false,
  chatFocusToken: 0,   // bumped to pull focus into the chat input
  chatRipple: 0,       // bumped to fire an edge ripple ('on' alert mode)
  alertMode: 'focus',  // 'focus' | 'on' | 'mute'
  toasts: [],
}

function reducer(state, action) {
  switch (action.type) {
    case 'SET_SESSION':
      return { ...state, session: action.session, role: action.role }
    case 'SET_ROLE':
      return { ...state, role: action.role }
    case 'UPDATE_SESSION':
      return { ...state, session: { ...state.session, ...action.patch } }
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
      return { ...state, toasts: [...state.toasts, { id: Date.now(), ...action.toast }] }
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

export function PartyProvider({ children, userId }) {
  const [state, dispatch] = useReducer(reducer, initialState)
  const { socket } = useSocket()
  const stateRef = useRef(state)
  stateRef.current = state

  useEffect(() => {
    function toast(msg, level = 'info') {
      const id = Date.now()
      dispatch({ type: 'ADD_TOAST', toast: { msg, level, id } })
      setTimeout(() => dispatch({ type: 'REMOVE_TOAST', id }), 4000)
    }

    socket.on('party:state', (sess) => {
      const role = sess.hostId === userId ? 'host' : 'guest'
      dispatch({ type: 'SET_SESSION', session: sess, role })
    })

    socket.on('party:waiting', (user) => {
      dispatch({ type: 'WAITING_USER', user })
      toast(`${user.name} wants to join`, 'warning')
    })

    socket.on('party:approved', ({ session: sess }) => {
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

    socket.on('user:joined', (user) => {
      dispatch({ type: 'USER_JOINED', user })
      toast(`${user.name} joined`)
    })

    socket.on('user:left', ({ userId: uid, name }) => {
      dispatch({ type: 'USER_LEFT', userId: uid })
      toast(`${name} left`)
    })

    socket.on('host:changed', ({ hostId }) => {
      dispatch({ type: 'HOST_CHANGED', hostId })
      if (hostId === userId) {
        dispatch({ type: 'SET_ROLE', role: 'host' })
        toast('You are now the host', 'success')
      }
    })

    socket.on('browse:state', (browse) => {
      dispatch({ type: 'UPDATE_SESSION', patch: { browse } })
    })

    // Host's live scroll/cursor → mirror store (kept out of React state; applied
    // imperatively by followers so we don't re-render 60×/sec).
    socket.on('browse:pointer', (p) => mirror.set(p))

    socket.on('chat:message', (msg) => {
      dispatch({ type: 'PUSH_MESSAGE', msg })
      const st = stateRef.current
      if (msg.userId === userId || st.chatOpen) return   // ignore own / already open
      if (st.alertMode === 'focus') dispatch({ type: 'OPEN_CHAT', focus: true })
      else if (st.alertMode === 'on') dispatch({ type: 'RIPPLE' })
      // 'mute' → nothing
    })

    socket.on('chat:history', (msgs) => {
      dispatch({ type: 'SET_MESSAGES', msgs })
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
      socket.emit('party:join', { partyId }, (res) => {
        if (res?.error) {
          dispatch({ type: 'CLEAR' })
          navigate('/library')
          return
        }
        if (res?.status === 'joined' && res.session) {
          const role = res.session.hostId === userId ? 'host' : 'guest'
          dispatch({ type: 'SET_SESSION', session: res.session, role })
        }
      })
    }
    socket.on('connect', onConnect)
    return () => socket.off('connect', onConnect)
  }, [socket, userId])

  // Actions
  function createParty(mediaItemId) {
    return new Promise((resolve, reject) => {
      socket.emit('party:create', { mediaItemId }, (res) => {
        if (res?.error) return reject(new Error(res.error))
        dispatch({ type: 'SET_SESSION', session: res.session, role: 'host' })
        resolve(res.partyId)
      })
    })
  }

  // Create an empty room (lobby stage — no title yet). Returns partyId.
  function createRoom() {
    return new Promise((resolve, reject) => {
      socket.emit('party:create', {}, (res) => {
        if (res?.error) return reject(new Error(res.error))
        dispatch({ type: 'SET_SESSION', session: res.session, role: 'host' })
        resolve(res.partyId)
      })
    })
  }

  // Drive the shared library browsing (host, or any guest when collaborative).
  function navigateBrowse(stack) {
    dispatch({ type: 'UPDATE_SESSION', patch: { browse: { stack } } }) // optimistic
    socket.emit('browse:navigate', { stack })
  }

  // Broadcast the driver's live scroll fraction + cursor to the room (throttled
  // by the caller via rAF). Fire-and-forget; the server relays to followers.
  function sendPointer(p) {
    socket.emit('browse:pointer', p)
  }

  // Pick a title from the lobby → everyone transitions into the player.
  function selectMedia(mediaItemId) {
    socket.emit('party:selectMedia', { mediaItemId })
  }

  // Stop the movie, return the room to shared browsing.
  function backToLobby() {
    socket.emit('party:backToLobby', {})
  }

  function joinParty(partyId) {
    return new Promise((resolve, reject) => {
      socket.emit('party:join', { partyId }, (res) => {
        if (res?.error) return reject(new Error(res.error))
        if (res.status === 'joined') {
          const role = res.session.hostId === userId ? 'host' : 'guest'
          dispatch({ type: 'SET_SESSION', session: res.session, role })
        } else {
          dispatch({ type: 'SET_ROLE', role: 'waiting' })
        }
        resolve(res.status)
      })
    })
  }

  function approveUser(targetUserId) {
    socket.emit('party:approve', { userId: targetUserId })
    const waiting = (stateRef.current.session?.waiting ?? []).filter(w => w.userId !== targetUserId)
    dispatch({ type: 'UPDATE_SESSION', patch: { waiting } })
  }

  function rejectUser(targetUserId) {
    socket.emit('party:reject', { userId: targetUserId })
    const waiting = (stateRef.current.session?.waiting ?? []).filter(w => w.userId !== targetUserId)
    dispatch({ type: 'UPDATE_SESSION', patch: { waiting } })
  }

  function kickUser(targetUserId) {
    socket.emit('party:kick', { userId: targetUserId })
  }

  // Host-only, deliberate teardown — ends the session for everyone right now.
  // Navigates the host's own client immediately rather than waiting on the
  // 'party:ended' broadcast (which is sent to guests only).
  function endParty() {
    return new Promise((resolve, reject) => {
      socket.emit('party:end', {}, (res) => {
        if (res?.error) return reject(new Error(res.error))
        dispatch({ type: 'CLEAR' })
        navigate('/library')
        resolve()
      })
    })
  }

  function transferHost(targetUserId) {
    socket.emit('party:transferHost', { userId: targetUserId })
  }

  function setCollaborative(enabled) {
    socket.emit('party:setCollaborative', { enabled })
  }

  function setSyncMode(mode) {
    socket.emit('party:setSyncMode', { mode })
  }

  function sendMessage(text) {
    socket.emit('chat:message', { text })
  }

  function removeCamera(targetUserId) {
    socket.emit('camera:remove', { userId: targetUserId })
  }

  function setLayout(mode) {
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
  function setAlertMode(mode) {
    dispatch({ type: 'SET_ALERT_MODE', mode })
  }

  return (
    <PartyContext.Provider value={{
      ...state,
      createParty, createRoom, joinParty,
      navigateBrowse, sendPointer, selectMedia, backToLobby,
      approveUser, rejectUser, kickUser, transferHost, endParty,
      setCollaborative, setSyncMode, sendMessage, removeCamera,
      setLayout, toggleChat, openChat, closeChat, setAlertMode,
    }}>
      {children}
    </PartyContext.Provider>
  )
}

export function useParty() {
  return useContext(PartyContext)
}
