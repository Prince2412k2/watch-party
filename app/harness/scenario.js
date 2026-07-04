// Non-interactive, scriptable sync scenario.
//   WP_SERVER=http://localhost:3999 node harness/scenario.js
//
// Spins up 1 host + N guests (some with injected latency), runs a timeline
// (play → wait → seek → wait → pause → wait), samples every ~500ms, and prints
// a drift table over time (each guest's VirtualPlayer position vs the ideal
// shared-timeline position). Exit 0 if every guest converges within CONVERGE_SEC
// after each correction settles, else 1.

import { HeadlessClient } from './client.js'
import { TICKS } from '../client/src/sync/syncCore.js'

const SERVER = process.env.WP_SERVER || 'http://localhost:3999'
const CONVERGE_SEC = 0.5          // pass threshold for |drift| after settling
const SAMPLE_MS = 500
const GUEST_LAGS = [0, 150, 400]  // injected send/schedule delay per guest (ms)

const sleep = (ms) => new Promise(r => setTimeout(r, ms))

// Ideal position (seconds) the shared timeline says everyone should be at *now*.
function idealPosition(schedule) {
  if (!schedule) return 0
  const P0 = schedule.positionTicks / TICKS
  if (schedule.paused || schedule.phase !== 'playing') return P0
  return P0 + (Date.now() - schedule.t0) / 1000
}

async function fetchSchedule(partyId) {
  const res = await fetch(`${SERVER}/api/debug/session/${partyId}`)
  if (!res.ok) throw new Error(`debug endpoint ${res.status} — WP_TEST_MODE=1 set?`)
  return (await res.json()).schedule
}

async function main() {
  const host = new HeadlessClient({ name: 'host' })
  await host.login(SERVER)
  await host.connect()
  const created = await host.createParty('test-media')
  const partyId = created.partyId
  console.log(`host "${host.name}" created party ${partyId}`)

  const guests = []
  for (let i = 0; i < GUEST_LAGS.length; i++) {
    const lag = GUEST_LAGS[i]
    const g = new HeadlessClient({ name: `guest${i + 1}(${lag}ms)`, sendDelayMs: lag, scheduleDelayMs: lag })
    await g.login(SERVER)
    await g.connect()
    const jr = await g.joinParty(partyId)
    if (jr?.status === 'waiting') await host.approve(g.userId)
    guests.push(g)
  }
  console.log(`spawned ${guests.length} guests with lags [${GUEST_LAGS.join(', ')}]ms\n`)

  await sleep(1500)  // let clocks converge

  const samples = []
  let running = true

  const sampler = setInterval(async () => {
    if (!running) return
    let schedule
    try { schedule = await fetchSchedule(partyId) } catch { return }
    const ideal = idealPosition(schedule)
    const row = { t: Date.now(), phase: schedule.phase, ideal, drifts: guests.map(g => g.player.currentTime - ideal) }
    samples.push(row)
    const cells = guests.map((g, i) => `${g.name}=${row.drifts[i].toFixed(3).padStart(7)}`).join('  ')
    console.log(`[${new Date().toISOString().slice(11, 19)}] ${schedule.phase.padEnd(8)} ideal=${ideal.toFixed(2).padStart(7)}  ${cells}`)
  }, SAMPLE_MS)

  // ── Timeline ──────────────────────────────────────────────────────────────
  console.log('--- PLAY from 0 ---')
  host.play(0)
  await sleep(5000)

  console.log('--- SEEK to 120 ---')
  host.seek(120)
  await sleep(5000)

  console.log('--- PAUSE ---')
  host.pause()
  await sleep(3000)

  running = false
  clearInterval(sampler)

  // ── Convergence check ───────────────────────────────────────────────────
  // Take the last sample from each of the three phases (after correction had
  // time to settle) and require every guest within threshold.
  const lastByPhase = {}
  for (const s of samples) lastByPhase[s.phase] = s
  let ok = true
  console.log('\n--- convergence (last sample per phase) ---')
  for (const [phase, s] of Object.entries(lastByPhase)) {
    const worst = Math.max(...s.drifts.map(Math.abs))
    const pass = worst < CONVERGE_SEC
    ok = ok && pass
    console.log(`${phase.padEnd(8)} worst |drift| = ${worst.toFixed(3)}s  → ${pass ? 'PASS' : 'FAIL'}`)
  }

  host.disconnect()
  guests.forEach(g => g.disconnect())

  console.log(`\nRESULT: ${ok ? 'CONVERGED — all guests within ' + CONVERGE_SEC + 's' : 'DID NOT CONVERGE'}`)
  process.exit(ok ? 0 : 1)
}

main().catch(err => { console.error(err); process.exit(1) })
