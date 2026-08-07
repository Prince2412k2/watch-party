// The vertical volume hairline.
//
// "Volume is adjusted with a compact vertical control near the right edge rather
// than a long horizontal slider in the bottom transport. The volume track
// follows the same hairline treatment and preserves mute, previous-volume
// restore, keyboard adjustment, and a sufficiently large touch target."
//
// Mute and volume are NOT gated on playback-control permission — a guest with no
// transport rights still has to be able to unmute — so this component takes no
// `canControl` at all.
//
// Keyboard adjustment comes from the player's existing window-level ↑/↓ binding
// rather than a second handler here: that binding runs in the capture phase and
// stops propagation, so a local one could never fire, and two of them would step
// the volume twice per press. What this component does provide is the thing that
// binding never had — a `volumechange` subscription in the caller, so the track
// actually follows the keyboard.

import { useEffect, useRef, useState } from 'react'
import type { CSSProperties, PointerEvent as ReactPointerEvent } from 'react'
import { analogTokens } from '../../design/analogTokens.ts'
import { chromeTransition, defaultDisplayPreferences, type DisplayPreferences } from './presentation.ts'
import { handleDiameterPx, hairlineThicknessPx, isHandleVisible, trackBoxPx } from './timelineGeometry.ts'
import { renderedLevel, setVolume, volumeFromPointer, type VolumeState } from './volumeCore.ts'

export interface AnalogVolumeProps {
  volume: number
  muted: boolean
  onSetVolume: (volume: number) => void
  onToggleMute: () => void
  /** Touch has no hover, so the phone keeps the track permanently revealed. */
  reveal?: 'hover' | 'always'
  /** Button edge: 34 on desktop, 44 to hold the touch floor on phones. */
  size?: number
  glyph?: number
  trackHeight?: number
  preferences?: DisplayPreferences
  onHold?: () => void
  onRelease?: () => void
}

