// Host jump / seek scenarios. Verify every guest converges to the new position
// (hard-seek branch) within a tick or two and nobody is left behind.

import { spawnHost, spawnGuest, startSampler, sleep, check, worstDrift, makeFetchSchedule } from './_helpers.js'

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

// Seek to a large position mid-playback.
export const jumpMiddle = {
  name: 'host-jump-to-middle',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setup(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(4000)
    host.seek(500)                 // jump way ahead
    await sleep(4000)
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    const worst = worstDrift(rows, 'playing', 3)
    // also assert no guest stuck near old position (0) after settle
    const last = rows[rows.length - 1]
    const stuckOld = last.positions.some(p => p < 400)
    return { checks: [
      check('all converge to seek target', worst < 0.5, `worst=${worst.toFixed(3)}s`),
      check('nobody left behind at old pos', !stuckOld, `positions=[${last.positions.map(p=>p.toFixed(1)).join(', ')}]`),
    ] }
  },
}

// Seek BACKWARD mid-playback.
export const jumpBackward = {
  name: 'host-seek-backward',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setup(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(400)
    await sleep(4000)
    host.seek(30)                  // jump back
    await sleep(4000)
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    const worst = worstDrift(rows, 'playing', 3)
    const last = rows[rows.length - 1]
    const stuckAhead = last.positions.some(p => p > 200)
    return { checks: [
      check('all converge backward', worst < 0.5, `worst=${worst.toFixed(3)}s`),
      check('nobody stuck ahead', !stuckAhead, `positions=[${last.positions.map(p=>p.toFixed(1)).join(', ')}]`),
    ] }
  },
}

// Rapid multiple seeks in quick succession (scrub storm).
export const scrubStorm = {
  name: 'host-scrub-storm',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setup(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(2000)
    // fire many seeks within <1s
    const targets = [100, 250, 80, 600, 300, 450, 200, 512]
    for (const t of targets) { host.seek(t); await sleep(90) }
    const finalTarget = 512
    await sleep(5000)              // let the dust settle on the final target
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    const worst = worstDrift(rows, 'playing', 3)
    const last = rows[rows.length - 1]
    // final schedule position should reflect the last seek (~finalTarget)
    const schedPos = last.schedule.positionTicks / 10_000_000
    return { checks: [
      check('converge after scrub storm', worst < 0.6, `worst=${worst.toFixed(3)}s`),
      check('landed on last seek target', Math.abs(schedPos - finalTarget) < 5, `schedPos=${schedPos.toFixed(1)} target=${finalTarget}`),
    ] }
  },
}

// Seek while paused, then play.
export const seekPausedThenPlay = {
  name: 'host-seek-while-paused-then-play',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setup(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(2000)
    host.pause()
    await sleep(1500)
    host.seek(240)                 // seek while paused → server starts a segment
    await sleep(2000)
    host.play(240)
    await sleep(4000)
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    const worst = worstDrift(rows, 'playing', 3)
    const last = rows[rows.length - 1]
    return { checks: [
      check('converge after seek-paused-play', worst < 0.5, `worst=${worst.toFixed(3)}s`),
      check('near seek target ~240+', last.positions.every(p => p > 235), `positions=[${last.positions.map(p=>p.toFixed(1)).join(', ')}]`),
    ] }
  },
}

// Play → immediate pause → seek.
export const playPauseSeek = {
  name: 'host-play-pause-seek',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setup(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(120)
    host.pause()
    await sleep(120)
    host.seek(360)
    await sleep(5000)
    const rows = s.stop()
    host.disconnect(); guests.forEach(g => g.disconnect())
    // after seek, phase is playing; everyone should be at ~360
    const worst = worstDrift(rows, 'playing', 3)
    const last = rows[rows.length - 1]
    return { checks: [
      check('converge after play-pause-seek', worst < 0.5, `worst=${worst.toFixed(3)}s`),
      check('at seek target ~360', last.positions.every(p => p > 355), `positions=[${last.positions.map(p=>p.toFixed(1)).join(', ')}]`),
    ] }
  },
}
