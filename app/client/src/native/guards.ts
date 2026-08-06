import type { DownloadRecord } from './contract'
import type { DownloadDonePayload, DownloadErrorPayload, DownloadProgressPayload } from './offline/reconcile'

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

export function isDownloadRecord(value: unknown): value is DownloadRecord {
  if (!isRecord(value)) return false
  return typeof value.id === 'string' && typeof value.itemId === 'string' &&
    typeof value.title === 'string' &&
    ['queued', 'active', 'paused', 'done', 'error'].includes(String(value.state)) &&
    isFiniteNumber(value.receivedBytes) && isFiniteNumber(value.totalBytes) &&
    isFiniteNumber(value.parts)
}

export function isDownloadProgress(value: unknown): value is DownloadProgressPayload {
  return isRecord(value) && typeof value.id === 'string' &&
    isFiniteNumber(value.receivedBytes) && isFiniteNumber(value.totalBytes) &&
    (value.bytesPerSec === undefined || isFiniteNumber(value.bytesPerSec))
}

export function isDownloadDone(value: unknown): value is DownloadDonePayload {
  return isRecord(value) && typeof value.id === 'string' &&
    typeof value.itemId === 'string' && typeof value.path === 'string'
}

export function isDownloadError(value: unknown): value is DownloadErrorPayload {
  return isRecord(value) && typeof value.id === 'string' &&
    (value.message === undefined || typeof value.message === 'string')
}
