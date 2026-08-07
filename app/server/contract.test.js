// The socket vocabulary in app/shared/contracts/socket-events.json, checked
// against the server that defines it.
//
// The server is the truth for the wire protocol; the two clients only mirror
// it. So this test asserts *equality* in both directions — a handler the
// fixture doesn't know about is drift just as much as a fixture entry with no
// handler behind it. The client-side halves of the same fixture live in
// app/client/src/sync/contractParity.test.ts and
// flutter_app/test/sync/contract_parity_test.dart, and they only assert
// containment, because a client is allowed to ignore events it has no use for.

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

const contract = JSON.parse(
  readFileSync(new URL('../shared/contracts/socket-events.json', import.meta.url), 'utf8'),
)

const serverDir = new URL('.', import.meta.url).pathname

function sourceFiles(dir) {
  const out = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules') continue
    const full = join(dir, entry.name)
    if (entry.isDirectory()) out.push(...sourceFiles(full))
    else if (entry.name.endsWith('.js') && !entry.name.endsWith('.test.js')) out.push(full)
  }
  return out
}

const sources = sourceFiles(serverDir).map(f => readFileSync(f, 'utf8')).join('\n')

function matchAll(pattern) {
  return new Set([...sources.matchAll(pattern)].map(m => m[1]))
}

// 'disconnect' is Socket.IO's own lifecycle event, not part of our vocabulary.
const registered = matchAll(/socket\.on\(\s*'([^']+)'/g)
registered.delete('disconnect')
const emitted = matchAll(/\.emit\(\s*'([^']+)'/g)

const sorted = set => [...set].sort()

test('every client→server event the server handles is in the shared contract', () => {
  assert.deepEqual(sorted(registered), [...contract.clientToServer].sort())
})

test('every server→client event the server emits is in the shared contract', () => {
  assert.deepEqual(sorted(emitted), [...contract.serverToClient].sort())
})

test('the sync:schedule payload the server builds matches the shared contract', () => {
  // session.js constructs the schedule literal in two places (fresh party and
  // restore fallback); both must carry exactly the contracted field set.
  const sessionSource = readFileSync(new URL('./session.js', import.meta.url), 'utf8')
  const literals = sessionSource.match(/\{\s*positionTicks:[^}]*\}/g) ?? []
  assert.equal(literals.length, 2, 'expected both schedule literals in session.js')
  for (const literal of literals) {
    // Property names only: the leading `{` or a comma, then the identifier,
    // then `:` (or `,`/`}` for shorthand). Skips values, including the ternary
    // in `mediaGeneration: mediaItemId ? 1 : 0`.
    const keys = [...literal.matchAll(/[{,]\s*([A-Za-z_$][\w$]*)\s*(?=[:,}])/g)].map(m => m[1]).sort()
    assert.deepEqual(keys, [...contract.syncScheduleFields].sort())
  }
})
