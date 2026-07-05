// Phase 12 — HLS buffering / chase-loop scenarios.
//
// A "slow" guest runs the VirtualPlayer buffering model (seekBufferMs > 0): a
// hard-seek to an un-buffered position stalls while segments download, so a
// naive "jump to live and keep playing" catch-up would land behind, re-seek,
// stall again — the buffering chase loop. These scenarios assert the buffer-
// aware routine (a) converges the slow guest to the shared timeline and (b)
// does so with a BOUNDED number of hard-seeks (≤2 after the trigger) — i.e. no
// loop. Hard-seeks are counted on the client via HeadlessClient.hardSeekCount.

import { spawnHost, spawnGuest, startSampler, sleep, check, worstDrift, makeFetchSchedule } from './_helpers.js'
import { PAUSED_BUFFER_AHEAD_SEC } from '../../client/src/sync/syncCore.js'
import { isBuffered } from '../../client/src/sync/bufferSeek.js'

// A slow guest on HLS: seeks stall for 1.5s; buffer fills at 3x realtime so the
// BUFFER_AHEAD_SEC runway (4s) fills within the routine, letting the re-read
// live position land inside the buffered window instead of re-stalling.
const SLOW = { name: 'slow-hls', sendDelayMs: 200, scheduleDelayMs: 150, seekBufferMs: 1500, bufferFillRate: 3 }

// Host plays, then jumps to the middle. The slow guest must catch up over HLS
// without entering a chase loop.
export const chaseLoopHostJump = {
  name: 'hls-chase-loop-host-jump',
  async run({ SERVER }) {
    const fetchSchedule = makeFetchSchedule(SERVER)
    const { host, partyId } = await spawnHost(SERVER)
    const slow = await spawnGuest(SERVER, host, partyId, SLOW)
    const fast = await spawnGuest(SERVER, host, partyId, { name: 'fast', sendDelayMs: 0 })
    const guests = [slow, fast]
    await sleep(1800)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(3500)
    const beforeJump = slow.hardSeekCount
    host.seek(500)                 // jump way ahead → slow guest must re-buffer
    await sleep(9000)              // let the buffer-aware catch-up converge
    const rows = s.stop()
    const seeksAfter = slow.hardSeekCount - beforeJump
    host.disconnect(); guests.forEach(g => g.disconnect())
    const worst = worstDrift(rows, 'playing', 3)
    const last = rows[rows.length - 1]
    return { checks: [
      check('slow guest converges after jump', worst < 0.8, `worst=${worst.toFixed(3)}s`),
      check('bounded hard-seeks after jump (no chase loop)', seeksAfter <= 2, `seeksAfterJump=${seeksAfter} total=${slow.hardSeekCount}`),
      check('slow guest not stuck at old pos', last.positions[0] > 480, `pos=${last.positions[0].toFixed(1)}`),
    ], notes: [
      'VirtualPlayer approximates HLS: seek stalls seekBufferMs while a buffered range fills at bufferFillRate. Real hls.js segment timing differs; this validates the control logic, not exact buffer math.',
    ] }
  },
}

// A slow guest joins while the host is already well into the movie: it must
// catch up from 0 to live with bounded hard-seeks.
export const chaseLoopLateJoin = {
  name: 'hls-chase-loop-late-join',
  async run({ SERVER }) {
    const fetchSchedule = makeFetchSchedule(SERVER)
    const { host, partyId } = await spawnHost(SERVER)
    host.play(0)
    await sleep(6000)              // host well into playback
    const slow = await spawnGuest(SERVER, host, partyId, SLOW)
    const s = startSampler(fetchSchedule, partyId, [slow])
    await sleep(9000)              // catch-up window
    const rows = s.stop()
    host.disconnect(); slow.disconnect()
    const worst = worstDrift(rows, 'playing', 3)
    return { checks: [
      check('late slow guest converges', worst < 0.8, `worst=${worst.toFixed(3)}s`),
      check('bounded hard-seeks on catch-up (no loop)', slow.hardSeekCount <= 2, `hardSeeks=${slow.hardSeekCount}`),
    ], notes: [
      'Slow HLS guest catches up from 0 to live via the buffer-aware routine; a naive re-seek loop would show many hard-seeks.',
    ] }
  },
}

