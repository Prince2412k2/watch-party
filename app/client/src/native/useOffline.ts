// @ts-nocheck
// Native-only download/offline state — reconciles live dl:* events against
// dl_list()/offline_list() (the source of truth per docs/native/PLAN.md §4.2).
// Gated on IS_NATIVE by the caller; safe to import from a web bundle (it just
// no-ops) since ipc.js stays a dumb transport.
//
// The actual reconciliation logic (queued -> active -> done/error, dl_list()
// as source of truth) lives in offline/reconcile.js as pure functions over a
// Map, so it's unit-testable without a React renderer — see
// offline/reconcile.test.js.
import { useCallback, useEffect, useRef, useState } from 'react'
import { invoke, listen } from './ipc'
import { IPC, EVENTS } from './contract'
import { IS_NATIVE } from './env'
import { reconcileList, applyStart, applyProgress, applyDone, applyError, toSortedList, type DownloadProgressPayload, type DownloadDonePayload, type DownloadErrorPayload } from './offline/reconcile'
import type { DownloadRecord, OfflineRecord } from './contract'

const POLL_MS = 5000

// Tracks every in-flight/finished download this session knows about, keyed by
// download id.
export function useDownloads() {
  const [downloads, setDownloads] = useState<DownloadRecord[]>([])
  const mapRef = useRef<Map<string, DownloadRecord>>(new Map())

  const emit = useCallback(() => {
    setDownloads(toSortedList(mapRef.current))
  }, [])

  const refresh = useCallback(async () => {
    if (!IS_NATIVE) return
    const list = await invoke<DownloadRecord[]>(IPC.DL_LIST, {})
    mapRef.current = reconcileList(mapRef.current, list)
    emit()
  }, [emit])

  useEffect(() => {
    if (!IS_NATIVE) return
    let disposed = false
    const unlisten = []

    ;(async () => {
      await refresh()
      unlisten.push(
        await listen(EVENTS.DL_PROGRESS, ({ payload }) => {
          mapRef.current = applyProgress(mapRef.current, payload as DownloadProgressPayload)
          emit()
        })
      )
      unlisten.push(
        await listen(EVENTS.DL_DONE, ({ payload }) => {
          mapRef.current = applyDone(mapRef.current, payload as DownloadDonePayload)
          emit()
        })
      )
      unlisten.push(
        await listen(EVENTS.DL_ERROR, ({ payload }) => {
          mapRef.current = applyError(mapRef.current, payload as DownloadErrorPayload)
          emit()
        })
      )
      if (disposed) unlisten.forEach((u) => u && u())
    })()

    const interval = setInterval(refresh, POLL_MS)
    return () => {
      disposed = true
      clearInterval(interval)
      unlisten.forEach((u) => u && u())
    }
  }, [refresh, emit])

  const start = useCallback(
    async ({ itemId, url, title, parts }: { itemId: string; url: string; title: string; parts?: number }) => {
      const { id } = await invoke<{ id: string }>(IPC.DL_START, { itemId, url, title, parts })
      mapRef.current = applyStart(mapRef.current, { id, itemId, title, parts })
      emit()
      return id
    },
    [emit]
  )

  const pause = useCallback((id: string) => invoke(IPC.DL_PAUSE, { id }).then(refresh), [refresh])
  const resume = useCallback((id: string) => invoke(IPC.DL_RESUME, { id }).then(refresh), [refresh])
  const cancel = useCallback((id: string) => invoke(IPC.DL_CANCEL, { id }).then(refresh), [refresh])

  return { downloads, refresh, start, pause, resume, cancel }
}

// Completed offline titles (separate from the in-flight download list — this
// is the manifest of what's actually on disk and playable without a server).
export function useOfflineLibrary() {
  const [items, setItems] = useState<OfflineRecord[]>([])

  const refresh = useCallback(async () => {
    if (!IS_NATIVE) return
    const list = await invoke(IPC.OFFLINE_LIST, {})
    setItems((list as OfflineRecord[]) || [])
  }, [])

  useEffect(() => {
    refresh()
  }, [refresh])

  const remove = useCallback(
    async (itemId: string) => {
      await invoke(IPC.OFFLINE_REMOVE, { itemId })
      await refresh()
    },
    [refresh]
  )

  return { items, refresh, remove }
}

// Playback should prefer a downloaded file over the network stream. Returns
// { url, offline } — `url` is a local file path when offline, else the
// caller's streamUrl unchanged. Safe to call when !IS_NATIVE (always misses).
export async function resolveOfflinePlayback(itemId: string | undefined, streamUrl: string) {
  if (IS_NATIVE && itemId) {
    try {
      const result = await invoke<{ path?: string }>(IPC.OFFLINE_PATH, { itemId })
      if (result && result.path) return { url: result.path, offline: true }
    } catch {
      // fall through to the stream URL — offline lookup failing shouldn't block playback
    }
  }
  return { url: streamUrl, offline: false }
}
