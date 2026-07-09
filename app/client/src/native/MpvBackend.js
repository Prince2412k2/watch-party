// ── MpvBackend — MediaBackend (see contract.ts) over Tauri IPC ──────────────
// TEMPORARY STAND-IN written by N5 (player-native-branch) so Player.jsx's
// native branch has something concrete to build/type against while N4
// (mpv-adapter) builds the real implementation in parallel on its own
// worktree. This file is N4's to own — reconcile/replace in Phase 2
// integration. Implements exactly the documented public surface from
// PLAN.md §4.1 so useSyncPlay's duck-typed HTMLMediaElement usage works
// unchanged.
import { IPC, EVENTS } from './contract.ts'
import { invoke, listen } from './ipc.js'

export class MpvBackend {
  constructor() {
    this._currentTime = 0
    this._duration = NaN
    this._paused = true
    this._playbackRate = 1
    this._volume = 1
    this._muted = false
    this._cachedAheadSec = 0
    this._listeners = new Map()
    this._unlisten = []
    this._wireEvents()
  }

  _wireEvents() {
    const on = (evt, fn) => listen(evt, ({ payload }) => fn(payload)).then(u => this._unlisten.push(u))
    on(EVENTS.MPV_TIMEPOS, ({ sec }) => { this._currentTime = sec; this._emit('timeupdate') })
    on(EVENTS.MPV_PAUSE, ({ paused }) => { this._paused = paused; this._emit(paused ? 'pause' : 'play') })
    on(EVENTS.MPV_DURATION, ({ sec }) => { this._duration = sec; this._emit('durationchange') })
    on(EVENTS.MPV_SEEKING, () => this._emit('seeking'))
    on(EVENTS.MPV_SEEKED, ({ sec }) => { this._currentTime = sec; this._emit('seeked') })
    on(EVENTS.MPV_BUFFERING, ({ active }) => this._emit(active ? 'waiting' : 'playing'))
    on(EVENTS.MPV_EOF, () => this._emit('ended'))
    on(EVENTS.MPV_LOADEDMETADATA, ({ durationSec }) => { this._duration = durationSec; this._emit('loadedmetadata') })
    on(EVENTS.MPV_SPEED, ({ rate }) => { this._playbackRate = rate; this._emit('ratechange') })
    on(EVENTS.MPV_CACHE, ({ cachedAheadSec }) => { this._cachedAheadSec = cachedAheadSec; this._emit('progress') })
  }

  get currentTime() { return this._currentTime }
  set currentTime(sec) { this._currentTime = sec; invoke(IPC.MPV_SEEK, { sec }) }
  get duration() { return this._duration }
  get paused() { return this._paused }
  get playbackRate() { return this._playbackRate }
  set playbackRate(rate) { this._playbackRate = rate; invoke(IPC.MPV_SET_SPEED, { rate }) }
  get volume() { return this._volume }
  set volume(vol) { this._volume = vol; invoke(IPC.MPV_SET_VOLUME, { vol }) }
  get muted() { return this._muted }
  set muted(muted) { this._muted = muted; invoke(IPC.MPV_SET_MUTED, { muted }) }
  get buffered() {
    const ahead = this._cachedAheadSec || 0
    const start = this._currentTime
    const end = start + ahead
    return { length: ahead > 0 ? 1 : 0, start: () => start, end: () => end }
  }

  async play() { this._paused = false; await invoke(IPC.MPV_PLAY) }
  pause() { this._paused = true; invoke(IPC.MPV_PAUSE) }
  load(url, opts = {}) {
    this._currentTime = opts.startSec || 0
    this._paused = opts.paused ?? true
    invoke(IPC.MPV_LOAD, { url, startSec: opts.startSec || 0, paused: opts.paused ?? true })
  }
  destroy() {
    this._unlisten.forEach(u => { try { u() } catch {} })
    this._unlisten = []
    invoke(IPC.MPV_TEARDOWN)
  }

  addEventListener(type, cb) {
    if (!this._listeners.has(type)) this._listeners.set(type, new Set())
    this._listeners.get(type).add(cb)
  }
  removeEventListener(type, cb) { this._listeners.get(type)?.delete(cb) }
  _emit(type, detail) {
    this._listeners.get(type)?.forEach(cb => { try { cb(detail ? { detail } : undefined) } catch {} })
  }
}
