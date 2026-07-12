import type { PlaybackTrack } from './types/media'

export type PartyRole = 'host' | 'guest' | 'waiting' | null

export interface AuthUser {
  userId: string
  name?: string
  username?: string
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
}

export interface PartyPlayback {
  audioStreams?: PlaybackTrack[]
  subtitleStreams?: PlaybackTrack[]
  selectedAudioIndex?: number | null
  selectedSubtitleIndex?: number | null
  mediaSourceId?: string | null
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
}

export interface PartySession {
  id: string
  hostId: string
  hostName?: string
  stage?: string
  guests?: PartyUser[]
  waiting?: PartyUser[]
  collaborativeControl?: boolean
  syncMode?: 'hopping' | 'dragging'
  browse?: PartyBrowse
  playback?: PartyPlayback
  mediaItemId?: string
  mediaSourceId?: string | null
}

export interface ToastRecord {
  id: number
  msg: string
  level: string
}

export interface AuthContextValue {
  user: AuthUser | null
  loading: boolean
  login: (username: string, password: string) => Promise<AuthUser>
  logout: () => Promise<void>
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
  navigateBrowse: (stack: BrowseEntry[]) => void
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
