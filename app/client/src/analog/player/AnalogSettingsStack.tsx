// The settings surface: a compact vertical stack that expands UPWARD from the
// lower-right control area.
//
// "Activating the gear expands a compact vertical stack upward from the
// lower-right control area. It does not open a full-screen modal. […] The direct
// subtitle button remains outside this menu for fast track selection and Off."
//
// So this is a shell, not a menu: it owns the anchoring, the upward entrance,
// the dismissal and the surface treatment, and the caller owns the rows. That
// split is what keeps the direct subtitle action outside — a stack that
// rendered its own contents would inevitably grow a subtitle row.
//
// The dismiss layer is a bare click-catcher, not a scrim: it paints nothing, so
// the movie stays fully visible and playable behind an open stack, which is the
// difference between this and the modal the reference rules out.

import { useEffect, useRef } from 'react'
import type { CSSProperties, ReactNode } from 'react'
import { analogTokens } from '../../design/analogTokens.ts'
import { defaultDisplayPreferences, panelSurface, riseAnimation, type DisplayPreferences } from './presentation.ts'

export interface AnalogSettingsStackProps {
  open: boolean
  onDismiss: () => void
  children?: ReactNode
  /** Distance above the control row the stack rises from. */
  bottom: number
  /** Offset from the right edge of the anchoring cluster. */
  right: number
  width: number
  maxWidth?: string
  maxHeight: string
  radius?: number
  preferences?: DisplayPreferences
  label?: string
  /** Pin the chrome open while the stack is up. */
  onHold?: () => void
  onRelease?: () => void
}

export default function AnalogSettingsStack({
  open,
  onDismiss,
  children,
  bottom,
  right,
  width,
  maxWidth,
  maxHeight,
  radius = analogTokens.radius.sheetPx,
  preferences = defaultDisplayPreferences,
  label = 'Player settings',
  onHold,
  onRelease,
}: AnalogSettingsStackProps) {
  const releaseRef = useRef(onRelease)
  releaseRef.current = onRelease

  useEffect(() => {
    if (!open) return
    onHold?.()
    return () => releaseRef.current?.()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  // Esc closes the stack. Registered only while open, and only on `keydown` at
  // the bubble phase, so it cannot shadow the player's own capture-phase keys.
  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.stopPropagation()
      onDismiss()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onDismiss])

  if (!open) return null

  const panel: CSSProperties = {
    ...panelSurface(preferences),
    position: 'absolute',
    bottom,
    right,
    zIndex: 31,
    width,
    ...(maxWidth ? { maxWidth } : {}),
    maxHeight,
    display: 'flex',
    flexDirection: 'column',
    borderRadius: radius,
    overflow: 'hidden',
    color: 'var(--an-color-ink)',
    animation: riseAnimation(preferences),
  }

  return (
    <>
      <div
        onClick={(event) => { event.stopPropagation(); onDismiss() }}
        style={{ position: 'fixed', inset: 0, zIndex: 30 }}
      />
      <div role="group" aria-label={label} style={panel}>
        {children}
      </div>
    </>
  )
}
