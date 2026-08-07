// The precision hairline timeline.
//
// One component for both bars. Layers, weakest to strongest:
//
//   1. unloaded duration — a low-contrast hairline across the whole track
//   2. loaded/buffered ranges — quieter tonal segments, WITH their real gaps
//   3. cached/offline spans — visually distinct from transient network buffer
//   4. played progress — the strongest segment
//
// The interactive box is a constant `hairline.hitPx` tall, so the visible line
// growing from `idlePx` to `activePx` on hover/focus/scrub never moves anything
// around it, and the touch target never shrinks to the thickness of the line.
//
// Layer 3 renders empty in this client today: React has no on-disk cache to
// source spans from (the native download queue tracks whole files in bytes, not
// time ranges). The layer exists, ordered and styled, so the day a source
// appears it is a prop rather than a redesign.

import { useEffect, useRef, useState } from 'react'
import type { CSSProperties, PointerEvent as ReactPointerEvent, ReactNode } from 'react'
import { analogTokens } from '../../design/analogTokens.ts'
import { formatClock, spokenClock } from './format.ts'
import { chromeTransition, defaultDisplayPreferences, type DisplayPreferences } from './presentation.ts'
import {
  clampPopupCenter,
  handleDiameterPx,
  hairlineThicknessPx,
  isHandleVisible,
  ratioFromPointer,
  seekTimeFromRatio,
  timelineLayers,
  trackBoxPx,
  type PercentSpan,
  type TimeSpan,
} from './timelineGeometry.ts'

export interface TimelinePreview {
  node: ReactNode
  /** Needed to keep the popup inside the track; the caller owns its size. */
  width: number
}

export interface AnalogTimelineProps {
  positionSec: number
  durationSec: number
  /** Real `buffered` ranges. Disjoint ranges render as disjoint segments. */
  buffered?: readonly TimeSpan[]
  /** Offline/on-disk spans, drawn distinctly from network buffer. */
  cached?: readonly TimeSpan[]
  canControl?: boolean
  /** Called continuously through a drag, with the target time in seconds. */
  onScrub?: (seconds: number) => void
  onScrubStart?: () => void
  onScrubEnd?: () => void
  /**
   * Trickplay artwork for a hovered/dragged time. Returning `null` (no manifest
   * for this title) falls back to a bare time chip, so a scrub preview exists
   * either way.
   */
  renderPreview?: (seconds: number) => TimelinePreview | null
  /** Phone bar: `current` and `duration` either side of the track. */
  labels?: boolean
  /** Trailing content in the label row (the guest "Host controls" hint). */
  trailing?: ReactNode
  preferences?: DisplayPreferences
  ariaLabel?: string
}

