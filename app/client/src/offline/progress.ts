export const PROGRESS_CHANNEL = 'watchparty-download-progress-v1'
export interface DownloadProgress {
  key: string
  generation: string
  run: string
  bytes: number
  transferred: number
  active: boolean
}
/** Rolling network throughput; storage commits and reused bytes are not speed. */
export class DownloadRate {
  private samples: { at: number; bytes: number }[] = []
  private run = ''
  update(run: string, bytes: number, now: number) {
    if (
      run !== this.run ||
      bytes < (this.samples[this.samples.length - 1]?.bytes ?? 0)
    ) {
      this.run = run
      this.samples = []
    }
    this.samples.push({ at: now, bytes })
    while (this.samples.length > 2 && this.samples[1].at <= now - 2000)
      this.samples.shift()
    const first = this.samples[0]
    return now > first.at
      ? ((bytes - first.bytes) * 8000) / (now - first.at) / 1_000_000
      : 0
  }
}
export async function readDownload(
  response: Response,
  signal: AbortSignal,
  onBytes: (count: number) => void,
  expectedBytes?: number
) {
  if (!response.body) throw new Error('Empty media response')
  const reader = response.body.getReader()
  const parts: Uint8Array<ArrayBuffer>[] = []
  let received = 0
  try {
    while (true) {
      signal.throwIfAborted()
      const { done, value } = await reader.read()
      if (done) break
      received += value.length
      if (expectedBytes != null && received > expectedBytes)
        throw new Error('Invalid media chunk length')
      parts.push(value)
      onBytes(value.length)
    }
    if (expectedBytes != null && received !== expectedBytes)
      throw new Error('Incomplete media chunk')
    return new Blob(parts)
  } finally {
    await reader.cancel().catch(() => {})
    reader.releaseLock()
  }
}
