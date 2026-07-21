import { useEffect, useRef, useState } from 'react'
import { NekoConnection } from '../neko/nekoConnection'
import type { ScreenResolution } from '../neko/nekoConnection'
import createGuacamoleKeyboard from '../neko/guacamoleKeyboard'
import type { GuacamoleKeyboardInterface } from '../neko/guacamoleKeyboard'

const FALLBACK_RESOLUTION: ScreenResolution = { width: 1280, height: 720 }

export default function NekoScreen({
  wsUrl, token, canControl, onError,
}: {
  wsUrl: string
  token: string
  canControl?: boolean
  onError?: (err: Error) => void
}) {
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const overlayRef = useRef<HTMLDivElement | null>(null)
  const connectionRef = useRef<NekoConnection | null>(null)
  const resolutionRef = useRef<ScreenResolution>(FALLBACK_RESOLUTION)
  const keyboardRef = useRef<GuacamoleKeyboardInterface | null>(null)
  const [hasStream, setHasStream] = useState(false)

  useEffect(() => {
    const conn = new NekoConnection({
      wsUrl,
      token,
      onStream: (stream) => {
        if (videoRef.current) videoRef.current.srcObject = stream
        setHasStream(true)
      },
      onResolution: (res) => { resolutionRef.current = res },
      onDisconnected: (err) => { if (err) onError?.(err) },
    })
    connectionRef.current = conn
    conn.connect()

    return () => {
      conn.disconnect()
      connectionRef.current = null
      setHasStream(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wsUrl, token])

  useEffect(() => {
    if (!canControl) return
    const overlay = overlayRef.current
    if (!overlay) return

    const keyboard = createGuacamoleKeyboard()
    keyboardRef.current = keyboard
    keyboard.onkeydown = (key: number) => {
      connectionRef.current?.sendData('keydown', { key })
      return false
    }
    keyboard.onkeyup = (key: number) => {
      connectionRef.current?.sendData('keyup', { key })
    }
    keyboard.listenTo(overlay)

    function pointerPos(e: MouseEvent) {
      const rect = overlay!.getBoundingClientRect()
      const { width: w, height: h } = resolutionRef.current
      return {
        x: Math.round((w / rect.width) * (e.clientX - rect.left)),
        y: Math.round((h / rect.height) * (e.clientY - rect.top)),
      }
    }

    function onMouseMove(e: MouseEvent) {
      connectionRef.current?.sendData('mousemove', pointerPos(e))
    }
    function onMouseDown(e: MouseEvent) {
      connectionRef.current?.sendData('mousemove', pointerPos(e))
      connectionRef.current?.sendData('mousedown', { key: e.button + 1 })
    }
    function onMouseUp(e: MouseEvent) {
      connectionRef.current?.sendData('mousemove', pointerPos(e))
      connectionRef.current?.sendData('mouseup', { key: e.button + 1 })
    }
    let wheelThrottle = false
    function onWheel(e: WheelEvent) {
      e.preventDefault()
      const x = Math.max(-32767, Math.min(32767, e.deltaX))
      const y = Math.max(-32767, Math.min(32767, e.deltaY))
      if (!wheelThrottle) {
        wheelThrottle = true
        connectionRef.current?.sendData('wheel', { x, y })
        window.setTimeout(() => { wheelThrottle = false }, 100)
      }
    }
    function onContextMenu(e: MouseEvent) {
      e.preventDefault()
    }

    overlay.addEventListener('mousemove', onMouseMove)
    overlay.addEventListener('mousedown', onMouseDown)
    overlay.addEventListener('mouseup', onMouseUp)
    overlay.addEventListener('wheel', onWheel, { passive: false })
    overlay.addEventListener('contextmenu', onContextMenu)

    return () => {
      overlay.removeEventListener('mousemove', onMouseMove)
      overlay.removeEventListener('mousedown', onMouseDown)
      overlay.removeEventListener('mouseup', onMouseUp)
      overlay.removeEventListener('wheel', onWheel)
      overlay.removeEventListener('contextmenu', onContextMenu)
      keyboardRef.current = null
    }
  }, [canControl])

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#000' }}>
      <video
        ref={videoRef}
        autoPlay
        playsInline
        muted={false}
        style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'contain', background: '#000' }}
      />
      <div
        ref={overlayRef}
        tabIndex={canControl ? 0 : -1}
        style={{
          position: 'absolute', inset: 0,
          cursor: canControl ? 'default' : 'not-allowed',
          outline: 'none',
        }}
      />
      {!hasStream && (
        <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', pointerEvents: 'none' }}>
          <span style={{ color: 'var(--text3, #9aa)', fontSize: 13 }}>Connecting to shared browser…</span>
        </div>
      )}
    </div>
  )
}
