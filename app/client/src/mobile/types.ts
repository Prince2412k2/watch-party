import type { CSSProperties, ReactNode } from 'react'

/** Jellyfin/library records used by the phone presentation layer. */
export interface MobileItem {
  Id: string
  Name: string
  Type: string
  CollectionType?: string
  SeriesId?: string
  SeriesName?: string
  ParentIndexNumber?: number
  IndexNumber?: number
  ProductionYear?: number
  RunTimeTicks?: number
  Overview?: string
  OfficialRating?: string
  CommunityRating?: number
  Genres?: string[]
  UserData?: { PlayedPercentage?: number; PlaybackPositionTicks?: number }
}

/** qBittorrent/enriched download record rendered in the phone queue. */
export interface MobileTorrent {
  hash: string
  name: string
  progress?: number
  state?: string
  dlspeed?: number
  displayTitle?: string
  subtitle?: string
  posterUrl?: string
  kind?: string
}

export type Style = CSSProperties
export type Children = ReactNode
export type Click = () => void

/**
 * Boundary shape for backend records that have not been normalized yet.  The
 * mobile surfaces deliberately render only optional Jellyfin/qBittorrent
 * fields, so this keeps the boundary honest without pretending an API field is
 * available until it is modeled above.
 */
export type UnmodeledRecord = Record<string, unknown>
