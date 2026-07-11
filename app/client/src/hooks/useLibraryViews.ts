import { useEffect, useState } from 'react'
import { apiJson, arrayOf, isLibraryView, objectField, type LibraryView } from '../types/guards'

/* Shared source of the Jellyfin library nav rows (e.g. "Movies", and "Series"
 * once a TV library exists). The Library page fetches /api/library/home for its
 * content; Browse and Downloads have no reason to fetch home except to render the
 * SAME nav — so this tiny hook pulls just the views once per page mount, letting
 * every sidebar render an identical Home → [views] → Browse → Downloads list.
 * Degrades to [] on any error (unauthed/offline), so the sidebar simply omits the
 * library rows rather than breaking. */
export function useLibraryViews() {
  const [views, setViews] = useState<LibraryView[]>([])
  useEffect(() => {
    let cancel = false
    fetch('/api/library/home', { credentials: 'include' })
      .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
      .then((d) => { if (!cancel) setViews(arrayOf(objectField(d, 'views'), isLibraryView)) })
      .catch(() => {})
    return () => { cancel = true }
  }, [])
  return views
}
