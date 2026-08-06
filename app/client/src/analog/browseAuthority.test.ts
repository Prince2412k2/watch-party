// Nobody may hand-roll "who is allowed to drive shared browsing".
//
// partyAuthority.ts owns that rule, mirrors the server's canDrive(), and is
// covered by partyAuthority.test.ts. The rule has three parts and only one of
// them is obvious:
//
//   host                                     -> drives
//   guest, host handed out collaborative     -> drives
//   guest without it, or a waiting member    -> follows
//
// A surface that writes `role === 'host'` inline gets the first and third right
// and silently drops the second, so PartyPanel's "Let guests browse, play,
// pause & seek" switch appears to do nothing — and the failure is invisible
// unless somebody actually turns collaborative control on with a guest present.
// The server would happily accept the guest's navigate; the client just never
// sends it.
//
// This is a source-text scan for the same reason downloadsCore.test.ts scans for
// poller mounts: the bug is in which module a surface reaches for, which no
// unit test of either module can see.

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const SRC = fileURLToPath(new URL('..', import.meta.url)).replace(/\/$/, '')

// .js/.jsx as well as .ts/.tsx: the local test harness transpiles the tree
// before running it, and a scan that only knew about TypeScript would find
// nothing there and pass without having looked at anything.
function sourceFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) return entry.name === 'node_modules' ? [] : sourceFiles(path)
    if (!/\.[jt]sx?$/.test(entry.name) || /\.test\.[jt]sx?$/.test(entry.name)) return []
    return [path]
  })
}

/** Reads the shared browse stack, so it is a browsing surface. */
const READS_SHARED_STACK = /\bsession\??\.?\.browse\b|\bnavigateBrowse\b/

// A drive decision computed inline from the role. Deliberately narrow: a file
// may legitimately hold other host checks — Party.tsx gates LiveKit on
// `role === 'host' || role === 'guest'` and keeps an `isHost` flag — while
// leaving the browse decision to the surface it renders. Only an assignment to
// the drive flag itself is the mistake this guards against.
const INLINE_DRIVE_DECISION =
  /\b(?:can(?:Drive|Browse)\w*|driving)\s*=\s*[^\n]*\brole\s*===\s*['"]host['"]/

test('browse surfaces decide driving through partyAuthority, not inline', () => {
  const surfaces = sourceFiles(SRC)
    .map((path) => ({ path, source: readFileSync(path, 'utf8') }))
    .filter(({ source }) => READS_SHARED_STACK.test(source))

  // Without this the whole test is `[] === []` the moment the scan looks at the
  // wrong tree or the wrong extension — a guard that silently stops guarding is
  // worse than no guard, because the green tick says it is still working.
  assert.ok(
    surfaces.length >= 2,
    `expected to find the shared-browsing surfaces under ${SRC}, found ${surfaces.length}`,
  )

  const offenders = surfaces
    .filter(({ source }) => INLINE_DRIVE_DECISION.test(source))
    .filter(({ source }) => !/\bcanDriveBrowse\b/.test(source))
    .map(({ path }) => path.slice(SRC.length + 1))
    .sort()

  assert.deepEqual(
    offenders,
    [],
    'these files gate shared browsing on an inline host check — import canDriveBrowse ' +
      'from partyAuthority instead, or the collaborative-control case is dropped',
  )
})
