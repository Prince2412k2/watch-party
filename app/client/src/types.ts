import type { PlaybackTrack } from './types/media.ts'
import type { AvatarConfig } from './lib/avatar.ts'

export type PartyRole = 'host' | 'guest' | 'waiting' | null

export interface AuthUser {
  userId: string
  name?: string
  username?: string
}

/** The signed-in user's own profile. Both fields are null for anyone who has
    never saved one, which is the default case rather than a missing record:
    the account name and a derived avatar stand in. */
export interface UserProfile {
  displayName: string | null
  avatar: AvatarConfig | null
}

export interface ChatMessage {
  id?: string
  userId?: string
  name?: string
  text?: string
  ts?: number
  timestamp?: number
}

export interface PartyUser {
  userId: string
  name: string
  /** Their saved customisation, or null when they have never saved one — in
      which case their avatar is derived from `userId`. */
  avatar?: AvatarConfig | null
}

export interface PartyPlayback {
  audioStreams?: PlaybackTrack[]
  subtitleStreams?: PlaybackTrack[]
  selectedAudioIndex?: number | null
  selectedSubtitleIndex?: number | null
  mediaSourceId?: string | null
}

export interface SubtitlePreferences {
  delayMs: number
  fontScalePercent: number
  /** How far above the bottom edge the subtitles sit, 0-100. 0 is the bottom. */
  verticalOffsetPercent: number
  fontFamily: 'sans' | 'serif' | 'mono'
  textColor: string
  backgroundOpacityPercent: number
}

export interface BrowseEntry {
  id?: string
  name?: string
  type?: string
  // Browse stack entries carry Jellyfin navigation metadata beyond the shared keys.
  [key: string]: unknown
}

export interface PartyBrowse {
  stack?: BrowseEntry[]
  tab?: 'movies' | 'series' | 'discover' | 'downloads'
  screen?: 'grid' | 'detail'
  mediaId?: string | null
  seasonId?: string | null
  episodeId?: string | null
  revision?: number
}

export interface PartySession {
  id: string
  hostId: string
  hostName?: string
  hostAvatar?: AvatarConfig | null
  /** 'lobby' | 'watching' — exactly one current activity. */
  stage?: string
  guests?: PartyUser[]
  waiting?: PartyUser[]
  collaborativeControl?: boolean
  syncMode?: 'hopping' | 'dragging'
  browse?: PartyBrowse
  playback?: PartyPlayback | null
  mediaItemId?: string | null
  mediaSourceId?: string | null
  subtitlePreferences?: SubtitlePreferences
}

export interface ToastRecord {
  id: number
  msg: string
  level: string
}

export interface AuthContextValue {
  user: AuthUser | null
  profile: UserProfile | null
  loading: boolean
  login: (username: string, password: string) => Promise<AuthUser>
  logout: () => Promise<void>
  /** Called by the profile page after a successful save so every surface
      showing the signed-in user redraws without a reload. */
  applyProfile: (profile: UserProfile) => void
}

export interface PartyContextValue {
  session: PartySession | null
  role: PartyRole
  messages: ChatMessage[]
  layoutMode: 'float' | 'dock'
  chatOpen: boolean
  chatFocusToken: number
  chatRipple: number
  alertMode: 'focus' | 'on' | 'mute'
  toasts: ToastRecord[]
  createParty: (mediaItemId: string, tracks?: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null }) => Promise<string>
  createRoom: () => Promise<string>
  joinParty: (partyId: string) => Promise<string>
  /**
   * Drop the session this client is holding, without ending it for anyone else.
   * Used when the party surface is re-pointed at a DIFFERENT party id, so the
   * previous room's session/role/messages can't bleed into the new one.
   */
  leaveParty: () => void
  navigateBrowse: (stack: BrowseEntry[]) => void
  shareView: (patch: Partial<PartyBrowse>) => void
  sendPointer: (point: MirrorPoint) => void
  selectMedia: (mediaItemId: string, tracks?: { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null }) => void
  backToLobby: () => void
  approveUser: (userId: string) => void
  rejectUser: (userId: string) => void
  kickUser: (userId: string) => void
  transferHost: (userId: string) => void
  endParty: () => Promise<void>
  setCollaborative: (enabled: boolean) => void
  setSyncMode: (mode: string) => void
  setMessage?: (text: string) => void
  sendMessage: (text: string) => void
  removeCamera: (userId: string) => void
  setPlaybackTracks: (tracks?: {
    audioStreamIndex?: number | null
    subtitleStreamIndex?: number | null
  }) => void
  setSubtitlePreferences: (preferences: SubtitlePreferences) => void
  setLayout: (mode: 'float' | 'dock') => void
  toggleChat: () => void
  openChat: (focus?: boolean) => void
  closeChat: () => void
  setAlertMode: (mode: 'focus' | 'on' | 'mute') => void
}

export interface MirrorPoint {
  scroll?: number
  x?: number
  y?: number
}
