// The React client's half of the analog interaction contract.
//
// app/shared/design/interaction.json holds the canonical behaviour cases for
// the five interaction cores that #66/#67 require to behave identically in both
// clients. This file drives the TypeScript implementations from those cases;
// flutter_app/test/analog/interaction_parity_test.dart drives the Dart ports
// from the same bytes.
//
// Nothing in the build links the two ports together, so without this the stage
// could step one item per flick in React and three in Flutter, and both suites
// would stay green. See app/shared/design/README.md.

import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { analogTokens } from '../design/analogTokens.ts'
import {
  newSteppedScrollState,
  steppedScroll,
  restoreFocus,
  resolveSeasonArtwork,
  railWindow,
  type SteppedScrollConfig,
  type FocusMemory,
  type ShelfSnapshot,
} from './browseCore.ts'
import {
  newToastQueueState,
  pushToast,
  expireToasts,
  setChatOpen,
  toastView,
  newAutoHideState,
  noteInput,
  holdControls,
  releaseControls,
  setPlaying,
  tickAutoHide,
  shouldToggleChat,
  type ToastQueueState,
  type AutoHideState,
  type PlayerInputKind,
} from './playerCore.ts'

const fixture = JSON.parse(
  readFileSync(new URL('../../../shared/design/interaction.json', import.meta.url), 'utf8'),
)

test('stepped scroll matches the shared interaction cases', () => {
  const config = fixture.steppedScroll.config as SteppedScrollConfig

  for (const testCase of fixture.steppedScroll.cases) {
    const state = newSteppedScrollState()
    testCase.events.forEach((event: { deltaPx: number; atMs: number; expect: number }, index: number) => {
      const steps = steppedScroll(state, event.deltaPx, event.atMs, config)
      assert.equal(
        steps,
        event.expect,
        `${testCase.name}: event ${index} (delta ${event.deltaPx} at ${event.atMs}ms) ` +
          `produced ${steps}, expected ${event.expect}`,
      )
    })
  }
})

test('focus restoration matches the shared interaction cases', () => {
  for (const testCase of fixture.focusRestore.cases) {
    const result = restoreFocus(
      testCase.memory as FocusMemory,
      testCase.surfaceId,
      testCase.shelves as ShelfSnapshot[],
      testCase.rememberedIndex,
    )
    assert.deepEqual(
      { kind: result.kind, position: result.position },
      testCase.expect,
      testCase.name,
    )
  }
})

test('season artwork fallback matches the shared interaction cases', () => {
  for (const testCase of fixture.seasonArtwork.cases) {
    assert.deepEqual(resolveSeasonArtwork(testCase.input), testCase.expect, testCase.name)
  }
})

test('the chat toast queue matches the shared interaction cases', () => {
  for (const testCase of fixture.toastQueue.cases) {
    let state: ToastQueueState = newToastQueueState()

    for (const op of testCase.ops) {
      switch (op.op) {
        case 'push':
          state = pushToast(state, {
            id: op.id,
            sender: op.sender,
            preview: op.preview,
            receivedAtMs: op.atMs,
          })
          break
        case 'expire':
          state = expireToasts(state, op.atMs)
          break
        case 'chat':
          state = setChatOpen(state, op.open)
          break
        case 'view': {
          const view = toastView(state)
          assert.deepEqual(
            view.toasts.map((toast) => toast.id),
            op.toasts,
            `${testCase.name}: visible toasts`,
          )
          assert.equal(view.collapsedCount, op.collapsedCount, `${testCase.name}: collapsed count`)
          break
        }
        default:
          assert.fail(`${testCase.name}: unknown toastQueue op "${op.op}"`)
      }
    }
  }
})

test('control auto-hide matches the shared interaction cases', () => {
  for (const testCase of fixture.autoHide.cases) {
    let state: AutoHideState = newAutoHideState(testCase.startAtMs, true)

    for (const op of testCase.ops) {
      switch (op.op) {
        case 'input':
          state = noteInput(state, op.kind as PlayerInputKind, op.atMs)
          break
        case 'hold':
          state = holdControls(state, op.reason)
          break
        case 'release':
          state = releaseControls(state, op.reason, op.atMs)
          break
        case 'playing':
          state = setPlaying(state, op.value, op.atMs)
          break
        case 'tick':
          state = tickAutoHide(state, op.atMs)
          assert.equal(
            state.visible,
            op.expectVisible,
            `${testCase.name}: visible at ${op.atMs}ms`,
          )
          break
        default:
          assert.fail(`${testCase.name}: unknown autoHide op "${op.op}"`)
      }
    }
  }
})

test('the chat shortcut guard matches the shared interaction cases', () => {
  for (const testCase of fixture.chatShortcut.cases) {
    assert.equal(shouldToggleChat(testCase.context), testCase.expect, testCase.name)
  }
})

test('the toast and auto-hide timings come from the design tokens', () => {
  // The fixture hard-codes 4000ms / 3000ms / a stack of three. Those numbers are
  // design decisions that live in analog-tokens.json, so pin them together —
  // otherwise changing a token silently invalidates every timing case above.
  assert.equal(analogTokens.timing.toastLifetimeMs, 4000, 'toast lifetime')
  assert.equal(analogTokens.timing.chromeAutoHideMs, 3000, 'chrome auto-hide')
  assert.equal(analogTokens.timing.toastMaxStack, 3, 'toast stack depth')
})

test('the fixed-cursor rail window matches the shared interaction cases', () => {
  for (const testCase of fixture.railWindow.cases) {
    const window = railWindow(testCase.input)
    assert.deepEqual(window.visible, testCase.expect.visible, `${testCase.name}: visible`)
    assert.deepEqual(window.prefetch, testCase.expect.prefetch, `${testCase.name}: prefetch`)
  }
})
