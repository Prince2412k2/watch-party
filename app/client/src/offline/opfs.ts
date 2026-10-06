import type { SavedMedia } from './storage.ts'
export const DOWNLOAD_DIRECTORY = 'watchparty-downloads-v1'
export const OPFS_SUPPORTED = () =>
  typeof navigator !== 'undefined' &&
  typeof navigator.storage?.getDirectory === 'function'
export const fileLock = (generation: string) => `watchparty-file:${generation}`
export const transferLock = (generation: string) =>
  `watchparty-transfer:${generation}`
export function downloadName(record: SavedMedia) {
  const title = record.series
    ? `${record.series} S${record.season ?? 0} E${record.episode ?? 0} ${record.title}`
    : record.title
  // Fifty Unicode characters plus the UUID fit within a 255-byte file name,
  // including titles written with four-byte characters.
  const stem =
    Array.from(
      title.normalize('NFC').replace(/[\u0000-\u001f/\\:*?"<>|]/g, '_')
    )
      .slice(0, 50)
      .join('')
      .trim() || 'Movie'
  return `${stem}--${record.generation}.mp4`
}
export async function downloadDirectory(create = false) {
  if (!OPFS_SUPPORTED())
    throw new Error(
      'This browser does not support local movie files. Update your browser and retry.'
    )
  const root = await navigator.storage.getDirectory()
  return root.getDirectoryHandle(DOWNLOAD_DIRECTORY, { create })
}
export async function downloadFile(record: Pick<SavedMedia, 'fileName'>) {
  if (
    !record.fileName ||
    record.fileName.includes('/') ||
    record.fileName.includes('\\')
  )
    throw new Error('Invalid downloaded file name')
  return (
    await (await downloadDirectory()).getFileHandle(record.fileName)
  ).getFile()
}
export async function withFileLock<T>(
  generation: string,
  run: () => Promise<T>
) {
  return navigator.locks
    ? navigator.locks.request(fileLock(generation), run)
    : run()
}
export async function removeDownloadFile(
  record: Pick<SavedMedia, 'fileName' | 'generation'>
) {
  if (!record.fileName || !OPFS_SUPPORTED()) return
  await withFileLock(record.generation, async () => {
    try {
      await (await downloadDirectory()).removeEntry(record.fileName!)
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'NotFoundError'))
        throw error
    }
  })
}
interface SyncHandle {
  write(buffer: ArrayBufferView, options: { at: number }): number
  flush(): void
  close(): void
}
export async function writeFileChunk(
  record: SavedMedia,
  index: number,
  data: Blob,
  chunkSize: number
) {
  const bytes = new Uint8Array(await data.arrayBuffer())
  await withFileLock(record.generation, async () => {
    const file = await (
      await downloadDirectory(true)
    ).getFileHandle(record.fileName!, { create: true })
    // Only dedicated workers expose sync access. Close after each durable range
    // so readers, other tabs, deletion and background imports can acquire it.
    const handle = await (
      file as FileSystemFileHandle & {
        createSyncAccessHandle(): Promise<SyncHandle>
      }
    ).createSyncAccessHandle()
    try {
      let written = 0
      while (written < bytes.length) {
        const count = handle.write(bytes.subarray(written), {
          at: index * chunkSize + written
        })
        if (!count) throw new Error('Could not write the downloaded file')
        written += count
      }
      handle.flush()
    } finally {
      handle.close()
    }
  })
}
