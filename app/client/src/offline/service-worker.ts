/// <reference lib="webworker" />
import {
  CHUNK_SIZE,
  cancelDownload,
  chunk,
  clearCache,
  fileComplete,
  getMedia,
  listMedia,
  owner,
  putChunk,
  putSubtitle,
  read,
  removeMedia,
  storageError,
  updateMedia,
  type SavedMedia
} from './storage.ts'
import { availableChunk } from './files.ts'
import { streamMediaRange } from './mediaStream.ts'
import { transferLock } from './opfs.ts'
import { byteRange, validateChunk } from './ranges.ts'
import { runChunkQueue } from './queue.ts'
import {
  abortBackground,
  backgroundManager,
  backgroundResponse,
  finishBackground,
  mediaRequest,
  type BackgroundJob
} from './background.ts'
const sw = self as unknown as ServiceWorkerGlobalScope
const inflight = new Map<string, Promise<Blob>>()
const downloads = new Map<string, AbortController>()
const running = new Map<string, Promise<void>>()
const active = new Map<string, number>()
const SHELL = 'watchparty-shell-v1'
async function cachePoster(record: SavedMedia) {
  if (record.artwork || record.posterAttempted) return
  let claimed = false
  await updateMedia(record.key, (current) => {
    if (current?.generation !== record.generation || current.posterAttempted)
      return current
    claimed = true
    return { ...current, posterAttempted: true }
  })
  if (!claimed || (await owner()) !== record.owner) return
  try {
    const response = await fetch(
      `/api/library/image/${record.posterItemId || record.itemId}?maxWidth=240`,
      { credentials: 'include' }
    )
    if (
      !response.ok ||
      !response.headers.get('content-type')?.startsWith('image/')
    )
      return
    const artwork = await response.blob()
    if (artwork.size > 2 * 1024 * 1024 || (await owner()) !== record.owner)
      return
    await updateMedia(record.key, (current) =>
      current?.generation === record.generation
        ? { ...current, artwork }
        : current
    )
  } catch {
    /* Artwork must never delay or fail a movie download. */
  }
}
const retain = (key: string) => {
  active.set(key, (active.get(key) || 0) + 1)
  let ended = false
  return () => {
    if (ended) return
    ended = true
    const n = (active.get(key) || 1) - 1
    if (n) active.set(key, n)
    else active.delete(key)
  }
}

async function loadChunk(
  record: SavedMedia,
  index: number,
  saveRequired = false,
  signal?: AbortSignal
): Promise<Blob> {
  if ((await owner()) !== record.owner) throw new Error('Account changed')
  const stored = await availableChunk(record, index)
  if (stored) return stored
  const id = `${record.key}/${record.generation}/${index}`
  const pending = inflight.get(id)
  if (pending) return pending
  const task = (async () => {
    const current = await getMedia(record.key)
    if (current?.generation !== record.generation)
      throw new Error('File removed')
    const start = index * CHUNK_SIZE,
      end = Math.min(record.size - 1, start + CHUNK_SIZE - 1)
    const request = mediaRequest(record, index, sw.location.origin)
    const response =
      (await backgroundResponse(sw.registration, current, request)) ||
      (await fetch(request, { signal }))
    validateChunk(response, start, end, record.size)
    const data = await response.blob()
    if (data.size !== end - start + 1) throw new Error('Incomplete media chunk')
    try {
      await putChunk(record, index, data)
    } catch (error) {
      if (saveRequired) throw error
      // Playback remains usable when caching hits the browser's quota.
      await updateMedia(
        record.key,
        (current) =>
          current && {
            ...current,
            error: `${storageError(error).message} Playback continues without saving new chunks.`
          }
      ).catch(() => {})
    }
    return data
  })()
  inflight.set(id, task)
  try {
    return await task
  } finally {
    inflight.delete(id)
  }
}

async function cacheCaptions(
  record: SavedMedia,
  controller = new AbortController()
) {
  const key = record.key
  await updateMedia(key, (current) =>
    current?.generation === record.generation
      ? { ...current, subtitleError: undefined }
      : current
  )
  for (const subtitle of record.subtitles) {
    if (controller.signal.aborted)
      throw new DOMException('Paused', 'AbortError')
    if (await read('subtitles', [key, subtitle.index])) continue
    try {
      const response = await fetch(
        `/api/library/items/${record.itemId}/subtitles/${subtitle.index}/content?mediaSourceId=${record.sourceId}`,
        { credentials: 'include', signal: controller.signal }
      )
      if (!response.ok) throw new Error('Subtitle unavailable')
      await putSubtitle(record, subtitle.index, await response.blob())
    } catch (error) {
      if (controller.signal.aborted) throw error
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? {
              ...current,
              subtitleError:
                'Some subtitles could not be saved. Retry to save them.'
            }
          : current
      )
    }
  }
}

