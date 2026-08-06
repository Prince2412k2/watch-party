import { useSyncExternalStore } from 'react'
import { useMediaQuery, usePhone } from '../hooks/useIsMobile.ts'
import { motionProfile, stageLayout, type MotionProfile, type StageLayout } from './stageLayout.ts'

/**
 * The two environment branches every analog surface needs, resolved once.
 *
 * The device split is `usePhone()` — a coarse-pointer query — and NOT the 640px
 * `useIsMobile()` breakpoint that desktop components use internally. A narrow
 * desktop window has a mouse and a keyboard and should keep the desktop shelf.
 */

function subscribeToResize(onChange: () => void) {
  window.addEventListener('resize', onChange)
  window.addEventListener('orientationchange', onChange)
  return () => {
    window.removeEventListener('resize', onChange)
    window.removeEventListener('orientationchange', onChange)
  }
}

/** `w,h` rather than an object, so useSyncExternalStore's snapshot is stable. */
function useViewportSize(): [number, number] {
  const packed = useSyncExternalStore(
    subscribeToResize,
    () => `${window.innerWidth},${window.innerHeight}`,
    // Server/prerender: the desktop branch is the safe default, since a phone
    // corrects itself on the first client render anyway.
    () => '1280,800',
  )
  const [width, height] = packed.split(',')
  return [Number(width), Number(height)]
}

export interface StageMetrics {
  layout: StageLayout
  motion: MotionProfile
  reducedMotion: boolean
}

export function useStageMetrics(): StageMetrics {
  const phone = usePhone()
  const [width, height] = useViewportSize()
  const reducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)')
  return {
    layout: stageLayout(width, height, phone),
    motion: motionProfile(reducedMotion),
    reducedMotion,
  }
}