export default function AnalogVolume({
  volume,
  muted,
  onSetVolume,
  onToggleMute,
  reveal = 'hover',
  size = 34,
  glyph = 18,
  trackHeight = 96,
  preferences = defaultDisplayPreferences,
  onHold,
  onRelease,
}: AnalogVolumeProps) {
  const [hovered, setHovered] = useState(false)
  const [focused, setFocused] = useState(false)
  const [dragging, setDragging] = useState(false)
  const trackRef = useRef<HTMLDivElement | null>(null)
  const dragCleanupRef = useRef<(() => void) | null>(null)

  useEffect(() => () => dragCleanupRef.current?.(), [])

  const state: VolumeState = { volume, muted, restoreVolume: volume > 0 ? volume : 1 }
  const level = renderedLevel(state)
  const activity = { hovered, focused, dragging }
  const thickness = hairlineThicknessPx(activity)
  const handleSize = handleDiameterPx(activity)
  // On touch the handle is permanent. Hiding it until hover is what makes the
  // timeline's handle unobtrusive on a mouse, but a permanently revealed track
  // with no handle on a phone is a line the user has no reason to believe is a
  // control at all.
  const showHandle = isHandleVisible(activity) || reveal === 'always'
  const open = reveal === 'always' || hovered || focused || dragging
  const hit = trackBoxPx()

  const lineTransition = chromeTransition(preferences, ['height', 'width'], analogTokens.motion.detentMs)
  const revealTransition = chromeTransition(preferences, ['opacity'], analogTokens.motion.chromeFadeMs)

  const apply = (next: number) => {
    const resolved = setVolume(state, next)
    onSetVolume(resolved.volume)
    // The mute flag lives in the player (it drives the media element's `muted`),
    // so a level change that crosses zero has to ask for the toggle rather than
    // set it. Same rule the horizontal slider used, kept verbatim.
    if (resolved.muted !== muted) onToggleMute()
  }

  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    event.stopPropagation()
    setDragging(true)
    onHold?.()
    const adjust = (clientY: number) => {
      const element = trackRef.current
      if (!element) return
      const rect = element.getBoundingClientRect()
      apply(volumeFromPointer(clientY, rect))
    }
    adjust(event.clientY)
    const move = (moveEvent: PointerEvent) => adjust(moveEvent.clientY)
    const up = () => {
      setDragging(false)
      onRelease?.()
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      window.removeEventListener('pointercancel', up)
      dragCleanupRef.current = null
    }
    dragCleanupRef.current?.()
    dragCleanupRef.current = up
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up, { once: true })
    window.addEventListener('pointercancel', up, { once: true })
  }

  const line = (extra: CSSProperties): CSSProperties => ({
    position: 'absolute',
    left: '50%',
    transform: 'translateX(-50%)',
    width: thickness,
    transition: lineTransition,
    pointerEvents: 'none',
    ...extra,
  })

  const percent = Math.round(level * 100)

  return (
    <div
      style={{ position: 'relative', display: 'inline-flex', flexDirection: 'column', alignItems: 'center', flexShrink: 0 }}
      onPointerEnter={() => setHovered(true)}
      onPointerLeave={() => setHovered(false)}
    >
      <div style={{
        position: 'absolute',
        bottom: '100%',
        left: '50%',
        transform: 'translateX(-50%)',
        paddingBottom: 4,
        opacity: open ? 1 : 0,
        pointerEvents: open ? 'auto' : 'none',
        transition: revealTransition,
      }}>
        <div
          ref={trackRef}
          role="slider"
          aria-label="Volume"
          aria-orientation="vertical"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
          aria-valuetext={muted ? 'Muted' : `${percent}%`}
          tabIndex={0}
          onFocus={(event) => {
            let visible = true
            try { visible = event.currentTarget.matches(':focus-visible') } catch { visible = true }
            if (visible) setFocused(true)
          }}
          onBlur={() => setFocused(false)}
          onPointerDown={onPointerDown}
          onClick={(event) => event.stopPropagation()}
          style={{
            // A 2px line is not a touch target; the box around it is `hitPx`
            // wide and never changes size with the line inside it.
            position: 'relative',
            width: hit,
            height: trackHeight,
            cursor: 'pointer',
            touchAction: 'none',
            outline: 'none',
          }}
        >
          <div aria-hidden style={line({ top: 0, bottom: 0, background: 'var(--an-color-line)' })} />
          <div aria-hidden style={line({ bottom: 0, height: `${percent}%`, background: 'var(--an-color-ink)' })} />
          <div aria-hidden style={{
            position: 'absolute',
            left: '50%',
            bottom: `${percent}%`,
            width: handleSize,
            height: handleSize,
            marginBottom: -handleSize / 2,
            transform: 'translateX(-50%)',
            borderRadius: '50%',
            background: 'var(--an-color-ink)',
            boxShadow: focused ? '0 0 0 2px var(--an-color-stage-void), 0 0 0 4px var(--an-color-ink-dim)' : 'none',
            opacity: showHandle ? 1 : 0,
            transition: chromeTransition(preferences, ['opacity'], analogTokens.motion.detentMs),
            pointerEvents: 'none',
          }} />
        </div>
      </div>

      <button
        onClick={(event) => { event.stopPropagation(); onToggleMute() }}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        title={muted ? 'Unmute (M)' : 'Mute (M)'}
        aria-label={muted ? 'Unmute' : 'Mute'}
        aria-pressed={muted}
        style={{
          width: size,
          height: size,
          border: 'none',
          background: 'transparent',
          borderRadius: analogTokens.radius.chromePx,
          display: 'grid',
          placeItems: 'center',
          cursor: 'pointer',
          color: muted ? 'var(--an-color-ink)' : 'var(--an-color-ink-dim)',
          transition: chromeTransition(preferences, ['color'], analogTokens.motion.chromeFadeMs),
          flexShrink: 0,
        }}
      >
        {muted
          ? <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M11 5 6 9H2v6h4l5 4V5Z" /><path d="M23 9l-6 6M17 9l6 6" /></svg>
          : <svg width={glyph} height={glyph} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M11 5 6 9H2v6h4l5 4V5Z" /><path d="M15.5 8.5a5 5 0 0 1 0 7M18.5 6a9 9 0 0 1 0 12" /></svg>}
      </button>
    </div>
  )
}
