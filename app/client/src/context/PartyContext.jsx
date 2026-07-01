import { createContext, useContext, useEffect, useReducer, useRef } from 'react'
import { useSocket } from '../hooks/useSocket.js'
import { navigate } from '../router.js'

const PartyContext = createContext(null)

const initialState = {
  session: null,       // publicSession from server
  role: null,          // 'host' | 'guest' | 'waiting'
  messages: [],
  layoutMode: 'float', // 'float' | 'dock'
  chatOpen: true,
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
      return { ...state, chatOpen: !state.chatOpen }
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

    socket.on('chat:message', (msg) => {
      dispatch({ type: 'PUSH_MESSAGE', msg })
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
      socket.off('user:joined')
      socket.off('user:left')
      socket.off('host:changed')
      socket.off('chat:message')
      socket.off('chat:history')
    }
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

  function transferHost(targetUserId) {
    socket.emit('party:transferHost', { userId: targetUserId })
  }

  function setCollaborative(enabled) {
    socket.emit('party:setCollaborative', { enabled })
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

  return (
    <PartyContext.Provider value={{
      ...state,
      createParty, joinParty,
      approveUser, rejectUser, kickUser, transferHost,
      setCollaborative, sendMessage, removeCamera,
      setLayout, toggleChat,
    }}>
      {children}
    </PartyContext.Provider>
  )
}

export function useParty() {
  return useContext(PartyContext)
}
