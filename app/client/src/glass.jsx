// ── Liquid glass ────────────────────────────────────────────────────────────
// Real refractive glass (per atlaspuplabs "Liquid Glass in CSS"): an SVG
// displacement map whose R channel encodes horizontal and B channel vertical
// offset, with the gradients bunched at the edges (0–6% / 94–100%) so the
// backdrop *bulges/refracts* at the rim like a lens — not a uniform frost.
// Chromium-only (SVG in backdrop-filter); elsewhere degrades to frost+specular.

const CAN_REFRACT = typeof window !== 'undefined' && (() => {
  try {
    return CSS.supports('backdrop-filter', 'url(#a) blur(1px)') ||
           CSS.supports('-webkit-backdrop-filter', 'url(#a) blur(1px)')
  } catch { return false }
})()

/**
 * @param level  'clear' | 'light' | 'medium' | 'heavy'
 * @param opts   { refract?: bool, radius?: number, ...extra style }
 */
export function glass(level = 'medium', opts = {}) {
  const { refract = false, radius, ...extra } = opts
  // Higher base tint so the panel has *material* even over pure black (where a
  // lens has nothing to refract). Neutral (white) specular — the article's
  // blue/green fresnel tints read as fake smudges on a dark UI.
  const c = {
    clear:  { blur: 5,  tint: 0.14 },
    light:  { blur: 10, tint: 0.20 },
    medium: { blur: 16, tint: 0.30 },
    heavy:  { blur: 26, tint: 0.46 },
  }[level] || {}

  const filter = `${refract && CAN_REFRACT ? 'url(#lg-refract) ' : ''}blur(${c.blur}px) saturate(1.5) brightness(1.06)`

  return {
    backgroundImage: [
      // top-lit sheen so it looks like a physical slab even with no backdrop
      'linear-gradient(180deg, rgba(255,255,255,.12) 0%, rgba(255,255,255,.03) 38%, rgba(255,255,255,0) 100%)',
      'linear-gradient(135deg, rgba(255,255,255,.10), transparent 40%)',
    ].join(','),
    backgroundColor: `rgba(30,32,40,${c.tint})`,
    backdropFilter: filter,
    WebkitBackdropFilter: filter,
    border: '1px solid rgba(255,255,255,.12)',
    boxShadow: [
      'inset 0 1px 0 rgba(255,255,255,.30)',      // crisp lit top edge
      'inset 0 0 0 1px rgba(255,255,255,.04)',    // faint inner containment
      'inset 0 -24px 40px rgba(0,0,0,.14)',       // soft base falloff → depth
      '0 14px 40px rgba(0,0,0,.5)',               // cast shadow
    ].join(','),
    ...(radius != null ? { borderRadius: radius } : {}),
    ...extra,
  }
}

// Edge-refraction displacement map: R = x-offset, B = y-offset, bunched at rim.
const MAP = 'data:image/svg+xml,' + encodeURIComponent(
  `<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400'>
    <defs>
      <linearGradient id='r' x1='0' x2='1' y1='0' y2='0'>
        <stop offset='0' stop-color='#f00' stop-opacity='1'/>
        <stop offset='0.06' stop-color='#f00' stop-opacity='.5'/>
        <stop offset='0.94' stop-color='#f00' stop-opacity='.3'/>
        <stop offset='1' stop-color='#f00' stop-opacity='0'/>
      </linearGradient>
      <linearGradient id='b' x1='0' x2='0' y1='0' y2='1'>
        <stop offset='0' stop-color='#00f' stop-opacity='1'/>
        <stop offset='0.06' stop-color='#00f' stop-opacity='.5'/>
        <stop offset='0.94' stop-color='#00f' stop-opacity='.3'/>
        <stop offset='1' stop-color='#00f' stop-opacity='0'/>
      </linearGradient>
    </defs>
    <rect width='400' height='400' fill='#000'/>
    <rect width='400' height='400' fill='url(#r)' style='mix-blend-mode:lighten'/>
    <rect width='400' height='400' fill='url(#b)' style='mix-blend-mode:lighten'/>
  </svg>`
)

// Mount once near the app root. Referenced by backdrop-filter: url(#lg-refract).
export function GlassDefs() {
  return (
    <svg aria-hidden="true" width="0" height="0" style={{ position: 'absolute', pointerEvents: 'none' }}>
      <filter id="lg-refract" x="-15%" y="-15%" width="130%" height="130%" colorInterpolationFilters="sRGB">
        <feImage href={MAP} preserveAspectRatio="none" result="map" />
        <feDisplacementMap in="SourceGraphic" in2="map" scale="16" xChannelSelector="R" yChannelSelector="B" />
      </filter>
    </svg>
  )
}
