// HeadlessClient — a browser-free watch-party participant that speaks the exact
// same socket protocol as the React app and runs the SAME sync core against a
// VirtualPlayer, so a headless guest tracks the shared timeline just like a
// browser guest. Used by the CLI and scenario runner to test/observe sync
// without a browser or real Jellyfin media.

import { io } from 'socket.io-client'
import { decideSyncAction, predictPosition, CONTROL_MS, TICKS, BUFFER_AHEAD_SEC, PAUSED_BUFFER_AHEAD_SEC, SEEK_TIMEOUT_MS, BUFFER_TIMEOUT_MS, HARD_SEEK_COOLDOWN_MS } from '../client/src/sync/syncCore.js'
import { waitForSeeked, waitForBuffer, isBuffered, ensureHlsLoad, selectBufferedResumeTarget } from '../client/src/sync/bufferSeek.js'

// ── VirtualPlayer: the minimal HTMLMediaElement surface the sync core uses ──
// currentTime advances by playbackRate*dt while playing, on a timer.
//
// Phase 12 adds an OPT-IN buffering model (seekBufferMs > 0). When enabled it
// approximates HLS: a seek to an un-buffered position stalls — currentTime is
// frozen for seekBufferMs while it fires 'waiting', then 'seeked'/'canplay' —
// and it maintains a `buffered` TimeRange that fills ahead at bufferFillRate
// (media-seconds per wall-second). With seekBufferMs = 0 (the default) the
// player behaves EXACTLY as before: instant seeks, no stalls, always-buffered —
// so the existing 19 scenarios are untouched.
class VirtualPlayer {
  // `now`      — injectable wall-clock (defaults to Date.now) for skewed clocks.
  // `clockRate`— media clock fast/slow multiplier (1.0 = perfect).
  // `seekBufferMs` — >0 enables the buffering model; a fresh seek stalls this long.
  // `fillRate` — buffered runway growth in media-sec per wall-sec (default Infinity
  //              = the legacy "always fully buffered" behaviour).
  constructor(now = Date.now, clockRate = 1, seekBufferMs = 0, fillRate = Infinity) {
    this._now = now
    this._clockRate = clockRate
    this.seekBufferMs = seekBufferMs
    this._fillRate = fillRate
    this._bufferMode = seekBufferMs > 0
    this._currentTime = 0
    this.paused = true
    this.playbackRate = 1
    this._timer = null
    this._last = 0
    // Buffered window [start, end] (only meaningful in buffer mode).
    this._bufStart = 0
    this._bufEnd = 0
    this._stalled = false
    this._stallUntil = 0
    this._listeners = Object.create(null)
    this._tick = this._tick.bind(this)
  }

  // ── minimal event surface (mirrors addEventListener/removeEventListener) ──
  addEventListener(type, fn) { (this._listeners[type] ||= []).push(fn) }
  removeEventListener(type, fn) {
    const a = this._listeners[type]
    if (!a) return
    const i = a.indexOf(fn)
    if (i >= 0) a.splice(i, 1)
  }
  _emit(type) { for (const fn of (this._listeners[type] || []).slice()) { try { fn({ type }) } catch { /* */ } } }
  // Fire asynchronously so a listener attached right after the mutation (as the
  // buffer-aware routine does: `v.currentTime = x; await waitForSeeked(v)`) still
  // catches it — real media events are always async too.
  _fire(type) { setTimeout(() => this._emit(type), 0) }

  // ── currentTime as a getter/setter so a *seek* (external write) can stall,
  //    while internal playback advancement writes _currentTime directly. ──
  get currentTime() { return this._currentTime }
  set currentTime(v) {
    v = Math.max(0, v)
    if (!this._bufferMode) { this._currentTime = v; this._fire('seeked'); return }
    const buffered = v >= this._bufStart && v <= this._bufEnd
    this._currentTime = v
    if (buffered) {
      // Seek within already-buffered range: instant (still fires 'seeked').
      this._fire('seeked')
    } else {
      // Un-buffered seek: stall while hls.js fetches segments. Reset the buffered
      // window to start at the seek target; it refills from here.
      this._bufStart = v
      this._bufEnd = v
      this._stalled = true
      this._stallUntil = this._now() + this.seekBufferMs
      this._fire('waiting')
      // 'seeked'/'canplay' fire when the stall clears (in _tick). Ensure the
      // background tick is running so the stall clears and the buffer refills
      // even while PAUSED — real hls.js (once kicked via startLoad) fetches and
      // decodes the frozen frame without playback, and the paused buffer-ensure
      // relies on that. Without this the tick only ran after play(), so a
      // never-played late joiner would never buffer its frozen frame.
      if (!this._timer) { this._last = this._now(); this._timer = setInterval(this._tick, 50) }
    }
  }

