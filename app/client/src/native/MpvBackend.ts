// MediaBackend implementation over Tauri IPC — duck-types HTMLMediaElement on
// the surface useSyncPlay + Player.jsx touch (see contract.ts's MediaBackend
// typedef and docs/native/PLAN.md §4.1). A drop-in replacement for the real
// <video> element passed as playerRef.current, so the sync engine
// (syncCore.js, bufferSeek.js, useSyncPlay.js) runs unmodified against it.
//
// Local mpv OSC interaction and remote sync corrections both flow through the
// same mpv:* events from Rust, so from this class's point of view there's no
// difference between "the user clicked mpv's own play button" and "a sync
// correction called .play()" — both just show up as property changes to relay
// onward as standard media events.

import { invoke, listen } from './ipc.ts'
import { IPC, EVENTS, MEDIA_EVENTS } from './contract.ts'
import { isFiniteNumber, isRecord } from './guards.ts'

export class MpvBackend {
  private _currentTime = 0
  private _duration = Number.NaN
  private _paused = true
  private _playbackRate = 1
  private _volume = 1
  private _muted = false
  private _cachedAheadSec = 0
  private _cachedBytes = 0
  private _listeners: Map<string, Set<() => void>>
  private _unlistens: Array<Promise<() => void>>

  constructor() {
    this._currentTime = 0
    this._duration = NaN
    this._paused = true
    this._playbackRate = 1
    this._volume = 1
    this._muted = false
    this._cachedAheadSec = 0
    this._cachedBytes = 0

    this._listeners = new Map(MEDIA_EVENTS.map((eventName) => [eventName, new Set<() => void>()]))
    this._unlistens = []

    this._subscribe(EVENTS.MPV_TIMEPOS, isSecPayload, ({ sec }) => {
      this._currentTime = sec
      this._emit('timeupdate')
    })
    this._subscribe(EVENTS.MPV_PAUSE, isPausedPayload, ({ paused }) => {
      this._paused = paused
      this._emit(paused ? 'pause' : 'play')
    })
    this._subscribe(EVENTS.MPV_DURATION, isSecPayload, ({ sec }) => {
      this._duration = sec
      this._emit('durationchange')
    })
    this._subscribe(EVENTS.MPV_SEEKING, isRecord, () => {
      this._emit('seeking')
    })
    this._subscribe(EVENTS.MPV_SEEKED, isSecPayload, ({ sec }) => {
      this._currentTime = sec
      this._emit('seeked')
    })
    this._subscribe(EVENTS.MPV_BUFFERING, isActivePayload, ({ active }) => {
      this._emit(active ? 'waiting' : 'playing')
    })
    this._subscribe(EVENTS.MPV_EOF, isRecord, () => {
      this._paused = true
      this._emit('ended')
    })
    this._subscribe(EVENTS.MPV_LOADEDMETADATA, isDurationPayload, ({ durationSec }) => {
      this._duration = durationSec
      this._emit('loadedmetadata')
    })
    this._subscribe(EVENTS.MPV_SPEED, isRatePayload, ({ rate }) => {
      this._playbackRate = rate
      this._emit('ratechange')
    })
    this._subscribe(EVENTS.MPV_CACHE, isCachePayload, ({ cachedAheadSec, cachedBytes }) => {
      this._cachedAheadSec = cachedAheadSec
      this._cachedBytes = cachedBytes
      this._emit('progress')
    })
  }

  _subscribe<T>(eventName: string, guard: (payload: unknown) => payload is T, handler: (payload: T) => void) {
    // listen() is async (dynamic-imports @tauri-apps/api on first real call);
    // fire-and-forget is fine here — nothing needs the unlisten fn before
    // destroy(), and destroy() itself just awaits whatever accumulated.
    const p = listen(eventName, (event) => {
      if (guard(event.payload)) handler(event.payload)
    })
    this._unlistens.push(p)
  }

  _emit(type: string) {
    const set = this._listeners.get(type)
    if (!set) return
    for (const cb of set) {
      try { cb() } catch { /* one bad listener must not break the others */ }
    }
  }

  // ── getters/setters ──────────────────────────────────────────────────────
  get currentTime() { return this._currentTime }
  set currentTime(sec: number) {
    this._currentTime = sec
    invoke(IPC.MPV_SEEK, { sec })
  }

  get duration() { return this._duration }
  get paused() { return this._paused }

  get playbackRate() { return this._playbackRate }
  set playbackRate(rate: number) {
    this._playbackRate = rate
    invoke(IPC.MPV_SET_SPEED, { rate })
  }

  get volume() { return this._volume }
  set volume(vol: number) {
    this._volume = vol
    invoke(IPC.MPV_SET_VOLUME, { vol })
  }

  get muted() { return this._muted }
  set muted(muted: boolean) {
    this._muted = muted
    invoke(IPC.MPV_SET_MUTED, { muted })
  }

  get buffered() {
    const aheadSec = this._cachedAheadSec
    const start = this._currentTime
    const end = start + Math.max(0, aheadSec)
    return {
      length: aheadSec > 0 ? 1 : 0,
      start: (i: number) => { if (i !== 0) throw new Error('index out of range'); return start },
      end: (i: number) => { if (i !== 0) throw new Error('index out of range'); return end },
    }
  }

  // ── methods ───────────────────────────────────────────────────────────────
  async play() {
    this._paused = false
    await invoke(IPC.MPV_PLAY, {})
  }

  pause() {
    this._paused = true
    invoke(IPC.MPV_PAUSE, {})
  }

  load(url: string, opts: { startSec?: number; paused?: boolean } = {}) {
    const { startSec = 0, paused = false } = opts
    this._currentTime = startSec
    this._paused = paused
    this._duration = NaN
    invoke(IPC.MPV_LOAD, { url, startSec, paused })
  }

  destroy() {
    invoke(IPC.MPV_TEARDOWN, {})
    for (const set of this._listeners.values()) set.clear()
    for (const p of this._unlistens) {
      p.then((unlisten: () => void) => { try { unlisten() } catch { /* already torn down */ } }).catch(() => {})
    }
    this._unlistens = []
  }

  addEventListener(type: string, cb: () => void) {
    const set = this._listeners.get(type)
    if (set) set.add(cb)
  }

  removeEventListener(type: string, cb: () => void) {
    const set = this._listeners.get(type)
    if (set) set.delete(cb)
  }
}

function isSecPayload(value: unknown): value is { sec: number } {
  return isRecord(value) && isFiniteNumber(value.sec)
}
function isPausedPayload(value: unknown): value is { paused: boolean } {
  return isRecord(value) && typeof value.paused === 'boolean'
}
function isActivePayload(value: unknown): value is { active: boolean } {
  return isRecord(value) && typeof value.active === 'boolean'
}
function isDurationPayload(value: unknown): value is { durationSec: number } {
  return isRecord(value) && isFiniteNumber(value.durationSec)
}
function isRatePayload(value: unknown): value is { rate: number } {
  return isRecord(value) && isFiniteNumber(value.rate)
}
function isCachePayload(value: unknown): value is { cachedAheadSec: number; cachedBytes: number } {
  return isRecord(value) && isFiniteNumber(value.cachedAheadSec) && isFiniteNumber(value.cachedBytes)
}
