// The Movies stage's browse model: the two modes, the keys that move between
// them, and the collection drill-in.
//
// "We want to add support for movie collections/franchise. The way we have a
// slider for seasons in the show screen, on movies tab will have two options —
// singles and collections. Up down and scroll updown (when not in the movie
// grid) will toggle it. When we click on a collection a show like screen opens
// for that collection."
//
// The mode lives on the browse STACK rather than in component state, because the
// stack is what a party host publishes (`session.browse.stack`). A follower who
// only received a drill-in level would otherwise sit in Singles looking at a
// franchise's parts. `BrowseEntry` is explicitly open-ended on the wire
// (types.ts) and other surfaces already carry extra keys on it — the phone tree
// publishes `seriesId`/`seriesName` the same way.
//
// Pure: no React, no fetching. The page is the only thing that knows a URL.

import type { StackLevel } from './surface.ts'

// ── the two modes ───────────────────────────────────────────────────────────

export type BrowseMode = 'singles' | 'collections'

/** Slider order, top to bottom. Up moves towards the first, Down the last. */
export const BROWSE_MODES: readonly BrowseMode[] = ['singles', 'collections']

export const BROWSE_MODE_LABELS: Record<BrowseMode, string> = {
  singles: 'Singles',
  collections: 'Collections',
}

export const isBrowseMode = (value: unknown): value is BrowseMode =>
  value === 'singles' || value === 'collections'

/**
 * One step of the mode slider.
 *
 * Clamped, not wrapping. A two-position slider that wraps is indistinguishable
 * from a toggle, and "controls should feel deterministic" — holding Down must
 * settle on Collections rather than flickering between the two. The same
 * function serves the arrow keys and a stepped scroll, so the two input routes
 * cannot drift.
 */
export function stepBrowseMode(mode: BrowseMode, direction: number): BrowseMode {
  const index = BROWSE_MODES.indexOf(mode)
  const next = index + Math.sign(direction)
  return BROWSE_MODES[Math.max(0, Math.min(next, BROWSE_MODES.length - 1))]
}

// ── input intents ───────────────────────────────────────────────────────────

export type StageIntent =
  /** Move the cursor along the rail. */
  | 'rail-prev'
  | 'rail-next'
  /** Move the Singles/Collections slider. */
  | 'mode-prev'
  | 'mode-next'
  | 'activate'
  | 'back'

/**
 * Key → intent for this stage.
 *
 * Deliberately NOT `stageCore.focusIntentForKey`, which folds Up/Down onto the
 * same track as Left/Right because a kit surface has one shelf that owns focus.
 * This stage has two axes: the rail runs horizontally and the mode slider
 * vertically, exactly as the sketch draws them, so the four arrows are four
 * different movements and a remote's d-pad lands on the same four names.
 */
export function stageKeyIntent(key: string): StageIntent | null {
  switch (key) {
    case 'ArrowLeft':
      return 'rail-prev'
    case 'ArrowRight':
      return 'rail-next'
    case 'ArrowUp':
      return 'mode-prev'
    case 'ArrowDown':
      return 'mode-next'
    case 'Enter':
    case ' ':
    case 'Spacebar':
      return 'activate'
    case 'Escape':
    case 'Backspace':
      return 'back'
    default:
      return null
  }
}

/** The mode step a `steppedScroll` result outside the rail produces. */
export const modeForScrollStep = (mode: BrowseMode, step: number): BrowseMode =>
  step === 0 ? mode : stepBrowseMode(mode, step)

// ── the browse stack ────────────────────────────────────────────────────────

/** A stack level, plus the mode the root level carries for followers. */
export interface MovieLevel extends StackLevel {
  mode?: BrowseMode
}

/** Jellyfin models a movie collection/franchise as a box set. */
export const COLLECTION_TYPE = 'BoxSet'

export const isCollection = (item: { Type?: string } | null | undefined): boolean =>
  item?.Type === COLLECTION_TYPE

export interface MoviesView {
  Id: string
  Name: string
  Type?: string
}