  // A TimeRanges-like view of the buffered window.
  get buffered() {
    const ranges = this._bufferMode ? [[this._bufStart, this._bufEnd]] : [[0, 1e9]]
    return { length: ranges.length, start: (i) => ranges[i][0], end: (i) => ranges[i][1] }
  }

  _tick() {
    const now = this._now()
    const dt = (now - this._last) / 1000
    this._last = now
    if (!this._bufferMode) {
      if (!this.paused) this._currentTime = Math.max(0, this._currentTime + this.playbackRate * this._clockRate * dt)
      return
    }
    // Buffer keeps filling ahead (bounded runway) whether stalled or playing —
    // hls.js downloads segments continuously.
    if (Number.isFinite(this._fillRate)) {
      const maxAhead = this._currentTime + 30
      this._bufEnd = Math.min(maxAhead, this._bufEnd + this._fillRate * dt)
    }
    if (this._stalled) {
      if (now >= this._stallUntil) {
        this._stalled = false
        this._emit('seeked')
        this._emit('canplay')
        if (!this.paused) this._emit('playing')   // don't fake 'playing' on a paused buffer-ensure
      } else {
        return   // currentTime frozen while (re)buffering
      }
    }
    if (!this.paused) {
      const next = this._currentTime + this.playbackRate * this._clockRate * dt
      if (next <= this._bufEnd) {
        this._currentTime = Math.max(0, next)
      } else {
        // Playback outran the buffer → underrun: freeze and re-stall.
        this._currentTime = Math.max(0, this._bufEnd)
        this._stalled = true
        this._stallUntil = now + this.seekBufferMs
        this._fire('waiting')
      }
    }
  }
  play() {
    if (this.paused) { this.paused = false; this._last = this._now() }
    if (!this._timer) { this._last = this._now(); this._timer = setInterval(this._tick, 50) }
    return Promise.resolve()
  }
  pause() { this._tick(); this.paused = true }
  stop() { if (this._timer) { clearInterval(this._timer); this._timer = null } }
}

// ── NTP-lite clock sync — a faithful port of useServerClock ─────────────────
// `now` is the client's (possibly skewed) local clock. The min-RTT offset
// selection must cancel that skew so serverNow() lands on the true server
// timeline regardless of how wrong the local wall clock is.
function makeClock(socket, now = Date.now) {
  let offset = 0
  let ready = false
  const samples = []
  let stopped = false

  function sample() {
    const t1 = now()
    socket.timeout(2000).emit('clock:ping', t1, (err, serverTs) => {
      if (stopped || err || typeof serverTs !== 'number') return
      const t4 = now()
      const rtt = t4 - t1
      const off = serverTs - (t1 + t4) / 2
      samples.push({ rtt, offset: off })
      if (samples.length > 12) samples.shift()
      const best = samples.reduce((a, b) => (b.rtt < a.rtt ? b : a))
      offset = best.offset
      ready = true
    })
  }

  sample()
  let n = 0
  const burst = setInterval(() => { sample(); if (++n >= 5) clearInterval(burst) }, 500)
  const drift = setInterval(sample, 5000)

  return {
    serverNow: () => now() + offset,
    clockReady: () => ready,
    stop: () => { stopped = true; clearInterval(burst); clearInterval(drift) },
  }
}

