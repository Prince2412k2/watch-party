/// <reference lib="webworker" />
import {
  CHUNK_SIZE,
  ensureDownloadFile,
  fileComplete,
  getMedia,
  owner,
  storageError,
  updateMedia
} from './storage.ts'
import { availableChunk, reconcileFiles, saveFileChunk } from './files.ts'
import { mediaRequest } from './background.ts'
import { validateChunk } from './ranges.ts'
import { runChunkQueue } from './queue.ts'
import { downloadFile, transferLock, withFileLock } from './opfs.ts'
const worker = self as unknown as DedicatedWorkerGlobalScope
const jobs = new Map<
  string,
  { controller: AbortController; task: Promise<void>; full: boolean }
>()
async function transfer(
  key: string,
  full: boolean,
  controller: AbortController
) {
  const original = await getMedia(key)
  if (
    !original ||
    original.retention !== 'download' ||
    original.owner !== (await owner())
  )
    return
  const run = async () => {
    const record = await ensureDownloadFile(original)
    if (
      record?.generation !== original.generation ||
      record.retention !== 'download'
    )
      return
    if (
      full &&
      (!record.resumeOnOpen || record.backgroundId || fileComplete(record))
    )
      return
    if (full)
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? { ...current, state: 'downloading', error: undefined }
          : current
      )
    try {
      let length = 0
      try {
        length = await withFileLock(
          record.generation,
          async () => (await downloadFile(record)).size
        )
      } catch (error) {
        if (!(error instanceof DOMException && error.name === 'NotFoundError'))
          throw error
      }
      await runChunkQueue(
        Math.ceil(record.size / CHUNK_SIZE),
        async (index) => {
          const current = await getMedia(key)
          if (
            current?.generation !== record.generation ||
            current.retention !== 'download' ||
            controller.signal.aborted ||
            (full && !current.resumeOnOpen) ||
            (await owner()) !== record.owner
          )
            throw new DOMException('Paused', 'AbortError')
          // Resume checks the durable range map and file length, rather than
          // reading gigabytes of completed ranges before fetching missing ones.
          if (
            current.fileChunks?.includes(index) &&
            Math.min(record.size, (index + 1) * CHUNK_SIZE) <= length
          )
            return
          let data = await availableChunk(current, index)
          if (!data) {
            if (!full || !worker.navigator.onLine) return
            const response = await fetch(
              mediaRequest(record, index, worker.location.origin),
              { signal: controller.signal }
            )
            const start = index * CHUNK_SIZE,
              end = Math.min(record.size - 1, start + CHUNK_SIZE - 1)
            validateChunk(response, start, end, record.size)
            data = await response.blob()
          }
          if (controller.signal.aborted)
            throw new DOMException('Paused', 'AbortError')
          if (!(await saveFileChunk(record, index, data)))
            throw new DOMException('Paused', 'AbortError')
        },
        controller.signal,
        full ? 3 : 1
      )
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? {
              ...current,
              state: fileComplete(current) ? 'complete' : 'paused',
              error: undefined
            }
          : current
      )
    } catch (error) {
      const aborted =
        controller.signal.aborted ||
        (error instanceof DOMException && error.name === 'AbortError')
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? {
              ...current,
              state: fileComplete(current)
                ? 'complete'
                : aborted
                  ? 'paused'
                  : 'error',
              error: aborted
                ? undefined
                : error instanceof DOMException &&
                    error.name === 'QuotaExceededError'
                  ? storageError(error).message
                  : error instanceof Error
                    ? error.message
                    : storageError(error).message
            }
          : current
      )
    }
  }
  const locked = async () => {
    if (!worker.navigator.locks) return run()
    // A requested Resume waits for a migration in another tab instead of
    // silently dropping the request. Pause can abort a queued lock request.
    await worker.navigator.locks.request(
      transferLock(original.generation),
      full ? { signal: controller.signal } : { ifAvailable: true },
      (lock) => (lock ? run() : Promise.resolve())
    )
  }
  try {
    // Avoid opening every legacy movie at once during a library migration.
    if (!full && worker.navigator.locks)
      await worker.navigator.locks.request(
        'watchparty-file-migration',
        { signal: controller.signal },
        locked
      )
    else await locked()
  } catch (error) {
    if (!controller.signal.aborted) throw error
  }
}
function start(key: string, full: boolean) {
  const previous = jobs.get(key)
  if (previous) {
    if (full && (!previous.full || previous.controller.signal.aborted)) {
      previous.controller.abort()
      void previous.task.catch(() => {}).then(() => start(key, true))
    }
    return
  }
  const controller = new AbortController()
  const task = transfer(key, full, controller).finally(() => jobs.delete(key))
  jobs.set(key, { controller, task, full })
  void task.catch(() => {})
}
worker.addEventListener('message', (event) => {
  const { action, key } = event.data as { action: string; key?: string }
  const run = async () => {
    if (action === 'reconcile') {
      await reconcileFiles()
      return
    }
    if (action === 'pause') {
      jobs.get(key!)?.controller.abort()
      await jobs.get(key!)?.task
      return
    }
    start(key!, action === 'download')
  }
  void run().then(
    () => event.ports[0]?.postMessage({ ok: true }),
    (error) =>
      event.ports[0]?.postMessage({
        error:
          error instanceof DOMException && error.name === 'QuotaExceededError'
            ? storageError(error).message
            : error instanceof Error
              ? error.message
              : storageError(error).message
      })
  )
})