export default function AnalogTimeline({
  positionSec,
  durationSec,
  buffered,
  cached,
  canControl = false,
  onScrub,
  onScrubStart,
  onScrubEnd,
  renderPreview,
  labels = false,
  trailing,
  preferences = defaultDisplayPreferences,
  ariaLabel = 'Seek',
}: AnalogTimelineProps) {
  const [hovered, setHovered] = useState(false)
  const [focused, setFocused] = useState(false)
  const [dragging, setDragging] = useState(false)
  const [pointerTime, setPointerTime] = useState<{ time: number; x: number } | null>(null)
  const trackRef = useRef<HTMLDivElement | null>(null)
  const dragCleanupRef = useRef<(() => void) | null>(null)

  useEffect(() => () => dragCleanupRef.current?.(), [])

  const activity = { hovered, focused, dragging }
  const thickness = hairlineThicknessPx(activity)
  const boxHeight = trackBoxPx()
  const handleSize = handleDiameterPx(activity)
  const showHandle = canControl && isHandleVisible(activity)
  const { playedPct, buffered: bufferedSpans, cached: cachedSpans } = timelineLayers({
    durationSec,
    positionSec,
    buffered,
    cached,
  })

  const lineTransition = chromeTransition(preferences, ['height'], analogTokens.motion.detentMs)
  const fadeTransition = chromeTransition(preferences, ['opacity'], analogTokens.motion.detentMs)

  const layer = (background: string, extra: CSSProperties): CSSProperties => ({
    position: 'absolute',
    top: '50%',
    transform: 'translateY(-50%)',
    height: thickness,
    background,
    transition: lineTransition,
    pointerEvents: 'none',
    ...extra,
  })

  const spanStyle = (span: PercentSpan, background: string): CSSProperties =>
    layer(background, {
      left: `${span.startPct}%`,
      // The gap is a MINIMUM separation: two ranges a fraction of a percent
      // apart must still read as two ranges rather than one continuous bar.
      width: span.gapAfterPx > 0 ? `calc(${span.widthPct}% - ${span.gapAfterPx}px)` : `${span.widthPct}%`,
    })

  const updatePointer = (clientX: number) => {
    const element = trackRef.current
    if (!element || durationSec <= 0) return
    const rect = element.getBoundingClientRect()
    const ratio = ratioFromPointer(clientX, rect)
    setPointerTime({ time: seekTimeFromRatio(ratio, durationSec), x: ratio * rect.width })
  }

  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!canControl || durationSec <= 0) return
    event.stopPropagation()
    setDragging(true)
    onScrubStart?.()
    const seek = (clientX: number) => {
      const element = trackRef.current
      if (!element) return
      updatePointer(clientX)
      onScrub?.(seekTimeFromRatio(ratioFromPointer(clientX, element.getBoundingClientRect()), durationSec))
    }
    seek(event.clientX)
    const move = (moveEvent: PointerEvent) => seek(moveEvent.clientX)
    const up = () => {
      setDragging(false)
      setPointerTime(null)
      onScrubEnd?.()
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

  // "Hover, focus, and drag retain the time label and trickplay preview." A
  // keyboard user never produces a pointer position, so focus previews the
  // position itself.
  const previewTime = pointerTime ? pointerTime.time : focused && durationSec > 0 ? positionSec : null
  const previewX =
    pointerTime ? pointerTime.x : previewTime != null && durationSec > 0 ? (positionSec / durationSec) * (trackRef.current?.clientWidth ?? 0) : 0
  const preview = previewTime != null ? renderPreview?.(previewTime) ?? null : null
  const previewWidth = preview ? preview.width : 62
  const previewLeft = clampPopupCenter(previewX, previewWidth, trackRef.current?.clientWidth ?? 0)

  const track = (
    <div
      ref={trackRef}
      role="slider"
      aria-label={ariaLabel}
      aria-valuemin={0}
      aria-valuemax={Math.max(0, Math.floor(durationSec))}
      aria-valuenow={Math.max(0, Math.floor(positionSec))}
      aria-valuetext={spokenClock(positionSec)}
      aria-disabled={!canControl}
      // Focusable only when it can actually do something. Arrow keys are already
      // bound at the window (capture phase, stopPropagation) for controllers, so
      // a focused track seeks ±5s without this component binding — and without
      // two handlers both seeking on one press.
      tabIndex={canControl ? 0 : -1}
      onFocus={(event) => {
        // Pointer focus must not paint a focus ring; keyboard focus must.
        let visible = true
        try { visible = event.currentTarget.matches(':focus-visible') } catch { visible = true }
        if (visible) setFocused(true)
      }}
      onBlur={() => setFocused(false)}
      onPointerEnter={(event) => { setHovered(true); updatePointer(event.clientX) }}
      onPointerMove={(event) => updatePointer(event.clientX)}
      onPointerLeave={() => { setHovered(false); if (!dragging) setPointerTime(null) }}
      onPointerDown={onPointerDown}
      // A completed tap is a separate `click`; stopping pointerdown does not
      // stop it reaching the stage and registering as chrome-toggle or half of a
      // double-tap seek.
      onClick={(event) => event.stopPropagation()}
      style={{
        position: 'relative',
        flex: 1,
        minWidth: 0,
        // Constant. The line thickens inside this box; the box never moves.
        height: boxHeight,
        display: 'flex',
        alignItems: 'center',
        cursor: canControl ? 'pointer' : 'default',
        touchAction: canControl ? 'none' : undefined,
        outline: 'none',
      }}
    >
      {preview && previewTime != null && (
        <div style={{
          position: 'absolute',
          left: previewLeft,
          bottom: boxHeight - 2,
          width: previewWidth,
          transform: 'translateX(-50%)',
          pointerEvents: 'none',
          zIndex: 2,
        }}>
          {preview.node}
        </div>
      )}
      {!preview && previewTime != null && (
        <div style={{
          position: 'absolute',
          left: previewLeft,
          bottom: boxHeight - 2,
          transform: 'translateX(-50%)',
          padding: '3px 7px',
          borderRadius: analogTokens.radius.chromePx,
          background: 'var(--an-color-backdrop-scrim)',
          border: '1px solid var(--an-color-line-strong)',
          fontFamily: analogTokens.type.mono,
          fontSize: 11,
          color: 'var(--an-color-ink)',
          whiteSpace: 'nowrap',
          pointerEvents: 'none',
          zIndex: 2,
        }}>
          {formatClock(previewTime)}
        </div>
      )}

      {/* 1 — unloaded duration */}
      <div aria-hidden style={layer('var(--an-color-line)', { left: 0, right: 0 })} />
      {/* 2 — loaded/buffered, with real gaps */}
      {bufferedSpans.map((span, index) => (
        <div key={`buffered-${index}`} aria-hidden style={spanStyle(span, 'var(--an-color-line-strong)')} />
      ))}
      {/* 3 — cached/offline, distinct from network buffer */}
      {cachedSpans.map((span, index) => (
        <div key={`cached-${index}`} aria-hidden style={spanStyle(span, 'var(--an-color-ink-faint)')} />
      ))}
      {/* 4 — played progress */}
      <div aria-hidden style={layer('var(--an-color-ink)', { left: 0, width: `${playedPct}%` })} />

      {canControl && (
        <div aria-hidden style={{
          position: 'absolute',
          left: `${playedPct}%`,
          top: '50%',
          width: handleSize,
          height: handleSize,
          marginLeft: -handleSize / 2,
          transform: 'translateY(-50%)',
          borderRadius: '50%',
          background: 'var(--an-color-ink)',
          // Focus keeps the handle honest without permanently enlarging it: the
          // ring only exists while focused.
          boxShadow: focused ? '0 0 0 2px var(--an-color-stage-void), 0 0 0 4px var(--an-color-ink-dim)' : 'none',
          opacity: showHandle ? 1 : 0,
          transition: fadeTransition,
          pointerEvents: 'none',
        }} />
      )}
    </div>
  )

  if (!labels && !trailing) return track

  const labelStyle: CSSProperties = {
    fontFamily: analogTokens.type.mono,
    fontSize: 11,
    fontVariantNumeric: 'tabular-nums',
    minWidth: 36,
    flexShrink: 0,
  }

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: analogTokens.space.smPx, width: '100%' }}>
      {labels && (
        <span style={{ ...labelStyle, textAlign: 'right', color: 'var(--an-color-ink)' }}>{formatClock(positionSec)}</span>
      )}
      {track}
      {labels && (
        <span style={{ ...labelStyle, color: 'var(--an-color-ink-dim)' }}>{formatClock(durationSec)}</span>
      )}
      {trailing}
    </div>
  )
}
