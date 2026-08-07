// Player interaction core — the parts of the analog player model that must
// behave identically in React and Flutter.
//
// Ported verbatim to flutter_app/lib/analog/player_core.dart and driven by the
// same cases in app/shared/design/interaction.json.
//
// Pure: no DOM, no timers. Callers own the clock and feed `atMs` / `nowMs` in,
// which is also what makes the timing rules ("four seconds", "three seconds")
// testable without waiting in real time.

import { analogTokens } from '../design/analogTokens.ts'

// ── chat message toasts ─────────────────────────────────────────────────────
//
// "Up to three messages stack at once. Additional older messages collapse into
// a count rather than extending across the player." (player-interface-reference)
//
// Toasts exist only while the drawer is closed; opening chat dismisses them
// because the messages are then visible in full.

export interface ToastMessage {
  id: string
  sender: string
  preview: string
  receivedAtMs: number
}

export interface ToastQueueState {
  /** Oldest first. Everything still inside its lifetime. */
  queue: ToastMessage[]
  chatOpen: boolean
}

export const newToastQueueState = (chatOpen = false): ToastQueueState => ({ queue: [], chatOpen })

export interface ToastView {
  /** At most `toastMaxStack`, newest last. */
  toasts: ToastMessage[]
  /** Live messages beyond the visible stack, shown as a count. */
  collapsedCount: number
}

/**
 * Record an incoming chat message.
 *
 * While the drawer is open nothing is queued at all — the message is already
 * on screen, and queueing it would make it toast the moment chat closes.
 */
export function pushToast(state: ToastQueueState, message: ToastMessage): ToastQueueState {
  if (state.chatOpen) return state
  if (state.queue.some((existing) => existing.id === message.id)) return state
  return { ...state, queue: [...state.queue, message] }
}

/** Drop everything past its lifetime. Each toast expires on its own clock. */
export function expireToasts(state: ToastQueueState, nowMs: number): ToastQueueState {
  const lifetime = analogTokens.timing.toastLifetimeMs
  const queue = state.queue.filter((message) => nowMs - message.receivedAtMs < lifetime)
  return queue.length === state.queue.length ? state : { ...state, queue }
}

/** Opening chat dismisses visible toasts; closing it does not resurrect them. */
export function setChatOpen(state: ToastQueueState, chatOpen: boolean): ToastQueueState {
  if (chatOpen === state.chatOpen) return state
  return { chatOpen, queue: chatOpen ? [] : state.queue }
}

export function toastView(state: ToastQueueState): ToastView {
  if (state.chatOpen) return { toasts: [], collapsedCount: 0 }
  const max = analogTokens.timing.toastMaxStack
  if (state.queue.length <= max) return { toasts: [...state.queue], collapsedCount: 0 }
  return {
    toasts: state.queue.slice(state.queue.length - max),
    collapsedCount: state.queue.length - max,
  }
}

// ── control auto-hide ───────────────────────────────────────────────────────
//
// "During playback, controls hide after three seconds without relevant input."
// "Auto-hidden controls must return on pointer movement, tap, focus movement,
// or a relevant media key without changing playback state."
//
// The hold set is what keeps the chrome up while the user is mid-interaction:
// scrubbing, a settings stack open, focus inside the chat composer. Without it
// the menu you just opened vanishes under your cursor.

export type PlayerInputKind =
  | 'pointer'
  | 'tap'
  | 'focus'
  | 'key'
  | 'mediaKey'
  | 'scroll'

export interface AutoHideState {
  visible: boolean
  lastInputAtMs: number
  /** Reasons the chrome is pinned open. Non-empty means never hide. */
  holds: string[]
  /** Chrome stays up whenever playback is not running. */
  playing: boolean
}

export const newAutoHideState = (atMs = 0, playing = true): AutoHideState => ({
  visible: true,
  lastInputAtMs: atMs,
  holds: [],
  playing,
})

/** Any relevant input reveals the chrome and restarts the timer. */
export function noteInput(
  state: AutoHideState,
  _kind: PlayerInputKind,
  atMs: number,
): AutoHideState {
  return { ...state, visible: true, lastInputAtMs: atMs }
}

export function holdControls(state: AutoHideState, reason: string): AutoHideState {
  if (state.holds.includes(reason)) return state
  return { ...state, visible: true, holds: [...state.holds, reason] }
}

/**
 * Release a hold. The auto-hide timer restarts from `atMs` rather than from
 * whenever the hold was taken, so closing a menu gives the full three seconds
 * instead of hiding instantly.
 */
export function releaseControls(state: AutoHideState, reason: string, atMs: number): AutoHideState {
  if (!state.holds.includes(reason)) return state
  return {
    ...state,
    holds: state.holds.filter((held) => held !== reason),
    lastInputAtMs: atMs,
  }
}

export function setPlaying(state: AutoHideState, playing: boolean, atMs: number): AutoHideState {
  if (playing === state.playing) return state
  // Pausing reveals the chrome and keeps it up; resuming restarts the timer.
  return { ...state, playing, visible: true, lastInputAtMs: atMs }
}

/** Advance the clock. Returns the state with `visible` resolved for `nowMs`. */
export function tickAutoHide(state: AutoHideState, nowMs: number): AutoHideState {
  if (state.holds.length > 0 || !state.playing) {
    return state.visible ? state : { ...state, visible: true }
  }
  const elapsed = nowMs - state.lastInputAtMs
  const visible = elapsed < analogTokens.timing.chromeAutoHideMs
  return visible === state.visible ? state : { ...state, visible }
}

// ── chat shortcut guard ─────────────────────────────────────────────────────
//
// "`Ctrl+C` toggles the same surface. The shortcut must not fire while focus is
// inside an editable text field and must not override the platform copy
// command when text is selected."
//
// Both conditions are real: binding Ctrl+C naively breaks copy, which users
// notice immediately and blame on the app.

export interface ChatShortcutContext {
  ctrlOrMeta: boolean
  key: string
  /** Focus is in an input, textarea or contenteditable. */
  editable: boolean
  /** A non-empty selection exists in the document. */
  hasSelection: boolean
}

export function shouldToggleChat(context: ChatShortcutContext): boolean {
  if (!context.ctrlOrMeta) return false
  if (context.key.toLowerCase() !== 'c') return false
  if (context.editable) return false
  if (context.hasSelection) return false
  return true
}
