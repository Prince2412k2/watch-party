import { test } from 'node:test'
import assert from 'node:assert/strict'
import { streamMediaRange } from './mediaStream.ts'
import { DownloadRate, readDownload } from './progress.ts'

const response = (
  body: ReadableStream<Uint8Array>,
  start = 0,
  end = 7,
  size = 8
) =>
  new Response(body, {
    status: 206,
    headers: { 'Content-Range': `bytes ${start}-${end}/${size}` }
  })
test('missing ranges stream before a storage chunk completes, then cache identical bytes', async () => {
  let source!: ReadableStreamDefaultController<Uint8Array>
  let saved: Blob | undefined
  const network = new ReadableStream<Uint8Array>({
    start(c) {
      source = c
    }
  })
  const stream = streamMediaRange({
    start: 0,
    end: 7,
    size: 8,
    chunkSize: 8,
    signal: new AbortController().signal,
    stored: async () => undefined,
    fetchChunk: async () => response(network),
    save: async (_, blob) => {
      saved = blob
    }
  })
  const first = stream.next()
  source.enqueue(Uint8Array.of(0, 1))
  assert.deepEqual((await first).value, Uint8Array.of(0, 1))
  assert.equal(saved, undefined)
  source.enqueue(Uint8Array.of(2, 3, 4, 5, 6, 7))
  source.close()
  assert.deepEqual((await stream.next()).value, Uint8Array.of(2, 3, 4, 5, 6, 7))
  assert.equal((await stream.next()).done, true)
  assert.deepEqual(
    new Uint8Array(await saved!.arrayBuffer()),
    Uint8Array.of(0, 1, 2, 3, 4, 5, 6, 7)
  )
})
test('Safari two-byte probes finish and cancel without waiting for a whole chunk', async () => {
  let cancelled = false
  const network = new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(Uint8Array.of(0, 1))
    },
    cancel() {
      cancelled = true
    }
  })
  const stream = streamMediaRange({
    start: 0,
    end: 1,
    size: 8,
    chunkSize: 8,
    signal: new AbortController().signal,
    stored: async () => undefined,
    fetchChunk: async () => response(network),
    save: async () => assert.fail('partial range cached')
  })
  assert.deepEqual((await stream.next()).value, Uint8Array.of(0, 1))
  assert.equal((await stream.next()).done, true)
  assert.equal(cancelled, true)
})
test('seek across cached and missing ranges returns exact requested bytes', async () => {
  const requested: number[] = [],
    saved: number[] = []
  const stream = streamMediaRange({
    start: 2,
    end: 12,
    size: 16,
    chunkSize: 4,
    signal: new AbortController().signal,
    stored: async (index) =>
      index % 2 === 0
        ? new Blob([Uint8Array.from({ length: 4 }, (_, n) => index * 4 + n)])
        : undefined,
    fetchChunk: async (index) => {
      requested.push(index)
      return response(
        new ReadableStream({
          start(c) {
            c.enqueue(Uint8Array.from({ length: 4 }, (_, n) => index * 4 + n))
            c.close()
          }
        }),
        index * 4,
        index * 4 + 3,
        16
      )
    },
    save: async (index) => {
      saved.push(index)
    }
  })
  const actual: number[] = []
  for await (const bytes of stream) actual.push(...bytes)
  assert.deepEqual(
    actual,
    Array.from({ length: 11 }, (_, i) => i + 2)
  )
  assert.deepEqual(requested, [1, 3])
  assert.deepEqual(saved, [1, 3])
})
test('truncated or wrong revision ranges are never committed as complete', async () => {
  for (const wrongRange of [false, true]) {
    const stream = streamMediaRange({
      start: 0,
      end: 7,
      size: 8,
      chunkSize: 8,
      signal: new AbortController().signal,
      stored: async () => undefined,
      fetchChunk: async () =>
        response(
          new ReadableStream({
            start(c) {
              c.enqueue(Uint8Array.of(1, 2))
              c.close()
            }
          }),
          wrongRange ? 2 : 0
        ),
      save: async () => assert.fail('invalid range cached')
    })
    await assert.rejects(async () => {
      for await (const _ of stream) {
        /* consume */
      }
    })
  }
})
test('aborting an abandoned seek cancels its upstream without affecting a new seek', async () => {
  const abort = new AbortController()
  const stream = streamMediaRange({
    start: 0,
    end: 7,
    size: 8,
    chunkSize: 8,
    signal: abort.signal,
    stored: async () => undefined,
    fetchChunk: async (_, signal) =>
      response(
        new ReadableStream({
          start(c) {
            c.enqueue(Uint8Array.of(0, 1))
            signal.addEventListener('abort', () => c.error(signal.reason), {
              once: true
            })
          }
        })
      ),
    save: async () => assert.fail('aborted range cached')
  })
  await stream.next()
  const pending = stream.next()
  abort.abort()
  await assert.rejects(pending, { name: 'AbortError' })
})
test('download byte reports precede commit and speed ignores resume baselines', async () => {
  let source!: ReadableStreamDefaultController<Uint8Array>
  let bytes = 0
  const task = readDownload(
    new Response(
      new ReadableStream({
        start(c) {
          source = c
        }
      })
    ),
    new AbortController().signal,
    (count) => {
      bytes += count
    }
  )
  source.enqueue(Uint8Array.of(1, 2, 3))
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(bytes, 3)
  source.enqueue(Uint8Array.of(4))
  source.close()
  assert.equal((await task).size, 4)
  const rate = new DownloadRate()
  assert.equal(rate.update('one', 10_000_000, 0), 0)
  assert.equal(rate.update('one', 11_000_000, 1000), 8)
  assert.equal(rate.update('two', 0, 1100), 0)
  assert.equal(rate.update('two', 1_000_000, 2100), 8)
  rate.update('two', 1_000_000, 4100)
  assert.equal(rate.update('two', 1_000_000, 5100), 0)
})
