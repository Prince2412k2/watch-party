// Turning the party's chat log into the toast queue `playerCore` owns.
//
// The queue rules themselves — three visible, older ones collapsing to a count,
// four seconds each, nothing queued while the drawer is open — live in
// ../playerCore.ts and are pinned across both clients by
// app/shared/design/interaction.json. Nothing here re-implements them; this is
// only the feed: which messages become toasts, what they say, when the caller's
// timer has to fire, and the one rule the shared core cannot express because it
// is a property of the device rather than of the queue.

import type { ToastMessage, ToastQueueState } from '../playerCore.ts'
import { analogTokens } from '../../design/analogTokens.ts'

/** The party's chat message shape (app/client/src/types.ts). */
export interface ChatLike {
  id?: string
  userId?: string
  name?: string
  text?: string
  ts?: number
  timestamp?: number
}

/** A preview, not the message. Long lines must not stretch across the player. */
export const PREVIEW_MAX_CHARS = 90

export function previewText(text: string | undefined, max = PREVIEW_MAX_CHARS): string {
  const trimmed = (text ?? '').replace(/\s+/g, ' ').trim()
  if (trimmed.length <= max) return trimmed
  return `${trimmed.slice(0, max - 1).trimEnd()}…`
}

/**
 * A stable identity for a message the server did not id.
 *
 * The chat log is an append-only array keyed by index in the drawer, so the
 * index is part of the fallback: two identical messages from one sender in the
 * same millisecond must not collapse into one toast (or, worse, be dropped by
 * `pushToast`'s duplicate guard).
 */
export const toastId = (message: ChatLike, index: number): string =>
  message.id ?? `${message.userId ?? 'anon'}:${message.ts ?? message.timestamp ?? 0}:${index}`

/**
 * `receivedAtMs` is the LOCAL arrival time, not the message's own timestamp:
 * the four-second lifetime is measured on the clock the caller ticks, and a
 * server timestamp skewed by even a few seconds would expire a toast before it
 * was ever painted.
 */
export const toToastMessage = (message: ChatLike, index: number, receivedAtMs: number): ToastMessage => ({
  id: toastId(message, index),
  sender: message.name ?? 'Someone',
  preview: previewText(message.text),
  receivedAtMs,
})

/** My own message is already on my screen the moment I press send. */
export const isFromOther = (message: ChatLike, selfUserId?: string): boolean =>
  !selfUserId || message.userId !== selfUserId

/**
 * The messages appended since the caller last looked.
 *
 * Mounting into a party with scrollback must not fire a burst of toasts for
 * history, so the caller seeds `seenCount` with the log length it started from.
 */
export function newMessages<T>(messages: readonly T[], seenCount: number): { messages: T[]; from: number } {
  const from = Math.max(0, Math.min(seenCount, messages.length))
  return { messages: messages.slice(from), from }
}

/**
 * "Message content must not remain visible on a locked or backgrounded device."
 *
 * The shared core has no concept of a device, so this is expressed here: hiding
 * the page empties the queue outright rather than pausing it, and nothing is
 * queued while hidden, so returning to the tab cannot replay what arrived while
 * the screen was off.
 */
export const concealToasts = (state: ToastQueueState): ToastQueueState =>
  state.queue.length === 0 ? state : { ...state, queue: [] }

export const isPageVisible = (visibilityState?: string): boolean => visibilityState !== 'hidden'

export const shouldQueueMessages = (state: ToastQueueState, visibilityState?: string): boolean =>
  !state.chatOpen && isPageVisible(visibilityState)

/**
 * The instant the caller must call `expireToasts` again, or `null` when there
 * is nothing pending. Each toast runs its own clock, so the next deadline is the
 * OLDEST one's — expiring on the newest would leave stale toasts up.
 *
 * Absolute rather than relative on purpose: a React effect keyed on a remaining
 * delay reschedules on every unrelated re-render, which postpones the very
 * expiry it is supposed to run.
 */
export function nextToastDeadlineMs(state: ToastQueueState): number | null {
  if (state.queue.length === 0) return null
  let earliest = Infinity
  for (const toast of state.queue) {
    if (toast.receivedAtMs < earliest) earliest = toast.receivedAtMs
  }
  return earliest + analogTokens.timing.toastLifetimeMs
}

/** How long until that deadline, floored at zero. */
export function nextToastExpiryMs(state: ToastQueueState, nowMs: number): number | null {
  const deadline = nextToastDeadlineMs(state)
  return deadline == null ? null : Math.max(0, deadline - nowMs)
}

/**
 * What a screen reader hears. Announced politely into a live region — the
 * reference requires notifications be "announced accessibly without moving
 * keyboard focus", so the stack is never focusable and never grabs focus.
 */
export const toastAnnouncement = (toast: ToastMessage): string =>
  toast.preview ? `${toast.sender}: ${toast.preview}` : `${toast.sender} sent a message`

export const collapsedLabel = (count: number): string =>
  count === 1 ? '1 earlier message' : `${count} earlier messages`
