import { useCallback, useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext.tsx'
import { apiJson } from '../types/guards.ts'
import {
  arrDeletePath,
  arrLibraryPath,
  deleteConfirmation,
  matchArrRecord,
  providerIdOf,
  type ArrKind,
  type ArrRecord,
} from '../analog/libraryDelete.ts'

/**
 * The "delete this from the server" action for a library title, or nothing.
 *
 * Three things have to hold before it exists, and each is a reason not to offer
 * a control that could not work:
 *
 *   * the account is a Jellyfin administrator — the server enforces this and
 *     answers 403 otherwise; this only keeps a member from being handed a
 *     button that fails,
 *   * the Jellyfin item carries the Tmdb/Tvdb id the *arr record joins on,
 *   * and Radarr/Sonarr actually holds a record for it.
 *
 * The join itself is in `analog/libraryDelete.ts`, with its own tests.
 */
export function useLibraryDelete(
  kind: ArrKind,
  item: { Id?: string; ProviderIds?: unknown } | null | undefined,
  onDeleted?: () => void,
) {
  const { user } = useAuth()
  const [record, setRecord] = useState<ArrRecord | null>(null)
  const [deleting, setDeleting] = useState(false)

  const isAdmin = Boolean(user?.isAdmin)
  const providerId = providerIdOf(item?.ProviderIds, kind)

  useEffect(() => {
    setRecord(null)
    if (!isAdmin || providerId === null) return
    let cancelled = false
    fetch(`/api/servarr/${arrLibraryPath(kind)}`, { credentials: 'include' })
      .then(r => (r.ok ? apiJson(r) : null))
      .then(rows => {
        if (!cancelled) setRecord(matchArrRecord(rows, kind, providerId))
      })
      // Unconfigured, unreachable, a 503 — nothing to offer, quietly. This must
      // never be why a title fails to open.
      .catch(() => {})
    return () => { cancelled = true }
  }, [isAdmin, kind, providerId])

  const remove = useCallback(async () => {
    if (!record || deleting) return
    if (!window.confirm(deleteConfirmation(kind, record.title))) return
    setDeleting(true)
    try {
      const response = await fetch(
        `/api/servarr/${arrDeletePath(kind, record.id)}?deleteFiles=true`,
        { method: 'DELETE', credentials: 'include' },
      )
      if (!response.ok) throw new Error(String(response.status))
      setRecord(null)
      onDeleted?.()
    } catch {
      // Left on screen deliberately: reporting success while the file is still
      // on disk is the one outcome worth avoiding here.
    } finally {
      setDeleting(false)
    }
  }, [record, deleting, kind, onDeleted])

  return { canDelete: record !== null, deleting, remove }
}