export class HeadlessClient {
  constructor({ name, sendDelayMs = 0, scheduleDelayMs = 0, jitterMs = 0, clockSkewMs = 0, playbackClockRate = 1, seekBufferMs = 0, bufferFillRate = Infinity } = {}) {
    this.name = name
    this.sendDelayMs = sendDelayMs        // simulate a laggy uplink
    this.scheduleDelayMs = scheduleDelayMs // simulate slow inbound schedule apply
    this.jitterMs = jitterMs              // extra uniform-random [0,jitter) per message
    this.clockSkewMs = clockSkewMs        // this machine's wall clock is wrong by this much
    // Local clock: the true epoch plus a fixed skew. Everything on this client
    // (clock pings, player ticks) reads time through here.
    this.now = () => Date.now() + this.clockSkewMs
    this.cookie = null
    this.socket = null
    this.clock = null
    // seekBufferMs>0 turns on the VirtualPlayer HLS buffering model (stall on
    // un-buffered seek); bufferFillRate is the buffered-ahead growth rate.
    this.player = new VirtualPlayer(this.now, playbackClockRate, seekBufferMs, bufferFillRate)
    this.schedule = null
    this.isHost = false
    this.syncMode = 'hopping'
    this.partyId = null
    this.userId = null
    this.userSeeking = false
    this._loop = null
    this._lastReport = 0
    this.onWaiting = null
    this.lastDrift = 0
    this._schedSeq = 0
    this._schedApplied = 0
    // Phase 12: buffer-aware hard-seek state (mirrors useSyncPlay).
    this._seeking = false      // a buffer-aware seek is in flight → suppress the loop
    this.hardSeekCount = 0     // total hopping-guest hard seeks (chase-loop assertion)
    this._lastHardSeekAt = 0
    this.pausedBufferEnsures = 0 // total paused buffer-ensures (paused-frame assertion)
    this._alive = true
    // Mirrors useSyncPlay's lastAppliedVersionRef/lastMediaGenRef: reject a
    // schedule whose version doesn't strictly advance (stale/duplicate/
    // out-of-order delivery), resetting the baseline on a media-generation
    // change. See _applySchedule.
    this._lastAppliedVersion = -Infinity
    this._lastMediaGen = undefined
    this.staleSchedulesDropped = 0
  }

  // The single place a received (or, in a test, directly injected) schedule
  // becomes `this.schedule` — mirrors useSyncPlay.js's onSchedule guard so the
  // headless client exercises the exact same stale-schedule-rejection logic a
  // browser guest does.
  _applySchedule(s) {
    const gen = s?.mediaGeneration
    if (gen !== this._lastMediaGen) {
      this._lastMediaGen = gen
      this._lastAppliedVersion = -Infinity
    }
    if (s?.version != null) {
      if (s.version <= this._lastAppliedVersion) { this.staleSchedulesDropped++; return }
      this._lastAppliedVersion = s.version
    }
    this.schedule = s
    this.userSeeking = false
  }

  _jitter() { return this.jitterMs > 0 ? Math.random() * this.jitterMs : 0 }

