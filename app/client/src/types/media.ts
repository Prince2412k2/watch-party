/** Normalized stream shape used by party state and player controls. */
export interface PlaybackTrack {
  index: number
  displayTitle?: string
  title?: string
  language?: string
  codec?: string
  isDefault?: boolean
  isForced?: boolean
  isExternal?: boolean
  deliveryUrl?: string | null
}
