// Play/pause storms, late joiners, and mode switching mid-playback.

import { spawnHost, spawnGuest, startSampler, sleep, check, worstDrift, positionSpread, makeFetchSchedule } from './_helpers.js'

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
