// Audio and subtitle tracks for the stage's track menu.
//
// `/api/library/playback-info/:id` is normalised server-side, but it still
// crosses HTTP, so it is parsed rather than cast — and the two decisions worth
// pinning are made here rather than inside a component: which track a title
// opens on, and what a track without a display title is called.

import { isRecord } from '../types/guards.ts'

export interface PlaybackTrack {
  index: number
  displayTitle?: string
  title?: string
  language?: string
  codec?: string
  isDefault: boolean
  isForced: boolean
  isExternal: boolean
}

export interface PlaybackTracks {
  mediaSourceId: string | null
  audioStreams: PlaybackTrack[]
  subtitleStreams: PlaybackTrack[]
}

export interface TrackSelection {
  audioStreamIndex?: number | null
  subtitleStreamIndex?: number | null
}

function parseTrack(value: unknown): PlaybackTrack[] {
  if (!isRecord(value) || typeof value.index !== 'number') return []
  const text = (key: string) => (typeof value[key] === 'string' ? (value[key] as string) : undefined)
  return [{
    index: value.index,
    displayTitle: text('displayTitle'),
    title: text('title'),
    language: text('language'),
    codec: text('codec'),
    isDefault: value.isDefault === true,
    isForced: value.isForced === true,
    isExternal: value.isExternal === true,
  }]
}

export function parsePlaybackTracks(value: unknown): PlaybackTracks | null {
  if (!isRecord(value)) return null
  const list = (raw: unknown) => (Array.isArray(raw) ? raw.flatMap(parseTrack) : [])
  return {
    mediaSourceId: typeof value.mediaSourceId === 'string' ? value.mediaSourceId : null,
    audioStreams: list(value.audioStreams),
    subtitleStreams: list(value.subtitleStreams),
  }
}

/** A track's row label. Falls back through the fields Jellyfin may leave unset. */
export function trackLabel(track: PlaybackTrack, fallback: string): string {
  const base = track.displayTitle || track.title || track.language || fallback
  const tags = [track.isDefault ? 'Default' : null, track.isForced ? 'Forced' : null].filter(Boolean)
  return tags.length > 0 ? `${base} · ${tags.join(' · ')}` : base
}

/**
 * What a title opens on.
 *
 * Audio follows the file's default and falls back to the first track, because
 * "no audio" is not a state anyone wants. Subtitles default to OFF unless the
 * file marks a track default or forced — a forced track carries dialogue the
 * viewer cannot otherwise follow, so suppressing it is worse than showing it.
 */
export function defaultSelection(tracks: PlaybackTracks): TrackSelection {
  const audio = tracks.audioStreams.find((track) => track.isDefault) ?? tracks.audioStreams[0]
  const subtitle = tracks.subtitleStreams.find((track) => track.isDefault || track.isForced)
  return {
    audioStreamIndex: audio?.index ?? null,
    subtitleStreamIndex: subtitle?.index ?? null,
  }
}

/** The shape the player expects. `-1` is how "subtitles off" is spelled on the wire. */
export const wireSelection = (selection: TrackSelection): TrackSelection => ({
  audioStreamIndex: selection.audioStreamIndex ?? null,
  subtitleStreamIndex: selection.subtitleStreamIndex ?? -1,
})

/**
 * The player URL's query for a chosen title.
 *
 * The `-1` has to survive into the query string. Dropping the key because the
 * value is "off" would let the player fall back to the file's default and turn
 * subtitles back on for a viewer who has just turned them off — the same bug in
 * reverse as omitting the audio index. A selection that was never made carries
 * nothing at all, which is what leaves the player its own defaulting.
 */
export function playbackQuery(itemId: string, selection?: TrackSelection): URLSearchParams {
  const query = new URLSearchParams({ itemId })
  if (!selection) return query
  if (Number.isInteger(selection.audioStreamIndex)) {
    query.set('audioStreamIndex', String(selection.audioStreamIndex))
  }
  if (Number.isInteger(selection.subtitleStreamIndex)) {
    query.set('subtitleStreamIndex', String(selection.subtitleStreamIndex))
  }
  return query
}
