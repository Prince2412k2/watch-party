import test from 'node:test'
import assert from 'node:assert/strict'

process.env.NEKO_INTERNAL_URL = process.env.NEKO_INTERNAL_URL || 'http://neko.internal:8080'

const { recreateContainer, waitForHealthy } = await import('./container.js')

test('recreateContainer calls the injected runner exactly once', async () => {
  let calls = 0
  const runner = async () => { calls += 1 }
  await recreateContainer({ runner })
  assert.equal(calls, 1)
})

test('recreateContainer rejects when the runner fails', async () => {
  const runner = async () => { throw new Error('ssh exited 1') }
  await assert.rejects(recreateContainer({ runner }), /ssh exited 1/)
})

test('recreateContainer in noop mode resolves without calling the runner', async () => {
  const saved = process.env.NEKO_RECREATE_MODE
  process.env.NEKO_RECREATE_MODE = 'noop'
  try {
    let calls = 0
    const runner = async () => { calls += 1 }
    await recreateContainer({ runner })
    assert.equal(calls, 0)
  } finally {
    if (saved === undefined) delete process.env.NEKO_RECREATE_MODE
    else process.env.NEKO_RECREATE_MODE = saved
  }
})

test('waitForHealthy resolves on first successful poll', async () => {
  let calls = 0
  const poll = async () => { calls += 1; return true }
  await waitForHealthy({ timeoutMs: 1000, poll })
  assert.equal(calls, 1)
})

test('waitForHealthy rejects on timeout when poll never succeeds', async () => {
  const poll = async () => false
  await assert.rejects(waitForHealthy({ timeoutMs: 300, poll }), /timed out/)
})
