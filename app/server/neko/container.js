import { execFile } from 'node:child_process'
import { nekoConfig } from './config.js'

function defaultRunner(config) {
  return new Promise((resolve, reject) => {
    execFile('ssh', [
      '-i', config.sshKeyPath,
      '-o', 'StrictHostKeyChecking=yes',
      '-o', 'BatchMode=yes',
      '-o', 'ConnectTimeout=10',
      `neko-recreate@${config.sshHost}`,
    ], { timeout: 45_000 }, (error) => {
      if (error) reject(new Error(`neko container recreate failed: ${error.message}`))
      else resolve()
    })
  })
}

export async function recreateContainer({ runner } = {}) {
  const config = nekoConfig()
  const run = runner || (() => defaultRunner(config))
  await run(config)
}

function defaultFetch(...args) {
  return fetch(...args)
}

// A0 spike (docs/specs/2026-07-20-neko-spike-decision.md) did not confirm a working
// /api/health endpoint (observed 404 in 3.1.4); poll the root path instead, which the
// spike confirmed returns 200 when the path-prefix-configured server is up.
export async function waitForHealthy({ timeoutMs = 30_000, poll, fetchImpl = defaultFetch } = {}) {
  const config = nekoConfig()
  const deadline = Date.now() + timeoutMs
  const pollFn = poll || (async () => {
    const response = await fetchImpl(config.internalUrl + '/')
    return response.status === 200
  })

  while (Date.now() < deadline) {
    let healthy = false
    try {
      healthy = await pollFn()
    } catch {
      healthy = false
    }
    if (healthy) return
    await new Promise(resolve => setTimeout(resolve, 200))
  }
  throw new Error('neko container: waitForHealthy timed out')
}
