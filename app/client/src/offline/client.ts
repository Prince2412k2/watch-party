import { startBackground } from './background.ts'
import workerUrl from './service-worker.ts?worker&url'
import downloadWorkerUrl from './download-worker.ts?worker&url'
import { downloadFile, OPFS_SUPPORTED, transferLock } from './opfs.ts'
import {
  CHUNK_SIZE,
  ensureDownloadFile,
  fileComplete,
  owner,
  getMedia,
  listMedia,
  mediaKey,
  prepare,
  setOwner,
  type MediaInfo,
  type SavedMedia
} from './storage.ts'
let fileWorker: Worker | undefined
const recoveries = new Map<string, Promise<void>>()
async function fileCommand(action: string, key?: string) {
  fileWorker ??= new Worker(downloadWorkerUrl, { type: 'module' })
  const target = fileWorker
  return new Promise<void>((resolve, reject) => {
    const channel = new MessageChannel()
    const stop = () => {
      clearTimeout(timer)
      channel.port1.close()
      target.removeEventListener('error', failed)
    }
    const failed = () => {
      stop()
      target.terminate()
      if (fileWorker === target) fileWorker = undefined
      reject(new Error('The file writer stopped. Reopen the app to resume.'))
    }
    const timer = setTimeout(() => {
      stop()
      reject(new Error('The file writer did not respond. Reload and retry.'))
    }, 30000)
    target.addEventListener('error', failed)
    channel.port1.onmessage = (event) => {
      stop()
      event.data.error ? reject(new Error(event.data.error)) : resolve()
    }
    target.postMessage({ action, key }, [channel.port2])
  })
}
let initialized: Promise<ServiceWorkerRegistration> | undefined
export const OFFLINE_SUPPORTED =
  typeof navigator !== 'undefined' &&
  'serviceWorker' in navigator &&
  typeof indexedDB !== 'undefined' &&
  window.isSecureContext
export async function ready() {
  if (!OFFLINE_SUPPORTED)
    throw new Error(
      'Local downloads require HTTPS and browser storage support.'
    )
  initialized ??=
    navigator.serviceWorker.controller && !navigator.onLine
      ? navigator.serviceWorker.getRegistration('/').then((registration) => {
          if (!registration) throw new Error('Open the app online once first.')
          return registration
        })
      : navigator.serviceWorker.register(workerUrl, {
          scope: '/',
          type: 'module',
          updateViaCache: 'none'
        })
  const registration = await initialized.catch((error) => {
    initialized = undefined
    throw error
  })
  // Wait for this build's worker before sending its command protocol. An older
  // controller may still be active briefly while an update installs.
  const installing = registration.installing
  if (installing)
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        installing.removeEventListener('statechange', changed)
        reject(new Error('Download support is updating. Reload and retry.'))
      }, 10000)
      const changed = () => {
        if (
          installing.state === 'activated' ||
          installing.state === 'redundant'
        ) {
          clearTimeout(timeout)
          installing.removeEventListener('statechange', changed)
          installing.state === 'activated'
            ? resolve()
            : reject(
                new Error(
                  'Could not update download support. Reload and retry.'
                )
              )
        }
      }
      installing.addEventListener('statechange', changed)
      changed()
    })
  await navigator.serviceWorker.ready
  if (!navigator.serviceWorker.controller)
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        navigator.serviceWorker.removeEventListener('controllerchange', change)
        reject(new Error('Reload once to enable local playback.'))
      }, 10000)
      const change = () => {
        clearTimeout(timeout)
        navigator.serviceWorker.removeEventListener('controllerchange', change)
        resolve()
      }
      navigator.serviceWorker.addEventListener('controllerchange', change)
    })
  return registration
}
export async function command(action: string, key?: string, urls?: string[]) {
  const registration = await ready()
  const run = async () => {
    if (
      (action === 'download' || action === 'pin' || action === 'resume') &&
      key
    ) {
      if (action === 'resume') {
        const current = await getMedia(key)
        if (
          !current ||
          current.resumeOnOpen !== true ||
          current.retention !== 'download' ||
          current.state === 'complete'
        )
          return {}
      }
      if (!OPFS_SUPPORTED())
        throw new Error(
          'Local movie files require OPFS support. Update your browser and retry.'
        )
      await workerCommand('intent', key)
      const original = await getMedia(key)
      const record = original ? await ensureDownloadFile(original) : undefined
      // Chromium requires creation in a window; the worker receives the completed
      // transfer even after that window is closed. Unsupported browsers use the queue.
      if (
        record &&
        (await startBackground(registration, record, location.origin))
      )
        return workerCommand('background', key)
      await workerCommand('background', key)
      await fileCommand('download', key)
      return {}
    }
    if (key && ['pause', 'cancel', 'remove'].includes(action)) {
      const record = await getMedia(key)
      // Mark the pause for every tab before draining this window's worker.
      await workerCommand('pause', key)
      await fileCommand('pause', key)
      if (record && navigator.locks)
        await navigator.locks.request(
          transferLock(record.generation),
          async () => {}
        )
      if (action === 'pause') return {}
    }
    return workerCommand(action, key, urls)
  }
  return key && navigator.locks
    ? navigator.locks.request(`watchparty-download:${key}`, run)
    : run()
}

