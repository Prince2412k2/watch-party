// ── Mobile design tokens ──────────────────────────────────────────────────
// Single source of truth for the phone presentation layer ("Midnight Glass").
// Reconciles the divergent palettes in the codebase (styles.css :root vs. the
// per-page `C = {…}` objects) into ONE token module every mobile screen imports.
// Dark-first and canonical — this is the theme the PWA manifest/theme-color
// commit to. Do NOT add new font families; these are already loaded in styles.css.

export const T = {
  bg:        '#12100e',   // warm charcoal page ground (matches desktop C.bg)
  bgDeep:    '#0b0806',   // status-bar / manifest theme-color, behind everything
  surface:   '#1b1714',
  surface2:  '#26221e',
  text:      '#F3ECE3',   // warm paper
  dim:       '#ABA095',
  faint:     '#75695E',
  line:      'rgba(243,236,227,.09)',
  line2:     'rgba(243,236,227,.18)',
  // `brand` stays the FUNCTIONAL success/live color (download progress, speed,
  // seeds, presence, "Monitoring") — warm-tuned green. The editorial deep-red
  // is a SEPARATE `accent`, migrated onto emphasis/selection/CTA surfaces
  // screen-by-screen so functional greens never turn red (which would read as
  // error). Both coexist during the page-migration phase.
  brand:     '#54B487',   // warm-tuned functional green (live/active/progress)
  brandInk:  '#08160e',   // ink on brand green
  accent:    '#C4392F',   // deep brick red — editorial emphasis/CTA accent
  accentInk: '#FBF4EC',   // warm paper ink on the red accent
  onLight:   '#FBF4EC',   // ink on the primary button
  primary:   '#C4392F',   // primary pill — the deep-red accent
  red:       '#E5484D',   // danger — distinct from the brand red
  glass:     'rgba(27,23,20,.66)',
  glassHi:   'rgba(41,35,30,.74)',
}

export const SERIF = "'Fraunces', 'Iowan Old Style', Georgia, serif"
export const SANS = "'Hanken Grotesk', system-ui, -apple-system, sans-serif"
export const MONO = "'JetBrains Mono', ui-monospace, monospace"

export const R = { sm: 12, md: 16, lg: 22, pill: 999 }
export const EASE = 'cubic-bezier(.2,.8,.2,1)'   // spring-ish, iOS cadence
export const DUR = { fast: '.14s', base: '.24s', slow: '.32s' }

// Type scale (§1.2) — spread onto style objects. Sizes in px (root 16px).
export const TYPE = {
  display:  { fontFamily: SERIF, fontSize: 32,  lineHeight: 1.04, fontWeight: 600, letterSpacing: '-0.02em' },
  title:    { fontFamily: SERIF, fontSize: 22,  lineHeight: 1.12, fontWeight: 600, letterSpacing: '-0.02em' },
  headline: { fontFamily: SANS, fontSize: 17,   lineHeight: 1.25, fontWeight: 700 },
  body:     { fontFamily: SANS, fontSize: 15,   lineHeight: 1.5,  fontWeight: 500 },
  label:    { fontFamily: SANS, fontSize: 13,   lineHeight: 1.3,  fontWeight: 600 },
  meta:     { fontFamily: MONO, fontSize: 11.5, lineHeight: 1.2,  fontWeight: 700, letterSpacing: '.14em', textTransform: 'uppercase' },
  input:    { fontFamily: SANS, fontSize: 16,   lineHeight: 1.4,  fontWeight: 500 },   // never below 16 (iOS zoom)
}

// Signature brand mark gradient (logo/accents). Replaces the old green→blue→
// purple "AI gradient" with a warm editorial deep-red→ember ramp. Ambient page
// glows below are warm-tinted so sections gain depth without the cool cast.
export const BRAND_GRADIENT = 'linear-gradient(135deg, #C4392F, #8f2a22)'
export const AMBIENT = [
  'radial-gradient(62% 46% at 12% -4%, rgba(196,57,47,.16), transparent 60%)',
  'radial-gradient(58% 46% at 104% 6%, rgba(160,80,40,.12), transparent 62%)',
].join(',')

// Spacing scale (px) — keep rhythm consistent across screens.
export const SP = { xs: 6, sm: 10, md: 14, lg: 20, xl: 28, xxl: 40 }

// Fixed z-bands for shell overlays (the Watch screen owns its own bands in
// watchLayers.js; these are only for the shell tree).
export const Z = { base: 1, tabbar: 40, scrim: 90, sheet: 100, toast: 200 }
