// Play/pause storms, late joiners, and mode switching mid-playback.

import { spawnHost, spawnGuest, startSampler, sleep, check, worstDrift, positionSpread, makeFetchSchedule, TICKS } from './_helpers.js'

const GUESTS = [
  { name: 'g0', sendDelayMs: 0 },
  { name: 'g150', sendDelayMs: 150, scheduleDelayMs: 150 },
  { name: 'g400', sendDelayMs: 400, scheduleDelayMs: 250, jitterMs: 80 },
]

async function setup(SERVER, guestSpecs = GUESTS) {
  const fetchSchedule = makeFetchSchedule(SERVER)
  const { host, partyId } = await spawnHost(SERVER)
  const guests = []
  for (const spec of guestSpecs) guests.push(await spawnGuest(SERVER, host, partyId, spec))
  await sleep(1800)
  return { host, partyId, guests, fetchSchedule }
}

// Many play/pause toggles in <1s; final state must be consistent for all.
export const playPauseStorm = {
  name: 'play-pause-storm',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setup(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(2000)
    // storm of toggles
    for (let i = 0; i < 12; i++) {
      if (i % 2 === 0) host.pause()
      else host.play(host.player.currentTime || 20)
      await sleep(70)
    }
    // settle on a definite final state: paused
    host.pause()
    await sleep(4000)
    const rows = s.stop()
    const finalPhase = rows[rows.length - 1].phase
    const allPaused = guests.every(g => g.player.paused)
    const spread = positionSpread(rows, 2)
    host.disconnect(); guests.forEach(g => g.disconnect())
    return { checks: [
      check('final phase paused', finalPhase === 'paused', `phase=${finalPhase}`),
      check('all guests paused', allPaused, `paused=[${guests.map(g=>g.player.paused).join(',')}]`),
      check('frozen positions equal', spread < 0.5, `spread=${spread.toFixed(3)}s`),
    ] }
  },
}

// Storm ending on PLAY: nobody should be left paused while others play.
export const playPauseStormEndPlay = {
  name: 'play-pause-storm-end-playing',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setup(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(1500)
    for (let i = 0; i < 11; i++) {
      if (i % 2 === 0) host.pause()
      else host.play(host.player.currentTime || 10)
      await sleep(70)
    }
    host.play(host.player.currentTime || 10)  // end on PLAY
    await sleep(5000)
    const rows = s.stop()
    const finalPhase = rows[rows.length - 1].phase
    const anyPaused = guests.some(g => g.player.paused)
    const worst = worstDrift(rows, 'playing', 3)
    host.disconnect(); guests.forEach(g => g.disconnect())
    return { checks: [
      check('final phase playing', finalPhase === 'playing', `phase=${finalPhase}`),
      check('no guest left paused', !anyPaused, `paused=[${guests.map(g=>g.player.paused).join(',')}]`),
      check('all converge', worst < 0.5, `worst=${worst.toFixed(3)}s`),
    ] }
  },
}

// Late joiner: guest spawns AFTER playback is well underway.
export const lateJoiner = {
  name: 'late-joiner',
  async run({ SERVER }) {
    const fetchSchedule = makeFetchSchedule(SERVER)
    const { host, partyId } = await spawnHost(SERVER)
    const early = await spawnGuest(SERVER, host, partyId, { name: 'early', sendDelayMs: 50 })
    await sleep(1500)
    host.play(0)
    // simulate being well underway by seeking to 120s then playing a bit
    host.seek(120)
    await sleep(3000)
    // NOW a late guest joins with real network lag
    const late = await spawnGuest(SERVER, host, partyId, { name: 'late', sendDelayMs: 200, scheduleDelayMs: 200, jitterMs: 60 })
    const s = startSampler(fetchSchedule, partyId, [early, late])
    await sleep(5000)
    const rows = s.stop()
    const worst = worstDrift(rows, 'playing', 3)
    // the late guest must be near live (~130+), not at 0
    const lastPos = rows[rows.length - 1].positions[1]
    host.disconnect(); early.disconnect(); late.disconnect()
    return { checks: [
      check('late guest aligned (not at 0)', lastPos > 120, `latePos=${lastPos.toFixed(1)}s`),
      check('both converge to live', worst < 0.5, `worst=${worst.toFixed(3)}s`),
    ] }
  },
}