/** The root of the stack: the Movies library view, tagged with the current mode. */
export const rootLevel = (view: MoviesView, mode: BrowseMode): MovieLevel => ({
  id: view.Id,
  name: view.Name,
  type: view.Type ?? 'CollectionFolder',
  mode,
})

export const rootOf = (stack: readonly MovieLevel[]): MovieLevel | null => stack[0] ?? null

export function modeFromStack(
  stack: readonly MovieLevel[],
  fallback: BrowseMode = 'singles',
): BrowseMode {
  const root = rootOf(stack)
  return isBrowseMode(root?.mode) ? root.mode : fallback
}

/**
 * The collection currently drilled into, or null at the list level.
 *
 * Read off the stack rather than held separately so that a guest following a
 * host lands in the same franchise without a second wire field, and so Back is
 * just "pop".
 *
 * The type check is what keeps a follower sane when the driver is on the
 * superseded Library implementation, which pushes a `Movie` level for a title's
 * detail page. Treating that as a franchise would fetch a box set's contents for
 * a movie id and render an empty rail. A level with no type at all is still
 * accepted — the wire allows every field to be absent, and this surface only
 * ever pushes box sets.
 */
export function collectionFromStack(stack: readonly MovieLevel[]): MovieLevel | null {
  const top = stack[stack.length - 1]
  if (!top || stack.length < 2 || typeof top.id !== 'string') return null
  if (top.type !== undefined && top.type !== COLLECTION_TYPE) return null
  return top
}

/**
 * Switch modes.
 *
 * Truncates to the root: a franchise's parts are not a thing Singles can show,
 * so staying drilled in across the switch would leave the rail rendering a
 * collection's contents under a Singles heading.
 */
export function withMode(stack: readonly MovieLevel[], mode: BrowseMode): MovieLevel[] {
  const root = rootOf(stack)
  if (!root) return []
  return [{ ...root, mode }]
}

/** Enter on a collection: a show-like level for its parts. */
export function openCollection(
  stack: readonly MovieLevel[],
  collection: { Id: string; Name: string; Type?: string },
): MovieLevel[] {
  const root = rootOf(stack)
  if (!root) return [...stack]
  return [
    { ...root, mode: 'collections' },
    { id: collection.Id, name: collection.Name, type: collection.Type ?? COLLECTION_TYPE },
  ]
}

/** Back out of a collection to the list it came from. */
export function closeCollection(stack: readonly MovieLevel[]): MovieLevel[] {
  return stack.length > 1 ? stack.slice(0, -1) : [...stack]
}

// ── activation ──────────────────────────────────────────────────────────────

export type Activation =
  /** Details are already on the stage, so Enter plays — exactly like an episode. */
  | { kind: 'play'; itemId: string }
  | { kind: 'open'; collection: { Id: string; Name: string; Type?: string } }
  | { kind: 'none' }

const NONE: Activation = { kind: 'none' }

/**
 * What Enter/click does to the focused item.
 *
 * Driven by the item's type rather than the current mode: a box set opens
 * wherever it is encountered, and everything else plays. That is the same answer
 * for a single, for a part inside a franchise, and for a box set that turns up in
 * a library listing — one rule instead of three that have to agree.
 */
export function activationFor(
  item: { Id?: string; Name?: string; Type?: string } | null | undefined,
): Activation {
  if (!item || typeof item.Id !== 'string' || item.Id.length === 0) return NONE
  if (isCollection(item)) {
    return { kind: 'open', collection: { Id: item.Id, Name: item.Name ?? '', Type: item.Type } }
  }
  return { kind: 'play', itemId: item.Id }
}

// ── surfaces ────────────────────────────────────────────────────────────────

/**
 * The focus-memory key for where the user is.
 *
 * The mode is part of the identity: Singles and Collections are two different
 * lists of two different lengths, and sharing one memory would restore focus in
 * one from a position only the other ever had. `surfaceId` already folds the
 * drill-in path in, which keeps a franchise's position separate from the list's.
 */
export const moviesTab = (mode: BrowseMode): string => `movies:${mode}`
