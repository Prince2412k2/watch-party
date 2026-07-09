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
  // seeds, presence, "Monitoring") — muted green. The primary CTA is near-white
  // (Apple-TV play pill); the one quiet color accent is a warm amber (`accent`),
  // used for emphasis/active/focus. Migrated onto surfaces screen-by-screen so
  // functional greens never turn amber. Both coexist during page migration.
  brand:     '#63B98A',   // muted functional green (live/active/progress)
  brandInk:  '#08160e',   // ink on brand green
  accent:    '#E0A458',   // quiet warm amber — emphasis/active/focus accent
  accentInk: '#1A1206',   // dark ink on the amber accent
  onLight:   '#101012',   // dark ink on the near-white primary button
  primary:   '#F3F3F4',   // primary pill — near-white (Apple-TV play)
  red:       '#E06A63',   // muted danger
  glass:     '#151517',   // solid surface (flat, no blur)
  glassHi:   '#202023',
}

export const SANS = "'Hanken Grotesk', system-ui, -apple-system, sans-serif"
export const MONO = "'JetBrains Mono', ui-monospace, monospace"

export const R = { sm: 12, md: 16, lg: 22, pill: 999 }
export const EASE = 'cubic-bezier(.2,.8,.2,1)'   // spring-ish, iOS cadence
export const DUR = { fast: '.14s', base: '.24s', slow: '.32s' }

// Type scale (§1.2) — spread onto style objects. Sizes in px (root 16px).
export const TYPE = {
  display:  { fontFamily: SANS, fontSize: 30,   lineHeight: 1.06, fontWeight: 700, letterSpacing: '-0.03em' },
  title:    { fontFamily: SANS, fontSize: 21,   lineHeight: 1.15, fontWeight: 700, letterSpacing: '-0.02em' },
  headline: { fontFamily: SANS, fontSize: 17,   lineHeight: 1.25, fontWeight: 600 },
  body:     { fontFamily: SANS, fontSize: 15,   lineHeight: 1.5,  fontWeight: 500 },
  label:    { fontFamily: SANS, fontSize: 13,   lineHeight: 1.3,  fontWeight: 600 },
  meta:     { fontFamily: MONO, fontSize: 11.5, lineHeight: 1.2,  fontWeight: 700, letterSpacing: '.14em', textTransform: 'uppercase' },
  input:    { fontFamily: SANS, fontSize: 16,   lineHeight: 1.4,  fontWeight: 500 },   // never below 16 (iOS zoom)
}

// Accent mark gradient for avatars/initials — a restrained warm-amber ramp
// (replaces the old green→blue→purple "AI gradient"). Dark ink stays readable
// on it. Ambient page glow is a single, barely-there warm wash so sections gain
// depth without decoration — cinematic minimal keeps chrome quiet.
export const BRAND_GRADIENT = 'linear-gradient(135deg, #E0A458, #C98A3E)'
export const AMBIENT = 'radial-gradient(80% 60% at 50% -10%, rgba(224,164,88,.07), transparent 60%)'

// Spacing scale (px) — keep rhythm consistent across screens.
export const SP = { xs: 6, sm: 10, md: 14, lg: 20, xl: 28, xxl: 40 }

// Fixed z-bands for shell overlays (the Watch screen owns its own bands in
// watchLayers.js; these are only for the shell tree).
export const Z = { base: 1, tabbar: 40, scrim: 90, sheet: 100, toast: 200 }
