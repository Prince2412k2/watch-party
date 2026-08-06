import { useEffect, useRef, type CSSProperties, type KeyboardEvent as ReactKeyboardEvent, type TouchEvent as ReactTouchEvent } from 'react'
import { newSteppedScrollState, steppedScroll } from './browseCore.ts'
import {
  centreScrollDelta,
  focusIntentForKey,
  rovingTabIndex,
  shouldCentre,
  stepFocus,
  touchDeltaPx,
  wheelDeltaPx,
} from './stageCore.ts'
import { playDetentCue } from './cue.ts'
import { AnalogPoster } from './AnalogPoster.tsx'
import type { ArtworkItem } from './artwork.ts'
import type { MotionProfile } from './stageLayout.ts'

/**
 * One horizontal shelf, and it owns focus.
 *
 * Every input route ends in the same place: wheel, trackpad and touch drag all
 * feed pixel deltas to `steppedScroll` (one deliberate gesture, one item, the
 * momentum tail absorbed), arrows and a remote's d-pad go through
 * `focusIntentForKey`, and Enter or a click activate whatever is focused. The
 * shelf never invents a second selection model for touch — that is what makes
 * "phones keep the same stage and focus model" true rather than aspirational.
 */

export interface AnalogShelfItem {
  id: string
  label: string
  badge?: string | null
  progressPct?: number | null
  art: ArtworkItem
}

export interface AnalogShelfProps {
  label: string
  items: readonly AnalogShelfItem[]
  focusedIndex: number
  onFocusChange: (index: number) => void
  onActivate: (index: number) => void
  /** Escape/Backspace. Omitted means the keys pass through untouched. */
  onBack?: () => void
  motion: MotionProfile
  posterWidthPx: number
  gapPx: number
  loading?: boolean
  skeletonCount?: number
  emptyTitle?: string
  emptyHint?: string
  disabled?: boolean
}

