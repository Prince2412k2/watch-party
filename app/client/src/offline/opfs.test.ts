import test from 'node:test'
import assert from 'node:assert/strict'
import 'fake-indexeddb/auto'
import {
  CHUNK_SIZE,
  cachedChunks,
  cancelDownload,
  chunk,
  clearCache,
  database,
  ensureDownloadFile,
  fileComplete,
  getMedia,
  prepare,
  putChunk,
  removeMedia,
  setOwner,
  storageError,
  transactionDone,
  updateMedia
} from './storage.ts'
import { availableChunk, reconcileFiles, saveFileChunk } from './files.ts'
import { DOWNLOAD_DIRECTORY, downloadFile, downloadName } from './opfs.ts'
import {
  finishBackground,
  startBackground,
  mediaRequest,
  type BackgroundJob,
  type BackgroundRegistration
} from './background.ts'

// A durable file mock: sync ranges publish immediately, asynchronous writers
// stage a replacement until close, matching the two actual browser APIs.
const files = new Map<string, Uint8Array<ArrayBuffer>>()
let directoryExists = false
let held: { name: string }[] = []
const missing = () => new DOMException('Missing file', 'NotFoundError')
function replace(bytes: Uint8Array, data: Uint8Array, at: number) {
  const next = new Uint8Array(Math.max(bytes.length, at + data.length))
  next.set(bytes)
  next.set(data, at)
  return next
}
const directory = {
  async getFileHandle(name: string, options?: { create?: boolean }) {
    if (!files.has(name)) {
      if (!options?.create) throw missing()
      files.set(name, new Uint8Array())
    }
    return {
      async getFile() {
        if (!files.has(name)) throw missing()
        return new File([files.get(name)!], name)
      },
      async createSyncAccessHandle() {
        return {
          write(bytes: Uint8Array, { at }: { at: number }) {
            files.set(name, replace(files.get(name)!, bytes, at))
            return bytes.length
          },
          flush() {},
          close() {}
        }
      },
      async createWritable() {
        let staged = files.get(name)!.slice()
        return {
          async write({ position, data }: { position: number; data: Blob }) {
            staged = replace(
              staged,
              new Uint8Array(await data.arrayBuffer()),
              position
            )
          },
          async close() {
            files.set(name, staged)
          },
          async abort() {}
        }
      }
    }
  },
  async removeEntry(name: string) {
    if (!files.delete(name)) throw missing()
  },
  async *entries() {
    for (const name of files.keys()) yield [name, { kind: 'file' }]
  }
}
Object.defineProperty(globalThis, 'navigator', {
  configurable: true,
  value: {
    storage: {
      async getDirectory() {
        return {
          async getDirectoryHandle(
            name: string,
            options?: { create?: boolean }
          ) {
            assert.equal(name, DOWNLOAD_DIRECTORY)
            if (!directoryExists && !options?.create) throw missing()
            directoryExists = true
            return directory
          }
        }
      }
    },
    locks: {
      async request(_name: string, run: () => Promise<unknown>) {
        return run()
      },
      async query() {
        return { held }
      }
    }
  }
})
const info = (id: string, account = 'alice') => ({
  owner: account,
  itemId: id,
  sourceId: 'source',
  revision: 'one',
  size: CHUNK_SIZE + 3,
  title: `Movie / ${id}`,
  series: '',
  duration: 120,
  audioIndex: 1,
  etag: '"one"',
  modified: '',
  subtitles: []
})

test('watched bytes migrate to one named MP4; sparse file length never marks holes complete', async () => {
  await setOwner('alice')
  const cached = await prepare(info('migration'), 'cache')
  const first = new Blob([new Uint8Array(CHUNK_SIZE).fill(5)]),
    last = new Blob(['end'])
  await putChunk(cached, 0, first)
  const pin = await ensureDownloadFile(
    await prepare(info('migration'), 'download')
  )
  assert.equal(await saveFileChunk(pin, 1, last), true)
  const sparse = (await getMedia(pin.key))!
  assert.equal((await downloadFile(sparse)).size, sparse.size)
  assert.equal(fileComplete(sparse), false)
  assert.equal((await availableChunk(sparse, 0))?.size, CHUNK_SIZE)
  assert.equal(
    await saveFileChunk(pin, 0, (await availableChunk(sparse, 0))!),
    true
  )
  const complete = (await getMedia(pin.key))!
  assert.equal(complete.received, complete.size)
  assert.equal(fileComplete(complete), true)
  assert.equal(complete.state, 'complete')
  assert.match(complete.fileName!, /^Movie _ migration--.*\.mp4$/)
  assert.deepEqual(await cachedChunks(pin.key), [])
  assert.equal(await (await availableChunk(complete, 1))?.text(), 'end')
  assert.equal((await downloadFile(complete)).size, CHUNK_SIZE + 3)
  await saveFileChunk(complete, 1, last)
  assert.equal((await getMedia(pin.key))?.received, pin.size)
  await clearCache('alice')
  assert.ok(await downloadFile(complete))
})

