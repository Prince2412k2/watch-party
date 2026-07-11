// Pure reconciliation core for useDownloads (native/useOffline.js), split out
// so it's testable without a React renderer. Each function takes the current
// `Map<id, record>` and returns a NEW map with one update applied — dl_list()
// is the source of truth for state/byte totals (reconcileList), dl:* events
// patch individual records between polls.

import type { DownloadRecord } from '../contract.ts'
export interface DownloadProgressPayload { id: string; receivedBytes: number; totalBytes: number; bytesPerSec?: number }
export interface DownloadDonePayload { id: string; itemId: string; path: string }
export interface DownloadErrorPayload { id: string; message?: string }
export function reconcileList(map: Map<string, DownloadRecord>, list: DownloadRecord[] = []) {
  const next = new Map<string, DownloadRecord>()
  for (const rec of list || []) {
    const prev = map.get(rec.id)
    next.set(rec.id, { bytesPerSec: prev?.bytesPerSec ?? 0, ...rec })
  }
  return next
}

export function applyStart(map: Map<string, DownloadRecord>, { id, itemId, title, parts }: { id: string; itemId: string; title: string; parts?: number }) {
  const next = new Map(map)
  next.set(id, {
    id,
    itemId,
    title,
    state: 'queued',
    receivedBytes: 0,
    totalBytes: 0,
    parts: parts || 1,
    bytesPerSec: 0,
  })
  return next
}

export function applyProgress(map: Map<string, DownloadRecord>, payload: DownloadProgressPayload) {
  const next = new Map(map)
  const prev = next.get(payload.id)
  next.set(payload.id, {
    id: payload.id,
    itemId: prev?.itemId ?? '',
    title: prev?.title ?? '',
    parts: prev?.parts ?? 1,
    ...prev,
    state: 'active',
    receivedBytes: payload.receivedBytes,
    totalBytes: payload.totalBytes,
    bytesPerSec: payload.bytesPerSec,
  })
  return next
}

export function applyDone(map: Map<string, DownloadRecord>, payload: DownloadDonePayload) {
  const next = new Map(map)
  const prev = next.get(payload.id)
  next.set(payload.id, {
    ...prev,
    id: payload.id,
    itemId: payload.itemId,
    title: prev?.title ?? '',
    totalBytes: prev?.totalBytes ?? 0,
    parts: prev?.parts ?? 1,
    state: 'done',
    path: payload.path,
    receivedBytes: prev?.totalBytes ?? prev?.receivedBytes ?? 0,
  })
  return next
}

export function applyError(map: Map<string, DownloadRecord>, payload: DownloadErrorPayload) {
  const next = new Map(map)
  const prev = next.get(payload.id)
  next.set(payload.id, {
    ...prev,
    id: payload.id,
    itemId: prev?.itemId ?? '',
    title: prev?.title ?? '',
    state: 'error',
    receivedBytes: prev?.receivedBytes ?? 0,
    totalBytes: prev?.totalBytes ?? 0,
    parts: prev?.parts ?? 1,
    message: payload.message,
  })
  return next
}

export function toSortedList(map: Map<string, DownloadRecord>): DownloadRecord[] {
  const values = Array.from(map.values())
  return values.sort((a, b) => (a.title || '').localeCompare(b.title || ''))
}
