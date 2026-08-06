// The outcome → state mapping, and the precedence between what the server said
// and what the download client is actually doing.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  canChooseSource,
  outcomeToState,
  primaryActionLabel,
  stateDetail,
  titleState,
  type RequestState,
} from './cardState.ts'
import type { CatalogItem } from './catalog.ts'

const item = (over: Partial<CatalogItem> = {}): CatalogItem => ({ title: 'Dune', ...over })
const downloading = (progress: number, state = 'downloading') => ({ progress, state })

test('every outcome the server can return maps to a state', () => {
  assert.equal(outcomeToState('grabbed'), 'grabbed')
  assert.equal(outcomeToState('no_release'), 'no_release')
  assert.equal(outcomeToState('search_failed'), 'search_failed')
  assert.equal(outcomeToState('monitoring'), 'monitoring')
  assert.equal(outcomeToState('exists'), 'added')
})

test('an unknown or missing outcome is an error, never a silent success', () => {
  // A future outcome this build has not learned must surface as something the
  // user can retry, not as a download that never starts.
  assert.equal(outcomeToState(undefined), 'error')
  assert.equal(outcomeToState(''), 'error')
  assert.equal(outcomeToState('queued_for_later'), 'error')
})

// ── precedence ──────────────────────────────────────────────────────────────

test('nothing requested and nothing in the library is idle', () => {
  const state = titleState({ item: item() })
  assert.equal(state.phase, 'idle')
  assert.equal(state.inLibrary, false)
  assert.equal(state.badge, null)
  assert.equal(state.progressPct, null)
  assert.equal(state.retryable, false)
})

test('a title the catalog already tracks reads as in-library with no request', () => {
  const state = titleState({ item: item({ id: 9 }) })
  assert.equal(state.phase, 'added')
  assert.equal(state.inLibrary, true)
  assert.equal(state.badge, 'Library')
})

test('every rail badge stays short enough to read on a phone-sized poster', () => {
  // A rail poster is 68px wide there; the stage carries the full sentence.
  const badges = (['searching', 'monitoring', 'no_release', 'search_failed', 'added', 'error'] as const).map(
    (requested) => titleState({ item: item(), requested }).badge ?? '',
  )
  for (const badge of [...badges, 'Starting', '100%']) {
    assert.ok(badge.length <= 10, `"${badge}" is too long for a rail badge`)
  }
})

test('a live download outranks both the request outcome and library membership', () => {
  // The old surface showed "In library" while a picker-grabbed release
  // downloaded, because one value had to carry both answers.
  const state = titleState({
    item: item({ id: 9 }),
    requested: 'added',
    torrent: downloading(0.42),
  })
  assert.equal(state.phase, 'downloading')
  assert.equal(state.inLibrary, true, 'it is still in the library while it downloads')
  assert.equal(state.pct, 42)
  assert.equal(state.live, true)
  assert.equal(state.badge, '42%')
  assert.equal(state.progressPct, 42)
})

test('grabbed before the poller catches up reads as Starting, not as 0%', () => {
  const state = titleState({ item: item(), requested: 'grabbed' })
  assert.equal(state.phase, 'downloading')
  assert.equal(state.live, false)
  assert.equal(state.pct, null)
  assert.equal(state.badge, 'Starting')
  assert.equal(primaryActionLabel(state), 'Starting download…')
})

test('a paused torrent is not a download in progress', () => {
  const state = titleState({ item: item({ id: 3 }), torrent: downloading(0.5, 'pausedDL') })
  assert.equal(state.phase, 'added')
  assert.equal(state.live, false)
  assert.equal(state.progressPct, null)
})

test('a finished torrent stops claiming the stage', () => {
  // 100% is a completed file, not a download; the library state is what matters.
  const state = titleState({ item: item({ id: 3 }), torrent: downloading(1) })
  assert.equal(state.phase, 'added')
  assert.equal(state.progressPct, null)
})

test('progress is clamped into 0..100 whatever the client reports', () => {
  // A torrent that has just been handed over reports nothing useful yet — it is
  // still a download, and 0% is the honest number rather than a reason to fall
  // back to the library state.
  const negative = titleState({ item: item(), torrent: downloading(-0.2) })
  assert.equal(negative.phase, 'downloading')
  assert.equal(negative.pct, 0)
  assert.equal(negative.badge, '0%')

  const noProgress = titleState({ item: item(), torrent: { state: 'downloading' } })
  assert.equal(noProgress.phase, 'downloading')
  assert.equal(noProgress.pct, 0)

  assert.equal(titleState({ item: item(), requested: 'grabbed', torrent: downloading(0.005) }).pct, 1)
  // Over 100% is a completed file, so the download panel stands down.
  assert.equal(titleState({ item: item({ id: 2 }), torrent: downloading(1.4) }).phase, 'added')
})

test('the transient states each keep their own panel and their own retry', () => {
  const cases: Array<[RequestState, string, boolean]> = [
    ['searching', 'Finding a release…', false],
    ['monitoring', 'Added — monitoring', false],
    ['no_release', 'Try again', true],
    ['search_failed', 'Retry', true],
    ['error', 'Retry download', true],
    ['added', 'In library', false],
  ]
  for (const [requested, label, retryable] of cases) {
    const state = titleState({ item: item(), requested })
    assert.equal(state.phase, requested === 'grabbed' ? 'downloading' : requested)
    assert.equal(primaryActionLabel(state), label)
    assert.equal(state.retryable, retryable, `${requested} retryability`)
  }
})

test('every state the rail can be in says so without a hover', () => {
  const phases: Array<RequestState | null> = [
    null,
    'searching',
    'monitoring',
    'no_release',
    'search_failed',
    'added',
    'error',
  ]
  for (const requested of phases) {
    const state = titleState({ item: item(), requested })
    if (requested === null) {
      assert.equal(state.badge, null, 'an untouched title needs no badge')
    } else {
      assert.ok(state.badge, `${requested} must carry a visible badge`)
    }
  }
})

test('the failure states explain themselves and the working ones do not need to', () => {
  assert.match(stateDetail(titleState({ item: item(), requested: 'no_release' }), 'movie') ?? '', /try again later/i)
  assert.match(stateDetail(titleState({ item: item(), requested: 'error' }), 'series') ?? '', /series/)
  assert.match(stateDetail(titleState({ item: item(), requested: 'monitoring' }), 'series') ?? '', /on their own/)
  assert.equal(stateDetail(titleState({ item: item() }), 'movie'), null)
  assert.equal(stateDetail(titleState({ item: item({ id: 1 }) }), 'movie'), null)
})

test('choosing a source is offered only when no grab is already in flight', () => {
  assert.equal(canChooseSource(titleState({ item: item() })), true)
  assert.equal(canChooseSource(titleState({ item: item({ id: 2 }) })), true)
  assert.equal(canChooseSource(titleState({ item: item(), requested: 'no_release' })), true)
  assert.equal(canChooseSource(titleState({ item: item(), requested: 'searching' })), false)
  assert.equal(canChooseSource(titleState({ item: item(), torrent: downloading(0.3) })), false)
})
