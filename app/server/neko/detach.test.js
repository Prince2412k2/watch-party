import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const databasePath = join(tmpdir(), `watchparty-detach-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath

const { detachMember } = await import('./detach.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

function makeDeps({ leaseState = 'active', sessions = [], wasController = false, deleteError = null } = {}) {
  const calls = []
  let mapped = [...sessions]
  const lease = {
    getLease: () => ({ partyId: 'p1', state: leaseState, leaseId: 'lease-1' }),
    sessionsForUser: (partyId, userId) => {
      calls.push('sessionsForUser')
      return mapped.filter(s => s.userId === userId).map(({ nekoSessionId }) => ({ nekoSessionId }))
    },
    removeUserSession: (partyId, userId, nekoSessionId) => {
      calls.push(`removeUserSession:${nekoSessionId}`)
      mapped = mapped.filter(s => !(s.userId === userId && s.nekoSessionId === nekoSessionId))
    },
  }
  const admin = {
    deleteSession: async (sessionId) => {
      calls.push(`deleteSession:${sessionId}`)
      if (deleteError) throw deleteError
    },
    resetControl: async () => { calls.push('resetControl') },
  }
  const controller = {
    isController: async () => { calls.push('isController'); return wasController },
  }
  let broadcasted = null
  const broadcast = (payload) => { calls.push('broadcast'); broadcasted = payload }
  return { calls, lease, admin, controller, broadcast, get mapped() { return mapped }, get broadcasted() { return broadcasted } }
}

test('no active lease is a no-op', async () => {
  const deps = makeDeps({ leaseState: 'cleaning', sessions: [{ userId: 'u1', nekoSessionId: 'n1' }] })
  await detachMember('p1', 'u1', { deps })
  assert.deepEqual(deps.calls, [])
})

test('no mapped sessions and not controller is a no-op', async () => {
  const deps = makeDeps({ sessions: [] })
  await detachMember('p1', 'u1', { deps })
  assert.deepEqual(deps.calls, ['isController', 'sessionsForUser'])
})

test('deletes exactly the departing user\'s sessions, leaves others', async () => {
  const deps = makeDeps({ sessions: [{ userId: 'u1', nekoSessionId: 'n1' }, { userId: 'u2', nekoSessionId: 'n2' }] })
  await detachMember('p1', 'u1', { deps })
  assert.ok(deps.calls.includes('deleteSession:n1'))
  assert.ok(!deps.calls.includes('deleteSession:n2'))
  assert.deepEqual(deps.mapped, [{ userId: 'u2', nekoSessionId: 'n2' }])
})

test('controller status is read before mappings are dropped', async () => {
  const deps = makeDeps({ sessions: [{ userId: 'u1', nekoSessionId: 'n1' }], wasController: true })
  await detachMember('p1', 'u1', { deps })
  const idx = name => deps.calls.indexOf(name)
  assert.ok(idx('isController') < idx('removeUserSession:n1'))
})

test('a failed delete leaves the mapping recorded for retry (no orphan)', async () => {
  const deps = makeDeps({ sessions: [{ userId: 'u1', nekoSessionId: 'n1' }], deleteError: new Error('neko admin: deleteSession failed with status 500') })
  await detachMember('p1', 'u1', { deps })
  assert.deepEqual(deps.mapped, [{ userId: 'u1', nekoSessionId: 'n1' }])
})

test('a 404 delete failure is treated as already-gone and drops the mapping', async () => {
  const deps = makeDeps({ sessions: [{ userId: 'u1', nekoSessionId: 'n1' }], deleteError: new Error('neko admin: deleteSession failed with status 404') })
  await detachMember('p1', 'u1', { deps })
  assert.deepEqual(deps.mapped, [])
})

test('resets control only when the departing user held it', async () => {
  const deps = makeDeps({ sessions: [{ userId: 'u1', nekoSessionId: 'n1' }], wasController: false })
  await detachMember('p1', 'u1', { deps })
  assert.ok(!deps.calls.includes('resetControl'))
  assert.equal(deps.broadcasted, null)
})

test('resets control and broadcasts null when the departing user held control', async () => {
  const deps = makeDeps({ sessions: [{ userId: 'u1', nekoSessionId: 'n1' }], wasController: true })
  await detachMember('p1', 'u1', { deps })
  assert.ok(deps.calls.includes('resetControl'))
  assert.deepEqual(deps.broadcasted, { controllerUserId: null })
})
