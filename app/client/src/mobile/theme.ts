// ── Mobile design tokens ──────────────────────────────────────────────────
// Single source of truth for the phone presentation layer ("Midnight Glass").
// Reconciles the divergent palettes in the codebase (styles.css :root vs. the
// per-page `C = {…}` objects) into ONE token module every mobile screen imports.
// Dark-first and canonical — this is the theme the PWA manifest/theme-color
// commit to. Do NOT add new font families; these are already loaded in styles.css.

// Cinematic minimal — dark, flat, monochrome (matches desktop C in lib/ui.jsx).
// `brand` stays the FUNCTIONAL status color (active download/recording dot)
// only — it is never used as a fill, emphasis, or active-state color. Progress
// bars are near-white, not colored.
export const T = {
  bg:        '#0a0a0b',   // page ground (matches desktop C.bg)
  bgDeep:    '#0a0a0b',   // status-bar / manifest theme-color, behind everything
  surface:   '#141416',
  surface2:  '#1e1e21',
  surface3:  '#2a2a2e',
  text:      '#F4F4F5',
  dim:       'rgba(244,244,245,.62)',
  faint:     'rgba(244,244,245,.36)',
  line:      'rgba(255,255,255,.08)',
  line2:     'rgba(255,255,255,.14)',
  brand:     '#E0655E',   // active-download / recording status dot ONLY
  brandInk:  '#2a0f0d',   // ink on brand
  onLight:   '#0a0a0b',   // ink on the near-white primary button
  primary:   '#F4F4F5',   // "Play"/primary pill — near-white, not a color accent
  red:       '#E0655E',
  green:     '#5AB98A',   // success tick, sparingly
  glass:     '#141416',   // flat solid surface (no blur)
  glassHi:   '#1e1e21',
}

export const SANS = "'Circular XX', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
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

// Gradients are gone (cinematic-minimal: no color, no gradients). These two
// exports are kept so importing screens don't break the build immediately —
// each mobile-screen agent replaces its own usages with AVATAR_BG / nothing
// per the redesign plan (docs/redesign/PLAN.md, foundation step 4).
export const BRAND_GRADIENT = '#1e1e21'
export const AVATAR_BG = '#1e1e21'
export const AMBIENT = 'none'

// Spacing scale (px) — keep rhythm consistent across screens.
export const SP = { xs: 6, sm: 10, md: 14, lg: 20, xl: 28, xxl: 40 }

// Fixed z-bands for shell overlays (the Watch screen owns its own bands in
// watchLayers.js; these are only for the shell tree).
export const Z = { base: 1, tabbar: 40, scrim: 90, sheet: 100, toast: 200 }
