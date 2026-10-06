import {
  CHUNK_SIZE,
  allMedia,
  cachedChunks,
  chunk,
  chunkBytes,
  ensureDownloadFile,
  fileComplete,
  getMedia,
  owner,
  putChunk,
  updateMedia,
  type SavedMedia
} from './storage.ts'
import {
  downloadDirectory,
  downloadFile,
  OPFS_SUPPORTED,
  removeDownloadFile,
  writeFileChunk,
  fileLock,
  withFileLock
} from './opfs.ts'
export async function availableChunk(record: SavedMedia, index: number) {
  const current = await getMedia(record.key)
  if (current?.generation !== record.generation) return undefined
  if (current.fileName && current.fileChunks?.includes(index)) {
    try {
      const data = await withFileLock(current.generation, async () => {
        const file = await downloadFile(current)
        const range = file.slice(
          index * CHUNK_SIZE,
          Math.min(record.size, (index + 1) * CHUNK_SIZE)
        )
        // File snapshots can become unreadable after another range is written.
        // Materialize only this bounded range while the writer is excluded.
        return range.size === chunkBytes(record, index)
          ? new Blob([await range.arrayBuffer()])
          : undefined
      })
      if (data) return data
    } catch (error) {
      if (!(
        error instanceof DOMException &&
        ['NotFoundError', 'NoModificationAllowedError'].includes(error.name)
      ))
        throw error
    }
  }
  return chunk(record.key, index)
}
export async function saveFileChunk(
  record: SavedMedia,
  index: number,
  data: Blob
) {
  if (data.size !== chunkBytes(record, index))
    throw new Error('Incomplete media chunk')
  const current = await getMedia(record.key)
  if (
    current?.generation !== record.generation ||
    current.retention !== 'download' ||
    (await owner()) !== record.owner
  )
    return false
  const target = await ensureDownloadFile(current)
  await writeFileChunk(target, index, data, CHUNK_SIZE)
  const saved = await putChunk(target, index, data, true)
  if (!saved) {
    const latest = await getMedia(record.key)
    if (latest?.fileName !== target.fileName) await removeDownloadFile(target)
  }
  return saved
}
export async function reconcileFiles() {
  if (!OPFS_SUPPORTED()) return
  const records = await allMedia(),
    referenced = new Set(
      records.map((record) => record.fileName).filter(Boolean)
    )
  let directory: FileSystemDirectoryHandle | undefined
  try {
    directory = await downloadDirectory()
  } catch (error) {
    if (!(error instanceof DOMException && error.name === 'NotFoundError'))
      throw error
  }
  if (directory)
    for await (const [name, entry] of directory.entries()) {
      if (
        entry.kind === 'file' &&
        name.endsWith('.mp4') &&
        !referenced.has(name)
      ) {
        // Metadata reserves the generation's name before creating a file. Repeat
        // the lookup to protect a transfer that started during this inventory.
        const generation = /--([0-9a-f-]{36})\.mp4$/.exec(name)?.[1]
        if (generation)
          await withFileLock(generation, async () => {
            if (!(await allMedia()).some((record) => record.fileName === name))
              await directory!.removeEntry(name)
          })
      }
    }
  const held = (await navigator.locks?.query())?.held ?? []
  for (const record of records) {
    if (
      !record.fileName ||
      held.some((lock) =>
        [
          fileLock(record.generation),
          `watchparty-transfer:${record.generation}`
        ].includes(lock.name ?? '')
      )
    )
      continue
    let length = 0
    try {
      length = (await downloadFile(record)).size
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'NotFoundError'))
        throw error
    }
    const indexes = (record.fileChunks ?? []).filter(
      (index) =>
        index >= 0 &&
        Number.isInteger(index) &&
        index < Math.ceil(record.size / CHUNK_SIZE) &&
        Math.min(record.size, (index + 1) * CHUNK_SIZE) <= length
    )
    if (
      indexes.length === record.fileChunks?.length &&
      (!fileComplete(record) || length === record.size)
    )
      continue
    const cached = await cachedChunks(record.key)
    await updateMedia(record.key, (current) =>
      current?.generation === record.generation &&
      current.fileName === record.fileName &&
      (current.fileChunks ?? []).join(',') ===
        (record.fileChunks ?? []).join(',')
        ? {
            ...current,
            fileChunks: indexes,
            received:
              indexes.reduce((n, index) => n + chunkBytes(record, index), 0) +
              cached
                .filter((c) => !indexes.includes(c.index))
                .reduce((n, c) => n + c.size, 0),
            state: 'paused',
            error:
              'Downloaded file is missing or incomplete. Resume to restore it.'
          }
        : current
    )
  }
}
