import { validateChunk } from './ranges.ts'

/** Stream requested bytes immediately, retaining at most one storage chunk.
 * A cancelled seek aborts its own fetch; it cannot cancel another reader. */
export async function* streamMediaRange(options: {
  start: number
  end: number
  size: number
  chunkSize: number
  signal: AbortSignal
  stored: (index: number) => Promise<Blob | undefined>
  fetchChunk: (index: number, signal: AbortSignal) => Promise<Response>
  save: (index: number, data: Blob) => Promise<void>
}) {
  const { end, size, chunkSize, signal } = options
  let offset = options.start
  while (offset <= end) {
    signal.throwIfAborted()
    const index = Math.floor(offset / chunkSize)
    const start = index * chunkSize
    const stop = Math.min(size, start + chunkSize)
    const stored = await options.stored(index)
    signal.throwIfAborted()
    if (stored) {
      const limit = Math.min(stop, end + 1)
      yield new Uint8Array(
        await stored.slice(offset - start, limit - start).arrayBuffer()
      )
      offset = limit
      continue
    }
    const response = await options.fetchChunk(index, signal)
    validateChunk(response, start, stop - 1, size)
    if (!response.body) throw new Error('Empty media response')
    const reader = response.body.getReader()
    const parts: Uint8Array<ArrayBuffer>[] = []
    let received = 0
    try {
      while (true) {
        signal.throwIfAborted()
        const { done, value } = await reader.read()
        if (done) break
        if (received + value.length > stop - start)
          throw new Error('Invalid media chunk length')
        parts.push(value)
        const first = Math.max(0, offset - start - received)
        const last = Math.min(value.length, end + 1 - start - received)
        received += value.length
        if (last > first) {
          offset += last - first
          yield value.subarray(first, last)
        }
        // Safari probes just two bytes initially. Do not download the rest of
        // a 2 MiB chunk before finishing that probe (or a suffix-only request).
        if (offset > end && received < stop - start) return
      }
      if (received !== stop - start) throw new Error('Incomplete media chunk')
      signal.throwIfAborted()
      await options.save(index, new Blob(parts))
    } finally {
      await reader.cancel().catch(() => {})
      reader.releaseLock()
    }
  }
}