  async login(baseUrl, name = this.name) {
    this.baseUrl = baseUrl
    const res = await fetch(`${baseUrl}/api/auth/test-login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name }),
    })
    if (!res.ok) throw new Error(`test-login failed (${res.status}) — is WP_TEST_MODE=1 set?`)
    const raw = res.headers.get('set-cookie') || ''
    // Keep only the cookie name=value pairs (drop attributes like Path, HttpOnly)
    this.cookie = raw.split(/,(?=[^;]+=)/).map(c => c.split(';')[0].trim()).join('; ')
    const body = await res.json()
    this.userId = body.userId
    this.name = body.name
    return body
  }

  connect() {
    return new Promise((resolve, reject) => {
      // Polling first so the session cookie rides the handshake HTTP request
      // (extraHeaders/Cookie is honored by the polling transport, letting
      // express-session attach socket.request.session for io.use auth).
      this.socket = io(this.baseUrl, {
        withCredentials: true,
        extraHeaders: { Cookie: this.cookie },
        transports: ['polling', 'websocket'],
      })
      const onSchedule = (s) => {
        const d = this.scheduleDelayMs + this._jitter()
        // Apply schedules in order even with random jitter (a later schedule
        // must never be overwritten by an earlier, more-delayed one).
        if (d > 0) {
          const seq = ++this._schedSeq
          setTimeout(() => { if (seq >= this._schedApplied) { this._schedApplied = seq; this._applySchedule(s) } }, d)
        } else {
          this._schedApplied = ++this._schedSeq
          this._applySchedule(s)
        }
      }
      this.socket.on('sync:schedule', onSchedule)
      this.socket.on('sync:host_gone', () => { this.player.pause() })
      this.socket.on('party:waiting', (p) => { this.onWaiting?.(p) })
      this.socket.on('party:approved', ({ session } = {}) => { if (session) this._absorb(session) })
      this.socket.on('party:state', (session) => { if (session) this._absorb(session) })
      this.socket.on('connect', () => {
        this.clock = makeClock(this.socket, this.now)
        this._startLoop()
        this.socket.emit('sync:hello')
        resolve(this)
      })
      this.socket.on('connect_error', (err) => reject(new Error(`connect_error: ${err.message}`)))
    })
  }

  _absorb(session) {
    this.partyId = session.id
    this.syncMode = session.syncMode || this.syncMode
    this.isHost = session.hostId === this.userId
  }

  _emit(event, payload, ack) {
    const fire = () => this.socket.emit(event, payload, ack)
    const d = this.sendDelayMs + this._jitter()
    if (d > 0) setTimeout(fire, d)
    else fire()
  }

  // sync:stall — mirror the browser hook's reportStall (drives dragging mode).
  reportStall(stalled) { this._emit('sync:stall', { stalled: !!stalled }) }

  // Simulate the local user scrubbing the scrubber (suppresses correction).
  setSeeking(on) { this.userSeeking = !!on }

  // Buffer-aware hard seek — the headless mirror of useSyncPlay.bufferAwareSeek,
  // so the sim exercises the SAME catch-up logic that ships in the browser:
  // pause → seek to predicted → await 'seeked' → await buffered runway → re-read
  // live once → snap → play. _seeking suppresses the loop for the duration.
  async _bufferAwareSeek(v) {
    if (this._seeking) return
    this._seeking = true
    const originSchedule = this.schedule
    const originVersion = originSchedule?.version
    const stillCurrent = () => this._alive && (originVersion == null
      ? this.schedule === originSchedule
      : this.schedule?.version === originVersion)
    try {
      if (!v.paused) v.pause()
      const predicted = predictPosition(originSchedule, this.clock.serverNow())
      v.currentTime = predicted

      await waitForSeeked(v, SEEK_TIMEOUT_MS)
      if (!stillCurrent()) return
      await waitForBuffer(v, predicted, BUFFER_AHEAD_SEC, BUFFER_TIMEOUT_MS)
      if (!stillCurrent()) return

      if (this.clock.clockReady()) {
        const live = predictPosition(originSchedule, this.clock.serverNow())
        if (live >= 0) v.currentTime = selectBufferedResumeTarget(v, predicted, live)
      }
      if (this.schedule?.phase === 'playing') v.play()
    } finally {
      this._seeking = false
    }
  }

  // Buffer-aware PAUSED seek — the headless mirror of useSyncPlay's
  // bufferAwarePausedSeek: pause → seek to the frozen position → kick hls.js to
  // fetch it (no-op here: VirtualPlayer has no .engine, it buffers on the seek)
  // → await 'seeked' → await a small buffered runway → stay paused (NO play()).
  // Proves the frozen frame gets buffered without resuming. _seeking suppresses
  // the loop for the duration.
  async _bufferAwarePausedSeek(v) {
    if (this._seeking) return
    this._seeking = true
    // Same operation-identity guard as _bufferAwareSeek (mirrors useSyncPlay's
    // parity fix): if the schedule moves on — host resumes/seeks, or a media
    // generation change — while this paused buffer-ensure is mid-await, it must
    // not keep driving toward a target that's no longer current.
    const originSchedule = this.schedule
    const originVersion = originSchedule?.version
    const stillCurrent = () => this._alive && (originVersion == null
      ? this.schedule === originSchedule
      : this.schedule?.version === originVersion)
    try {
      if (!v.paused) v.pause()
      v.playbackRate = 1
      const target = originSchedule.positionTicks / TICKS
      v.currentTime = target
      if (!isBuffered(v, target)) ensureHlsLoad(v, target)

      await waitForSeeked(v, SEEK_TIMEOUT_MS)
      if (!stillCurrent()) return
      await waitForBuffer(v, target, PAUSED_BUFFER_AHEAD_SEC, BUFFER_TIMEOUT_MS)
      // Intentionally NO play(): stay paused, now holding the frozen frame.
    } finally {
      this._seeking = false
    }
  }

  // The control loop: identical core to the browser hook, applied to the
  // VirtualPlayer. Runs for guests always and for a dragging host.
  _startLoop() {
    this._loop = setInterval(() => {
      const s = this.schedule
      const v = this.player
      if (!s) return
      // Buffer-aware seek in flight → don't stack corrections (chase-loop guard).
      if (this._seeking) return
      const intent = decideSyncAction({
        schedule: s,
        serverNowMs: this.clock.serverNow,
        clockReady: this.clock.clockReady,
        currentTime: v.currentTime,
        paused: v.paused,
        isHost: this.isHost,
        mode: this.syncMode,
        userSeeking: this.userSeeking,
        suppressHardSeek: Date.now() - this._lastHardSeekAt < HARD_SEEK_COOLDOWN_MS,
      })
      if (!intent) return
      // Hopping-guest hard catch-up → buffer-aware routine (fire-and-forget).
      if (intent.hardSeek && !this.isHost && this.syncMode === 'hopping') {
        this.hardSeekCount++
        this._lastHardSeekAt = Date.now()
        this._bufferAwareSeek(v)
        return
      }
      // Guest positioned while paused/stalled → buffer the frozen frame without
      // resuming (mirrors the browser hook; both modes, local-only).
      if (intent.pausedSeek && !this.isHost) {
        this.pausedBufferEnsures++
        this._bufferAwarePausedSeek(v)
        return
      }
      if (intent.seekTo != null) v.currentTime = intent.seekTo
      if (intent.rate != null) v.playbackRate = intent.rate
      if (intent.play) v.play()
      if (intent.pause && !v.paused) v.pause()
      if (intent.drift != null) this.lastDrift = intent.drift

      // Drift telemetry — guests only, throttled ~1s (mirrors the browser hook).
      if (!this.isHost && intent.drift != null) {
        const now = Date.now()
        if (now - this._lastReport >= 1000) {
          this._lastReport = now
          this._emit('sync:report', { position: v.currentTime, drift: intent.drift, rate: v.playbackRate })
        }
      }
    }, CONTROL_MS)
  }

  status() {
    return {
      name: this.name,
      isHost: this.isHost,
      position: +this.player.currentTime.toFixed(3),
      drift: +this.lastDrift.toFixed(3),
      rate: +this.player.playbackRate.toFixed(3),
      paused: this.player.paused,
      hardSeeks: this.hardSeekCount,
      pausedBufferEnsures: this.pausedBufferEnsures,
    }
  }

  // ── Protocol methods (mirror the browser client) ──────────────────────────
  createParty(mediaItemId = 'test-media') {
    return new Promise((resolve) => {
      this._emit('party:create', { mediaItemId }, (r) => {
        if (r?.session) { this._absorb(r.session); this.isHost = true }
        this._emit('party:selectMedia', { mediaItemId }, () => resolve(r))
      })
    })
  }
  joinParty(code) {
    return new Promise((resolve) => this._emit('party:join', { partyId: code }, (r) => {
      if (r?.session) this._absorb(r.session)
      resolve(r)
    }))
  }
  approve(userId) {
    return new Promise((resolve) => this._emit('party:approve', { userId }, resolve))
  }
  setSyncMode(mode) {
    this.syncMode = mode === 'dragging' ? 'dragging' : 'hopping'
    return new Promise((resolve) => this._emit('party:setSyncMode', { mode: this.syncMode }, resolve))
  }
  // Host toggles collaborative control (lets guests author the shared timeline).
  setCollaborative(enabled) {
    return new Promise((resolve) => this._emit('party:setCollaborative', { enabled: !!enabled }, resolve))
  }
  play(sec = this.player.currentTime) {
    this._emit('sync:play', { positionTicks: Math.round(sec * TICKS), t0: this.clock.serverNow() })
  }
  pause(sec = this.player.currentTime) {
    this._emit('sync:pause', { positionTicks: Math.round(sec * TICKS) })
  }
  seek(sec) {
    this._emit('sync:seek', { positionTicks: Math.round(sec * TICKS), t0: this.clock.serverNow() })
  }

  disconnect() {
    this._alive = false
    clearInterval(this._loop)
    this.clock?.stop()
    this.player.stop()
    this.socket?.disconnect()
  }
}

export { VirtualPlayer }
