import test from 'node:test'
import assert from 'node:assert/strict'
import { createLifecycleRun, isAbortError } from './liveKitLifecycle.ts'

function fakeRoom(name: string) {
  return { name, disconnects: 0, disconnect() { this.disconnects += 1 } }
}
type FakeRoom = ReturnType<typeof fakeRoom>

const newRun = () => createLifecycleRun<FakeRoom>({ dispose: room => room.disconnect() })

test('a run that finishes normally owns its room and leaves it connected', () => {
  const run = newRun()
  const room = fakeRoom('a')

  assert.equal(run.adopt(room), true)
  assert.equal(run.resource, room)
  assert.equal(room.disconnects, 0)
  assert.equal(run.cancelled, false)
  assert.equal(run.signal.aborted, false)
})

test('cancelling aborts the token request and disconnects the adopted room', () => {
  const run = newRun()
  const room = fakeRoom('a')
  run.adopt(room)

  run.cancel()

  assert.equal(run.signal.aborted, true, 'the in-flight /api/livekit/token fetch must be aborted')
  assert.equal(room.disconnects, 1)
  assert.equal(run.cancelled, true)
})

test('a room created after teardown is disposed instead of published', () => {
  // The token fetch resolved after the effect cleanup ran: the old code built a
  // Room here, assigned it to roomRef and connected it — a live WebRTC session
  // with no owner, holding the camera, on top of whatever room came next.
  const run = newRun()
  run.cancel()
  const late = fakeRoom('late')

  assert.equal(run.adopt(late), false, 'the caller must be told to stop')
  assert.equal(late.disconnects, 1, 'the late room must not be left connected')
  assert.equal(run.resource, null, 'and must never become the published room')
})

test('cancelling twice disconnects once', () => {
  const run = newRun()
  const room = fakeRoom('a')
  run.adopt(room)

  run.cancel()
  run.cancel()

  assert.equal(room.disconnects, 1)
})

test('cancelling a run that never got a room is harmless', () => {
  const run = newRun()
  run.cancel()
  assert.equal(run.resource, null)
  assert.equal(run.signal.aborted, true)
})

test('a stale run cannot replace the room a newer run published', () => {
  // Party switch: run 1 is still awaiting its token when run 2 wins. Ownership
  // lives on the run, so the identity check in the cleanup keeps run 1 from
  // nulling out (or overwriting) run 2's room.
  const stale = newRun()
  const fresh = newRun()
  const published: { current: FakeRoom | null } = { current: null }

  const winner = fakeRoom('fresh')
  fresh.adopt(winner)
  published.current = winner

  // run 1's cleanup, running after run 2 published.
  const owned = stale.resource
  stale.cancel()
  if (published.current === owned) published.current = null

  assert.equal(published.current, winner)
  assert.equal(winner.disconnects, 0)

  // run 1's token finally resolves.
  const loser = fakeRoom('stale')
  assert.equal(stale.adopt(loser), false)
  assert.equal(loser.disconnects, 1)
  assert.equal(published.current, winner)
})

test('an aborted fetch is recognised so teardown never shows an error banner', () => {
  assert.equal(isAbortError(new DOMException('Aborted', 'AbortError')), true)
  assert.equal(isAbortError({ name: 'AbortError' }), true)
  assert.equal(isAbortError(new Error('Failed to get LiveKit token')), false)
  assert.equal(isAbortError(null), false)
  assert.equal(isAbortError('AbortError'), false)
})