// Mode switching mid-playback (hopping↔dragging) while playing and while paused.
export const modeSwitch = {
  name: 'mode-switch-midplayback',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setup(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(2500)
    const posBefore = host.player // hopping host doesn't advance; use schedule
    await host.setSyncMode('dragging')
    for (const g of guests) g.syncMode = 'dragging'
    await sleep(3000)
    await host.setSyncMode('hopping')
    for (const g of guests) g.syncMode = 'hopping'
    await sleep(2500)
    // switch again while paused
    host.pause()
    await sleep(1000)
    await host.setSyncMode('dragging')
    for (const g of guests) g.syncMode = 'dragging'
    await sleep(2000)
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    // No position jump: playing-phase drift stays bounded across switches
    const worst = worstDrift(rows, 'playing', 5)
    const spreadPaused = positionSpread(rows.filter(r => r.phase !== 'playing'), 2)
    return { checks: [
      check('no desync across mode switch (playing)', worst < 0.6, `worst=${worst.toFixed(3)}s`),
      check('paused positions equal after switch', spreadPaused < 0.5, `spread=${spreadPaused.toFixed(3)}s`),
    ] }
  },
}

// Regression for HOOK finding #7: schedule.version is monotonic per party
// session (never resets on media change) and the client must ignore any
// received schedule whose version doesn't strictly advance — a replayed
// snapshot, a reconnect race, or out-of-order delivery on a future transport
// must never overwrite a fresher, already-applied schedule. Socket.IO
// preserves order on one connection so the real server can't trigger this in
// a normal run; this exercises the guard directly (HeadlessClient._applySchedule
// is the exact function the real socket handler calls) against a live
// schedule pulled from the real server, so the fixture is realistic even
// though the delivery is injected rather than actually reordered on the wire.
export const staleScheduleVersionRejected = {
  name: 'stale-schedule-version-rejected',
  async run({ SERVER }) {
    const { host, partyId } = await spawnHost(SERVER)
    const guest = await spawnGuest(SERVER, host, partyId, { name: 'g' })
    host.play(0)
    await sleep(1000)
    const live = guest.schedule
    const checks = []
    checks.push(check('precondition: guest holds a real versioned schedule', live && live.version >= 0, `version=${live?.version}`))

    // A lower-versioned duplicate (e.g. a replayed party:state snapshot) must
    // be dropped — this pretends positionTicks jumped back to 0, which would
    // be very visible if it were wrongly applied.
    const dropsBefore = guest.staleSchedulesDropped
    const stale = { ...live, version: live.version - 1, positionTicks: 0 }
    guest._applySchedule(stale)
    checks.push(check('lower-version schedule dropped', guest.staleSchedulesDropped === dropsBefore + 1 && guest.schedule === live, `schedule unchanged=${guest.schedule === live}`))

    // An EQUAL-version duplicate (re-delivery of the same schedule) must also
    // be dropped — the guard is "> last applied", not ">=".
    const dup = { ...live, positionTicks: 0 }
    guest._applySchedule(dup)
    checks.push(check('equal-version (duplicate) schedule dropped', guest.schedule === live, `schedule unchanged=${guest.schedule === live}`))

    // A genuinely newer schedule must still be accepted (the guard doesn't
    // just wedge the client on the first schedule it ever saw).
    const fresh = { ...live, version: live.version + 1, positionTicks: Math.round(999 * TICKS) }
    guest._applySchedule(fresh)
    checks.push(check('strictly newer schedule accepted', guest.schedule === fresh, `accepted=${guest.schedule === fresh}`))

    // A media-generation change resets the version baseline to -Infinity, so
    // an old-looking version under a NEW generation (new media selected /
    // back-to-lobby) must still be accepted, not mistaken for staleness.
    const newGen = { ...fresh, version: 0, mediaGeneration: (fresh.mediaGeneration || 0) + 1, positionTicks: 0 }
    guest._applySchedule(newGen)
    checks.push(check('version baseline resets on mediaGeneration change', guest.schedule === newGen, `accepted=${guest.schedule === newGen}`))

    host.disconnect(); guest.disconnect()
    return { checks }
  },
}
