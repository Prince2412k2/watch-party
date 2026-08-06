// Reading a keyboard event into the shared `shouldToggleChat` guard.
//
// The guard itself is in ../playerCore.ts and is driven by the same cases as the
// Dart port. What lives here is the DOM half: deciding whether focus is in an
// editable field and whether the document has a selection, which is precisely
// where a naive Ctrl+C binding breaks the platform copy command.
//
// React does not bind Ctrl+C today — the blanket `if (e.ctrlKey || e.metaKey ||
// e.altKey) return` in Player.tsx is what keeps copy working — so this guard has
// to be at least as careful as that bail before the binding can exist at all.

import { shouldToggleChat, type ChatShortcutContext } from '../playerCore.ts'

export interface KeyLike {
  key: string
  ctrlKey?: boolean
  metaKey?: boolean
  altKey?: boolean
  shiftKey?: boolean
  target?: unknown
}

export interface EditableLike {
  tagName?: string
  isContentEditable?: boolean
}

/** Input, textarea or contenteditable — anywhere a copy is a text copy. */
export function isEditableTarget(node: unknown): boolean {
  if (!node || typeof node !== 'object') return false
  const element = node as EditableLike
  if (element.isContentEditable === true) return true
  const tag = typeof element.tagName === 'string' ? element.tagName.toUpperCase() : ''
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT'
}

export interface ShortcutEnvironment {
  /** Usually `document.activeElement` — the event target may be `window`. */
  activeElement?: unknown
  /** Usually `String(window.getSelection() ?? '')`. */
  selectionText?: string
}

export function chatShortcutContext(event: KeyLike, environment: ShortcutEnvironment = {}): ChatShortcutContext {
  return {
    ctrlOrMeta: Boolean(event.ctrlKey || event.metaKey),
    key: event.key ?? '',
    editable: isEditableTarget(event.target) || isEditableTarget(environment.activeElement),
    hasSelection: (environment.selectionText ?? '').trim().length > 0,
  }
}

/**
 * The whole decision in one call: `true` means take the event for chat, `false`
 * means leave it entirely alone.
 *
 * Alt and Shift are refused on top of the shared guard. Ctrl+Shift+C is the
 * devtools element picker in both Chrome and Firefox, and Alt+C is a platform
 * accelerator — the shared cases do not model either modifier, so the extra
 * strictness lives on this side of the boundary rather than in the fixture.
 */
export function shouldToggleChatFromEvent(event: KeyLike, environment: ShortcutEnvironment = {}): boolean {
  if (event.altKey || event.shiftKey) return false
  return shouldToggleChat(chatShortcutContext(event, environment))
}
