export function byteRange(
  header: string | null,
  size: number
): { start: number; end: number } | null {
  if (!header) return { start: 0, end: size - 1 }
  const match = /^bytes=(\d*)-(\d*)$/.exec(header)
  if (!match || (!match[1] && !match[2])) return null
  let start: number, end: number
  if (!match[1]) {
    const suffix = Number(match[2])
    if (!Number.isSafeInteger(suffix) || suffix <= 0) return null
    start = Math.max(0, size - suffix)
    end = size - 1
  } else {
    start = Number(match[1])
    end = match[2] ? Math.min(size - 1, Number(match[2])) : size - 1
  }
  return Number.isSafeInteger(start) &&
    Number.isSafeInteger(end) &&
    start >= 0 &&
    start < size &&
    end >= start
    ? { start, end }
    : null
}
export function validateChunk(
  response: Response,
  start: number,
  end: number,
  size: number
) {
  if (
    response.status !== 206 ||
    response.headers.get('content-range') !== `bytes ${start}-${end}/${size}`
  )
    throw new Error(
      'The file changed or the server did not return the requested range'
    )
}
