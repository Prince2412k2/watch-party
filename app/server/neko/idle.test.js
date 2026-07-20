import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const databasePath = join(tmpdir(), `watchparty-idle-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath

const { startIdleMonitor } = await import('./idle.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

function makeDeps({ leaseId = 'lease-1', recorded = [{ userId: 'u1', nekoSessionId: 'n1' }], live = [], idleTimeoutMs = 1000 } = {}) {
  const calls = []
  const state = { leaseId, recorded, live, active: true, listSessionsError: null }
  const lease = {
    getLease: () => (state.active ? { partyId: 'p1', state: 'active', leaseId: state.leaseId } : null),
    sessionsFor: () => state.recorded.map(({ userId, nekoSessionId }) => ({ userId, nekoSessionId })),
  }
  const admin = {
    listSessions: async () => {
      calls.push('listSessions')
      if (state.listSessionsError) throw state.listSessionsError
      return state.live
    },
  }
  const teardownBrowser = async (partyId, opts) => { calls.push(`teardown:${partyId}:${opts.reason}`) }
  return { calls, state, deps: { admin, lease, teardownBrowser, idleTimeoutMs } }
}

test('zero viewers across the full idle window triggers teardown', async () => {
  const { calls, deps } = makeDeps({ live: [] })
  let t = 0
  const { tick } = startIdleMonitor({ now: () => t, deps })

  await tick() // idleSince = 0
  await tick() // t still 0, no teardown
  t = 500
  await tick() // 500ms elapsed, below 1000ms timeout
  assert.ok(!calls.some(c => c.startsWith('teardown')))
  t = 1200
  await tick() // >= 1000ms since idleSince → teardown
  assert.ok(calls.includes('teardown:p1:idle'))
})

test('a viewer reconnecting resets the idle timer', async () => {
  const { calls, deps, state } = makeDeps({ live: [] })
  let t = 0
  const { tick } = startIdleMonitor({ now: () => t, deps })

  await tick() // idleSince = 0
  t = 900
  state.live = [{ id: 'n1', isConnected: true, isWatching: true }]
  await tick() // viewer present → resets idleSince to null
  t = 1200
  state.live = []
  await tick() // only 300ms since reset (t=900 -> would need new idleSince)
  assert.ok(!calls.some(c => c.startsWith('teardown')))
  t = 2300 // idleSince was set to 1200 on the previous tick; 2300-1200 >= 1000
  await tick()
  assert.ok(calls.some(c => c.startsWith('teardown')))
})

test('a lease id change resets the idle timer', async () => {
  const { calls, deps, state } = makeDeps({ live: [] })
  let t = 0
  const { tick } = startIdleMonitor({ now: () => t, deps })

  await tick() // idleSince = 0 under lease-1
  t = 900
  state.leaseId = 'lease-2'
  await tick() // new lease → idleSince reset to 900
  t = 1200 // only 300ms since reset
  await tick()
  assert.ok(!calls.some(c => c.startsWith('teardown')))
  t = 1950 // >= 1000ms since 900
  await tick()
  assert.ok(calls.some(c => c.startsWith('teardown')))
})

test('a listSessions failure skips the tick and never counts as idle', async () => {
  const { calls, deps, state } = makeDeps({ live: [] })
  state.listSessionsError = new Error('network down')
  let t = 0
  const { tick } = startIdleMonitor({ now: () => t, deps })

  await tick()
  t = 5000
  await tick()
  assert.ok(!calls.some(c => c.startsWith('teardown')))
})

test('a restored lease (no start-via-C7) is monitored the same way', async () => {
  const { calls, deps } = makeDeps({ live: [] })
  let t = 0
  const { tick } = startIdleMonitor({ now: () => t, deps })
  await tick()
  t = 1500
  await tick()
  assert.ok(calls.some(c => c.startsWith('teardown')))
})

test('no active lease is a no-op', async () => {
  const { calls, deps, state } = makeDeps()
  state.active = false
  const { tick } = startIdleMonitor({ now: () => 0, deps })
  await tick()
  assert.deepEqual(calls, [])
})
