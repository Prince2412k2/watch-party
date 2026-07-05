// Clock skew, host migration, long-run stability, and quality-tier reauthor.

import { spawnHost, spawnGuest, startSampler, sleep, check, worstDrift, positionSpread, makeFetchSchedule, makeFetchView, idealPosition } from './_helpers.js'
import { HeadlessClient } from '../client.js'

// ── Clock skew ──────────────────────────────────────────────────────────────
// Give VirtualPlayers artificially skewed local clocks; the NTP-lite offset
// correction must still land everyone on the same server timeline.
export const clockSkew = {
  name: 'clock-skew',
  async run({ SERVER }) {
    const fetchSchedule = makeFetchSchedule(SERVER)
    // Host also skewed: it authors t0 with its serverNow() (corrected), so if
    // correction works, ground-truth idealPosition (Date.now vs t0) stays right.
    const { host, partyId } = await spawnHost(SERVER, { clockSkewMs: 5000 })
    const guests = [
      await spawnGuest(SERVER, host, partyId, { name: 'skew+30s', clockSkewMs: 30_000, sendDelayMs: 50 }),
      await spawnGuest(SERVER, host, partyId, { name: 'skew-45s', clockSkewMs: -45_000, sendDelayMs: 120, scheduleDelayMs: 120 }),
      await spawnGuest(SERVER, host, partyId, { name: 'skew+8s', clockSkewMs: 8_000, sendDelayMs: 300, jitterMs: 80 }),
    ]
    await sleep(3000)   // clocks need extra time to converge under skew+jitter
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(5000)
    host.seek(200)
    await sleep(5000)
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    const worst = worstDrift(rows, 'playing', 4)
    return { checks: [
      check('skewed clocks converge to server timeline', worst < 0.5, `worst=${worst.toFixed(3)}s`),
    ] }
  },
}

// ── Host migration ──────────────────────────────────────────────────────────
// Host disconnects mid-playback → grace-period freeze → oldest guest becomes
// host, timeline continuity preserved, new host can drive.
// Server HOST_GRACE_MS is 30s. To keep the run short we assert the freeze and
// the continuity, and (since we cannot shrink the constant without editing the
// server behaviour) verify migration via a shortened wait is impractical — so
// we drive the migration by having the new host reconnect logic exercised
// through the grace timer only if feasible. We keep the grace check strict and
// note the 30s constant.
export const hostMigration = {
  name: 'host-migration',
  async run({ SERVER }) {
    const fetchSchedule = makeFetchSchedule(SERVER)
    const fetchView = makeFetchView(SERVER)
    const { host, partyId } = await spawnHost(SERVER)
    const g1 = await spawnGuest(SERVER, host, partyId, { name: 'oldest', sendDelayMs: 40 })
    await sleep(300)
    const g2 = await spawnGuest(SERVER, host, partyId, { name: 'newer', sendDelayMs: 40 })
    await sleep(1500)
    host.play(0)
    await sleep(4000)

    const liveBefore = idealPosition(await fetchSchedule(partyId))
    // Host vanishes mid-playback
    host.disconnect()
    await sleep(1200)  // let host_gone + freeze land
    const frozen = await fetchSchedule(partyId)
    const froze = frozen.paused === true && frozen.phase === 'paused'
    const continuityErr = Math.abs((frozen.positionTicks / 10_000_000) - liveBefore)
    const guestsPaused = g1.player.paused && g2.player.paused
    const guestsPausedDetail = `g1=${g1.player.paused} g2=${g2.player.paused}`

    const notes = []
    let migrated = false, newHostDrove = false, staysPausedUntilResumed = false, seekDidNotAutoResume = false
    const GRACE = Number(process.env.WP_HOST_GRACE_MS || 0)
    if (GRACE > 0 && GRACE <= 8000) {
      // Server was started with a shortened grace for testing — verify migration.
      await sleep(GRACE + 2500)
      const view = await fetchView(partyId)
      migrated = view.members.find(m => m.isHost)?.userId === g1.userId
      // Host migration deliberately discards playback intent (see the comment
      // block on handleHostDisconnect in server/index.js): the new host inherits
      // a paused, frozen timeline and must explicitly resume it — promotion
      // itself must not auto-resume playback.
      const postPromotion = await fetchSchedule(partyId)
      staysPausedUntilResumed = postPromotion.phase === 'paused' && postPromotion.paused === true
      // new host drives: seek (NOT play) — the timeline should move to the new
      // position but STILL not start playing on its own (a scrub/seek while
      // paused must not resume the room; see the sync:seek "preserve intent"
      // comment in server/index.js).
      g1.isHost = true
      g1.seek(300)
      await sleep(2500)
      const after = await fetchSchedule(partyId)
      newHostDrove = Math.abs((after.positionTicks / 10_000_000) - 300) < 6
      seekDidNotAutoResume = after.phase === 'paused' && after.paused === true
    } else {
      notes.push(`migration (oldest→host) not force-tested: HOST_GRACE_MS=30s in prod; set WP_HOST_GRACE_MS<=8000 to exercise it`)
    }

    g1.disconnect(); g2.disconnect()
    const checks = [
      check('timeline freezes on host loss', froze, `phase=${frozen.phase} paused=${frozen.paused}`),
      check('freeze preserves live position', continuityErr < 0.8, `err=${continuityErr.toFixed(3)}s`),
      check('guests paused on host_gone', guestsPaused, guestsPausedDetail),
    ]
    if (GRACE > 0 && GRACE <= 8000) {
      checks.push(check('oldest guest promoted to host', migrated, `promoted=${migrated}`))
      checks.push(check('promotion does not auto-resume playback', staysPausedUntilResumed, `phase/paused=${staysPausedUntilResumed}`))
      checks.push(check('new host can drive timeline', newHostDrove, `drove=${newHostDrove}`))
      checks.push(check('new host seek does not auto-resume (must manually play)', seekDidNotAutoResume, `stillPaused=${seekDidNotAutoResume}`))
    }
    return { checks, notes }
  },
}

