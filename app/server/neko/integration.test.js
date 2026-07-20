// C17 — integration test against a REAL pinned Neko container.
//
// GATED: only runs when NEKO_IT=1 (default `node --test` skips it, so CI/unit
// runs never need Docker or a live Neko). Proves the real admin.js adapter
// against real Neko 3.1.4 — the mock-based admin.test.js cannot cover this.
//
// Fixture: docker-compose.neko.yml at the repo root (image pinned 3.1.4,
// NEKO_SESSION_API_TOKEN=spike-admin-api-token-000, user password `neko`,
// path_prefix=/neko). Bring it up before running:
//
//   docker compose -f docker-compose.neko.yml up -d
//   # then, because published ports may not be reachable from the test host
//   # (e.g. inside a container), point NEKO_IT_URL at a reachable base. When
//   # running ON the docker host: http://localhost:9876/neko
//   NEKO_IT=1 NEKO_IT_URL=http://localhost:9876/neko \
//     node --test app/server/neko/integration.test.js
//
// Live-verified interactively 2026-07-20 (see docs/specs/2026-07-20-neko-spike-decision.md):
// loginViewer (no password leak), listSessions field mapping, setControlLock,
// giveControl, controlStatus {has_host,host_id} mapping, resetControl,
// deleteSession (count decrements). Container-recreate isolation (SC-006) and
// non-controller input rejection (SC-008 input half) require a real browser and
// remain a manual acceptance step, documented in the decision record.

import { test } from 'node:test'
import assert from 'node:assert/strict'

const RUN = process.env.NEKO_IT === '1'
const base = process.env.NEKO_IT_URL || 'http://localhost:9876/neko'
const cfg = {
  internalUrl: base,
  apiToken: process.env.NEKO_IT_TOKEN || 'spike-admin-api-token-000',
  userPassword: process.env.NEKO_IT_PASSWORD || 'neko',
}

test('live admin adapter round-trip against pinned Neko', { skip: !RUN && 'set NEKO_IT=1 with a running docker-compose.neko.yml' }, async () => {
  const admin = await import('./admin.js')

  const viewer = await admin.loginViewer('it-viewer', cfg)
  assert.ok(viewer.sessionId, 'loginViewer returns a sessionId')
  assert.ok(viewer.cookie, 'loginViewer returns a Set-Cookie value')
  assert.ok(!JSON.stringify(viewer).includes(cfg.userPassword), 'no password in loginViewer output')

  const sessions = await admin.listSessions(cfg)
  assert.ok(Array.isArray(sessions), 'listSessions returns an array')
  const mine = sessions.find(s => s.id === viewer.sessionId)
  assert.ok(mine, 'the new session appears in listSessions')
  assert.equal(typeof mine.isConnected, 'boolean')
  assert.equal(typeof mine.isWatching, 'boolean')

  await admin.setControlLock(true, cfg)
  await admin.giveControl(viewer.sessionId, cfg)
  const status = await admin.controlStatus(cfg)
  assert.equal(status.hasHost, true)
  assert.equal(status.hostSessionId, viewer.sessionId, 'controlStatus maps host_id to our session')

  await admin.resetControl(cfg)
  const cleared = await admin.controlStatus(cfg)
  assert.equal(cleared.hasHost, false, 'resetControl clears the host')

  const before = (await admin.listSessions(cfg)).length
  await admin.deleteSession(viewer.sessionId, cfg)
  const after = (await admin.listSessions(cfg)).length
  assert.ok(after < before, 'deleteSession removes the session')
})
