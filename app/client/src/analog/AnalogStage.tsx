import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import type { MotionProfile, StageLayout } from './stageLayout.ts'

/**
 * The full-stage backdrop the whole browse model hangs off.
 *
 * The focused item's artwork fills the stage and cross-fades as focus moves; a
 * warm scrim keeps ink legible over it; fine grain sits on top at the token's
 * opacity. Nothing here is decorative — the backdrop IS the selection feedback,
 * which is why it is a primitive rather than a background image on a page.
 */

export interface AnalogStageProps {
  backdropUrl: string | null
  /**
   * Painted underneath the backdrop. A title with no wide art 404s its
   * Backdrop, and CSS simply skips an image it cannot load — so listing the
   * poster second is the fallback, with no request needed to discover it.
   */
  backdropFallbackUrl?: string | null
  layout: StageLayout
  motion: MotionProfile
  /** A party guest mirrors the host, so the stage is inert for them. */
  inert?: boolean
  header?: ReactNode
  /** Right-edge rail: the Singles/Collections selector. */
  side?: ReactNode
  nav?: ReactNode
  toolboxes?: ReactNode
  children?: ReactNode
}

interface Layer {
  key: number
  /** CSS background-image list: the backdrop, then whatever backs it up. */
  image: string
}

export function AnalogStage({
  backdropUrl,
  backdropFallbackUrl = null,
  layout,
  motion,
  inert = false,
  header,
  side,
  nav,
  toolboxes,
  children,
}: AnalogStageProps) {
  const [layers, setLayers] = useState<Layer[]>([])
  const nextKey = useRef(0)
  const navRef = useRef<HTMLDivElement>(null)
  const [navHeight, setNavHeight] = useState(64)

  const image = [backdropUrl, backdropFallbackUrl]
    .filter((url): url is string => Boolean(url))
    .map((url) => `url("${url}")`)
    .join(', ')

  useEffect(() => {
    if (!image) {
      setLayers([])
      return
    }
    setLayers((previous) =>
      previous.length > 0 && previous[previous.length - 1].image === image
        ? previous
        : [...previous, { key: (nextKey.current += 1), image }],
    )
  }, [image])

  // Drop everything under the newest layer once the cross-fade has run, so a
  // long browse does not accumulate a stack of full-bleed images.
  useEffect(() => {
    if (layers.length <= 1) return
    const timer = window.setTimeout(
      () => setLayers((previous) => previous.slice(-1)),
      motion.backdropCrossMs + 60,
    )
    return () => window.clearTimeout(timer)
  }, [layers, motion.backdropCrossMs])

  // The bottom-right toolbox opens ABOVE the nav rather than over it, so its
  // offset has to be the nav's real height, not a guess that drifts when the
  // labels wrap on a phone.
  useLayoutEffect(() => {
    const element = navRef.current
    if (!element) return
    const measure = () => setNavHeight(element.getBoundingClientRect().height)
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  const vars = {
    '--an-k-gutter': `${layout.gutterPx}px`,
    '--an-k-backdrop-ms': `${motion.backdropCrossMs}ms`,
    '--an-k-chrome-ms': `${motion.chromeFadeMs}ms`,
    '--an-k-drawer-ms': `${motion.drawerMs}ms`,
    '--an-k-nav-px': `${navHeight}px`,
  } as CSSProperties

  return (
    <div className="an-stage" data-size={layout.size} data-inert={inert} style={vars}>
      <div className="an-stage-backdrop" aria-hidden>
        {layers.map((layer) => (
          <BackdropLayer key={layer.key} image={layer.image} />
        ))}
      </div>
      <div className="an-stage-scrim" aria-hidden />
      <div className="an-stage-grain" aria-hidden />

      <div className="an-stage-content">
        {header ?? <div />}
        <div className="an-stage-shelves">{children}</div>
        {side ? <div className="an-stage-side">{side}</div> : null}
        <div ref={navRef}>{nav}</div>
      </div>

      {toolboxes}
    </div>
  )
}

/**
 * Mounts transparent and fades in on the next frame. Setting the class in the
 * same paint as the mount gives no transition — the element would simply appear
 * at full opacity, which is the cut the cross-fade exists to avoid.
 */
function BackdropLayer({ image }: { image: string }) {
  const [shown, setShown] = useState(false)
  useEffect(() => {
    const frame = requestAnimationFrame(() => setShown(true))
    return () => cancelAnimationFrame(frame)
  }, [])
  return <div className={`an-stage-layer${shown ? ' is-in' : ''}`} style={{ backgroundImage: image }} />
}
