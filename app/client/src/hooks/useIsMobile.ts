import { useSyncExternalStore } from 'react'

const query = '(max-width: 640px)'

// True on phone-width viewports. Drives responsive layout branches.
export function useIsMobile() {
  return matchStore(query)
}

// Phone-class device in ANY orientation. `useIsMobile` keys off width alone, so
// it misses a phone held in landscape (e.g. 844×390 → 844px wide reads as
// "desktop"). The watch screen needs a detector that fires for both a rotated
// portrait phone (≤900 device width) AND a short landscape phone (≤500 tall),
// gated on a coarse pointer so touch-only devices get the touch layout while
// mouse-driven small windows keep the desktop chrome.
const PHONE_QUERY = '(pointer: coarse) and (max-width: 900px), (pointer: coarse) and (max-height: 500px)'
export function usePhone() {
  return matchStore(PHONE_QUERY)
}

// Roomy-phone gate for the watch control bar. Below this the bar splits into a
// primary cluster + a "⋯" overflow popover; at/above it every control inlines
// back into the bar. 820px clears a landscape 740×360 (→ overflow) but lets a
// 844×390 phone (→ inline) fit all controls without horizontal scroll.
const WIDE_BAR_QUERY = '(min-width: 820px)'
export function useWideBar() {
  return matchStore(WIDE_BAR_QUERY)
}

function matchStore(q: string) {
  return useSyncExternalStore(
    (cb) => {
      const m = window.matchMedia(q)
      m.addEventListener('change', cb)
      return () => m.removeEventListener('change', cb)
    },
    () => window.matchMedia(q).matches,
    () => false,
  )
}
