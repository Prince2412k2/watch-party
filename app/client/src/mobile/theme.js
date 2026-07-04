// ── Mobile design tokens ──────────────────────────────────────────────────
// Single source of truth for the phone presentation layer ("Midnight Glass").
// Reconciles the divergent palettes in the codebase (styles.css :root vs. the
// per-page `C = {…}` objects) into ONE token module every mobile screen imports.
// Dark-first and canonical — this is the theme the PWA manifest/theme-color
// commit to. Do NOT add new font families; these are already loaded in styles.css.

export const T = {
  bg:        '#0b0d10',   // page ground (matches Library/FindDownload/Downloads)
  bgDeep:    '#08080a',   // status-bar / manifest theme-color, behind everything
  surface:   '#16191e',
  surface2:  '#20242b',
  text:      '#F1F3F6',
  dim:       '#A6ADB8',
  faint:     '#6B7280',
  line:      'rgba(255,255,255,.08)',
  line2:     'rgba(255,255,255,.16)',
  brand:     '#3ecf7e',   // green — live/active/accent (downloads, presence, progress)
  brandInk:  '#06210f',   // ink on brand
  onLight:   '#0a0b0d',   // ink on the white primary button
  primary:   '#FFFFFF',   // "Play"/primary pill (Sen-Player white)
  red:       '#FF6B6B',
  glass:     'rgba(20,24,30,.62)',
  glassHi:   'rgba(38,44,54,.7)',
}

export const SANS = "'Hanken Grotesk', system-ui, -apple-system, sans-serif"
export const MONO = "'JetBrains Mono', ui-monospace, monospace"

export const R = { sm: 12, md: 16, lg: 22, pill: 999 }
export const EASE = 'cubic-bezier(.2,.8,.2,1)'   // spring-ish, iOS cadence
export const DUR = { fast: '.14s', base: '.24s', slow: '.32s' }

// Type scale (§1.2) — spread onto style objects. Sizes in px (root 16px).
export const TYPE = {
  display:  { fontFamily: SANS, fontSize: 30,   lineHeight: 1.05, fontWeight: 800, letterSpacing: '-0.02em' },
  title:    { fontFamily: SANS, fontSize: 21,   lineHeight: 1.15, fontWeight: 800, letterSpacing: '-0.02em' },
  headline: { fontFamily: SANS, fontSize: 17,   lineHeight: 1.25, fontWeight: 700 },
  body:     { fontFamily: SANS, fontSize: 15,   lineHeight: 1.5,  fontWeight: 500 },
  label:    { fontFamily: SANS, fontSize: 13,   lineHeight: 1.3,  fontWeight: 600 },
  meta:     { fontFamily: MONO, fontSize: 11.5, lineHeight: 1.2,  fontWeight: 700, letterSpacing: '.14em', textTransform: 'uppercase' },
  input:    { fontFamily: SANS, fontSize: 16,   lineHeight: 1.4,  fontWeight: 500 },   // never below 16 (iOS zoom)
}

// Signature brand mark gradient (logo/accents). Ambient page glows below.
export const BRAND_GRADIENT = 'linear-gradient(135deg, #3ecf7e, #6a8bff, #d16aff)'
export const AMBIENT = [
  'radial-gradient(62% 46% at 12% -4%, rgba(62,207,126,.16), transparent 60%)',
  'radial-gradient(58% 46% at 104% 6%, rgba(106,139,255,.15), transparent 62%)',
].join(',')

// Spacing scale (px) — keep rhythm consistent across screens.
export const SP = { xs: 6, sm: 10, md: 14, lg: 20, xl: 28, xxl: 40 }

// Fixed z-bands for shell overlays (the Watch screen owns its own bands in
// watchLayers.js; these are only for the shell tree).
export const Z = { base: 1, tabbar: 40, scrim: 90, sheet: 100, toast: 200 }
