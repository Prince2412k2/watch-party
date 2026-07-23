import { useEffect, useRef, useState } from 'react'
import { NekoConnection } from '../neko/nekoConnection'
import type { ScreenResolution } from '../neko/nekoConnection'
import createGuacamoleKeyboard from '../neko/guacamoleKeyboard'
import type { GuacamoleKeyboardInterface } from '../neko/guacamoleKeyboard'

const FALLBACK_RESOLUTION: ScreenResolution = { width: 1280, height: 720 }

export default function NekoScreen({
  wsUrl, canControl, onError,
}: {
  wsUrl: string
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
  }, [wsUrl])

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

    // The <video> uses object-fit:contain, so unless its aspect ratio exactly
    // matches the overlay's, the rendered picture is letterboxed (bars on the
    // sides or top/bottom) and doesn't fill the full overlay rect. Mapping
    // pointer coords against the overlay's raw bounding rect (ignoring the
    // bars) produces a mismatch that's zero at the center and grows toward
    // the edges — exactly the drift symptom this fixes. Compute the actual
    // displayed video rect within the overlay first, then map against that.
    function pointerPos(e: MouseEvent) {
      const rect = overlay!.getBoundingClientRect()
      const { width: w, height: h } = resolutionRef.current
      const video = videoRef.current
      const videoW = video?.videoWidth || w
      const videoH = video?.videoHeight || h

      const containerRatio = rect.width / rect.height
      const videoRatio = videoW / videoH
      let contentWidth = rect.width
      let contentHeight = rect.height
      if (videoRatio > containerRatio) {
        contentHeight = rect.width / videoRatio
      } else {
        contentWidth = rect.height * videoRatio
      }
      const offsetX = rect.left + (rect.width - contentWidth) / 2
      const offsetY = rect.top + (rect.height - contentHeight) / 2

      const fracX = Math.min(1, Math.max(0, (e.clientX - offsetX) / contentWidth))
      const fracY = Math.min(1, Math.max(0, (e.clientY - offsetY) / contentHeight))
      const result = { x: Math.round(fracX * w), y: Math.round(fracY * h) }
      // eslint-disable-next-line no-console
      console.log('[neko pointer debug]', {
        clientX: e.clientX, clientY: e.clientY,
        rect: { left: rect.left, top: rect.top, width: rect.width, height: rect.height },
        video: { videoW, videoH },
        content: { offsetX, offsetY, contentWidth, contentHeight },
        target: { w, h },
        result,
      })
      return result
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
    // The server (xorg.c XScroll) fires ONE discrete X11 wheel-button click
    // per unit of delta (`for i in 0..abs(delta)`), not a pixel amount — so
    // clamping to +/-32767 let a normal 100+ pixel wheel tick fire 100+
    // clicks instantly. Match the reference client's default clamp (+/-10)
    // and its deltaMode normalization (some browsers report scroll in lines
    // rather than pixels; WHEEL_LINE_HEIGHT scales those up before clamping
    // to the same range pixel deltas use).
    const WHEEL_LINE_HEIGHT = 19
    const SCROLL_CLAMP = 10
    function onWheel(e: WheelEvent) {
      e.preventDefault()
      let dx = e.deltaX
      let dy = e.deltaY
      if (e.deltaMode !== 0) {
        dx *= WHEEL_LINE_HEIGHT
        dy *= WHEEL_LINE_HEIGHT
      }
      const x = Math.max(-SCROLL_CLAMP, Math.min(SCROLL_CLAMP, dx))
      const y = Math.max(-SCROLL_CLAMP, Math.min(SCROLL_CLAMP, dy))
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
