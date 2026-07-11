// ── Screen-mirror store ───────────────────────────────────────────────────
// The host's scroll position + cursor is high-frequency (30–60 fps). Routing
// it through React state would re-render the whole library on every frame, so
// we keep it in a module-level pub/sub and let followers apply it imperatively
// (scrollTop + a ghost-cursor transform) via a single rAF loop.

import type { MirrorPoint } from './types'

type MirrorState = Required<MirrorPoint>
const listeners = new Set<(value: MirrorState) => void>()
// scroll: 0..1 fraction of the scrollable height (viewport-independent, so it
// maps across different screen sizes). x/y: 0..1 fraction of the shared content
// pane's bounding rect (NOT the raw viewport) — the pane is laid out
// identically on host and guest, so a pane-relative fraction maps the ghost
// cursor onto the same content across different viewport sizes.
let latest: MirrorState = { scroll: 0, x: 0.5, y: 0.5 }

export const mirror = {
  get: () => latest,
  set: (v: MirrorPoint) => { latest = { ...latest, ...v }; for (const l of listeners) l(latest) },
  subscribe: (fn: (value: MirrorState) => void) => { listeners.add(fn); return () => listeners.delete(fn) },
}
