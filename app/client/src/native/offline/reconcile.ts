// Pure reconciliation core for useDownloads (native/useOffline.js), split out
// so it's testable without a React renderer. Each function takes the current
// `Map<id, record>` and returns a NEW map with one update applied — dl_list()
// is the source of truth for state/byte totals (reconcileList), dl:* events
// patch individual records between polls.

export function reconcileList(map: any, list: any) {
  const next = new Map()
  for (const rec of list || []) {
    const prev = map.get(rec.id)
    next.set(rec.id, { bytesPerSec: prev?.bytesPerSec ?? 0, ...rec })
  }
  return next
}

export function applyStart(map: any, { id, itemId, title, parts }: any) {
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

export function applyProgress(map: any, payload: any) {
  const next = new Map(map)
  const prev: any = next.get(payload.id)
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

export function applyDone(map: any, payload: any) {
  const next = new Map(map)
  const prev: any = next.get(payload.id)
  next.set(payload.id, {
    ...prev,
    id: payload.id,
    itemId: payload.itemId,
    state: 'done',
    path: payload.path,
    receivedBytes: prev?.totalBytes ?? prev?.receivedBytes ?? 0,
  })
  return next
}

export function applyError(map: any, payload: any) {
  const next = new Map(map)
  const prev: any = next.get(payload.id)
  next.set(payload.id, { ...prev, id: payload.id, state: 'error', message: payload.message })
  return next
}

export function toSortedList(map: any) {
  const values: any[] = Array.from(map.values())
  return values.sort((a, b) => (a.title || '').localeCompare(b.title || ''))
}
