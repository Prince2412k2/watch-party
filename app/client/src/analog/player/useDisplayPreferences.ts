import { useMediaQuery } from '../../hooks/useIsMobile.ts'
import type { DisplayPreferences } from './presentation.ts'

/**
 * The two accessibility preferences the player chrome branches on, read live.
 *
 * `prefers-reduced-transparency` is not universally implemented; browsers that
 * do not know the feature report `false`, which is the translucent branch — the
 * same result as today, never a regression.
 */
export function useDisplayPreferences(): DisplayPreferences {
  const reducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)')
  const reducedTransparency = useMediaQuery('(prefers-reduced-transparency: reduce)')
  return { reducedMotion, reducedTransparency }
}
