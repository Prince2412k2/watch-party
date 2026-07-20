import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const databasePath = join(tmpdir(), `watchparty-controller-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath

const { currentController, isController } = await import('./controller.js')

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (error) {
      if (error.code !== 'ENOENT') throw error
    }
  }
})

test('currentController maps the Neko host session to a Watchparty user', async () => {
  const deps = {
    controlStatus: async () => ({ hasHost: true, hostSessionId: 'neko-sess-1' }),
    controllerUserFor: sessionId => (sessionId === 'neko-sess-1' ? 'user-1' : null),
  }
  const result = await currentController('party-1', deps)
  assert.deepEqual(result, { userId: 'user-1', nekoSessionId: 'neko-sess-1' })
})

test('currentController returns null when Neko reports no host', async () => {
  const deps = {
    controlStatus: async () => ({ hasHost: false, hostSessionId: null }),
    controllerUserFor: () => { throw new Error('should not be called') },
  }
  const result = await currentController('party-1', deps)
  assert.equal(result, null)
})

test('currentController returns null when the host session has no mapped user', async () => {
  const deps = {
    controlStatus: async () => ({ hasHost: true, hostSessionId: 'neko-sess-orphan' }),
    controllerUserFor: () => null,
  }
  const result = await currentController('party-1', deps)
  assert.equal(result, null)
})

test('isController is true only for the mapped controller user', async () => {
  const deps = {
    controlStatus: async () => ({ hasHost: true, hostSessionId: 'neko-sess-1' }),
    controllerUserFor: () => 'user-1',
  }
  assert.equal(await isController('party-1', 'user-1', deps), true)
  assert.equal(await isController('party-1', 'user-2', deps), false)
})

test('isController is false when no one holds control', async () => {
  const deps = {
    controlStatus: async () => ({ hasHost: false, hostSessionId: null }),
    controllerUserFor: () => { throw new Error('should not be called') },
  }
  assert.equal(await isController('party-1', 'user-1', deps), false)
})
