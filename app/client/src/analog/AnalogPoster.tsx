import { useMemo, useSyncExternalStore, type CSSProperties } from 'react'
import { analogTokens } from '../design/analogTokens.ts'
import {
  artworkFailureVersion,
  artworkSrc,
  failedArtworkIds,
  noteArtworkFailure,
  resolveArtwork,
  subscribeArtworkFailures,
  type ArtworkItem,
} from './artwork.ts'
import { edgeLightOffsets, type MotionProfile } from './stageLayout.ts'

/**
 * Square, unrounded artwork at every size — including the skeleton and the
 * placeholder, which are the two variants that quietly reintroduce a radius
 * everywhere else in this codebase.
 *
 * Resting depth is a fine frame, a directional edge light and a tinted cast
 * shadow. Focus raises the elevation, brightens the lit edge and darkens the
 * backdrop immediately around the poster. There is no tilt and no bounce: the
 * easing curves keep every y control point inside 0..1, which is what an
 * overshoot needs to leave.
 */

/** One subscription for every poster, so a 404 learned by one is known to all. */
function useFailedArtworkIds(): string[] {
  const version = useSyncExternalStore(subscribeArtworkFailures, artworkFailureVersion, () => 0)
  return useMemo(failedArtworkIds, [version])
}

export function posterCssVars(motion: MotionProfile): CSSProperties {
  const edge = edgeLightOffsets(analogTokens.selection.sceneLightAngleDeg, motion.framePx)
  return {
    '--an-k-step-ms': `${motion.focusStepMs}ms`,
    '--an-k-chrome-ms': `${motion.chromeFadeMs}ms`,
    '--an-k-focus-scale': motion.focusScale,
    '--an-k-lift-px': `${motion.focusLiftPx}px`,
    '--an-k-frame-px': `${motion.framePx}px`,
    '--an-k-lit-x': `${edge.litX}px`,
    '--an-k-lit-y': `${edge.litY}px`,
    '--an-k-shade-x': `${edge.shadeX}px`,
    '--an-k-shade-y': `${edge.shadeY}px`,
  } as CSSProperties
}

export interface AnalogPosterProps {
  /** null renders the loading skeleton — square, like everything else here. */
  item: ArtworkItem | null
  focused: boolean
  motion: MotionProfile
  caption?: string | null
  badge?: string | null
  progressPct?: number | null
  /**
   * Load immediately rather than when the browser decides it is near the
   * viewport. The fixed-cursor rail mounts a few posters just outside its own
   * clipped viewport on purpose, so they are decoded a step before they arrive;
   * `loading="lazy"` would defer exactly those and undo it.
   */
  eager?: boolean
}

export function AnalogPoster({ item, focused, motion, caption, badge, progressPct, eager = false }: AnalogPosterProps) {
  const failed = useFailedArtworkIds()
  const artwork = item ? resolveArtwork(item, failed) : null
  const src = artwork ? artworkSrc(artwork) : null

  return (
    <span className="an-poster" data-focused={focused} style={posterCssVars(motion)}>
      <span className="an-poster-shade" aria-hidden />
      <span className="an-poster-frame">
        {item === null ? (
          <span className="an-poster-skeleton" aria-hidden />
        ) : src && artwork ? (
          <img
            className="an-poster-art"
            src={src}
            alt=""
            draggable={false}
            loading={eager ? 'eager' : 'lazy'}
            decoding="async"
            onError={() => noteArtworkFailure(artwork.itemId!)}
          />
        ) : (
          <span className="an-poster-placeholder" aria-hidden>
            {artwork?.label ?? '—'}
          </span>
        )}
        {badge ? <span className="an-poster-badge">{badge}</span> : null}
        {progressPct != null && progressPct > 0 ? (
          <span className="an-poster-progress" aria-hidden>
            <i style={{ width: `${Math.min(100, progressPct)}%` }} />
          </span>
        ) : null}
      </span>
      {caption !== undefined ? <span className="an-poster-caption">{caption}</span> : null}
    </span>
  )
}
