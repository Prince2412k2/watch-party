import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const databasePath = join(tmpdir(), `watchparty-lease-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath

let lease = await import('./lease.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

test.beforeEach(() => {
  const row = lease.getLease()
  if (row) {
    lease.beginCleaning(row.partyId)
    lease.releaseLease(row.partyId)
  }
})

test('acquire when free succeeds', () => {
  const result = lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  assert.equal(result.ok, true)
  assert.ok(result.leaseId)
  assert.equal(lease.getLease().state, 'starting')
})

test('second acquire while held fails with holder name', () => {
  lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  const result = lease.acquireLease({ partyId: 'p2', hostName: 'Bob' })
  assert.deepEqual(result, { ok: false, hostName: 'Alice' })
})

test('beginCleaning works from starting and active', () => {
  lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.beginCleaning('p1')
  assert.equal(lease.getLease().state, 'cleaning')

  lease.releaseLease('p1')
  lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.markActive('p1')
  assert.equal(lease.getLease().state, 'active')
  lease.beginCleaning('p1')
  assert.equal(lease.getLease().state, 'cleaning')
  // idempotent
  lease.beginCleaning('p1')
  assert.equal(lease.getLease().state, 'cleaning')
})

test('releaseLease clears the row', () => {
  lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.beginCleaning('p1')
  lease.releaseLease('p1')
  assert.equal(lease.getLease(), null)
})

test('release then reacquire yields a different leaseId, including across simulated restart', async () => {
  const first = lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.beginCleaning('p1')
  lease.releaseLease('p1')

  // simulate process restart by reloading the module against the same DB path
  lease = await import(`./lease.js?reload=${Date.now()}`)

  const second = lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  assert.notEqual(first.leaseId, second.leaseId)
  lease.beginCleaning('p1')
  lease.releaseLease('p1')
})

test('stale leaseId recordUserSession is ignored', () => {
  const { leaseId } = lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.recordUserSession('p1', 'stale-lease-id', 'user1', 'neko-sess-1')
  assert.deepEqual(lease.sessionsForUser('p1', 'user1'), [])
  lease.recordUserSession('p1', leaseId, 'user1', 'neko-sess-1')
  assert.deepEqual(lease.sessionsForUser('p1', 'user1'), [{ nekoSessionId: 'neko-sess-1' }])
})

test('sessionsForUser reads without dropping, removeUserSession drops one', () => {
  const { leaseId } = lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.recordUserSession('p1', leaseId, 'user1', 'neko-sess-1')
  lease.recordUserSession('p1', leaseId, 'user1', 'neko-sess-2')
  lease.recordUserSession('p1', leaseId, 'user2', 'neko-sess-3')

  assert.deepEqual(
    lease.sessionsForUser('p1', 'user1').sort((a, b) => a.nekoSessionId.localeCompare(b.nekoSessionId)),
    [{ nekoSessionId: 'neko-sess-1' }, { nekoSessionId: 'neko-sess-2' }],
  )
  // read does not drop
  assert.equal(lease.sessionsForUser('p1', 'user1').length, 2)

  lease.removeUserSession('p1', 'user1', 'neko-sess-1')
  assert.deepEqual(lease.sessionsForUser('p1', 'user1'), [{ nekoSessionId: 'neko-sess-2' }])

  assert.deepEqual(
    lease.sessionsFor('p1').sort((a, b) => a.nekoSessionId.localeCompare(b.nekoSessionId)),
    [{ userId: 'user1', nekoSessionId: 'neko-sess-2' }, { userId: 'user2', nekoSessionId: 'neko-sess-3' }],
  )

  assert.equal(lease.controllerUserFor('neko-sess-3'), 'user2')
  assert.equal(lease.controllerUserFor('missing'), null)
})

test('reconcile clears a starting lease', async () => {
  lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  let tornDown = null
  const result = await lease.reconcileLease({ teardown: async partyId => { tornDown = partyId } })
  assert.equal(result, null)
  assert.equal(tornDown, 'p1')
  assert.equal(lease.getLease(), null)
})

test('reconcile clears a dangling lease (no live party)', async () => {
  const { leaseId } = lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.markActive('p1')
  lease.recordUserSession('p1', leaseId, 'user1', 'neko-sess-1')
  let tornDown = null
  const result = await lease.reconcileLease({
    hasLiveParty: () => false,
    teardown: async partyId => { tornDown = partyId },
  })
  assert.equal(result, null)
  assert.equal(tornDown, 'p1')
  assert.equal(lease.getLease(), null)
})

test('reconcile keeps a valid active lease', async () => {
  const { leaseId } = lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.markActive('p1')
  lease.recordUserSession('p1', leaseId, 'user1', 'neko-sess-1')
  const result = await lease.reconcileLease({
    hasLiveParty: () => true,
    listSessions: async () => [{ id: 'neko-sess-1' }],
    teardown: async () => { throw new Error('should not be called') },
  })
  assert.ok(result)
  assert.equal(result.state, 'active')
  assert.equal(lease.getLease().state, 'active')
})

test('reconcile clears an active lease with mismatched recorded sessions', async () => {
  const { leaseId } = lease.acquireLease({ partyId: 'p1', hostName: 'Alice' })
  lease.markActive('p1')
  lease.recordUserSession('p1', leaseId, 'user1', 'neko-sess-1')
  let tornDown = null
  const result = await lease.reconcileLease({
    hasLiveParty: () => true,
    listSessions: async () => [],
    teardown: async partyId => { tornDown = partyId },
  })
  assert.equal(result, null)
  assert.equal(tornDown, 'p1')
})
