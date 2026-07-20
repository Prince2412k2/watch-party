import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const databasePath = join(tmpdir(), `watchparty-teardown-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath

const { teardownBrowser } = await import('./teardown.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

function makeDeps({ recreateFailures = 0 } = {}) {
  const calls = []
  let leaseRow = { partyId: 'p1', hostName: 'Alice', state: 'active', leaseId: 'lease-1' }
  let sessions = [{ userId: 'u1', nekoSessionId: 'n1' }, { userId: 'u2', nekoSessionId: 'n2' }]
  let recreateAttempts = 0

  const lease = {
    getLease: () => (leaseRow ? { ...leaseRow } : null),
    beginCleaning: partyId => { calls.push('beginCleaning'); if (leaseRow && leaseRow.partyId === partyId) leaseRow = { ...leaseRow, state: 'cleaning' } },
    releaseLease: partyId => { calls.push('releaseLease'); if (leaseRow && leaseRow.partyId === partyId) leaseRow = null },
    sessionsFor: () => [...sessions],
    removeUserSession: (partyId, userId, nekoSessionId) => {
      calls.push(`removeUserSession:${nekoSessionId}`)
      sessions = sessions.filter(s => !(s.userId === userId && s.nekoSessionId === nekoSessionId))
    },
  }
  const admin = {
    deleteSession: async sessionId => { calls.push(`deleteSession:${sessionId}`) },
    resetControl: async () => { calls.push('resetControl') },
  }
  const container = {
    recreateContainer: async () => {
      recreateAttempts++
      calls.push('recreateContainer')
      if (recreateAttempts <= recreateFailures) throw new Error('recreate failed')
    },
    waitForHealthy: async () => { calls.push('waitForHealthy') },
  }
  const session = { id: 'p1', activity: 'remote-browser', stage: 'remote-browser' }
  const getSession = () => session
  const setBrowserActivity = (sess, on) => { calls.push(`setBrowserActivity:${on}`); sess.activity = on ? 'remote-browser' : 'none' }
  const persistSession = () => { calls.push('persistSession') }
  const emitState = async () => { calls.push('emitState') }

  return { calls, lease, admin, container, getSession, setBrowserActivity, persistSession, emitState, session, get recreateAttempts() { return recreateAttempts } }
}

test('teardown order: beginCleaning before release; sessions before recreate before release', async () => {
  const deps = makeDeps()
  await teardownBrowser('p1', { reason: 'stop', deps })

  const idx = name => deps.calls.indexOf(name)
  assert.ok(idx('beginCleaning') < idx('deleteSession:n1'))
  assert.ok(idx('deleteSession:n1') < idx('recreateContainer'))
  assert.ok(idx('recreateContainer') < idx('releaseLease'))
  assert.ok(idx('beginCleaning') < idx('releaseLease'))
  assert.equal(deps.lease.getLease(), null)
  assert.equal(deps.session.activity, 'none')
})

test('double-invoke runs the teardown exactly once (single-flight)', async () => {
  const deps = makeDeps()
  const [a, b] = [teardownBrowser('p1', { deps }), teardownBrowser('p1', { deps })]
  await Promise.all([a, b])
  const recreateCalls = deps.calls.filter(c => c === 'recreateContainer').length
  assert.equal(recreateCalls, 1)
})

test('no lease held is a no-op', async () => {
  const deps = makeDeps()
  deps.lease.getLease = () => null
  await teardownBrowser('p1', { deps })
  assert.deepEqual(deps.calls, [])
})

test('teardown from a starting lease works and does not wedge', async () => {
  const deps = makeDeps()
  deps.lease.getLease = () => ({ partyId: 'p1', hostName: 'Alice', state: 'starting', leaseId: 'lease-1' })
  const originalBeginCleaning = deps.lease.beginCleaning
  let released = false
  deps.lease.beginCleaning = partyId => { originalBeginCleaning(partyId); deps.lease.getLease = () => ({ partyId: 'p1', state: 'cleaning', leaseId: 'lease-1' }) }
  deps.lease.releaseLease = () => { released = true; deps.lease.getLease = () => null }

  await teardownBrowser('p1', { reason: 'start-rollback', deps })
  assert.equal(released, true)
  assert.equal(deps.lease.getLease(), null)
})

test('a failing recreate retries up to 3x then eventually surfaces and does not release the lease', async () => {
  const deps = makeDeps({ recreateFailures: 5 })
  await assert.rejects(teardownBrowser('p1', { deps }))
  const recreateCalls = deps.calls.filter(c => c === 'recreateContainer').length
  assert.equal(recreateCalls, 3)
  assert.notEqual(deps.calls.includes('releaseLease'), true)
})

test('a recreate that fails twice then succeeds completes teardown and releases', async () => {
  const deps = makeDeps({ recreateFailures: 2 })
  await teardownBrowser('p1', { deps })
  const recreateCalls = deps.calls.filter(c => c === 'recreateContainer').length
  assert.equal(recreateCalls, 3)
  assert.equal(deps.lease.getLease(), null)
})
