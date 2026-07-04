// Shared helpers for the sync scenario suite. A scenario is an async function
// { name, run } that receives a context {SERVER, spawnHost, spawnGuest, sampler,
// fetchSchedule, sleep, idealPosition} and returns { pass, checks[], notes[] }.

import { HeadlessClient } from '../client.js'
import { TICKS } from '../../client/src/sync/syncCore.js'

export const sleep = (ms) => new Promise(r => setTimeout(r, ms))

// The position (seconds) the shared timeline says everyone should be at *now*,
// computed on the TRUE server clock (Date.now on this test box == server box).
// t0 is stored by the server in true-server-ms (the controller sends its
// clock-corrected serverNow(), which — if the clock sync works — equals true
// server time), so comparing against Date.now() is the honest "ground truth".
export function idealPosition(schedule) {
  if (!schedule) return 0
  const P0 = schedule.positionTicks / TICKS
  if (schedule.paused || schedule.phase !== 'playing') return P0
  return P0 + (Date.now() - schedule.t0) / 1000
}

export function makeFetchSchedule(SERVER) {
  return async function fetchSchedule(partyId) {
    const res = await fetch(`${SERVER}/api/debug/session/${partyId}`)
    if (!res.ok) throw new Error(`debug endpoint ${res.status} — WP_TEST_MODE=1 set?`)
    return (await res.json()).schedule
  }
}

export function makeFetchView(SERVER) {
  return async function fetchView(partyId) {
    const res = await fetch(`${SERVER}/api/debug/session/${partyId}`)
    if (!res.ok) throw new Error(`debug endpoint ${res.status}`)
    return res.json()
  }
}

// Spawn + login + connect a host and create a party. Returns {host, partyId}.
export async function spawnHost(SERVER, opts = {}) {
  const host = new HeadlessClient({ name: opts.name || 'host', ...opts })
  await host.login(SERVER)
  await host.connect()
  const created = await host.createParty('test-media')
  return { host, partyId: created.partyId }
}

// Spawn + login + connect + join (auto-approved by host). Returns the guest.
export async function spawnGuest(SERVER, host, partyId, opts = {}) {
  const g = new HeadlessClient({ name: opts.name || 'guest', ...opts })
  await g.login(SERVER)
  await g.connect()
  const jr = await g.joinParty(partyId)
  if (jr?.status === 'waiting') await host.approve(g.userId)
  // small settle so approval + first schedule land
  await sleep(150)
  return g
}

// Sample every SAMPLE_MS: record ideal + each guest's (currentTime - ideal).
// Returns a controller with .stop() → array of rows.
export function startSampler(fetchSchedule, partyId, clients, sampleMs = 500, log = false) {
  const rows = []
  let running = true
  const names = clients.map(c => c.name)
  const timer = setInterval(async () => {
    if (!running) return
    let schedule
    try { schedule = await fetchSchedule(partyId) } catch { return }
    const ideal = idealPosition(schedule)
    const drifts = clients.map(c => c.player.currentTime - ideal)
    const positions = clients.map(c => c.player.currentTime)
    const row = { t: Date.now(), phase: schedule.phase, ideal, drifts, positions, schedule }
    rows.push(row)
    if (log) {
      const cells = clients.map((c, i) => `${c.name}=${drifts[i].toFixed(3).padStart(8)}`).join('  ')
      console.log(`   [${new Date().toISOString().slice(11, 19)}] ${String(schedule.phase).padEnd(8)} ideal=${ideal.toFixed(2).padStart(8)}  ${cells}`)
    }
  }, sampleMs)
  return {
    names,
    rows,
    stop() { running = false; clearInterval(timer); return rows },
  }
}

// A check result. pass=false fails the scenario.
export function check(label, pass, detail = '') {
  return { label, pass: !!pass, detail }
}

// Worst |drift| across the last N settled samples (playing phase).
export function worstDrift(rows, phase, lastN = 1) {
  const matching = rows.filter(r => r.phase === phase)
  const tail = matching.slice(-lastN)
  let worst = 0
  for (const r of tail) worst = Math.max(worst, ...r.drifts.map(Math.abs))
  return worst
}

// Spread between clients' positions in the last sample (frozen equality check).
export function positionSpread(rows, lastN = 1) {
  const tail = rows.slice(-lastN)
  let worst = 0
  for (const r of tail) {
    const ps = r.positions
    worst = Math.max(worst, Math.max(...ps) - Math.min(...ps))
  }
  return worst
}

export { TICKS }
