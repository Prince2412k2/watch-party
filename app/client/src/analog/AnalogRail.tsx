import {
  useEffect,
  useRef,
  type CSSProperties,
  type KeyboardEvent as ReactKeyboardEvent,
  type ReactNode,
  type TouchEvent as ReactTouchEvent,
} from 'react'
import { newSteppedScrollState, steppedScroll } from './browseCore.ts'
import { rovingTabIndex, touchDeltaPx, wheelDeltaPx } from './stageCore.ts'
import { railCursor, railRendered, railStepPx, railTranslatePx } from './movieRail.ts'
import { stageKeyIntent, type StageIntent } from './movieBrowse.ts'
import { playDetentCue } from './cue.ts'
import { AnalogPoster } from './AnalogPoster.tsx'
import type { ArtworkItem } from './artwork.ts'
import type { MotionProfile } from './stageLayout.ts'

/**
 * The bottom rail: small posters, a cursor that does not move, and a row that
 * does.
 *
 * This is not `AnalogShelf` with different numbers. The shelf slides a highlight
 * along a stationary track and scrolls it into view afterwards; here the cursor
 * is a fixed position on the stage and the row translates underneath it, which
 * is a different geometry, a different DOM (a windowed track, not the whole
 * library) and a different scroll story (there is no scroll container at all).
 *
 * Only a window of the library is mounted — the visible slots plus the warmed
 * neighbours on either side — so a two-thousand-title library costs the same as
 * a twenty-title one. Arriving posters mount just outside the clipped viewport
 * and slide in with the track, so nothing pops.
 */

export interface AnalogRailItem {
  id: string
  label: string
  badge?: string | null
  progressPct?: number | null
  /**
   * A Jellyfin item, for the surfaces whose artwork comes from the library
   * proxy. Optional because not every rail's artwork does — see `artSrc` and
   * `renderPoster`.
   */
  art?: ArtworkItem | null
  /**
   * A resolved artwork URL, for rails whose items are not Jellyfin library
   * items — Discover's catalog results come from the same-origin
   * `/api/servarr/remote-image` proxy rather than the library image route.
   */
  artSrc?: string | null
}

export interface AnalogRailProps {
  label: string
  items: readonly AnalogRailItem[]
  /** The selected index. On this rail, selection and scroll are one number. */
  selection: number
  /** Every key the rail sees, including the ones it does not act on itself. */
  onIntent: (intent: StageIntent) => void
  onSelect: (index: number) => void
  onActivate: (index: number) => void
  motion: MotionProfile
  posterWidthPx: number
  gapPx: number
  slots: number
  loading?: boolean
  emptyTitle?: string
  emptyHint?: string
  disabled?: boolean
  /**
   * Draw the artwork for one slot. Defaults to `AnalogPoster` over the item's
   * Jellyfin `art`; a rail whose artwork comes from somewhere else supplies its
   * own so the geometry, the gestures, the windowing and the keyboard contract
   * stay in this one component rather than being copied per surface.
   */
  renderPoster?: (item: AnalogRailItem, focused: boolean) => ReactNode
}

