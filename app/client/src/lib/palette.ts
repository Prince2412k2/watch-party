/* ── Cinematic minimal — dark, flat, monochrome ──────────────────────────────
   Content is the interface (Apple TV / Max). Neutral near-black -> near-white
   ramp, ONE color family total: semantic status (danger/live/success), never
   used decoratively. No brand hue, no gradients, no glass. Keys match the old
   object 1:1 so every page inherits this untouched.

   Split out of ui.tsx, which is a React module: `format.ts` reads the status
   colours, so importing them from there dragged React and JSX into what is
   otherwise a pure formatter — and made it unloadable by the test runner, which
   strips types but cannot compile JSX. Nothing that only needs a colour should
   have to pull in a component tree to get one. ui.tsx re-exports `C`, so every
   existing caller is untouched. */
export const C = {
  bg: 'var(--wp-bg, #0a0a0b)',
  surface: 'var(--wp-surface, #141416)',
  surface2: 'var(--wp-surface-2, #1e1e21)',
  surface3: 'var(--wp-surface-3, #2a2a2e)',
  text: 'var(--wp-text, #F4F4F5)',
  dim: 'var(--wp-dim, rgba(244,244,245,.62))',
  faint: 'var(--wp-faint, rgba(244,244,245,.36))',
  line: 'var(--wp-line, rgba(255,255,255,.08))',
  line2: 'var(--wp-line-2, rgba(255,255,255,.14))',
  accent: 'var(--wp-text, #F4F4F5)',
  accentDim: 'var(--wp-dim, #CBCBCE)',
  accentSoft: 'var(--wp-line, rgba(255,255,255,.08))',
  onAccent: 'var(--wp-bg, #0a0a0b)',
  // Semantic status ONLY — never decorative, never "brand", never active-state fill.
  green: '#5AB98A',          // success tick, sparingly
  amber: '#E0655E',          // (legacy key name) — mapped to danger/live red, see `red`/`live`
  red: '#E0655E',
  live: '#E0655E',           // active-download / recording dot
  glass: '#141416',          // flat solid surface (no blur)
  glassHi: '#1e1e21',
}

export const SANS = "'Circular XX', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
export const MONO = "'JetBrains Mono', ui-monospace, monospace"
