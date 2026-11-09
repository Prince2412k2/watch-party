import test from 'node:test'
import assert from 'node:assert/strict'
import { deadline } from './platform.ts'

test('panel startup cannot wait indefinitely for an extension message', async () => {
  const started = Date.now()
  await assert.rejects(deadline(new Promise(() => {}), 20, 'Startup timed out'), /Startup timed out/)
  assert.ok(Date.now() - started < 500)
})
test('an available worker response resolves normally', async () => {
  assert.deepEqual(await deadline(Promise.resolve({ setup: null, tabId: 8 }), 20), { setup: null, tabId: 8 })
})
test('initialization failures reach the UI instead of leaving a loading state', async () => {
  await assert.rejects(deadline(Promise.reject(new Error('Context invalidated')), 20), /Context invalidated/)
})