test('legacy full downloads stay incomplete until every cached range has moved', async () => {
  const legacy = await prepare(info('full-legacy'), 'download')
  await putChunk(legacy, 0, new Blob([new Uint8Array(CHUNK_SIZE)]))
  await putChunk(legacy, 1, new Blob(['end']))
  assert.equal((await getMedia(legacy.key))?.state, 'complete')
  const target = await ensureDownloadFile((await getMedia(legacy.key))!)
  assert.equal(target.state, 'paused')
  assert.equal(fileComplete(target), false)
  for (const index of [0, 1])
    await saveFileChunk(target, index, (await availableChunk(target, index))!)
  assert.equal(fileComplete((await getMedia(target.key))!), true)
  assert.deepEqual(await cachedChunks(target.key), [])
})

test('removal and cancellation delete OPFS bytes and reject late writes, while keeping playback cache', async () => {
  const old = await ensureDownloadFile(
    await prepare(info('removed-file'), 'download')
  )
  await saveFileChunk(old, 1, new Blob(['end']))
  await removeMedia(old.key)
  assert.equal(files.has(old.fileName!), false)
  assert.equal(
    await saveFileChunk(old, 0, new Blob([new Uint8Array(CHUNK_SIZE)])),
    false
  )
  const replacement = await ensureDownloadFile(
    await prepare(info('removed-file'), 'download')
  )
  assert.notEqual(replacement.fileName, old.fileName)
  assert.equal(await putChunk(old, 1, new Blob(['old']), true), false)
  const cancelled = await ensureDownloadFile(
    await prepare(info('cancelled-file'), 'download')
  )
  await saveFileChunk(cancelled, 1, new Blob(['end']))
  await putChunk(cancelled, 0, new Blob([new Uint8Array(CHUNK_SIZE)]))
  await cancelDownload((await getMedia(cancelled.key))!)
  const cache = (await getMedia(cancelled.key))!
  assert.equal(files.has(cancelled.fileName!), false)
  assert.equal(cache.retention, 'cache')
  assert.equal(cache.fileName, undefined)
  assert.equal(cache.received, CHUNK_SIZE)
  assert.equal((await chunk(cache.key, 0))?.size, CHUNK_SIZE)
})

test('reconciliation removes orphans, protects other accounts and active writers, repairs lost ranges', async () => {
  const orphan = `Orphan--${crypto.randomUUID()}.mp4`
  files.set(orphan, new Uint8Array([1]))
  files.set('unrelated.txt', new Uint8Array([1]))
  const bob = await ensureDownloadFile(
    await prepare(info('bob', 'bob'), 'download')
  )
  // Write his file directly; Alice's migration is forbidden from importing it.
  files.set(bob.fileName!, new Uint8Array([7]))
  assert.equal(await saveFileChunk(bob, 1, new Blob(['end'])), false)
  const truncated = await ensureDownloadFile(
    await prepare(info('truncated'), 'download')
  )
  await saveFileChunk(truncated, 0, new Blob([new Uint8Array(CHUNK_SIZE)]))
  await saveFileChunk(truncated, 1, new Blob(['end']))
  files.set(
    truncated.fileName!,
    files.get(truncated.fileName!)!.slice(0, CHUNK_SIZE)
  )
  held = [{ name: `watchparty-transfer:${truncated.generation}` }]
  await reconcileFiles()
  assert.equal(fileComplete((await getMedia(truncated.key))!), true)
  held = []
  await reconcileFiles()
  assert.equal(files.has(orphan), false)
  assert.equal(files.has('unrelated.txt'), true)
  assert.equal(files.has(bob.fileName!), true)
  const repaired = (await getMedia(truncated.key))!
  assert.deepEqual(repaired.fileChunks, [0])
  assert.equal(repaired.received, CHUNK_SIZE)
  assert.equal(repaired.state, 'paused')
  assert.match(repaired.error!, /missing or incomplete/)
  files.clear()
  directoryExists = false
  await reconcileFiles()
  assert.deepEqual((await getMedia(truncated.key))?.fileChunks, [])
  assert.equal((await getMedia(truncated.key))?.received, 0)
})