// A slow-HLS guest joins into a PAUSED party positioned far from where it is.
// It must seek to the frozen point and BUFFER/render that frame while staying
// paused — never resuming. The bug: a bare paused `currentTime = P0` left the
// guest on a spinner over an unloaded frame until someone hit play. Asserts the
// paused buffer-aware seek runs, buffers the frozen frame (with runway), and
// leaves the guest paused.
export const pausedFrameBuffers = {
  name: 'hls-paused-frame-buffers',
  async run({ SERVER }) {
    const { host, partyId } = await spawnHost(SERVER)
    host.play(0)
    await sleep(2000)
    host.pause(400)                // freeze the shared timeline: paused @400
    await sleep(600)
    // Slow guest joins the already-paused party (its player is at 0).
    const slow = await spawnGuest(SERVER, host, partyId, SLOW)
    await sleep(6000)              // let the paused buffer-ensure fetch + settle
    const p = slow.player
    const pos = p.currentTime
    const paused = p.paused
    const ensures = slow.pausedBufferEnsures
    const framed = isBuffered(p, 400)
    let runway = 0
    try {
      const b = p.buffered
      for (let i = 0; i < b.length; i++) {
        if (400 >= b.start(i) - 0.25 && 400 <= b.end(i) + 0.25) runway = b.end(i) - 400
      }
    } catch { /* torn down */ }
    host.disconnect(); slow.disconnect()
    return { checks: [
      check('guest lands on frozen position ~400', Math.abs(pos - 400) < 1.0, `pos=${pos.toFixed(2)}`),
      check('guest stays PAUSED (never resumed)', paused === true, `paused=${paused}`),
      check('paused buffer-ensure ran', ensures >= 1, `ensures=${ensures}`),
      check('frozen frame buffered with runway', framed && runway >= PAUSED_BUFFER_AHEAD_SEC - 0.1, `buffered=${framed} runway=${runway.toFixed(2)}s`),
    ], notes: [
      'Headless proxy for a browser-only bug. The VirtualPlayer models "unbuffered seek stalls, then a buffered range fills" but CANNOT model real hls.js paused-fetch or first-frame paint — that needs a real browser. This asserts the control wiring: a guest positioned while paused routes through the paused buffer-aware seek, buffers the frozen frame, and stays paused (no play()). The hls.js startLoad(P0) kick and the "Catching up…" overlay clear are browser-only and unverified headlessly.',
    ] }
  },
}

// Regression for audit finding #1 ("late joiners skip buffer-aware catch-up"):
// a fresh guest's own <video> starts PAUSED (VirtualPlayer default) even though
// the ROOM is actively playing well underway. Before the fix, decideSyncAction's
// `if (paused)` branch (this is the "my player hasn't started yet" case, distinct
// from `s.phase !== 'playing'` which is the whole ROOM being paused/stalled —
// see hls-paused-frame-buffers above) returned a bare seek+play regardless of
// drift, which on real HLS seeks straight into unbuffered media and stalls. It
// must instead set `hardSeek` once drift exceeds HARD_SEEK_SEC and route through
// the SAME buffer-aware rendezvous a mid-playback hard-seek uses. Distinguishes
// this path from the paused-frame-buffers scenario via pausedBufferEnsures===0
// (that counter only increments on the OTHER branch, where the room itself is
// paused).
export const pausedLateJoinerUsesBufferedCatchup = {
  name: 'hls-paused-late-joiner-buffered-catchup',
  async run({ SERVER }) {
    const { host, partyId } = await spawnHost(SERVER)
    host.play(0)
    await sleep(6000)              // host well into playback, far from 0
    const slow = await spawnGuest(SERVER, host, partyId, SLOW)
    // Sanity: the guest's own player really does start paused (this is the
    // exact condition the fix must handle, not a room-level pause).
    const startedPaused = slow.player.paused
    const s = startSampler(makeFetchSchedule(SERVER), partyId, [slow])
    await sleep(9000)              // catch-up window
    const rows = s.stop()
    host.disconnect(); slow.disconnect()
    const worst = worstDrift(rows, 'playing', 3)
    return { checks: [
      check('guest video starts paused while room plays (precondition)', startedPaused, `paused=${startedPaused}`),
      check('routed through buffer-aware hard seek, not a naive seek+play', slow.hardSeekCount >= 1, `hardSeeks=${slow.hardSeekCount}`),
      check('did not take the room-paused branch', slow.pausedBufferEnsures === 0, `pausedBufferEnsures=${slow.pausedBufferEnsures}`),
      check('converges to live and resumes playing', worst < 0.8 && !slow.player.paused, `worst=${worst.toFixed(3)}s paused=${slow.player.paused}`),
    ] }
  },
}

// Regression for HOOK finding #15 (operation-identity parity): the paused
// buffer-aware seek must abandon itself — not resume the OLD frozen target —
// if the shared timeline moves on (host resumes play) while it's still
// awaiting the buffer. Before the parity fix this routine had no stillCurrent()
// re-check, so a resume mid-flight risked leaving the guest paused on a stale
// frame after the room started playing again.
export const pausedCatchupAbortsOnHostResume = {
  name: 'hls-paused-catchup-aborts-on-resume',
  async run({ SERVER }) {
    const { host, partyId } = await spawnHost(SERVER)
    host.play(0)
    await sleep(1500)
    host.pause(400)                 // freeze the shared timeline: paused @400
    await sleep(400)
    const slow = await spawnGuest(SERVER, host, partyId, SLOW) // joins paused, far from 400
    await sleep(300)                // let the paused buffer-aware seek start (mid-stall)
    const ensuresBefore = slow.pausedBufferEnsures
    host.play(400)                  // host resumes WHILE the guest is still buffering the frozen frame
    const s = startSampler(makeFetchSchedule(SERVER), partyId, [slow])
    await sleep(9000)               // let the guest recover and catch up to live playback
    const rows = s.stop()
    host.disconnect(); slow.disconnect()
    const worst = worstDrift(rows, 'playing', 3)
    return { checks: [
      check('paused buffer-ensure had actually started before the resume', ensuresBefore >= 1, `ensures=${ensuresBefore}`),
      check('guest recovers and ends up playing (not stuck paused on stale frame)', !slow.player.paused, `paused=${slow.player.paused}`),
      check('guest converges to the resumed timeline', worst < 0.8, `worst=${worst.toFixed(3)}s`),
    ] }
  },
}
