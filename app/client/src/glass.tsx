// ── Flat solid surfaces (liquid glass removed) ───────────────────────────────
// The app used to render "liquid glass" panels — SVG edge-refraction + frost
// blur. That whole aesthetic is gone: the cinematic-minimal redesign uses flat,
// solid, near-black surfaces with hairline dividers and no backdrop-filter.
//
// `glass(level, opts)` is kept as the single surface primitive so the ~11 call
// sites keep working, but it now returns a plain opaque panel. Levels map to a
// small elevation scale (deeper = slightly lighter surface + stronger shadow),
// NOT to blur. No backdrop-filter, no refraction, no specular sheen.

import type { CSSProperties } from 'react'

const SURFACE = {
  clear:  { bg: 'color-mix(in srgb, var(--wp-surface, #141416) 42%, transparent)', shadow: 'none' },
  light:  { bg: 'var(--wp-surface, #141416)', shadow: '0 2px 12px var(--wp-shadow, rgba(0,0,0,.4))' },
  medium: { bg: 'var(--wp-surface-2, #17171a)', shadow: '0 8px 30px var(--wp-shadow, rgba(0,0,0,.5))' },
  heavy:  { bg: 'var(--wp-surface, #1b1b1e)', shadow: '0 18px 46px var(--wp-shadow, rgba(0,0,0,.38))' },
}

/**
 * @param level  'clear' | 'light' | 'medium' | 'heavy'  (elevation, not blur)
 * @param opts   { radius?: number, ...extra style }
 */
export function glass(level: keyof typeof SURFACE = 'medium', opts: CSSProperties & { refract?: boolean; radius?: number } = {}) {
  const { refract, radius, ...extra } = opts   // `refract` accepted + ignored (legacy)
  const s = SURFACE[level] || SURFACE.medium
  return {
    backgroundColor: s.bg,
    border: '1px solid rgba(255,255,255,.08)',
    boxShadow: s.shadow,
    ...(radius != null ? { borderRadius: radius } : {}),
    ...extra,
  }
}

// Legacy no-op: the refraction filter is gone, but callers still mount this.
export function GlassDefs() {
  return null
}
