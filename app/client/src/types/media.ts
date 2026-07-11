import { arrayOf, booleanValue, isRecord, numberValue, stringValue } from './guards'

/** Jellyfin's playback stream metadata, shared by the player and party UI. */
export interface MediaStream {
  Index: number
  Type: 'Audio' | 'Subtitle' | string
  Codec?: string
  Language?: string
  DisplayTitle?: string
  Title?: string
  IsDefault?: boolean
  IsForced?: boolean
  IsExternal?: boolean
  IsHearingImpaired?: boolean
  DeliveryUrl?: string | null
}

/** Normalized stream shape used by party state and player controls. */
export interface PlaybackTrack {
  index: number
  displayTitle?: string
  title?: string
  language?: string
  codec?: string
  isDefault?: boolean
}

export interface PlaybackSource {
  Id: string
  DirectStreamUrl?: string
  TranscodingUrl?: string
  MediaStreams: MediaStream[]
}

export interface PlaybackInfoResponse {
  MediaSources: PlaybackSource[]
  PlaySessionId?: string
}

export interface PlaybackSelection {
  mediaSourceId?: string | null
  audioStreams?: MediaStream[]
  subtitleStreams?: MediaStream[]
  selectedAudioIndex?: number | null
  selectedSubtitleIndex?: number | null
}

export function isMediaStream(value: unknown): value is MediaStream {
  return isRecord(value) && numberValue(value.Index) !== undefined && typeof value.Type === 'string'
}

export function parsePlaybackInfo(value: unknown): PlaybackInfoResponse | null {
  if (!isRecord(value) || !Array.isArray(value.MediaSources)) return null
  const MediaSources = value.MediaSources.flatMap((raw): PlaybackSource[] => {
    if (!isRecord(raw) || typeof raw.Id !== 'string') return []
    return [{
      Id: raw.Id,
      DirectStreamUrl: stringValue(raw.DirectStreamUrl),
      TranscodingUrl: stringValue(raw.TranscodingUrl),
      MediaStreams: arrayOf(raw.MediaStreams, isMediaStream).map((stream) => ({
        Index: stream.Index, Type: stream.Type,
        Codec: stringValue(stream.Codec), Language: stringValue(stream.Language),
        DisplayTitle: stringValue(stream.DisplayTitle), Title: stringValue(stream.Title),
        IsDefault: booleanValue(stream.IsDefault), IsForced: booleanValue(stream.IsForced),
        IsExternal: booleanValue(stream.IsExternal), IsHearingImpaired: booleanValue(stream.IsHearingImpaired),
        DeliveryUrl: stream.DeliveryUrl === null ? null : stringValue(stream.DeliveryUrl),
      })),
    }]
  })
  return { MediaSources, PlaySessionId: stringValue(value.PlaySessionId) }
}
