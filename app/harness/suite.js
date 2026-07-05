// Comprehensive sync test suite runner.
//   cd app && WP_TEST_MODE=1 PORT=3999 node server/index.js &
//   WP_SERVER=http://localhost:3999 node harness/suite.js
//
// Runs every named scenario sequentially against the shared-timeline server,
// samples drift, asserts convergence, and prints a per-scenario PASS/FAIL
// matrix. Exit 0 iff every scenario passes.
//
// Filter: WP_ONLY=host-jump-to-middle,late-joiner  runs just those.

import { scale2, scale5, scale10 } from './scenarios/scale.js'
import { jumpMiddle, jumpBackward, scrubStorm, seekPausedThenPlay, playPauseSeek } from './scenarios/hostjump.js'
import { playPauseStorm, playPauseStormEndPlay, lateJoiner, modeSwitch, staleScheduleVersionRejected } from './scenarios/state.js'
import { singleStall, multiStall, deadClientDisconnect } from './scenarios/dragging.js'
import { clockSkew, hostMigration, longRun, qualityTierReauthor } from './scenarios/advanced.js'
import { chaseLoopHostJump, chaseLoopLateJoin, pausedFrameBuffers, pausedLateJoinerUsesBufferedCatchup, pausedCatchupAbortsOnHostResume } from './scenarios/hls.js'
import { guestCannotDrive } from './scenarios/permission.js'
import { softCorrectionHysteresis } from './scenarios/hysteresis.js'

const SERVER = process.env.WP_SERVER || 'http://localhost:3999'

const ALL = [
  scale2, scale5, scale10,
  jumpMiddle, jumpBackward, scrubStorm, seekPausedThenPlay, playPauseSeek,
  playPauseStorm, playPauseStormEndPlay, lateJoiner, modeSwitch,
  singleStall, multiStall, deadClientDisconnect,
  clockSkew, hostMigration, longRun, qualityTierReauthor,
  chaseLoopHostJump, chaseLoopLateJoin, pausedFrameBuffers,
  guestCannotDrive,
  pausedLateJoinerUsesBufferedCatchup, pausedCatchupAbortsOnHostResume,
  staleScheduleVersionRejected, softCorrectionHysteresis,
]

async function main() {
  const only = (process.env.WP_ONLY || '').split(',').map(s => s.trim()).filter(Boolean)
  const scenarios = only.length ? ALL.filter(s => only.includes(s.name)) : ALL

  // sanity: server reachable + test mode on
  const health = await fetch(`${SERVER}/api/debug/sessions`).catch(() => null)
  if (!health || !health.ok) {
    console.error(`Cannot reach ${SERVER}/api/debug/sessions — is the test server up with WP_TEST_MODE=1?`)
    process.exit(2)
  }

  const results = []
  for (const sc of scenarios) {
    process.stdout.write(`\n=== ${sc.name} ===\n`)
    const start = Date.now()
    let res
    try {
      res = await sc.run({ SERVER })
    } catch (err) {
      res = { checks: [{ label: 'threw', pass: false, detail: err.message }], error: err }
      console.error(err)
    }
    const secs = ((Date.now() - start) / 1000).toFixed(1)
    const pass = res.checks.every(c => c.pass)
    for (const c of res.checks) {
      console.log(`   [${c.pass ? 'PASS' : 'FAIL'}] ${c.label}${c.detail ? '  (' + c.detail + ')' : ''}`)
    }
    for (const n of res.notes || []) console.log(`   note: ${n}`)
    results.push({ name: sc.name, pass, checks: res.checks, secs, notes: res.notes || [] })
    // brief gap so socket teardown + session GC settle between scenarios
    await new Promise(r => setTimeout(r, 400))
  }

  // ── Matrix ────────────────────────────────────────────────────────────────
  console.log('\n\n========================= PASS/FAIL MATRIX =========================')
  const nameW = Math.max(...results.map(r => r.name.length), 8)
  for (const r of results) {
    const nChecks = r.checks.length
    const nPass = r.checks.filter(c => c.pass).length
    console.log(`${r.pass ? 'PASS' : 'FAIL'}  ${r.name.padEnd(nameW)}  ${String(nPass) + '/' + nChecks} checks  ${r.secs}s`)
  }
  console.log('====================================================================')
  const failed = results.filter(r => !r.pass)
  const total = results.length
  console.log(`\n${total - failed.length}/${total} scenarios PASS`)
  if (failed.length) {
    console.log(`FAILED: ${failed.map(f => f.name).join(', ')}`)
  }
  process.exit(failed.length ? 1 : 0)
}

main().catch(err => { console.error(err); process.exit(1) })