test('background completion publishes a durable MP4 and removes reused IDB bytes', async () => {
  const record = await ensureDownloadFile(
    await prepare(info('background-file'), 'download')
  )
  await putChunk(record, 0, new Blob([new Uint8Array(CHUNK_SIZE).fill(9)]))
  const id = `watchparty-media:${record.generation}:attempt:${encodeURIComponent(record.key)}`
  await updateMedia(
    record.key,
    (r) => r && { ...r, backgroundId: id, resumeOnOpen: true }
  )
  const job = {
    id,
    result: 'success',
    downloaded: 3,
    failureReason: '',
    recordsAvailable: true,
    abort: async () => true,
    matchAll: async () => [
      {
        request: mediaRequest(record, 1, 'https://test.invalid'),
        responseReady: Promise.resolve(
          new Response('end', {
            status: 206,
            headers: {
              'content-range': `bytes ${CHUNK_SIZE}-${CHUNK_SIZE + 2}/${record.size}`
            }
          })
        )
      }
    ]
  } as BackgroundJob
  await finishBackground(job)
  const current = (await getMedia(record.key))!
  assert.equal(fileComplete(current), true)
  assert.equal(current.state, 'complete')
  assert.deepEqual(await cachedChunks(current.key), [])
  assert.equal(
    await (await downloadFile(current)).slice(CHUNK_SIZE).text(),
    'end'
  )
})

test('transaction abort retains the request cause, and quota errors are actionable', async () => {
  const db = await database(),
    tx = db.transaction('settings', 'readwrite'),
    done = transactionDone(tx)
  tx.objectStore('settings').add('first', 'duplicate')
  tx.objectStore('settings').add('second', 'duplicate')
  await assert.rejects(done, {
    name: 'ConstraintError',
    message: /ConstraintError/
  })
  assert.match(
    storageError(new DOMException('Full', 'QuotaExceededError')).message,
    /Storage is full.*Remove/
  )
  const episode = {
    ...(await prepare(info('episode-name'), 'download')),
    series: 'The Show',
    season: 2,
    episode: 3
  }
  assert.match(downloadName(episode), /^The Show S2 E3 Movie _ episode-name/)
  assert.ok(
    new TextEncoder().encode(
      downloadName({ ...episode, series: '', title: '🎬'.repeat(100) })
    ).length <= 255
  )
  await assert.rejects(
    updateMedia(episode.key, () => {
      throw new DOMException('Expired', 'TransactionInactiveError')
    }),
    { name: 'TransactionInactiveError', message: /expired/ }
  )
})

test('background resume omits durable OPFS ranges without requiring duplicate cached bytes', async () => {
  const record = await ensureDownloadFile(
    await prepare(info('background-resume-file'), 'download')
  )
  await saveFileChunk(record, 0, new Blob([new Uint8Array(CHUNK_SIZE)]))
  await updateMedia(record.key, (r) => r && { ...r, resumeOnOpen: true })
  let requests: Request[] = []
  const registration = {
    backgroundFetch: {
      get: async () => undefined,
      fetch: async (id: string, parts: Request[]) => {
        requests = parts
        return { id, abort: async () => true }
      }
    }
  } as unknown as BackgroundRegistration
  assert.equal(
    await startBackground(
      registration,
      (await getMedia(record.key))!,
      'https://test.invalid'
    ),
    true
  )
  assert.equal(requests.length, 1)
  assert.equal(
    requests[0].headers.get('range'),
    `bytes=${CHUNK_SIZE}-${CHUNK_SIZE + 2}`
  )
  assert.deepEqual(await cachedChunks(record.key), [])
})
