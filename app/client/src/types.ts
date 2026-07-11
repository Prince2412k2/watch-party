export type PartyRole = 'host' | 'guest' | 'waiting' | null

export interface AuthUser {
  userId?: string
  name?: string
  [key: string]: any
}

export interface ChatMessage {
  id?: string
  userId?: string
  name?: string
  text?: string
  ts?: number
  [key: string]: any
}

export interface PartyUser {
  userId: string
  name: string
  [key: string]: any
}

export interface PartyPlayback {
  audioStreams?: any[]
  subtitleStreams?: any[]
  selectedAudioIndex?: number | null
  selectedSubtitleIndex?: number | null
  mediaSourceId?: string | null
  [key: string]: any
}

export interface PartyBrowse {
  stack?: any[]
  [key: string]: any
}

export interface PartySession {
  id: string
  hostId: string
  hostName?: string
  stage?: string
  guests?: PartyUser[]
  waiting?: PartyUser[]
  collaborativeControl?: boolean
  syncMode?: string
  browse?: PartyBrowse
  playback?: PartyPlayback
  mediaItemId?: string
  mediaSourceId?: string | null
  [key: string]: any
}

export interface ToastRecord {
  id: number
  msg: string
  level: string
  [key: string]: any
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
  createParty: (mediaItemId: string) => Promise<string>
  createRoom: () => Promise<string>
  joinParty: (partyId: string) => Promise<string>
  navigateBrowse: (stack: any[]) => void
  sendPointer: (point: any) => void
  selectMedia: (mediaItemId: string) => void
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
  [key: string]: any
}
