// Native (Tauri) contract — frozen, see docs/native/PLAN.md §4 ────────────
// This file is the single source of truth for the boundary between the React
// app and the Rust/Tauri host.

export interface BufferedRanges {
  length: number
  start: (i: number) => number
  end: (i: number) => number
}

export interface MediaBackend {
  currentTime: number
  duration: number
  paused: boolean
  playbackRate: number
  volume: number
  muted: boolean
  buffered: BufferedRanges
  play: () => Promise<void>
  pause: () => void
  load: (url: string, opts?: { startSec?: number; paused?: boolean }) => void
  destroy: () => void
  addEventListener: (type: string, cb: (e?: unknown) => void) => void
  removeEventListener: (type: string, cb: (e?: unknown) => void) => void
}

export type DownloadState = 'queued' | 'active' | 'paused' | 'done' | 'error'

export interface DownloadRecord {
  id: string
  itemId: string
  title: string
  state: DownloadState
  receivedBytes: number
  totalBytes: number
  parts: number
  bytesPerSec?: number
  path?: string
  message?: string
}

export interface OfflineRecord {
  itemId: string
  title: string
  path: string
  sizeBytes: number
  addedAt: string
}

export const MEDIA_EVENTS = [
  'play', 'pause', 'seeking', 'seeked', 'timeupdate', 'waiting', 'playing',
  'ended', 'durationchange', 'ratechange', 'volumechange', 'loadedmetadata', 'progress',
] as const

export const IPC = {
  MPV_LOAD: 'mpv_load',
  MPV_PLAY: 'mpv_play',
  MPV_PAUSE: 'mpv_pause',
  MPV_SEEK: 'mpv_seek',
  MPV_SET_SPEED: 'mpv_set_speed',
  MPV_SET_VOLUME: 'mpv_set_volume',
  MPV_SET_MUTED: 'mpv_set_muted',
  MPV_SET_REGION: 'mpv_set_region',
  MPV_SET_FULLSCREEN: 'mpv_set_fullscreen',
  MPV_SET_CAN_CONTROL: 'mpv_set_can_control',
  MPV_TEARDOWN: 'mpv_teardown',
  DL_START: 'dl_start',
  DL_PAUSE: 'dl_pause',
  DL_RESUME: 'dl_resume',
  DL_CANCEL: 'dl_cancel',
  DL_LIST: 'dl_list',
  OFFLINE_LIST: 'offline_list',
  OFFLINE_PATH: 'offline_path',
  OFFLINE_REMOVE: 'offline_remove',
  APP_QUIT: 'app_quit',
} as const

export const EVENTS = {
  MPV_TIMEPOS: 'mpv:timepos',
  MPV_PAUSE: 'mpv:pause',
  MPV_DURATION: 'mpv:duration',
  MPV_SEEKING: 'mpv:seeking',
  MPV_SEEKED: 'mpv:seeked',
  MPV_BUFFERING: 'mpv:buffering',
  MPV_EOF: 'mpv:eof',
  MPV_LOADEDMETADATA: 'mpv:loadedmetadata',
  MPV_SPEED: 'mpv:speed',
  MPV_CACHE: 'mpv:cache',
  DL_PROGRESS: 'dl:progress',
  DL_DONE: 'dl:done',
  DL_ERROR: 'dl:error',
} as const
