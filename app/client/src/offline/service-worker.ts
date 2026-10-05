/// <reference lib="webworker" />
import {
  CHUNK_SIZE,
  chunk,
  clearCache,
  getMedia,
  listMedia,
  owner,
  putChunk,
  putSubtitle,
  read,
  removeMedia,
  updateMedia,
  type SavedMedia
} from './storage.ts'
import { byteRange, validateChunk } from './ranges.ts'
const sw = self as unknown as ServiceWorkerGlobalScope
const inflight = new Map<string, Promise<Blob>>()
const downloads = new Map<string, AbortController>()
const running = new Map<string, Promise<void>>()
const active = new Map<string, number>()
const SHELL = 'watchparty-shell-v1'
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
  const stored = await chunk(record.key, index)
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
    const params = new URLSearchParams({
      source: record.sourceId,
      revision: record.revision
    })
    const response = await fetch(
      `/api/offline/${record.itemId}/media?${params}`,
      {
        credentials: 'include',
        headers: { Range: `bytes=${start}-${end}` },
        signal
      }
    )
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
            error: 'Storage full; playback continues without saving new chunks.'
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
          error: undefined,
          subtitleError: undefined
        }
      : current
  )
  try {
    // Download captions first so an interrupted media transfer can still use them.
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
    for (let index = 0; index < Math.ceil(record.size / CHUNK_SIZE); index++) {
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
    }
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
  let offset = range.start,
    cancelled = false
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        if (cancelled) return
        if (offset > range.end) {
          controller.close()
          release()
          return
        }
        const index = Math.floor(offset / CHUNK_SIZE)
        const data = await loadChunk(record, index)
        if (cancelled) return
        const stop = Math.min(range.end + 1, (index + 1) * CHUNK_SIZE)
        controller.enqueue(
          new Uint8Array(
            await data
              .slice(offset - index * CHUNK_SIZE, stop - index * CHUNK_SIZE)
              .arrayBuffer()
          )
        )
        offset = stop
      } catch (error) {
        controller.error(error)
        release()
      }
    },
    cancel() {
      cancelled = true
      release()
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
      // A terminated worker cannot resume automatically; keep the user's download intent.
      const account = await owner()
      if (account) {
        for (const record of await listMedia(account))
          if (record.state === 'downloading')
            await updateMedia(
              record.key,
              (current) => current && { ...current, state: 'paused' }
            )
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
      for (const record of await listMedia(account))
        if (record.state === 'downloading' && !running.has(record.key))
          await updateMedia(
            record.key,
            (current) => current && { ...current, state: 'paused' }
          )
      return
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
      await updateMedia(
        key,
        (current) => current && { ...current, retention: 'download' }
      )
      event.waitUntil(startDownload(key))
      return
    }
    if (message.action === 'download') {
      event.waitUntil(startDownload(key))
      return
    }
    if (message.action === 'pause') {
      downloads.get(key)?.abort()
      await running.get(key)
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? {
              ...current,
              state: current.received === current.size ? 'complete' : 'paused'
            }
          : current
      )
      return
    }
    if (message.action === 'cancel') {
      downloads.get(key)?.abort()
      await running.get(key)
      await updateMedia(key, (current) =>
        current?.generation === record.generation
          ? {
              ...current,
              retention: 'cache',
              state: current.received === current.size ? 'complete' : 'paused'
            }
          : current
      )
      return
    }
    if (message.action === 'remove') {
      downloads.get(key)?.abort()
      await removeMedia(key)
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
sw.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url)
  if (url.origin !== sw.location.origin) return
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
