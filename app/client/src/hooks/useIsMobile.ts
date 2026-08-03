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