async function download(key: string, controller: AbortController) {
  const record = await getMedia(key)
  if (
    !record ||
    record.owner !== (await owner()) ||
    record.retention !== 'download'
  )
    throw new Error('Saved file not found')
  await updateMedia(key, (current) =>
    current?.generation === record.generation
      ? {
          ...current,
          state: 'downloading',
          resumeOnOpen: true,
          error: undefined,
          subtitleError: undefined
        }
      : current
  )
  try {
    await cacheCaptions(record, controller)
    await runChunkQueue(
      Math.ceil(record.size / CHUNK_SIZE),
      async (index) => {
        const current = await getMedia(key)
        if (
          current?.generation !== record.generation ||
          current.retention !== 'download' ||
          controller.signal.aborted
        )
          throw new DOMException('Paused', 'AbortError')
        await loadChunk(record, index, true)
        if (!(await chunk(key, index)))
          throw new Error(
            'Could not save chunk. Check available storage and retry.'
          )
      },
      controller.signal
    )
    await updateMedia(key, (current) =>
      current?.generation === record.generation
        ? { ...current, state: 'complete', error: undefined }
        : current
    )
  } catch (error) {
    await updateMedia(key, (current) =>
      current?.generation === record.generation
        ? {
            ...current,
            state:
              current.received === current.size
                ? 'complete'
                : controller.signal.aborted
                  ? 'paused'
                  : 'error',
            error:
              current.received === current.size || controller.signal.aborted
                ? undefined
                : error instanceof Error
                  ? error.message
                  : 'Download failed'
          }
        : current
    )
  }
}

function startDownload(key: string): Promise<void> {
  const previous = running.get(key)
  if (previous)
    return downloads.get(key)?.signal.aborted
      ? previous.catch(() => {}).then(() => startDownload(key))
      : previous
  const controller = new AbortController()
  downloads.set(key, controller)
  const task = download(key, controller).finally(() => {
    downloads.delete(key)
    running.delete(key)
  })
  running.set(key, task)
  return task
}

async function mediaResponse(request: Request, key: string) {
  const record = await getMedia(key)
  if (!record || record.owner !== (await owner()))
    return new Response('Saved media not found', { status: 404 })
  const range = byteRange(request.headers.get('range'), record.size)
  if (!range)
    return new Response(null, {
      status: 416,
      headers: { 'Content-Range': `bytes */${record.size}` }
    })
  await updateMedia(
    key,
    (current) => current && { ...current, accessed: Date.now() }
  )
  const headers = {
    'Content-Type': 'video/mp4',
    'Content-Length': String(range.end - range.start + 1),
    'Accept-Ranges': 'bytes',
    'Cache-Control': 'no-store',
    ...(request.headers.has('range')
      ? { 'Content-Range': `bytes ${range.start}-${range.end}/${record.size}` }
      : {})
  }
  if (request.method === 'HEAD')
    return new Response(null, {
      status: request.headers.has('range') ? 206 : 200,
      headers
    })
  const release = retain(key)
  const abort = new AbortController()
  const cancel = () => {
    abort.abort()
    release()
  }
  request.signal.addEventListener('abort', cancel, { once: true })
  if (request.signal.aborted) cancel()
  const finish = () => {
    request.signal.removeEventListener('abort', cancel)
    release()
  }
  const stream = streamMediaRange({
    ...range,
    size: record.size,
    chunkSize: CHUNK_SIZE,
    signal: abort.signal,
    stored: async (index) => {
      if ((await owner()) !== record.owner) throw new Error('Account changed')
      const current = await getMedia(key)
      if (current?.generation !== record.generation)
        throw new Error('File removed')
      return availableChunk(record, index)
    },
    fetchChunk: async (index, signal) => {
      const request = mediaRequest(record, index, sw.location.origin)
      return (
        (await backgroundResponse(sw.registration, record, request)) ||
        fetch(request, { signal })
      )
    },
    save: async (index, data) => {
      // Quota errors affect caching, never the already playing stream.
      await putChunk(record, index, data).catch(() => {})
    }
  })
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const next = await stream.next()
        if (abort.signal.aborted) return
        if (next.done) {
          controller.close()
          finish()
        } else controller.enqueue(next.value)
      } catch (error) {
        if (!abort.signal.aborted) controller.error(error)
        finish()
      }
    },
    async cancel() {
      cancel()
      await stream.return().catch(() => {})
      finish()
    }
  })
  return new Response(body, {
    status: request.headers.has('range') ? 206 : 200,
    headers
  })
}

