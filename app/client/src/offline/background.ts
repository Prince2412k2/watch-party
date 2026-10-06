import {
  CHUNK_SIZE,
  chunk,
  getMedia,
  ensureDownloadFile,
  fileComplete,
  chunkBytes,
  owner,
  putChunk,
  storageError,
  updateMedia,
  type SavedMedia
} from './storage.ts'
import {
  downloadDirectory,
  downloadFile,
  OPFS_SUPPORTED,
  withFileLock
} from './opfs.ts'
import { validateChunk } from './ranges.ts'

// Background Fetch is implemented by Chromium, but not Safari or Firefox.
export interface BackgroundRecord {
  request: Request
  responseReady: Promise<Response>
}
export interface BackgroundJob {
  id: string
  downloaded: number
  result: '' | 'success' | 'failure'
  failureReason: string
  recordsAvailable: boolean
  matchAll(): Promise<BackgroundRecord[]>
  match?(request: Request): Promise<BackgroundRecord | undefined>
  abort(): Promise<boolean>
}
interface BackgroundManager {
  fetch(
    id: string,
    requests: Request[],
    options: { title: string; downloadTotal: number }
  ): Promise<BackgroundJob>
  get(id: string): Promise<BackgroundJob | undefined>
}
export type BackgroundRegistration = ServiceWorkerRegistration & {
  backgroundFetch?: BackgroundManager
}
const PREFIX = 'watchparty-media:'
export const backgroundManager = (registration: ServiceWorkerRegistration) =>
  (registration as BackgroundRegistration).backgroundFetch
