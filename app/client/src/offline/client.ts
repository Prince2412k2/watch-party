import workerUrl from './service-worker.ts?worker&url'
import {
  CHUNK_SIZE,
  getMedia,
  listMedia,
  mediaKey,
  prepare,
  setOwner,
  type MediaInfo,
  type SavedMedia
} from './storage.ts'
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
  await ready()
  return new Promise<{ skipped?: number }>((resolve, reject) => {
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
  })
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
    ...performance
      .getEntriesByType('resource')
      .map((e) => e.name)
      .filter((u) => u.includes('/assets/') || u.includes('/fonts/'))
  ]
  await command('shell', undefined, [...new Set(urls)])
}
export async function initializeOffline(account: string) {
  if (!OFFLINE_SUPPORTED) return
  await setOwner(account)
  await ready()
  await command('recover')
  await command('expire')
}
export { getMedia, listMedia, setOwner }
export type { SavedMedia }
