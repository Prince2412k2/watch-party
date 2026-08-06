import test from 'node:test'
import assert from 'node:assert/strict'
import { analogTokens } from '../../design/analogTokens.ts'
import {
  holdControls,
  newAutoHideState,
  noteInput,
  releaseControls,
  setPlaying,
  tickAutoHide,
} from '../playerCore.ts'
import { CHROME_HOLD, autoHideDeadlineMs, hideNow, msUntilAutoHide } from './autoHideWiring.ts'

const TIMEOUT = analogTokens.timing.chromeAutoHideMs

test('the deadline is three seconds after the last relevant input', () => {
  const state = noteInput(newAutoHideState(0, true), 'pointer', 1200)
  assert.equal(autoHideDeadlineMs(state), 1200 + TIMEOUT)
  assert.equal(msUntilAutoHide(state, 1200), TIMEOUT)
  assert.equal(msUntilAutoHide(state, 1200 + TIMEOUT + 500), 0, 'overdue is due now, never negative')
})

test('a held or paused player arms no timer at all', () => {
  const held = holdControls(newAutoHideState(0, true), CHROME_HOLD.settings)
  assert.equal(autoHideDeadlineMs(held), null)
  assert.equal(msUntilAutoHide(held, 10_000), null)

  const paused = setPlaying(newAutoHideState(0, true), false, 0)
  assert.equal(autoHideDeadlineMs(paused), null)
  assert.equal(msUntilAutoHide(paused, 10_000), null)
})

test('already-hidden chrome needs no timer', () => {
  const hidden = tickAutoHide(newAutoHideState(0, true), TIMEOUT)
  assert.equal(hidden.visible, false)
  assert.equal(msUntilAutoHide(hidden, TIMEOUT), null)
})

test('tap-to-hide dismisses immediately and the next input restores the full wait', () => {
  const state = hideNow(newAutoHideState(0, true), 5_000)
  assert.equal(state.visible, false)
  const woken = noteInput(state, 'tap', 5_100)
  assert.equal(woken.visible, true)
  assert.equal(tickAutoHide(woken, 5_100 + TIMEOUT - 1).visible, true)
  assert.equal(tickAutoHide(woken, 5_100 + TIMEOUT).visible, false)
})

test('tap-to-hide still refuses while a hold is taken or playback is paused', () => {
  // The old Party.tsx toggle wrote `visible = false` directly, so a tap could
  // pull the chrome out from under an open menu. Routing it through the shared
  // rules is what makes that impossible.
  const held = holdControls(newAutoHideState(0, true), CHROME_HOLD.scrubbing)
  assert.equal(hideNow(held, 9_000).visible, true)
  const paused = setPlaying(newAutoHideState(0, true), false, 0)
  assert.equal(hideNow(paused, 9_000).visible, true)
})

test('releasing a hold grants the full three seconds, not the remainder', () => {
  let state = newAutoHideState(0, true)
  state = holdControls(state, CHROME_HOLD.settings)
  state = tickAutoHide(state, 20_000)
  assert.equal(state.visible, true, 'a menu never fades out from under the cursor')
  state = releaseControls(state, CHROME_HOLD.settings, 20_000)
  assert.equal(autoHideDeadlineMs(state), 20_000 + TIMEOUT)
  assert.equal(tickAutoHide(state, 20_000 + TIMEOUT - 1).visible, true)
  assert.equal(tickAutoHide(state, 20_000 + TIMEOUT).visible, false)
})

test('holds are named, so two of them cannot cancel each other', () => {
  let state = newAutoHideState(0, true)
  state = holdControls(state, CHROME_HOLD.settings)
  state = holdControls(state, CHROME_HOLD.scrubbing)
  state = releaseControls(state, CHROME_HOLD.scrubbing, 1_000)
  assert.deepEqual(state.holds, [CHROME_HOLD.settings])
  assert.equal(autoHideDeadlineMs(state), null, 'the settings hold still pins it open')
  state = releaseControls(state, CHROME_HOLD.settings, 1_000)
  assert.equal(autoHideDeadlineMs(state), 1_000 + TIMEOUT)
})

test('pausing pins the chrome open and resuming restarts the countdown', () => {
  let state = newAutoHideState(0, true)
  state = setPlaying(state, false, 500)
  assert.equal(tickAutoHide(state, 60_000).visible, true)
  state = setPlaying(state, true, 60_000)
  assert.equal(tickAutoHide(state, 60_000 + TIMEOUT - 1).visible, true)
  assert.equal(tickAutoHide(state, 60_000 + TIMEOUT).visible, false)
})
