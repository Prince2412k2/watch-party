import { useEffect, useState } from 'react'

/* Shared source of the Jellyfin library nav rows (e.g. "Movies", and "Series"
 * once a TV library exists). The Library page fetches /api/library/home for its
 * content; Browse and Downloads have no reason to fetch home except to render the
 * SAME nav — so this tiny hook pulls just the views once per page mount, letting
 * every sidebar render an identical Home → [views] → Browse → Downloads list.
 * Degrades to [] on any error (unauthed/offline), so the sidebar simply omits the
 * library rows rather than breaking. */
export function useLibraryViews() {
  const [views, setViews] = useState([])
  useEffect(() => {
    let cancel = false
    fetch('/api/library/home', { credentials: 'include' })
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then((d) => { if (!cancel) setViews(Array.isArray(d?.views) ? d.views : []) })
      .catch(() => {})
    return () => { cancel = true }
  }, [])
  return views
}
