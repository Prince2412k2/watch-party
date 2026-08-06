import test from 'node:test'
import assert from 'node:assert/strict'
import {
  MIN_RESTORE_VOLUME,
  VOLUME_STEP,
  clampVolume,
  newVolumeState,
  renderedLevel,
  setVolume,
  stepVolume,
  toggleMute,
  volumeFromPointer,
  volumePercent,
} from './volumeCore.ts'

test('levels are clamped into 0..1', () => {
  assert.equal(clampVolume(-2), 0)
  assert.equal(clampVolume(1.4), 1)
  assert.equal(clampVolume(Number.NaN), 0)
  assert.equal(clampVolume(0.37), 0.37)
})

test('dragging above zero unmutes and dragging to zero mutes', () => {
  let state = newVolumeState(0.8)
  state = setVolume(state, 0)
  assert.deepEqual(state, { volume: 0, muted: true, restoreVolume: 0.8 })
  state = setVolume(state, 0.3)
  assert.deepEqual(state, { volume: 0.3, muted: false, restoreVolume: 0.3 })
})

test('unmute restores the previous volume rather than silence', () => {
  // The whole point of previous-volume restore: dragging to zero and pressing
  // the mute button again must not leave the user on a silent player.
  let state = setVolume(newVolumeState(0.6), 0)
  state = toggleMute(state)
  assert.equal(state.muted, false)
  assert.equal(state.volume, 0.6)
})

test('unmute from a never-set level still produces audible sound', () => {
  const state = toggleMute({ volume: 0, muted: true, restoreVolume: 0 })
  assert.equal(state.muted, false)
  assert.ok(state.volume >= MIN_RESTORE_VOLUME)
})

test('mute leaves the level alone so unmute is exact', () => {
  const muted = toggleMute(newVolumeState(0.45))
  assert.deepEqual(muted, { volume: 0.45, muted: true, restoreVolume: 0.45 })
  assert.deepEqual(toggleMute(muted), { volume: 0.45, muted: false, restoreVolume: 0.45 })
})

test('raising the volume with the keyboard force-unmutes', () => {
  // The existing ↑ binding sets muted = false as well as raising the level;
  // without that, ↑ while muted does nothing audible at all.
  const state = stepVolume({ volume: 0.2, muted: true, restoreVolume: 0.2 }, VOLUME_STEP)
  assert.equal(state.muted, false)
  assert.ok(Math.abs(state.volume - 0.3) < 1e-9)
})

test('lowering to zero does not latch a mute the user never asked for', () => {
  // ↓ matches the existing binding, which only ever wrote media.volume.
  const state = stepVolume(newVolumeState(0.05), -VOLUME_STEP)
  assert.equal(state.volume, 0)
  assert.equal(state.muted, false)
  assert.equal(state.restoreVolume, 0.05)
})

test('a muted control reads as empty, not as its stored level', () => {
  const state = toggleMute(newVolumeState(0.7))
  assert.equal(renderedLevel(state), 0)
  assert.equal(volumePercent(state), 0)
  assert.equal(renderedLevel(toggleMute(state)), 0.7)
})

test('the vertical track reads top as loud and bottom as silent', () => {
  const rect = { top: 100, height: 200 }
  assert.equal(volumeFromPointer(100, rect), 1)
  assert.equal(volumeFromPointer(300, rect), 0)
  assert.equal(volumeFromPointer(200, rect), 0.5)
  assert.equal(volumeFromPointer(-500, rect), 1)
  assert.equal(volumeFromPointer(9999, rect), 0)
  assert.equal(volumeFromPointer(150, { top: 0, height: 0 }), 0)
})
