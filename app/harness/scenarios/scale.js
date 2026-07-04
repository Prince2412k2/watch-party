// Scale scenarios: 2, 5, 10 guests with mixed latencies, asymmetric send vs
// schedule delay, and per-message random jitter (stresses the min-RTT clock
// offset selection).

import { spawnHost, spawnGuest, startSampler, sleep, check, worstDrift } from './_helpers.js'

const LATENCIES = [0, 50, 150, 400, 800]

function guestOpts(i) {
  const base = LATENCIES[i % LATENCIES.length]
  return {
    name: `g${i + 1}(${base})`,
    // asymmetric: send delay != schedule delay, plus random jitter on both
    sendDelayMs: base,
    scheduleDelayMs: Math.round(base * 0.6),
    jitterMs: 60,
  }
}

async function runScale(SERVER, n, converge) {
  const { host, partyId } = await spawnHost(SERVER)
  const guests = []
  for (let i = 0; i < n; i++) guests.push(await spawnGuest(SERVER, host, partyId, guestOpts(i)))
  await sleep(2000) // let clocks converge under jitter

  const s = startSampler((id) => fetch(`${SERVER}/api/debug/session/${id}`).then(r => r.json()).then(j => j.schedule), partyId, guests)

  host.play(0)
  await sleep(6000)          // steady-state playing
  host.seek(300)
  await sleep(6000)          // converge to mid-position
  host.pause()
  await sleep(2500)

  const rows = s.stop()
  host.disconnect(); guests.forEach(g => g.disconnect())

  const playWorst = worstDrift(rows, 'playing', 3)
  const pausedWorst = worstDrift(rows, 'paused', 2)
  return {
    checks: [
      check(`${n} guests playing |drift|<${converge}s`, playWorst < converge, `worst=${playWorst.toFixed(3)}s`),
      check(`${n} guests paused frozen`, pausedWorst < converge, `worst=${pausedWorst.toFixed(3)}s`),
    ],
  }
}

export const scale2 = { name: 'scale-2-guests', run: (ctx) => runScale(ctx.SERVER, 2, 0.5) }
export const scale5 = { name: 'scale-5-guests', run: (ctx) => runScale(ctx.SERVER, 5, 0.5) }
export const scale10 = { name: 'scale-10-guests-jitter', run: (ctx) => runScale(ctx.SERVER, 10, 0.5) }
