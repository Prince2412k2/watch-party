// Dragging mode + stalls: a stall from one/several guests freezes the group
// (phase 'stalled'); clearing stalls resumes; STALL_MAX_MS force-resumes a
// dead client. STALL_MAX_MS in the server is 30s — too long for CI, so the
// force-resume check is a lighter structural assertion (documented in notes).

import { spawnHost, spawnGuest, startSampler, sleep, check, positionSpread, worstDrift, makeFetchSchedule, makeFetchView } from './_helpers.js'

const GUESTS = [
  { name: 'g0', sendDelayMs: 0 },
  { name: 'g100', sendDelayMs: 100, scheduleDelayMs: 100 },
  { name: 'g300', sendDelayMs: 300, scheduleDelayMs: 200 },
]

async function setupDragging(SERVER) {
  const fetchSchedule = makeFetchSchedule(SERVER)
  const fetchView = makeFetchView(SERVER)
  const { host, partyId } = await spawnHost(SERVER)
  const guests = []
  for (const spec of GUESTS) guests.push(await spawnGuest(SERVER, host, partyId, spec))
  await host.setSyncMode('dragging')
  for (const g of guests) g.syncMode = 'dragging'
  host.syncMode = 'dragging'
  await sleep(1800)
  return { host, partyId, guests, fetchSchedule, fetchView }
}

// One guest stalls → group freezes; clears → resumes.
export const singleStall = {
  name: 'dragging-single-stall',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setupDragging(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(2500)
    // g300 stalls (buffering)
    guests[2].reportStall(true)
    await sleep(2500)
    const frozenRow = s.rows[s.rows.length - 1]
    const froze = frozenRow.phase === 'stalled'
    const spreadFrozen = positionSpread(s.rows.filter(r => r.phase === 'stalled'), 2)
    // clear the stall
    guests[2].reportStall(false)
    await sleep(3500)
    const rows = s.stop()
    const resumed = rows[rows.length - 1].phase === 'playing'
    const worst = worstDrift(rows, 'playing', 3)
    host.disconnect(); guests.forEach(g => g.disconnect())
    return { checks: [
      check('group freezes on stall (phase=stalled)', froze, `phase=${frozenRow.phase}`),
      check('frozen positions equal', spreadFrozen < 0.5, `spread=${spreadFrozen.toFixed(3)}s`),
      check('group resumes on clear', resumed, `finalPhase=${rows[rows.length-1].phase}`),
      check('converge after resume', worst < 0.6, `worst=${worst.toFixed(3)}s`),
    ] }
  },
}

// Several guests stall/clear in overlap; group stays frozen until ALL clear.
export const multiStall = {
  name: 'dragging-multi-stall',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setupDragging(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(2000)
    guests[1].reportStall(true)
    guests[2].reportStall(true)
    await sleep(1500)
    guests[1].reportStall(false)   // one clears, one still stalled → stay frozen
    await sleep(1800)
    const stillFrozen = s.rows[s.rows.length - 1].phase === 'stalled'
    guests[2].reportStall(false)   // now all clear → resume
    await sleep(3000)
    const rows = s.stop()
    const resumed = rows[rows.length - 1].phase === 'playing'
    const worst = worstDrift(rows, 'playing', 3)
    host.disconnect(); guests.forEach(g => g.disconnect())
    return { checks: [
      check('stays frozen while any stalled', stillFrozen, `phase=${s.rows[s.rows.length-1].phase}`),
      check('resumes only when all clear', resumed, `finalPhase=${rows[rows.length-1].phase}`),
      check('converge after resume', worst < 0.6, `worst=${worst.toFixed(3)}s`),
    ] }
  },
}

// A guest that stalls then DISCONNECTS must not keep the group frozen forever
// (server clears its stall on disconnect and reconciles).
export const deadClientDisconnect = {
  name: 'dragging-dead-client-disconnect',
  async run({ SERVER }) {
    const { host, partyId, guests, fetchSchedule } = await setupDragging(SERVER)
    const s = startSampler(fetchSchedule, partyId, guests)
    host.play(0)
    await sleep(2000)
    guests[2].reportStall(true)
    await sleep(2000)
    const froze = s.rows[s.rows.length - 1].phase === 'stalled'
    // the dead client vanishes without clearing its stall
    guests[2].disconnect()
    await sleep(3000)
    const rows = s.stop()
    const resumed = rows[rows.length - 1].phase === 'playing'
    host.disconnect(); guests[0].disconnect(); guests[1].disconnect()
    return { checks: [
      check('froze on dead-client stall', froze, `phase=${s.rows.find(r=>r.phase==='stalled')?'stalled':'never'}`),
      check('resumes after dead client leaves', resumed, `finalPhase=${rows[rows.length-1].phase}`),
    ] }
  },
}
