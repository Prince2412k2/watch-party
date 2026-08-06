// Focus persistence across a surface change.
//
// "Back returns to the exact browsing position and focused item." `restoreFocus`
// in browseCore.ts decides *which* item that is, driven by the shared fixture.
// This file is the surface-shaped layer around it: naming a surface so two
// browsing levels do not share one memory, describing the shelves in the shape
// the core wants, and turning the core's id answer back into the indices a
// shelf renders from.
//
// The memory is module-level on purpose. A surface unmounts entirely when you
// drill into a title, so component state cannot be what remembers where you
// were — that is precisely the bug this closes.

import {
  rememberFocus,
  restoreFocus,
  type FocusMemory,
  type FocusRestoreKind,
  type ShelfSnapshot,
} from './browseCore.ts'

export interface StackLevel {
  id?: string
  name?: string
  type?: string
}

/**
 * A stable name for "where the user is".
 *
 * Includes the drill-down path, so the top of Movies and a collection inside it
 * each keep their own focus rather than the deeper one overwriting the shallower
 * one on the way back out.
 */
export function surfaceId(tab: string, stack: readonly StackLevel[] = []): string {
  const path = stack.map((level) => level.id).filter((id): id is string => typeof id === 'string')
  return path.length ? `${tab}/${path.join('/')}` : tab
}

export function shelfSnapshot(shelfId: string, items: readonly { Id: string }[]): ShelfSnapshot {
  return { shelfId, itemIds: items.map((item) => item.Id) }
}

export interface FocusPlan {
  kind: FocusRestoreKind
  /** -1 when there is nothing focusable on the surface. */
  shelfIndex: number
  itemIndex: number
}

export const EMPTY_FOCUS_PLAN: FocusPlan = { kind: 'empty', shelfIndex: -1, itemIndex: -1 }

/**
 * Where focus lands when this surface comes back.
 *
 * `rememberedIndex` is the index the item held when it was last seen, and it is
 * what makes a removed item land next to where the user's attention was rather
 * than at the start of the shelf.
 */
export function focusPlan(
  memory: FocusMemory,
  id: string,
  shelves: readonly ShelfSnapshot[],
  rememberedIndex = 0,
): FocusPlan {
  const result = restoreFocus(memory, id, shelves, rememberedIndex)
  if (!result.position) return EMPTY_FOCUS_PLAN
  const shelfIndex = shelves.findIndex((shelf) => shelf.shelfId === result.position!.shelfId)
  if (shelfIndex < 0) return EMPTY_FOCUS_PLAN
  const itemIndex = shelves[shelfIndex].itemIds.indexOf(result.position.itemId)
  if (itemIndex < 0) return EMPTY_FOCUS_PLAN
  return { kind: result.kind, shelfIndex, itemIndex }
}

// ── the process-wide memory ─────────────────────────────────────────────────

let memory: FocusMemory = {}
let rememberedIndices: Record<string, number> = {}

export function rememberSurfaceFocus(
  id: string,
  shelfId: string,
  itemId: string,
  index: number,
): void {
  memory = rememberFocus(memory, id, { shelfId, itemId })
  rememberedIndices = { ...rememberedIndices, [id]: index }
}

export function planForSurface(id: string, shelves: readonly ShelfSnapshot[]): FocusPlan {
  return focusPlan(memory, id, shelves, rememberedIndices[id] ?? 0)
}

/** Tests only. */
export function resetSurfaceFocus(): void {
  memory = {}
  rememberedIndices = {}
}