export function mediaRequest(
  record: SavedMedia,
  index: number,
  origin: string
) {
  const start = index * CHUNK_SIZE
  const end = Math.min(record.size - 1, start + CHUNK_SIZE - 1)
  const params = new URLSearchParams({
    source: record.sourceId,
    revision: record.revision,
    chunk: String(index)
  })
  return new Request(`${origin}/api/offline/${record.itemId}/media?${params}`, {
    credentials: 'include',
    headers: { Range: `bytes=${start}-${end}` }
  })
}
export async function startBackground(
  registration: ServiceWorkerRegistration,
  record: SavedMedia,
  origin: string
) {
  const manager = backgroundManager(registration)
  if (!manager || record.received === record.size) return false
  if (record.backgroundId) {
    const existing = await manager.get(record.backgroundId)
    if (existing && !existing.result) return true
  }
  const requests: Request[] = []
  let length = 0
  if (record.fileName && OPFS_SUPPORTED()) {
    try {
      length = await withFileLock(
        record.generation,
        async () => (await downloadFile(record)).size
      )
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'NotFoundError'))
        throw error
    }
  }
  for (let index = 0; index < Math.ceil(record.size / CHUNK_SIZE); index++)
    if (
      !(
        record.fileChunks?.includes(index) &&
        Math.min(record.size, (index + 1) * CHUNK_SIZE) <= length
      ) &&
      !(await chunk(record.key, index))
    )
      requests.push(mediaRequest(record, index, origin))
  if (!requests.length) return false
  const missing = requests.reduce((sum, request) => {
    const [start, end] = request.headers
      .get('range')!
      .slice(6)
      .split('-')
      .map(Number)
    return sum + end - start + 1
  }, 0)
  // The browser holds responses until they are imported. Avoid doubling a large
  // download when storage cannot accommodate both copies; use the worker queue.
  const estimate = await navigator.storage?.estimate?.()
  if (
    estimate?.quota &&
    estimate.usage != null &&
    record.size + missing + CHUNK_SIZE > estimate.quota - estimate.usage
  )
    return false
  const id = `${PREFIX}${record.generation}:${crypto.randomUUID()}:${encodeURIComponent(record.key)}`
  const current = await updateMedia(record.key, (value) =>
    value?.generation === record.generation &&
    value.retention === 'download' &&
    value.resumeOnOpen
      ? {
          ...value,
          state: 'downloading',
          backgroundId: id,
          backgroundBase: value.received
        }
      : value
  )
  if (current?.backgroundId !== id || (await owner()) !== record.owner)
    return false
  try {
    const job = await manager.fetch(id, requests, {
      title: record.title,
      downloadTotal: missing
    })
    const latest = await getMedia(record.key)
    if (
      latest?.generation !== record.generation ||
      latest.backgroundId !== id ||
      !latest.resumeOnOpen ||
      (await owner()) !== record.owner
    )
      await job.abort()
    return true
  } catch {
    // Permission, browser limits, or quota must not prevent ordinary downloads.
    await updateMedia(record.key, (value) =>
      value?.backgroundId === id
        ? {
            ...value,
            state: 'paused',
            backgroundId: undefined,
            backgroundBase: undefined
          }
        : value
    )
    return false
  }
}
export async function backgroundProgress(
  registration: ServiceWorkerRegistration,
  files: SavedMedia[]
) {
  const manager = backgroundManager(registration)
  if (!manager) return files
  return Promise.all(
    files.map(async (file) => {
      if (!file.backgroundId) return file
      const job = await manager.get(file.backgroundId).catch(() => undefined)
      return job ? { ...file, backgroundDownloaded: job.downloaded } : file
    })
  )
}
// Playback takes an already delivered background range when available. A short
// wait lets priority playback proceed instead of waiting for the whole download.
export async function backgroundResponse(
  registration: ServiceWorkerRegistration,
  record: SavedMedia,
  request: Request
): Promise<Response | undefined> {
  if (!record.backgroundId) return
  let timer: ReturnType<typeof setTimeout> | undefined
  try {
    const job = await backgroundManager(registration)?.get(record.backgroundId)
    if (!job?.recordsAvailable || !job.match) return
    const part = await job.match(request)
    if (!part) return
    const response = await Promise.race([
      part.responseReady.catch(() => undefined),
      new Promise<undefined>((resolve) => {
        timer = setTimeout(() => resolve(undefined), 150)
      })
    ])
    return response?.clone()
  } catch {
    return undefined
  } finally {
    if (timer) clearTimeout(timer)
  }
}
export async function abortBackground(
  registration: ServiceWorkerRegistration,
  record: SavedMedia
) {
  if (!record.backgroundId) return
  const job = await backgroundManager(registration)?.get(record.backgroundId)
  await job?.abort()
}
export async function finishBackground(job: BackgroundJob) {
  if (!job.id.startsWith(PREFIX)) return
  const encoded = job.id.slice(PREFIX.length)
  const separator = encoded.indexOf(':')
  const generation = encoded.slice(0, separator)
  const remainder = encoded.slice(separator + 1)
  // A unique attempt keeps a late abort/completion from changing a resumed job.
  const key = decodeURIComponent(remainder.slice(remainder.indexOf(':') + 1))
  const record = await getMedia(key)
  if (
    !record ||
    record.generation !== generation ||
    record.backgroundId !== job.id ||
    record.owner !== (await owner()) ||
    record.retention !== 'download'
  )
    return
  let error: string | undefined
  if (job.recordsAvailable && OPFS_SUPPORTED()) {
    const target = await ensureDownloadFile(record)
    await withFileLock(generation, async () => {
      const handle = await (
        await downloadDirectory(true)
      ).getFileHandle(target.fileName!, { create: true })
      const writer = await handle.createWritable({ keepExistingData: true })
      const written: { index: number; size: number }[] = []
      let closed = false
      const valid = async () => {
        const current = await getMedia(key)
        return (
          current?.generation === generation &&
          current.backgroundId === job.id &&
          current.fileName === target.fileName &&
          current.retention === 'download' &&
          (await owner()) === record.owner
        )
      }
      try {
        // Background completion runs without a window. Use one asynchronous
        // writer for the entire batch, avoiding a whole-file copy per range.
        for (
          let index = 0;
          index < Math.ceil(record.size / CHUNK_SIZE);
          index++
        ) {
          if (target.fileChunks?.includes(index)) continue
          const data = await chunk(key, index)
          if (!data) continue
          if (!(await valid())) return
          if (data.size !== chunkBytes(record, index))
            throw new Error('Incomplete cached chunk')
          await writer.write({
            type: 'write',
            position: index * CHUNK_SIZE,
            data
          })
          written.push({ index, size: data.size })
        }
        for (const part of await job.matchAll()) {
          const index = Number(
            new URL(part.request.url).searchParams.get('chunk')
          )
          if (
            !Number.isSafeInteger(index) ||
            index < 0 ||
            index >= Math.ceil(record.size / CHUNK_SIZE)
          )
            continue
          try {
            const response = await part.responseReady
            const start = index * CHUNK_SIZE,
              end = Math.min(record.size - 1, start + CHUNK_SIZE - 1)
            validateChunk(response, start, end, record.size)
            const data = await response.blob()
            if (data.size !== end - start + 1)
              throw new Error('Incomplete media chunk')
            if (!(await valid())) return
            await writer.write({ type: 'write', position: start, data })
            written.push({ index, size: data.size })
          } catch (err) {
            error =
              err instanceof DOMException && err.name === 'QuotaExceededError'
                ? storageError(err).message
                : err instanceof Error
                  ? err.message
                  : 'Could not save media chunk'
          }
        }
        if (!(await valid())) return
        await writer.close()
        closed = true
        // Publish range metadata only after the file is durable. A killed
        // worker can redownload unindexed bytes, but cannot advertise holes.
        for (const part of written) {
          if (!(await valid())) return
          await putChunk(
            target,
            part.index,
            new Blob([new Uint8Array(part.size)]),
            true
          )
        }
      } finally {
        if (!closed) await writer.abort().catch(() => {})
      }
    }).catch((err) => {
      error =
        err instanceof DOMException && err.name === 'QuotaExceededError'
          ? storageError(err).message
          : err instanceof Error
            ? err.message
            : 'Could not save downloaded file'
    })
  } else if (job.recordsAvailable) {
    for (const part of await job.matchAll()) {
      const index = Number(new URL(part.request.url).searchParams.get('chunk'))
      if (
        !Number.isSafeInteger(index) ||
        index < 0 ||
        index >= Math.ceil(record.size / CHUNK_SIZE)
      )
        continue
      try {
        const response = await part.responseReady
        const start = index * CHUNK_SIZE,
          end = Math.min(record.size - 1, start + CHUNK_SIZE - 1)
        validateChunk(response, start, end, record.size)
        const data = await response.blob()
        if (data.size !== end - start + 1)
          throw new Error('Incomplete media chunk')
        const current = await getMedia(key)
        if (
          current?.generation !== generation ||
          current.backgroundId !== job.id ||
          current.retention !== 'download' ||
          (await owner()) !== record.owner
        )
          return
        await putChunk(record, index, data)
      } catch (err) {
        error =
          err instanceof Error ? err.message : 'Could not save media chunk'
      }
    }
  }
  await updateMedia(key, (current) => {
    if (current?.generation !== generation || current.backgroundId !== job.id)
      return current
    const complete = current.fileName
      ? fileComplete(current)
      : current.received === current.size
    const paused = !current.resumeOnOpen
    return {
      ...current,
      backgroundId: undefined,
      backgroundBase: undefined,
      backgroundDownloaded: undefined,
      state: complete ? 'complete' : paused ? 'paused' : 'error',
      error:
        complete || paused
          ? undefined
          : error || 'Download interrupted. Resume to keep going.'
    }
  })
}