// ── Long-run stability ────────────────────────────────────────────────────
// Play for an extended stretch; the soft rate-nudge must keep |drift| bounded
// and not oscillate. We inject a persistent small schedule delay so the nudge
// is genuinely exercised.
export const longRun = {
  name: 'long-run-stability',
  async run({ SERVER }) {
    const fetchSchedule = makeFetchSchedule(SERVER)
    const { host, partyId } = await spawnHost(SERVER)
    // Give each guest a media clock that runs slightly fast/slow so the soft
    // rate-nudge is CONTINUOUSLY exercised (a perfect clock never triggers it).
    const guests = [
      await spawnGuest(SERVER, host, partyId, { name: 'fast+2%', sendDelayMs: 80, scheduleDelayMs: 60, jitterMs: 40, playbackClockRate: 1.02 }),
      await spawnGuest(SERVER, host, partyId, { name: 'slow-2%', sendDelayMs: 250, scheduleDelayMs: 180, jitterMs: 60, playbackClockRate: 0.98 }),
    ]
    await sleep(2000)
    const s = startSampler(fetchSchedule, partyId, guests, 500)
    // sample the fast guest's playbackRate over time to detect oscillation
    const rateTrace = []
    const rateTimer = setInterval(() => rateTrace.push(guests[0].player.playbackRate), 500)
    host.play(0)
    await sleep(25000)   // 25s of continuous playback under a skewed media clock
    clearInterval(rateTimer)
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    // steady-state: worst drift after the first 3s of settling
    const settled = rows.filter(r => r.phase === 'playing').slice(4)
    let worst = 0
    for (const r of settled) worst = Math.max(worst, ...r.drifts.map(Math.abs))
    // The nudge must actually engage against the 2% skew (rate pushed off 1.0).
    const settledRates = rateTrace.slice(6)
    const engaged = settledRates.some(r => Math.abs(r - 1) > 0.005)
    // Oscillation guard: rate stays within the MAX_RATE_ADJ clamp (±0.08) and
    // never flips sign violently between consecutive settled samples.
    const withinClamp = settledRates.every(r => Math.abs(r - 1) <= 0.0801)
    let flips = 0
    for (let i = 1; i < settledRates.length; i++) {
      const a = settledRates[i - 1] - 1, b = settledRates[i] - 1
      if (a * b < 0 && Math.abs(a) > 0.02 && Math.abs(b) > 0.02) flips++
    }
    return { checks: [
      check('long-run |drift| bounded under clock skew', worst < 0.5, `worst=${worst.toFixed(3)}s over ${settled.length} samples`),
      check('soft rate-nudge engages against skew', engaged, `maxSettledRateAdj=${Math.max(...settledRates.map(r=>Math.abs(r-1))).toFixed(4)}`),
      check('rate stays within clamp, no runaway', withinClamp, `withinClamp=${withinClamp}`),
      check('nudge does not oscillate', flips <= 2, `sign-flips=${flips}`),
    ] }
  },
}

// ── Quality-tier reauthor (timeline correctness only; NOT real ABR) ─────────
// Simulate a host changing quality tier by re-authoring the schedule at the
// SAME live position (a real client re-seeks the new stream to where it was).
// The server timeline must stay continuous — no jump, everyone stays aligned.
export const qualityTierReauthor = {
  name: 'quality-tier-reauthor',
  async run({ SERVER }) {
    const fetchSchedule = makeFetchSchedule(SERVER)
    const { host, partyId } = await spawnHost(SERVER)
    const guests = [
      await spawnGuest(SERVER, host, partyId, { name: 'g0', sendDelayMs: 0 }),
      await spawnGuest(SERVER, host, partyId, { name: 'g200', sendDelayMs: 200, scheduleDelayMs: 150 }),
    ]
    await sleep(1800)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(4000)
    // "tier change": re-author at the current live position (seek to self).
    const live = idealPosition(await fetchSchedule(partyId))
    host.seek(live)              // same-position re-author
    await sleep(4000)
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    const worst = worstDrift(rows, 'playing', 4)
    // continuity: no backward jump in ideal across the reauthor boundary
    let maxBackJump = 0
    for (let i = 1; i < rows.length; i++) {
      const d = rows[i - 1].ideal - rows[i].ideal
      if (d > maxBackJump) maxBackJump = d
    }
    return {
      checks: [
        check('timeline stays continuous across tier change', maxBackJump < 1.0, `maxBackJump=${maxBackJump.toFixed(3)}s`),
        check('everyone aligned after reauthor', worst < 0.5, `worst=${worst.toFixed(3)}s`),
      ],
      notes: ['This validates TIMELINE math on a same-position schedule re-author only. Real ABR/HLS chunk-download behaviour requires a browser + real Jellyfin media and is OUT OF SCOPE for this headless run.'],
    }
  },
}
