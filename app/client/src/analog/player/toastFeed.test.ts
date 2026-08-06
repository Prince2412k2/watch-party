import test from 'node:test'
import assert from 'node:assert/strict'
import { analogTokens } from '../../design/analogTokens.ts'
import {
  expireToasts,
  newToastQueueState,
  pushToast,
  setChatOpen,
  toastView,
  type ToastQueueState,
} from '../playerCore.ts'
import {
  PREVIEW_MAX_CHARS,
  collapsedLabel,
  concealToasts,
  isFromOther,
  newMessages,
  nextToastDeadlineMs,
  nextToastExpiryMs,
  previewText,
  shouldQueueMessages,
  toToastMessage,
  toastAnnouncement,
  toastId,
} from './toastFeed.ts'

const feed = (state: ToastQueueState, messages: { name?: string; text?: string }[], atMs: number) =>
  messages.reduce((next, message, index) => pushToast(next, toToastMessage(message, index, atMs)), state)

test('a preview is a preview, not the message', () => {
  assert.equal(previewText('  hello   there \n friend '), 'hello there friend')
  const long = 'x'.repeat(PREVIEW_MAX_CHARS + 40)
  const preview = previewText(long)
  assert.equal(preview.length, PREVIEW_MAX_CHARS)
  assert.ok(preview.endsWith('…'))
  assert.equal(previewText(undefined), '')
})

test('two identical messages in the same millisecond stay two toasts', () => {
  // pushToast drops duplicate ids, so an id derived from sender and timestamp
  // alone would silently swallow the second of a double-send.
  const a = toastId({ userId: 'u1', ts: 5 }, 0)
  const b = toastId({ userId: 'u1', ts: 5 }, 1)
  assert.notEqual(a, b)
  assert.equal(toastId({ id: 'server-id', userId: 'u1', ts: 5 }, 3), 'server-id')
})

test('the toast clock is the local arrival time, not the message timestamp', () => {
  // A server clock a few seconds ahead would expire a toast before it painted.
  const toast = toToastMessage({ name: 'Ada', text: 'hi', ts: 1_000_000 }, 0, 42)
  assert.equal(toast.receivedAtMs, 42)
  assert.equal(toast.sender, 'Ada')
})

test('my own message never toasts at me', () => {
  assert.equal(isFromOther({ userId: 'me' }, 'me'), false)
  assert.equal(isFromOther({ userId: 'you' }, 'me'), true)
  assert.equal(isFromOther({ userId: 'you' }, undefined), true)
})

test('history does not toast on join', () => {
  const log = ['a', 'b', 'c', 'd']
  assert.deepEqual(newMessages(log, 4), { messages: [], from: 4 })
  assert.deepEqual(newMessages(log, 2), { messages: ['c', 'd'], from: 2 })
  // A log that shrank (a fresh session) must not produce a negative slice.
  assert.deepEqual(newMessages(['a'], 9), { messages: [], from: 1 })
})

test('nothing queues while the drawer is open or the device is asleep', () => {
  const open = setChatOpen(newToastQueueState(), true)
  assert.equal(shouldQueueMessages(open, 'visible'), false)
  assert.equal(shouldQueueMessages(newToastQueueState(), 'hidden'), false)
  assert.equal(shouldQueueMessages(newToastQueueState(), 'visible'), true)
  // A browser that reports nothing is treated as visible, never as asleep.
  assert.equal(shouldQueueMessages(newToastQueueState(), undefined), true)
})

test('backgrounding the device clears message content outright', () => {
  const state = feed(newToastQueueState(), [{ name: 'Ada', text: 'secret' }], 0)
  assert.equal(toastView(state).toasts.length, 1)
  const concealed = concealToasts(state)
  assert.deepEqual(toastView(concealed), { toasts: [], collapsedCount: 0 })
  // And returning to the tab must not resurrect it.
  assert.deepEqual(toastView(expireToasts(concealed, 10)), { toasts: [], collapsedCount: 0 })
})

test('the expiry timer is aimed at the oldest toast', () => {
  const lifetime = analogTokens.timing.toastLifetimeMs
  let state = feed(newToastQueueState(), [{ name: 'A', text: '1' }], 1000)
  state = feed(state, [{ name: 'B', text: '2' }], 3000)
  // Not 3000 + lifetime: expiring on the newest would leave the older toast up
  // past its own four seconds.
  assert.equal(nextToastDeadlineMs(state), 1000 + lifetime)
  assert.equal(nextToastExpiryMs(state, 2000), 1000 + lifetime - 2000)
  // Overdue reads as due now rather than as a negative timeout.
  assert.equal(nextToastExpiryMs(state, 99_999), 0)
  assert.equal(nextToastDeadlineMs(newToastQueueState()), null)
  assert.equal(nextToastExpiryMs(newToastQueueState(), 0), null)
})

test('the feed drives the shared queue: three visible, the rest a count', () => {
  const max = analogTokens.timing.toastMaxStack
  let state = newToastQueueState()
  state = feed(state, [
    { name: 'A', text: '1' },
    { name: 'B', text: '2' },
    { name: 'C', text: '3' },
    { name: 'D', text: '4' },
    { name: 'E', text: '5' },
  ], 0)
  const view = toastView(state)
  assert.equal(view.toasts.length, max)
  assert.equal(view.collapsedCount, 2)
  assert.deepEqual(view.toasts.map((toast) => toast.sender), ['C', 'D', 'E'])

  // Each runs its own four seconds off the same push instant here, so they all
  // fall together; the point is that the count follows the queue, not the view.
  const expired = expireToasts(state, analogTokens.timing.toastLifetimeMs)
  assert.deepEqual(toastView(expired), { toasts: [], collapsedCount: 0 })
})

test('what a screen reader hears', () => {
  assert.equal(
    toastAnnouncement({ id: '1', sender: 'Ada', preview: 'on my way', receivedAtMs: 0 }),
    'Ada: on my way',
  )
  assert.equal(
    toastAnnouncement({ id: '1', sender: 'Ada', preview: '', receivedAtMs: 0 }),
    'Ada sent a message',
  )
  assert.equal(collapsedLabel(1), '1 earlier message')
  assert.equal(collapsedLabel(4), '4 earlier messages')
})