export function AnalogRail({
  label,
  items,
  selection,
  onIntent,
  onSelect,
  onActivate,
  motion,
  posterWidthPx,
  gapPx,
  slots,
  loading = false,
  emptyTitle = 'Nothing here yet',
  emptyHint,
  disabled = false,
  renderPoster,
}: AnalogRailProps) {
  const viewportRef = useRef<HTMLDivElement>(null)
  const scrollState = useRef(newSteppedScrollState())
  const dragX = useRef<number | null>(null)
  const count = items.length

  const cursor = railCursor({ total: count, selection, slots })
  const rendered = railRendered(cursor)
  const step = railStepPx(posterWidthPx, gapPx)

  // Native listeners and gesture handlers outlive the render that created them,
  // so the intent sink is read through a ref rather than captured.
  const intentRef = useRef(onIntent)
  intentRef.current = onIntent

  // Non-passive, because React registers wheel at the root as passive and the
  // gesture MUST be swallowed: a sideways trackpad swipe that reaches an
  // ancestor scrolls the shell or triggers the browser's back-swipe. Stopping
  // propagation is what makes "scroll up/down toggles the mode when you are NOT
  // in the movie grid" true — inside the rail, the same gesture moves the rail.
  useEffect(() => {
    const viewport = viewportRef.current
    if (!viewport || disabled) return
    const onWheel = (event: WheelEvent) => {
      event.preventDefault()
      event.stopPropagation()
      const move = steppedScroll(scrollState.current, wheelDeltaPx(event), event.timeStamp)
      if (move !== 0) intentRef.current(move < 0 ? 'rail-prev' : 'rail-next')
    }
    viewport.addEventListener('wheel', onWheel, { passive: false })
    return () => viewport.removeEventListener('wheel', onWheel)
    // `loading` and `count` matter: React reuses this node across the
    // loading/empty/loaded branches, so without them the listener ends up
    // attached to what was still a skeleton, or never attached at all.
  }, [disabled, loading, count])

  // Roving tabindex: DOM focus follows the selection, but only while the user is
  // already inside the rail. Otherwise clicking the mode slider, or restoring a
  // remembered position on mount, would rip focus away from wherever it is.
  useEffect(() => {
    const viewport = viewportRef.current
    if (!viewport || count === 0) return
    if (!viewport.contains(document.activeElement)) return
    viewport
      .querySelector<HTMLElement>(`[data-analog-index="${selection}"]`)
      ?.focus({ preventScroll: true })
  }, [selection, count])

  const onKeyDown = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    const intent = stageKeyIntent(event.key)
    if (!intent) return
    event.preventDefault()
    onIntent(intent)
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
    const move = steppedScroll(scrollState.current, delta, event.timeStamp)
    if (move !== 0) intentRef.current(move < 0 ? 'rail-prev' : 'rail-next')
  }
  const onTouchEnd = () => {
    dragX.current = null
  }

  const vars = {
    '--an-k-poster-px': `${posterWidthPx}px`,
    '--an-k-gap-px': `${gapPx}px`,
    '--an-k-step-px': `${step}px`,
    '--an-k-chrome-ms': `${motion.chromeFadeMs}ms`,
    '--an-k-track-ms': `${motion.focusStepMs}ms`,
  } as CSSProperties

  if (loading) {
    return (
      <section className="an-rail" style={vars} aria-busy>
        <RailHead label={label} count={null} position={null} />
        <div className="an-rail-viewport">
          <div className="an-rail-track" aria-hidden>
            {Array.from({ length: slots + 1 }, (_, index) => (
              <span key={index} className="an-rail-slot">
                <AnalogPoster item={null} focused={false} motion={motion} caption={null} />
              </span>
            ))}
          </div>
        </div>
      </section>
    )
  }

  if (count === 0) {
    return (
      <section className="an-rail" style={vars}>
        <RailHead label={label} count={0} position={null} />
        <div className="an-rail-empty">
          <strong>{emptyTitle}</strong>
          {emptyHint ? <span>{emptyHint}</span> : null}
        </div>
      </section>
    )
  }

  return (
    <section className="an-rail" style={vars}>
      <RailHead label={label} count={count} position={selection + 1} />
      <div
        ref={viewportRef}
        className="an-rail-viewport"
        role="listbox"
        aria-label={label}
        aria-orientation="horizontal"
        onKeyDown={onKeyDown}
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        onTouchCancel={onTouchEnd}
      >
        {/* The cursor is a fixed mark on the stage, not a highlight that travels
            with the selection. It only leaves the first slot at the very end of
            the rail, where the row has no travel left to give. */}
        <span
          className="an-rail-cursor"
          aria-hidden
          style={{ transform: `translate3d(${cursor.cursorSlot * step}px, 0, 0)` }}
        />
        <div
          className="an-rail-track"
          style={{
            paddingLeft: `${(rendered[0] ?? 0) * step}px`,
            transform: `translate3d(${railTranslatePx(cursor.start, posterWidthPx, gapPx)}px, 0, 0)`,
          }}
        >
          {rendered.map((index) => {
            const item = items[index]
            if (!item) return null
            return (
              <button
                key={item.id}
                type="button"
                className="an-rail-slot"
                role="option"
                aria-selected={index === selection}
                aria-label={item.label}
                tabIndex={rovingTabIndex(index, selection)}
                data-analog-index={index}
                disabled={disabled}
                onFocus={() => onSelect(index)}
                // "Enter/click activates the FOCUSED item." Clicking elsewhere
                // in the rail brings that title under the cursor instead of
                // playing it outright — with the details on the stage, playing
                // something the user has not read yet is the wrong answer, and
                // the primary action is a labelled button either way, so nothing
                // is hidden behind a gesture.
                onClick={() => {
                  if (index !== selection) {
                    playDetentCue()
                    onSelect(index)
                    return
                  }
                  onActivate(index)
                }}
              >
                {/* Three artwork paths, narrowest first: a caller-supplied
                    renderer (Downloads' *arr poster), a pre-resolved URL
                    (Discover's proxied catalog art), or a Jellyfin item chained
                    through the library proxy. */}
                {renderPoster ? (
                  renderPoster(item, index === selection)
                ) : (
                  <AnalogPoster
                    item={item.art ?? null}
                    src={item.artSrc}
                    focused={index === selection}
                    motion={motion}
                    caption={item.label}
                    badge={item.badge}
                    progressPct={item.progressPct}
                    eager
                  />
                )}
              </button>
            )
          })}
        </div>
      </div>
    </section>
  )
}

/**
 * The rail's own label carries the position, because the cursor no longer does:
 * a highlight that never moves cannot tell you whether you are three titles in
 * or three hundred.
 */
function RailHead({ label, count, position }: { label: string; count: number | null; position: number | null }) {
  return (
    <div className="an-rail-head">
      <h2>{label}</h2>
      {count !== null && count > 0 && position !== null ? (
        <span className="an-rail-position">
          {position} / {count}
        </span>
      ) : null}
    </div>
  )
}
