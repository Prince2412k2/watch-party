import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { glass } from '../../glass.jsx'
import { T, R, EASE, Z, TYPE } from '../theme.js'

/**
 * Bottom sheet: scrim (scrimIn) + a glass panel that rises from the bottom
 * (sheetUp). Anchored to the DYNAMIC viewport and safe-area padded so it clears
 * the home indicator and never hides under Safari's collapsing toolbar. Closes
 * on scrim tap, the ✕, Escape, or a downward drag on the grab handle. Rendered
 * through a portal so it floats above the shell scroll region.
 *
 * Props: open, onClose, title?, children, maxHeight? ('85dvh' default).
 */
export function Sheet({ open, onClose, title, children, maxHeight = '85dvh' }) {
  const [mounted, setMounted] = useState(open)
  const [dragY, setDragY] = useState(0)
  const startRef = useRef(0)

  useEffect(() => { if (open) setMounted(true) }, [open])
  useEffect(() => {
    if (!open) return
    const onKey = (e) => { if (e.key === 'Escape') onClose?.() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!mounted && !open) return null

  const onPointerDown = (e) => { startRef.current = e.clientY; e.currentTarget.setPointerCapture?.(e.pointerId) }
  const onPointerMove = (e) => { if (startRef.current) setDragY(Math.max(0, e.clientY - startRef.current)) }
  const onPointerUp = () => {
    if (dragY > 90) onClose?.()
    setDragY(0); startRef.current = 0
  }

  return createPortal(
    <div
      role="dialog" aria-modal="true"
      style={{ position: 'fixed', inset: 0, zIndex: Z.sheet, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}
    >
      <div
        onClick={onClose}
        style={{
          position: 'absolute', inset: 0, background: 'rgba(4,5,7,.62)',
          animation: open ? 'scrimIn .22s ease both' : 'scrimIn .18s ease reverse both',
        }}
      />
      <div
        onAnimationEnd={() => { if (!open) setMounted(false) }}
        style={{
          ...glass('heavy', { refract: true }),
          position: 'relative',
          borderRadius: `${R.lg}px ${R.lg}px 0 0`,
          borderBottom: 'none',
          maxHeight, display: 'flex', flexDirection: 'column',
          paddingBottom: `calc(var(--sa-b) + 14px)`,
          transform: `translateY(${dragY}px)`,
          animation: open ? `sheetUp .28s ${EASE} both` : `sheetUp .2s ${EASE} reverse both`,
          transition: dragY === 0 ? `transform .2s ${EASE}` : 'none',
        }}
      >
        {/* grab handle — drag down to dismiss */}
        <div
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          style={{ display: 'grid', placeItems: 'center', padding: '10px 0 4px', cursor: 'grab', touchAction: 'none' }}
        >
          <span style={{ width: 40, height: 5, borderRadius: 99, background: T.line2 }} />
        </div>

        {title && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '4px 20px 12px', gap: 12 }}>
            <h2 style={{ ...TYPE.title, color: T.text }}>{title}</h2>
          </div>
        )}

        <div style={{ overflowY: 'auto', WebkitOverflowScrolling: 'touch', overscrollBehavior: 'contain', padding: '0 16px' }}>
          {children}
        </div>
      </div>
    </div>,
    document.body,
  )
}
