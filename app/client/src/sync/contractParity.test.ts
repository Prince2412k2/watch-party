// The React client's half of the cross-language wire contract.
//
// app/shared/contracts/ holds canonical JSON for the two things the React and
// Flutter clients each implement independently: the sync decision core and the
// socket vocabulary. This file drives the React implementation from those
// fixtures; flutter_app/test/sync/contract_parity_test.dart drives the Dart
// port from the same bytes. Changing one client's understanding of a payload
// means changing the fixture, and changing the fixture fails the other client.
//
// See app/shared/contracts/README.md.

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { decideSyncAction, predictPosition, type SyncIntent, type SyncSchedule } from './syncCore.ts'
import * as core from './syncCore.ts'

const read = (name: string) =>
  JSON.parse(readFileSync(new URL(`../../../shared/contracts/${name}`, import.meta.url), 'utf8'))

const syncContract = read('sync-core.json')
const eventContract = read('socket-events.json')

const EPSILON = 1e-9

/** Both languages compare through this shape, so the fixture pins semantics
 *  rather than either language's way of spelling "field not set". */
interface NormalizedIntent {
  seekTo: number | null
  rate: number | null
  play: boolean
  pause: boolean
  hardSeek: boolean
  pausedSeek: boolean
  drift: number | null
}

function normalize(intent: SyncIntent | null): NormalizedIntent | null {
  if (!intent) return null
  return {
    seekTo: intent.seekTo ?? null,
    rate: intent.rate ?? null,
    play: intent.play === true,
    pause: intent.pause === true,
    hardSeek: intent.hardSeek === true,
    pausedSeek: intent.pausedSeek === true,
    drift: intent.drift ?? null,
  }
}

function assertClose(actual: number | null, expected: number | null, what: string) {
  if (expected === null || actual === null) {
    assert.equal(actual, expected, what)
    return
  }
  assert.ok(
    Math.abs(actual - expected) < EPSILON,
    `${what}: expected ${expected}, got ${actual}`,
  )
}

test('the shared contract and syncCore agree on every correction-loop constant', () => {
  const declared = core as unknown as Record<string, unknown>
  for (const [name, value] of Object.entries(syncContract.constants)) {
    assert.equal(declared[name], value, `${name} drifted from the shared contract`)
  }
})

for (const c of syncContract.predictPosition) {
  test(`predictPosition: ${c.name}`, () => {
    assertClose(predictPosition(c.schedule as SyncSchedule | null, c.serverNowMs), c.expect, c.name)
  })
}

for (const c of syncContract.decideSyncAction) {
  test(`decideSyncAction: ${c.name}`, () => {
    const correctionState = c.correctionState ? { ...c.correctionState } : null
    const intent = normalize(decideSyncAction({
      schedule: c.schedule as SyncSchedule | null,
      serverNowMs: () => c.serverNowMs,
      clockReady: () => c.clockReady,
      currentTime: c.currentTime,
      paused: c.paused,
      isHost: c.isHost,
      mode: c.mode,
      userSeeking: c.userSeeking,
      suppressHardSeek: c.suppressHardSeek,
      correctionState,
    }))

    if (c.expect === null) {
      assert.equal(intent, null, 'expected a no-op tick')
      return
    }
    assert.notEqual(intent, null, 'expected an intent, got a no-op tick')
    const got = intent as NormalizedIntent
    assertClose(got.seekTo, c.expect.seekTo, 'seekTo')
    assertClose(got.rate, c.expect.rate, 'rate')
    assertClose(got.drift, c.expect.drift, 'drift')
    assert.equal(got.play, c.expect.play, 'play')
    assert.equal(got.pause, c.expect.pause, 'pause')
    assert.equal(got.hardSeek, c.expect.hardSeek, 'hardSeek')
    assert.equal(got.pausedSeek, c.expect.pausedSeek, 'pausedSeek')

    if (c.expectCorrectionState) {
      assert.equal(correctionState?.correcting, c.expectCorrectionState.correcting, 'correctionState')
    }
  })
}

// ── Socket vocabulary ───────────────────────────────────────────────────────
// A client is allowed to ignore events it has no use for, so this direction is
// containment, not equality: every name the client sends or listens for must
// exist in the contract, in the matching direction. That is what catches a
// typo or a rename applied to only one of the three implementations.

// Accepts compiled .js as well as .ts sources: the runner used on hosts whose
// node cannot load TypeScript transpiles the tree first, and this scan has to
// find the same event literals either way.
function clientSources(dir: string): string[] {
  const out: string[] = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === 'dist') continue
    const full = join(dir, entry.name)
    if (entry.isDirectory()) out.push(...clientSources(full))
    else if (/\.[jt]sx?$/.test(entry.name) && !/\.test\.[jt]sx?$/.test(entry.name)) out.push(full)
  }
  return out
}

const src = new URL('..', import.meta.url).pathname
const sources = clientSources(src).map(f => readFileSync(f, 'utf8')).join('\n')

/** Event names passed to a socket call site — `.emit('x')`, `.on('x')`,
 *  `.off('x')`, `.once('x')`. Deliberately narrow: bare `'a:b'` strings in the
 *  client also cover node: imports, mpv: player events and wp:/dl:/watch:
 *  window events, none of which are socket traffic. */
const used = new Set(
  [...sources.matchAll(/\.(?:on|off|once|emit|emitWithAck)\(\s*['"]([a-z]+:[A-Za-z_]+)['"]/g)].map(m => m[1]),
)

test('the client uses socket events that actually exist in the shared contract', () => {
  const known = new Set([...eventContract.clientToServer, ...eventContract.serverToClient])
  const unknown = [...used].filter(name => !known.has(name)).sort()
  assert.deepEqual(unknown, [], 'client uses socket events the server does not define')
})

test('the client covers the sync and party events the contract carries', () => {
  // Guard against the opposite failure: the extraction above silently matching
  // nothing (a refactor to a wrapper helper) and the test passing vacuously.
  for (const name of ['sync:schedule', 'sync:play', 'party:state', 'party:create']) {
    assert.ok(used.has(name), `expected the client to reference ${name}`)
  }
})

// `Required<SyncSchedule>` makes this literal exhaustive: dropping a field from
// the interface makes the extra property here a type error, and adding one
// makes the literal incomplete. So `tsc --noEmit` catches interface drift, and
// the assertion catches the fixture drifting away from the interface.
const contractedSchedule: Required<SyncSchedule> = {
  positionTicks: 0,
  t0: 0,
  rate: 0,
  paused: true,
  phase: 'paused',
  version: 0,
  mediaGeneration: 0,
}

test('the client SyncSchedule type declares every contracted sync:schedule field', () => {
  assert.deepEqual(Object.keys(contractedSchedule).sort(), [...eventContract.syncScheduleFields].sort())
})