sw.addEventListener('install', (event) => event.waitUntil(sw.skipWaiting()))
sw.addEventListener('activate', (event) =>
  event.waitUntil(
    (async () => {
      await sw.clients.claim()
      for (const cache of await caches.keys())
        if (cache.startsWith('watchparty-shell-') && cache !== SHELL)
          await caches.delete(cache)
      const account = await owner()
      if (account) {
        await clearCache(account, true)
      }
    })()
  )
)
sw.addEventListener('message', (event) => {
  const message = event.data as {
    action: string
    key?: string
    urls?: string[]
  }
  const run = async () => {
    const account = await owner()
    if (message.action === 'shell') {
      const cache = await caches.open(SHELL)
      for (const url of message.urls ?? []) {
        const parsed = new URL(url, sw.location.origin)
        if (
          parsed.origin !== sw.location.origin ||
          parsed.pathname.startsWith('/api/') ||
          parsed.pathname.startsWith('/__')
        )
          continue
        try {
          const response = await fetch(parsed.href)
          if (response.ok) await cache.put(parsed.href, response)
        } catch {}
      }
      return
    }
    if (!account) throw new Error('Sign in first')
    if (message.action === 'recover') {
      const held = (await sw.navigator.locks?.query())?.held ?? []
      const resume: string[] = []
      for (const record of await listMedia(account)) {
        if (
          record.retention !== 'download' ||
          running.has(record.key) ||
          held.some((lock) => lock.name === transferLock(record.generation))
        )
          continue
        const recover = async () => {
          if (running.has(record.key)) return
          const latest = await getMedia(record.key)
          if (!latest || latest.generation !== record.generation) return
          const job = latest.backgroundId
            ? await backgroundManager(sw.registration)?.get(latest.backgroundId)
            : undefined
          if (job && !job.result) return
          if (job?.recordsAvailable) await finishBackground(job)
          const current = await getMedia(record.key)
          if (!current || current.state === 'complete') return
          const interrupted = current.state === 'downloading'
          await updateMedia(record.key, (value) =>
            value?.generation === current.generation
              ? {
                  ...value,
                  state: interrupted ? 'paused' : value.state,
                  resumeOnOpen:
                    interrupted && value.resumeOnOpen !== false
                      ? true
                      : value.resumeOnOpen,
                  backgroundId: undefined,
                  backgroundBase: undefined
                }
              : value
          )
          if (
            sw.navigator.onLine &&
            (current.resumeOnOpen ||
              (interrupted && current.resumeOnOpen !== false))
          )
            resume.push(record.key)
        }
        if (sw.navigator.locks)
          await sw.navigator.locks.request(
            `watchparty-download:${record.key}`,
            recover
          )
        else await recover()
      }
      return { resume }
    }
    if (message.action === 'clear' || message.action === 'expire')
      return clearCache(
        account,
        message.action === 'expire',
        new Set(active.keys())
      )
    const key = message.key!,
      record = await getMedia(key)
    if (!record || record.owner !== account)
      throw new Error('Saved file not found')
    if (message.action === 'pin') {
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? { ...current, retention: 'download' }
          : current
      )
      event.waitUntil(startDownload(key))
      event.waitUntil(cachePoster(record))
      return
    }
    if (message.action === 'intent') {
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? {
              ...current,
              retention: 'download',
              resumeOnOpen: true,
              error: undefined
            }
          : current
      )
      return
    }
    if (message.action === 'background') {
      event.waitUntil(cacheCaptions(record))
      event.waitUntil(cachePoster(record))
      return
    }
    if (message.action === 'download') {
      event.waitUntil(startDownload(key))
      event.waitUntil(cachePoster(record))
      return
    }
    if (message.action === 'artwork') {
      await cachePoster(record)
      return
    }
    if (message.action === 'pause') {
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? { ...current, resumeOnOpen: false }
          : current
      )
      await abortBackground(sw.registration, record)
      downloads.get(key)?.abort()
      await running.get(key)
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? {
              ...current,
              state: (
                current.fileName
                  ? fileComplete(current)
                  : current.received === current.size
              )
                ? 'complete'
                : 'paused',
              resumeOnOpen: false
            }
          : current
      )
      return
    }
    if (message.action === 'cancel') {
      downloads.get(key)?.abort()
      await running.get(key)
      await cancelDownload(record)
      await abortBackground(sw.registration, record)
      return
    }
    if (message.action === 'remove') {
      downloads.get(key)?.abort()
      await removeMedia(key)
      await abortBackground(sw.registration, record)
      return
    }
  }
  event.waitUntil(
    run().then(
      (result) => event.ports[0]?.postMessage({ ok: true, ...result }),
      (error) =>
        event.ports[0]?.postMessage({
          error:
            error instanceof Error ? error.message : 'Storage action failed'
        })
    )
  )
})
// The browser dispatches these even after every app window has been closed.
for (const kind of [
  'backgroundfetchsuccess',
  'backgroundfetchfail',
  'backgroundfetchabort'
]) {
  sw.addEventListener(kind, (event) => {
    const backgroundEvent = event as ExtendableEvent & {
      registration: BackgroundJob
    }
    backgroundEvent.waitUntil(finishBackground(backgroundEvent.registration))
  })
}
sw.addEventListener('backgroundfetchclick', (event) => {
  const backgroundEvent = event as ExtendableEvent
  backgroundEvent.waitUntil(
    (async () => {
      const windows = await sw.clients.matchAll({ type: 'window' })
      const window = windows.find(
        (client) => new URL(client.url).pathname === '/saved'
      )
      if (window) await window.focus()
      else await sw.clients.openWindow('/saved')
    })()
  )
})
sw.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url)
  if (url.origin !== sw.location.origin) return
  if (url.pathname.startsWith('/__artwork/')) {
    event.respondWith(
      (async () => {
        const record = await getMedia(
          decodeURIComponent(url.pathname.slice('/__artwork/'.length))
        )
        if (!record?.artwork || record.owner !== (await owner()))
          return new Response(null, { status: 404 })
        return new Response(record.artwork, {
          headers: {
            'Content-Type': record.artwork.type,
            'Cache-Control': 'no-store'
          }
        })
      })()
    )
    return
  }
  if (url.pathname.startsWith('/__media/')) {
    const key = decodeURIComponent(
      url.pathname.slice('/__media/'.length).replace(/\.mp4$/, '')
    )
    event.respondWith(
      mediaResponse(event.request, key).catch(
        () => new Response('Local playback unavailable', { status: 503 })
      )
    )
    return
  }
  if (url.pathname.startsWith('/__subtitle/')) {
    event.respondWith(
      (async () => {
        const [key, index] = url.pathname
          .slice('/__subtitle/'.length)
          .split('/')
          .map(decodeURIComponent)
        const record = await getMedia(key)
        if (!record || record.owner !== (await owner()))
          return new Response(null, { status: 404 })
        const data = (
          await read<{ data: Blob }>('subtitles', [key, Number(index)])
        )?.data
        if (data)
          return new Response(data, { headers: { 'Content-Type': 'text/vtt' } })
        return fetch(
          `/api/library/items/${record.itemId}/subtitles/${index}/content?mediaSourceId=${record.sourceId}`,
          { credentials: 'include' }
        )
      })()
    )
    return
  }
  if (event.request.method !== 'GET') return
  // Only the app shell and public build assets. Never cache authenticated APIs,
  // Jellyfin media, LiveKit signaling or session responses in the shell cache.
  const shell = event.request.mode === 'navigate'
  const asset =
    url.pathname.startsWith('/assets/') ||
    url.pathname.startsWith('/fonts/') ||
    /^\/(icon.*|apple-touch-icon\.png|manifest\.webmanifest)$/.test(
      url.pathname
    )
  if (!shell && !asset) return
  event.respondWith(
    (async () => {
      const cache = await caches.open(SHELL)
      try {
        const response = await fetch(event.request)
        if (
          response.ok &&
          (asset || response.headers.get('content-type')?.includes('text/html'))
        )
          await cache.put(shell ? '/' : event.request, response.clone())
        return response
      } catch {
        return (
          (await cache.match(shell ? '/' : event.request)) ||
          new Response('Open Watchparty online once to save its app shell.', {
            status: 503
          })
        )
      }
    })()
  )
})
