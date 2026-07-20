import { useEffect, useState } from 'react'
import { io, type Socket } from 'socket.io-client'

let socketSingleton: Socket | null = null

function getSocket(): Socket {
  if (!socketSingleton) {
    // The deployed proxy path is failing WebSocket frames (`Invalid frame header`),
    // which breaks room state sync and prevents playback-track updates from
    // propagating. Socket.IO polling works with this server, so prefer it here.
    socketSingleton = io({
      withCredentials: true,
      autoConnect: true,
      transports: ['polling'],
      auth: { caps: { remoteBrowser: true } },
    })
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
