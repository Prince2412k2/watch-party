// ── Native (Tauri) contract — frozen, see docs/native/PLAN.md §4 ────────────
// This file is the single source of truth for the boundary between the React
// app and the Rust/Tauri host. It is plain JS-with-JSDoc (not compiled — the
// app doesn't use a TS build step) so it can be imported directly; the .ts
// extension signals "this is a type contract" to anyone reading the tree.
//
// MediaBackend duck-types HTMLMediaElement on exactly the surface useSyncPlay
// (app/client/src/hooks/useSyncPlay.js) and Player.jsx actually touch — see
// the plan for the audit. MpvBackend (native/MpvBackend.js) implements this;
// the web path keeps using the real <HlsVideo> element, which already
// satisfies the same shape natively.

/**
 * @typedef {Object} BufferedRanges
 * @property {number} length
 * @property {(i: number) => number} start
 * @property {(i: number) => number} end
 */

/**
 * @typedef {Object} MediaBackend
 * @property {number} currentTime            - seconds; set = seek
 * @property {number} duration                - seconds (NaN until known)
 * @property {boolean} paused
 * @property {number} playbackRate
 * @property {number} volume                  - 0..1
 * @property {boolean} muted
 * @property {BufferedRanges} buffered
 * @property {() => Promise<void>} play
 * @property {() => void} pause
 * @property {(url: string, opts?: { startSec?: number, paused?: boolean }) => void} load
 * @property {() => void} destroy
 * @property {(type: string, cb: (e?: any) => void) => void} addEventListener
 * @property {(type: string, cb: (e?: any) => void) => void} removeEventListener
 */

// Event names a MediaBackend implementation MUST fire, matching
// HTMLMediaElement semantics exactly (useSyncPlay/Player.jsx listen for these):
export const MEDIA_EVENTS = [
  'play', 'pause', 'seeking', 'seeked', 'timeupdate', 'waiting', 'playing',
  'ended', 'durationchange', 'ratechange', 'volumechange', 'loadedmetadata', 'progress',
]

// ── Tauri IPC command names (Rust #[tauri::command] in desktop/src-tauri/src/ipc.rs) ──
export const IPC = {
  // playback (mpv.rs)
  MPV_LOAD: 'mpv_load',                 // { url, startSec, paused }
  MPV_PLAY: 'mpv_play',
  MPV_PAUSE: 'mpv_pause',
  MPV_SEEK: 'mpv_seek',                 // { sec }
  MPV_SET_SPEED: 'mpv_set_speed',       // { rate }
  MPV_SET_VOLUME: 'mpv_set_volume',     // { vol }
  MPV_SET_MUTED: 'mpv_set_muted',       // { muted }
  MPV_SET_REGION: 'mpv_set_region',     // { x, y, w, h, dpr }
  MPV_SET_FULLSCREEN: 'mpv_set_fullscreen', // { on }
  MPV_TEARDOWN: 'mpv_teardown',
  // downloader (download.rs)
  DL_START: 'dl_start',                 // { itemId, url, title, parts? } -> { id }
  DL_PAUSE: 'dl_pause',                 // { id }
  DL_RESUME: 'dl_resume',               // { id }
  DL_CANCEL: 'dl_cancel',               // { id }
  DL_LIST: 'dl_list',                   // -> DownloadRecord[]
  // offline store (offline.rs)
  OFFLINE_LIST: 'offline_list',         // -> OfflineRecord[]
  OFFLINE_PATH: 'offline_path',         // { itemId } -> { path } | null
  OFFLINE_REMOVE: 'offline_remove',     // { itemId }
  // lifecycle (main.rs / window.rs)
  APP_QUIT: 'app_quit',
}

// ── Tauri event names (Rust `emit`, subscribed via @tauri-apps/api/event) ───
export const EVENTS = {
  MPV_TIMEPOS: 'mpv:timepos',           // { sec }            ~4-10Hz
  MPV_PAUSE: 'mpv:pause',               // { paused }
  MPV_DURATION: 'mpv:duration',         // { sec }
  MPV_SEEKING: 'mpv:seeking',           // {}
  MPV_SEEKED: 'mpv:seeked',             // { sec }
  MPV_BUFFERING: 'mpv:buffering',       // { active }
  MPV_EOF: 'mpv:eof',                   // {}
  MPV_LOADEDMETADATA: 'mpv:loadedmetadata', // { durationSec }
  MPV_SPEED: 'mpv:speed',               // { rate }
  MPV_CACHE: 'mpv:cache',               // { cachedAheadSec, cachedBytes }
  DL_PROGRESS: 'dl:progress',           // { id, receivedBytes, totalBytes, bytesPerSec }
  DL_DONE: 'dl:done',                   // { id, itemId, path }
  DL_ERROR: 'dl:error',                 // { id, message }
}

/**
 * @typedef {Object} DownloadRecord
 * @property {string} id
 * @property {string} itemId
 * @property {string} title
 * @property {'queued'|'active'|'paused'|'done'|'error'} state
 * @property {number} receivedBytes
 * @property {number} totalBytes
 * @property {number} parts
 */

/**
 * @typedef {Object} OfflineRecord
 * @property {string} itemId
 * @property {string} title
 * @property {string} path
 * @property {number} sizeBytes
 * @property {string} addedAt
 */
