// Permission / host-authority enforcement.
//
// A NON-controlling guest (collaborativeControl = false) must not be able to
// drive the shared timeline. This exercises the SERVER authority layer: the
// harness guest bypasses the browser's client-side canControl gate and emits
// sync:play / sync:seek / sync:pause directly, plus locally mutates its own
// VirtualPlayer (simulating an illicit UI action). We then assert:
//
//   1. the server schedule is byte-for-byte UNCHANGED by the guest's commands
//      (canDrive rejects them before any mutation — no setSchedule, no version
//      bump), and
//   2. the guest is SNAPPED BACK: its local player re-converges to the shared
//      timeline within a couple of control ticks (the correction loop reconciles
//      every guest to the schedule regardless of who tried to author).
//
// Then a POSITIVE control: the host flips collaborativeControl ON and the SAME
// guest's seek now DOES take effect (version bumps, everyone lands on the new
// target) — proving the gate is a real authority check, not a blanket "ignore
// all guests".
//
// NOTE: the browser also has four client-side defenses (VideoSkin pointerEvents,
// keyboard transport gate, double-tap seek gate, useSyncPlay.requestX canControl
// gate). Those are pure DOM/React gating and cannot be exercised headlessly — the
// harness deliberately drives the SERVER layer, which is the real enforcement.

import {
  spawnHost, spawnGuest, startSampler, sleep, check, worstDrift,
  makeFetchSchedule, makeFetchView, idealPosition, TICKS,
} from './_helpers.js'

const sameSchedule = (a, b) =>
  a.version === b.version && a.positionTicks === b.positionTicks &&
  a.t0 === b.t0 && a.phase === b.phase && a.paused === b.paused

export const guestCannotDrive = {
  name: 'guest-cannot-drive',
  async run({ SERVER }) {
    const fetchSchedule = makeFetchSchedule(SERVER)
    const fetchView = makeFetchView(SERVER)
    const { host, partyId } = await spawnHost(SERVER)
    // Non-controlling guest: collaborativeControl defaults false on the server.
    const guest = await spawnGuest(SERVER, host, partyId, { name: 'guest', sendDelayMs: 50, scheduleDelayMs: 50 })
    await sleep(1500)              // clocks converge

    host.play(0)                   // host authors: playing from 0
    await sleep(2000)              // guest locks onto the timeline

    const checks = []

    // ── 1. Illicit drive attempts by the non-controlling guest ────────────────
    const before = await fetchSchedule(partyId)
    // Simulate the illicit UI action locally AND fire the socket commands the
    // browser would have gated away.
    guest.player.pause()
    guest.player.currentTime = 999
    guest.seek(999)
    guest.pause(999)
    guest.play(999)
    guest.seek(12)
    await sleep(700)               // let the server process (and reject) them

    const after = await fetchSchedule(partyId)
    checks.push(check(
      'server schedule unaffected by non-driver commands',
      sameSchedule(before, after),
      `before{v:${before.version},pos:${(before.positionTicks / TICKS).toFixed(1)},ph:${before.phase}} after{v:${after.version},pos:${(after.positionTicks / TICKS).toFixed(1)},ph:${after.phase}}`,
    ))

    // ── 2. Guest is snapped back onto the shared timeline ─────────────────────
    const s = startSampler(fetchSchedule, partyId, [guest])
    await sleep(2500)              // correction loop reconciles the guest
    const rows = s.stop()
    const worst = worstDrift(rows, 'playing', 4)
    const last = rows[rows.length - 1]
    const guestPos = last.positions[0]
    checks.push(check('guest re-converges to host timeline', worst < 0.6, `worst=${worst.toFixed(3)}s`))
    checks.push(check('guest not stuck at illicit position', guestPos > 1 && guestPos < 60, `guestPos=${guestPos.toFixed(1)}s`))
    checks.push(check('guest is playing again (illicit pause overridden)', !guest.player.paused, `paused=${guest.player.paused}`))

    // ── 3. Positive control: with collaborative ON the SAME guest CAN drive ───
    await host.setCollaborative(true)
    await sleep(400)
    const preCollab = await fetchSchedule(partyId)
    guest.seek(300)                // now allowed → should author the timeline
    await sleep(2500)
    const view = await fetchView(partyId)
    const postCollab = view.schedule
    const schedPos = postCollab.positionTicks / TICKS
    checks.push(check(
      'collaborative guest CAN author (schedule advanced)',
      postCollab.version > preCollab.version && Math.abs(schedPos - 300) < 5,
      `preV=${preCollab.version} postV=${postCollab.version} schedPos=${schedPos.toFixed(1)}`,
    ))
    const ideal = idealPosition(postCollab)
    checks.push(check('group lands on collaborative seek target ~300',
      Math.abs(guest.player.currentTime - ideal) < 0.6 && guest.player.currentTime > 295,
      `guestPos=${guest.player.currentTime.toFixed(1)} ideal=${ideal.toFixed(1)}`))

    host.disconnect(); guest.disconnect()
    return { checks, notes: [
      'Drives the SERVER authority layer (canDrive). The browser also gates transport client-side (pointerEvents / keyboard / double-tap / requestX) — DOM-only, not covered headlessly.',
    ] }
  },
}