async function workerCommand(action: string, key?: string, urls?: string[]) {
  await ready()
  return new Promise<{ skipped?: number; resume?: string[] }>(
    (resolve, reject) => {
      const channel = new MessageChannel()
      const timeout = setTimeout(() => {
        channel.port1.close()
        reject(new Error('Storage did not respond. Reload and retry.'))
      }, 30000)
      channel.port1.onmessage = (event) => {
        clearTimeout(timeout)
        channel.port1.close()
        event.data.error
          ? reject(new Error(event.data.error))
          : resolve(event.data)
      }
      navigator.serviceWorker.controller!.postMessage({ action, key, urls }, [
        channel.port2
      ])
    }
  )
}
export async function infoFor(
  itemId: string,
  sourceId?: string | null
): Promise<MediaInfo> {
  const query = sourceId ? `?source=${encodeURIComponent(sourceId)}` : ''
  const response = await fetch(
    `/api/offline/${encodeURIComponent(itemId)}/info${query}`,
    { credentials: 'include' }
  )
  const value = (await response.json()) as MediaInfo & { error?: string }
  if (!response.ok) throw new Error(value.error || 'Could not load media')
  if (
    typeof value.owner !== 'string' ||
    typeof value.sourceId !== 'string' ||
    typeof value.revision !== 'string' ||
    !Number.isSafeInteger(value.size) ||
    value.size <= 0
  )
    throw new Error('Invalid media metadata')
  return value
}
export const localUrl = (record: SavedMedia) =>
  `/__media/${encodeURIComponent(record.key)}.mp4`
export async function playbackSource(record: SavedMedia) {
  const current = await getMedia(record.key)
  if (!current || current.owner !== (await owner()))
    throw new Error('Saved movie not found')
  if (fileComplete(current)) {
    try {
      const file = await downloadFile(current)
      if (file.size === current.size) {
        const url = URL.createObjectURL(file)
        return { url, release: () => URL.revokeObjectURL(url) }
      }
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'NotFoundError'))
        throw error
    }
  }
  return { url: localUrl(current), release: () => {} }
}
export const localSubtitles = (record: SavedMedia) =>
  record.subtitles.map((s) => ({
    ...s,
    isExternal: true,
    deliveryUrl: `/__subtitle/${encodeURIComponent(record.key)}/${s.index}`
  }))
export async function cachePlayback(info: MediaInfo) {
  await ready()
  const record = await prepare(info, 'cache')
  return record
}
export async function saveMovie(
  itemId: string,
  account: string,
  sourceId?: string | null
) {
  await ready()
  await setOwner(account)
  const info = await infoFor(itemId, sourceId)
  if (info.owner !== account)
    throw new Error('Account changed. Reload and retry.')
  await navigator.storage?.persist?.().catch(() => false)
  const estimate = await navigator.storage?.estimate?.()
  const existing = await getMedia(mediaKey(info))
  const needed = info.size - (existing?.received ?? 0)
  if (
    estimate?.quota &&
    estimate.usage != null &&
    needed + CHUNK_SIZE > estimate.quota - estimate.usage
  )
    throw new Error(
      'Not enough browser storage. Remove saved movies or clear cache first.'
    )
  // Intent is stored before any byte transfer. Completed caches can be promoted.
  const record = await prepare(info, 'download')
  await command('download', record.key)
  await cacheShell()
  return record
}
export async function cacheShell() {
  // Include lazy offline routes and the player before they are needed offline.
  await Promise.all([
    import('../pages/SavedMovies.tsx'),
    import('../pages/SavedWatch.tsx')
  ])
  const urls = [
    '/',
    '/manifest.webmanifest',
    downloadWorkerUrl,
    workerUrl,
    ...performance
      .getEntriesByType('resource')
      .map((e) => e.name)
      .filter((u) => u.includes('/assets/') || u.includes('/fonts/'))
  ]
  await command('shell', undefined, [...new Set(urls)])
}
export async function initializeOffline(account: string) {
  if (!OFFLINE_SUPPORTED) return
  const pending = recoveries.get(account)
  if (pending) return pending
  const task = (async () => {
    await setOwner(account)
    await ready()
    if (OPFS_SUPPORTED()) await fileCommand('reconcile')
    const { resume } = await command('recover')
    for (const key of resume ?? []) await command('resume', key)
    // Existing IDB downloads migrate offline, one bounded range at a time.
    if (OPFS_SUPPORTED())
      for (const file of await listMedia(account))
        if (
          file.retention === 'download' &&
          !fileComplete(file) &&
          !file.backgroundId
        )
          await fileCommand('migrate', file.key)
    await command('expire')
  })().finally(() => recoveries.delete(account))
  recoveries.set(account, task)
  return task
}
export { getMedia, listMedia, setOwner }
export type { SavedMedia }
