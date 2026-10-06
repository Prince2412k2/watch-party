import { downloadName, removeDownloadFile } from './opfs.ts'
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
  fileName?: string
  fileChunks?: number[]
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
      request.result.onclose = () => {
        opened = undefined
      }
      request.result.onversionchange = () => {
        request.result.close()
        opened = undefined
      }
      resolve(request.result)
    }
    request.onerror = () => {
      opened = undefined
      reject(storageError(request.error))
    }
  }))
}
export function requestValue<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(storageError(request.error))
  })
}
export function storageError(error: unknown): Error {
  const name =
    error && typeof error === 'object' && 'name' in error
      ? String(error.name)
      : 'AbortError'
  const detail = error instanceof Error ? error.message : ''
  const message =
    name === 'QuotaExceededError'
      ? 'Storage is full. Remove a download or clear cache, then retry.'
      : name === 'TransactionInactiveError'
        ? 'Storage transaction expired. Reload and retry.'
        : `Could not save browser storage (${name}). ${detail || 'Reload and retry.'}`
  const value = new Error(message)
  value.name = name
  return value
}
export function transactionDone(tx: IDBTransaction) {
  return new Promise<void>((resolve, reject) => {
    let failure: DOMException | null = null
    tx.oncomplete = () => resolve()
    // The request error arrives before tx.error is populated. Wait for abort
    // and keep its cause, rather than replacing it with a generic message.
    tx.onerror = (event) => {
      failure = (event.target as IDBRequest | null)?.error ?? failure
    }
    tx.onabort = () => reject(storageError(tx.error || failure))
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
  const db = await database(),
    tx = db.transaction('media', 'readwrite'),
    done = transactionDone(tx),
    store = tx.objectStore('media')
  let record: SavedMedia | undefined
  let failure: unknown
  const request = store.get(key)
  request.onsuccess = () => {
    // Issue dependent IDB requests in this callback, while Safari keeps the
    // transaction active. No awaits between reading and writing metadata.
    try {
      record = update(request.result)
      if (record) store.put(record)
    } catch (error) {
      failure = error
      tx.abort()
    }
  }
  await done.catch((error) => {
    throw failure ? storageError(failure) : error
  })
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
export const chunkBytes = (record: SavedMedia, index: number) =>
  Math.min(CHUNK_SIZE, record.size - index * CHUNK_SIZE)
export const fileComplete = (record: SavedMedia) => {
  const count = Math.ceil(record.size / CHUNK_SIZE),
    indexes = new Set(record.fileChunks)
  return (
    !!record.fileName &&
    indexes.size === count &&
    [...indexes].every(
      (index) => Number.isInteger(index) && index >= 0 && index < count
    )
  )
}
export async function allMedia() {
  const db = await database()
  return requestValue<SavedMedia[]>(
    db.transaction('media').objectStore('media').getAll()
  )
}
export async function cachedChunks(key: string) {
  const db = await database()
  return new Promise<{ index: number; size: number }[]>((resolve, reject) => {
    const values: { index: number; size: number }[] = []
    const request = db
      .transaction('chunks')
      .objectStore('chunks')
      .index('media')
      .openCursor(IDBKeyRange.only(key))
    request.onerror = () => reject(storageError(request.error))
    request.onsuccess = () => {
      const cursor = request.result
      if (cursor) {
        values.push({ index: cursor.value.index, size: cursor.value.data.size })
        cursor.continue()
      } else resolve(values)
    }
  })
}
export async function ensureDownloadFile(record: SavedMedia) {
  return (await updateMedia(record.key, (current) => {
    if (
      current?.generation !== record.generation ||
      current.retention !== 'download'
    )
      return current
    if (current.fileName) return current
    return {
      ...current,
      fileName: downloadName(current),
      fileChunks: [],
      state: current.state === 'complete' ? 'paused' : current.state
    }
  }))!
}
export async function putChunk(
  record: SavedMedia,
  index: number,
  data: Blob,
  toFile = false
) {
  const db = await database(),
    tx = db.transaction(['media', 'chunks'], 'readwrite'),
    done = transactionDone(tx),
    store = tx.objectStore('media'),
    chunks = tx.objectStore('chunks')
  let saved = false
  const request = store.get(record.key)
  request.onsuccess = () => {
    const current = request.result as SavedMedia | undefined
    if (
      current?.generation !== record.generation ||
      (toFile &&
        (current.retention !== 'download' ||
          current.fileName !== record.fileName))
    )
      return
    if (!toFile && current.fileChunks?.includes(index)) {
      saved = true
      return
    }
    const previous = chunks.get([record.key, index])
    previous.onsuccess = () => {
      if (!previous.result && !current.fileChunks?.includes(index))
        current.received += data.size
      if (toFile) {
        current.fileChunks = [
          ...new Set([...(current.fileChunks ?? []), index])
        ]
        chunks.delete([record.key, index])
      } else chunks.put({ media: record.key, index, data })
      if (
        current.fileName
          ? fileComplete(current)
          : current.received === current.size
      ) {
        current.state = 'complete'
        current.error = undefined
      }
      store.put(current)
      saved = true
    }
  }
  await done
  return saved
}
export async function putSubtitle(
  record: SavedMedia,
  index: number,
  data: Blob
) {
  const db = await database(),
    tx = db.transaction(['media', 'subtitles'], 'readwrite'),
    done = transactionDone(tx)
  const request = tx.objectStore('media').get(record.key)
  request.onsuccess = () => {
    if (request.result?.generation === record.generation)
      tx.objectStore('subtitles').put({ media: record.key, index, data })
  }
  await done
}
export async function cancelDownload(record: SavedMedia) {
  const db = await database(),
    tx = db.transaction(['media', 'chunks'], 'readwrite'),
    done = transactionDone(tx)
  const request = tx.objectStore('media').get(record.key)
  request.onsuccess = () => {
    const current = request.result as SavedMedia | undefined
    if (current?.generation !== record.generation) return
    let received = 0
    const scan = tx
      .objectStore('chunks')
      .index('media')
      .openCursor(IDBKeyRange.only(record.key))
    scan.onsuccess = () => {
      const cursor = scan.result
      if (cursor) {
        received += cursor.value.data.size
        cursor.continue()
        return
      }
      tx.objectStore('media').put({
        ...current,
        retention: 'cache',
        fileName: undefined,
        fileChunks: undefined,
        received,
        state: received === current.size ? 'complete' : 'paused',
        resumeOnOpen: false,
        backgroundId: undefined,
        backgroundBase: undefined,
        error: undefined
      })
    }
  }
  await done
  await removeDownloadFile(record)
}
export async function removeMedia(
  key: string,
  cacheOnly = false,
  expiredBefore?: number
) {
  const db = await database(),
    tx = db.transaction(['media', 'chunks', 'subtitles'], 'readwrite'),
    done = transactionDone(tx)
  let record: SavedMedia | undefined,
    removed = false
  const request = tx.objectStore('media').get(key)
  request.onsuccess = () => {
    record = request.result
    if (
      (cacheOnly && record?.retention === 'download') ||
      (expiredBefore !== undefined && record && record.accessed > expiredBefore)
    )
      return
    tx.objectStore('media').delete(key)
    removed = true
    for (const name of ['chunks', 'subtitles']) {
      const cursorRequest = tx
        .objectStore(name)
        .index('media')
        .openKeyCursor(IDBKeyRange.only(key))
      cursorRequest.onsuccess = () => {
        const cursor = cursorRequest.result
        if (cursor) {
          tx.objectStore(name).delete(cursor.primaryKey)
          cursor.continue()
        }
      }
    }
  }
  await done
  if (removed && record) await removeDownloadFile(record)
  return removed
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
