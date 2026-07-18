export interface SubtitleHlsTrack { url: string }
export interface SubtitleStream { index: number }

export function jellyfinStreamIndex(url: string, param: string, base = 'http://localhost'): number | null {
  try {
    const value = new URL(url, base).searchParams.get(param)
    return value != null && value !== '' && Number.isFinite(Number(value)) ? Number(value) : null
  } catch { return null }
}

export function hlsIndexForJellyfin<T extends SubtitleHlsTrack>(tracks: T[], jellyfinIndex: number, param: string, streams: SubtitleStream[] = []): number {
  const urlIndex = tracks.findIndex(track => jellyfinStreamIndex(track.url, param) === jellyfinIndex)
  if (urlIndex >= 0) return urlIndex
  const streamPosition = streams.findIndex(stream => stream.index === jellyfinIndex)
  return streamPosition >= 0 && streamPosition < tracks.length ? streamPosition : -1
}

export function subtitleContentUrl(itemId: string, index: number, mediaSourceId?: string | null): string {
  const path = `/api/library/items/${encodeURIComponent(itemId)}/subtitles/${encodeURIComponent(String(index))}/content`
  return mediaSourceId ? `${path}?mediaSourceId=${encodeURIComponent(mediaSourceId)}` : path
}
