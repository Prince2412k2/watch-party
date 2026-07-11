import { useEffect, useState } from 'react'
import { io, type Socket } from 'socket.io-client'

let socketSingleton: Socket | null = null

function getSocket(): Socket {
  if (!socketSingleton) {
    socketSingleton = io({ withCredentials: true, autoConnect: true })
  }
  return socketSingleton
}

export function useSocket() {
  const socket = getSocket()
  const [connected, setConnected] = useState(socket.connected)

  useEffect(() => {
    const onConnect = () => setConnected(true)
    const onDisconnect = () => setConnected(false)
    socket.on('connect', onConnect)
    socket.on('disconnect', onDisconnect)
    return () => {
      socket.off('connect', onConnect)
      socket.off('disconnect', onDisconnect)
    }
  }, [socket])

  return { socket, connected }
}