export function AnalogShelf({
  label,
  items,
  focusedIndex,
  onFocusChange,
  onActivate,
  onBack,
  motion,
  posterWidthPx,
  gapPx,
  loading = false,
  skeletonCount = 8,
  emptyTitle = 'Nothing here yet',
  emptyHint,
  disabled = false,
}: AnalogShelfProps) {
  const trackRef = useRef<HTMLDivElement>(null)
  const scrollState = useRef(newSteppedScrollState())
  const dragX = useRef<number | null>(null)
  const count = items.length

  // Native listeners and gesture handlers outlive the render that created them,
  // so the current index is read through a ref rather than captured.
  const focusRef = useRef(focusedIndex)
  focusRef.current = focusedIndex
  const stepRef = useRef<(direction: number) => void>(() => {})
  stepRef.current = (direction: number) => {
    const next = stepFocus(focusRef.current, count, direction)
    if (next.index === focusRef.current) return
    playDetentCue()
    onFocusChange(next.index)
  }

  // Non-passive, because React registers wheel at the root as passive and the
  // gesture MUST be swallowed: a sideways trackpad swipe that reaches an
  // ancestor scrolls the shell or triggers the browser's back-swipe.
  useEffect(() => {
    const track = trackRef.current
    if (!track || disabled) return
    const onWheel = (event: WheelEvent) => {
      event.preventDefault()
      const step = steppedScroll(scrollState.current, wheelDeltaPx(event), event.timeStamp)
      if (step !== 0) stepRef.current(step)
    }
    track.addEventListener('wheel', onWheel, { passive: false })
    return () => track.removeEventListener('wheel', onWheel)
    // `loading` and `count` matter: the track only carries the ref once real
    // items render, and React reuses the div across the loading/empty/loaded
    // branches — so without them the listener is attached to a node that was
    // still a skeleton, or never attached at all.
  }, [disabled, loading, count])

  // Centre the focused poster by moving THIS track and nothing else. Not
  // scrollIntoView — that scrolls every scrollable ancestor too, which slid the
  // whole shell sideways on every step (pages/Library.tsx:816-820).
  useEffect(() => {
    const track = trackRef.current
    if (!track || count === 0) return
    const option = track.querySelector<HTMLElement>(`[data-analog-index="${focusedIndex}"]`)
    if (!option) return
    const delta = centreScrollDelta(track.getBoundingClientRect(), option.getBoundingClientRect())
    if (shouldCentre(delta)) track.scrollBy({ left: delta, behavior: motion.scrollBehavior })
    // Roving tabindex: DOM focus follows the selection, but only while the user
    // is already in the shelf. Otherwise clicking an arrow button, or restoring
    // focus on mount, would rip focus away from wherever it actually is.
    if (track.contains(document.activeElement)) option.focus({ preventScroll: true })
  }, [focusedIndex, count, motion.scrollBehavior])

  const onKeyDown = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    const intent = focusIntentForKey(event.key)
    if (!intent) return
    if (intent === 'back' && !onBack) return
    event.preventDefault()
    if (intent === 'prev') stepRef.current(-1)
    else if (intent === 'next') stepRef.current(1)
    else if (intent === 'activate') onActivate(focusRef.current)
    else onBack?.()
  }

  const onTouchStart = (event: ReactTouchEvent<HTMLDivElement>) => {
    dragX.current = event.touches[0]?.clientX ?? null
  }
  const onTouchMove = (event: ReactTouchEvent<HTMLDivElement>) => {
    const x = event.touches[0]?.clientX
    if (x == null) return
    if (dragX.current == null) {
      dragX.current = x
      return
    }
    const delta = touchDeltaPx(dragX.current, x)
    dragX.current = x
    const step = steppedScroll(scrollState.current, delta, event.timeStamp)
    if (step !== 0) stepRef.current(step)
  }
  const onTouchEnd = () => {
    dragX.current = null
  }

  const vars = {
    '--an-k-poster-px': `${posterWidthPx}px`,
    '--an-k-gap-px': `${gapPx}px`,
    '--an-k-chrome-ms': `${motion.chromeFadeMs}ms`,
  } as CSSProperties

  return (
    <section className="an-shelf" style={vars}>
      <div className="an-shelf-head">
        <h2>{label}</h2>
        {!loading && count > 0 ? <span className="an-shelf-count">{count}</span> : null}
        {!loading && count > 0 ? (
          <div className="an-shelf-arrows">
            <button
              type="button"
              onClick={() => stepRef.current(-1)}
              disabled={disabled || focusedIndex <= 0}
              aria-label={`Previous title in ${label}`}
            >
              ‹
            </button>
            <button
              type="button"
              onClick={() => stepRef.current(1)}
              disabled={disabled || focusedIndex >= count - 1}
              aria-label={`Next title in ${label}`}
            >
              ›
            </button>
          </div>
        ) : null}
      </div>

      {loading ? (
        <div className="an-shelf-track" aria-hidden>
          {Array.from({ length: skeletonCount }, (_, index) => (
            <span key={index} className="an-shelf-option">
              <AnalogPoster item={null} focused={false} motion={motion} caption={null} />
            </span>
          ))}
        </div>
      ) : count === 0 ? (
        <div className="an-shelf-empty">
          <strong>{emptyTitle}</strong>
          {emptyHint ? <span>{emptyHint}</span> : null}
        </div>
      ) : (
        <div
          ref={trackRef}
          className="an-shelf-track"
          role="listbox"
          aria-label={label}
          aria-orientation="horizontal"
          onKeyDown={onKeyDown}
          onTouchStart={onTouchStart}
          onTouchMove={onTouchMove}
          onTouchEnd={onTouchEnd}
          onTouchCancel={onTouchEnd}
        >
          {items.map((item, index) => (
            <button
              key={item.id}
              type="button"
              className="an-shelf-option"
              role="option"
              aria-selected={index === focusedIndex}
              aria-label={item.label}
              tabIndex={rovingTabIndex(index, focusedIndex)}
              data-analog-index={index}
              onFocus={() => onFocusChange(index)}
              onClick={() => {
                onFocusChange(index)
                onActivate(index)
              }}
            >
              <AnalogPoster
                item={item.art}
                focused={index === focusedIndex}
                motion={motion}
                caption={item.label}
                badge={item.badge}
                progressPct={item.progressPct}
              />
            </button>
          ))}
        </div>
      )}
    </section>
  )
}
