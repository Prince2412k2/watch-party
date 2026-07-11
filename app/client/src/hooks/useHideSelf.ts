import { useCallback, useState } from 'react'

const KEY = 'wp:hideSelfView'

// Local-only preference: hide the user's OWN camera tile from their screen while
// STILL publishing video (others keep seeing them). Distinct from turning the
// camera off. Persisted so it survives reloads; default = show self-view.
function read() {
  try { return localStorage.getItem(KEY) === '1' } catch { return false }
}

export function useHideSelf(): [boolean, () => void, (value: boolean) => void] {
  const [hideSelf, setHideSelfState] = useState(read)

  const toggle = useCallback(() => {
    setHideSelfState(prev => {
      const next = !prev
      try { localStorage.setItem(KEY, next ? '1' : '0') } catch {}
      return next
    })
  }, [])

  // Imperative setter (persisted) for the one-way camera→self-view coupling:
  // turning the camera OFF auto-hides my self-view; turning it back ON shows it.
  // Toggling hide-self by hand never touches the camera (that stays in useLiveKit).
  const set = useCallback((value: boolean) => {
    setHideSelfState(prev => {
      const next = !!value
      if (next === prev) return prev
      try { localStorage.setItem(KEY, next ? '1' : '0') } catch {}
      return next
    })
  }, [])

  return [hideSelf, toggle, set]
}
