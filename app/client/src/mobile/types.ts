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
