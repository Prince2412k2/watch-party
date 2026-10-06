import { createContext, useContext, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import type { useLiveKit } from '../hooks/useLiveKit.ts'

export const PlayerPresentationContext = createContext({
  floating: false,
  overlay: null as HTMLElement | null,
  minimize: () => {},
  expand: () => {},
  close: () => {},
})
export const usePlayerPresentation = () => useContext(PlayerPresentationContext)

/** Room overlays never change DOM parents when the movie becomes a small window. */
export function RoomOverlay({ children }: { children: ReactNode }) {
  const { overlay } = usePlayerPresentation()
  return overlay ? createPortal(children, overlay) : null
}

export const RoomConnectionContext = createContext<ReturnType<
  typeof useLiveKit
> | null>(null)
export function useRoomConnection() {
  const connection = useContext(RoomConnectionContext)
  if (!connection) throw new Error('Room connection requires PlayerHost')
  return connection
}
