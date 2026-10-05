/** Keep a small window of chunks in flight. Stop scheduling on pause/failure,
 * and drain existing work before reporting that a download stopped. */
export async function runChunkQueue(
  count: number,
  consume: (index: number) => Promise<void>,
  signal: AbortSignal,
  concurrency = 3
) {
  let next = 0,
    failed = false,
    failure: unknown
  const worker = async () => {
    while (!failed && !signal.aborted && next < count) {
      const index = next++
      try {
        await consume(index)
      } catch (error) {
        if (!failed) {
          failed = true
          failure = error
        }
      }
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(count, concurrency) }, worker)
  )
  if (failed) throw failure
  if (signal.aborted) throw new DOMException('Paused', 'AbortError')
}
