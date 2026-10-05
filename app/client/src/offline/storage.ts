export const CHUNK_SIZE = 2 * 1024 * 1024
export const CACHE_TTL = 7 * 24 * 60 * 60 * 1000
export interface MediaInfo {
  owner: string
  itemId: string
  sourceId: string
  revision: string
  size: number
  title: string
  posterItemId?: string
  series: string
  season?: number
  episode?: number
  duration: number
  audioIndex: number | null
  etag: string
  modified: string
  subtitles: { index: number; language?: string; displayTitle: string }[]
}
export interface SavedMedia extends MediaInfo {
  key: string
  generation: string
  retention: 'download' | 'cache'
  state: 'paused' | 'downloading' | 'complete' | 'error'
  received: number
  accessed: number
  error?: string
  subtitleError?: string
  artwork?: Blob
  posterAttempted?: boolean
  resumeOnOpen?: boolean
  backgroundId?: string
  backgroundBase?: number
  backgroundDownloaded?: number
}
let opened: Promise<IDBDatabase> | undefined
export function database() {
  return (opened ??= new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open('watchparty-media', 1)
    request.onupgradeneeded = () => {
      request.result.createObjectStore('media', { keyPath: 'key' })
      const chunks = request.result.createObjectStore('chunks', {
        keyPath: ['media', 'index']
      })
      chunks.createIndex('media', 'media')
      const subtitles = request.result.createObjectStore('subtitles', {
        keyPath: ['media', 'index']
      })
      subtitles.createIndex('media', 'media')
      request.result.createObjectStore('settings')
    }
    request.onsuccess = () => {
      request.result.onversionchange = () => {
        request.result.close()
        opened = undefined
      }
      resolve(request.result)
    }
    request.onerror = () => {
      opened = undefined
      reject(request.error)
    }
  }))
}
export function requestValue<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}
export function transactionDone(tx: IDBTransaction) {
  return new Promise<void>((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onabort = tx.onerror = () =>
      reject(tx.error || new Error('Storage transaction failed'))
  })
}
export async function read<T>(
  store: string,
  key: IDBValidKey
): Promise<T | undefined> {
  const db = await database()
  return requestValue(db.transaction(store).objectStore(store).get(key))
}
export const getMedia = (key: string) => read<SavedMedia>('media', key)
export const owner = () => read<string>('settings', 'owner')
export async function setOwner(value: string | null) {
  const db = await database()
  const tx = db.transaction('settings', 'readwrite')
  const done = transactionDone(tx)
  if (value) tx.objectStore('settings').put(value, 'owner')
  else tx.objectStore('settings').delete('owner')
  await done
}
export async function listMedia(account: string) {
  const db = await database()
  const values = await requestValue<SavedMedia[]>(
    db.transaction('media').objectStore('media').getAll()
  )
  return values
    .filter((m) => m.owner === account)
    .sort((a, b) => b.accessed - a.accessed)
}
export async function updateMedia(
  key: string,
  update: (record: SavedMedia | undefined) => SavedMedia | undefined
) {
  const db = await database()
  const tx = db.transaction('media', 'readwrite')
  const done = transactionDone(tx)
  const store = tx.objectStore('media')
  const record = update(
    await requestValue<SavedMedia | undefined>(store.get(key))
  )
  if (record) store.put(record)
  await done
  return record
}
export const mediaKey = (info: MediaInfo) =>
  `${info.owner}:${info.itemId}:${info.sourceId}:${info.revision}`
export async function prepare(
  info: MediaInfo,
  retention: 'cache' | 'download'
) {
  return (await updateMedia(mediaKey(info), (current) =>
    current
      ? {
          ...current,
          ...info,
          accessed: Date.now(),
          retention: retention === 'download' ? 'download' : current.retention
        }
      : {
          ...info,
          key: mediaKey(info),
          generation: crypto.randomUUID(),
          retention,
          state: 'paused',
          received: 0,
          accessed: Date.now()
        }
  ))!
}
export async function chunk(key: string, index: number) {
  return (await read<{ data: Blob }>('chunks', [key, index]))?.data
}
export async function putChunk(record: SavedMedia, index: number, data: Blob) {
  const db = await database()
  const tx = db.transaction(['media', 'chunks'], 'readwrite')
  const done = transactionDone(tx)
  const store = tx.objectStore('media')
  const current = await requestValue<SavedMedia | undefined>(
    store.get(record.key)
  )
  if (current?.generation !== record.generation) {
    await done
    return false
  }
  const previous = await requestValue(
    tx.objectStore('chunks').get([record.key, index])
  )
  tx.objectStore('chunks').put({ media: record.key, index, data })
  if (!previous) current.received += data.size
  if (current.received === current.size) {
    current.state = 'complete'
    current.error = undefined
  }
  store.put(current)
  await done
  return true
}
export async function putSubtitle(
  record: SavedMedia,
  index: number,
  data: Blob
) {
  const db = await database()
  const tx = db.transaction(['media', 'subtitles'], 'readwrite')
  const done = transactionDone(tx)
  const current = await requestValue<SavedMedia | undefined>(
    tx.objectStore('media').get(record.key)
  )
  if (current?.generation === record.generation)
    tx.objectStore('subtitles').put({ media: record.key, index, data })
  await done
}
export async function removeMedia(
  key: string,
  cacheOnly = false,
  expiredBefore?: number
) {
  const db = await database()
  const tx = db.transaction(['media', 'chunks', 'subtitles'], 'readwrite')
  const done = transactionDone(tx)
  const record = await requestValue<SavedMedia | undefined>(
    tx.objectStore('media').get(key)
  )
  if (
    (cacheOnly && record?.retention === 'download') ||
    (expiredBefore !== undefined && record && record.accessed > expiredBefore)
  ) {
    await done
    return false
  }
  tx.objectStore('media').delete(key)
  for (const name of ['chunks', 'subtitles']) {
    const request = tx
      .objectStore(name)
      .index('media')
      .openKeyCursor(IDBKeyRange.only(key))
    request.onsuccess = () => {
      const cursor = request.result
      if (cursor) {
        tx.objectStore(name).delete(cursor.primaryKey)
        cursor.continue()
      }
    }
  }
  await done
  return true
}
export async function clearCache(
  account: string,
  expiredOnly = false,
  active: ReadonlySet<string> = new Set()
) {
  let skipped = 0
  const expiredBefore = expiredOnly ? Date.now() - CACHE_TTL : undefined
  for (const record of await listMedia(account)) {
    if (
      record.retention !== 'cache' ||
      (expiredBefore !== undefined && record.accessed > expiredBefore)
    )
      continue
    if (active.has(record.key)) {
      skipped++
      continue
    }
    await removeMedia(record.key, true, expiredBefore)
  }
  return { skipped }
}
