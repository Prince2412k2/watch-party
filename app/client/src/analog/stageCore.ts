// Stage wiring — the React-side glue around the shared browse cores.
//
// The behaviour both clients must agree on lives in browseCore.ts and is pinned
// by app/shared/design/interaction.json. NOTHING here may reimplement it: this
// file only turns browser input into the shape those cores already accept
// (a pixel delta, an intent, an index) and turns an index back into geometry.
//
// It is deliberately free of React and the DOM so the wiring is testable — the
// repo has no DOM tests at all, every suite runs on extracted pure logic.

// ── input normalisation ─────────────────────────────────────────────────────

export interface WheelSample {
  deltaX: number
  deltaY: number
  /** WheelEvent.deltaMode: 0 pixels, 1 lines, 2 pages. */
  deltaMode?: number
}

/** WheelEvent.DOM_DELTA_LINE is what Firefox reports for a notched wheel. */
const LINE_PX = 16
const PAGE_PX = 400

/**
 * One wheel/trackpad event → the pixel delta `steppedScroll` expects.
 *
 * Two conversions, both of which the old poster wall got wrong:
 *
 * 1. deltaMode. Firefox sends `deltaY: 3, deltaMode: 1` (three *lines*) for one
 *    notch. Fed raw into a 48px threshold that is sixteen notches per step.
 * 2. Axis. A horizontal shelf has to accept a sideways trackpad swipe AND a
 *    plain vertical wheel, so the dominant axis wins rather than one being
 *    hard-coded.
 */
export function wheelDeltaPx(sample: WheelSample): number {
  const scale = sample.deltaMode === 1 ? LINE_PX : sample.deltaMode === 2 ? PAGE_PX : 1
  const x = sample.deltaX * scale
  const y = sample.deltaY * scale
  return Math.abs(x) >= Math.abs(y) ? x : y
}

/**
 * Two points of a horizontal drag → the same pixel delta a wheel would produce.
 *
 * Dragging the content leftwards reveals what is to the right, which is forward
 * travel, so the sign is inverted relative to finger movement. Feeding this
 * through `steppedScroll` is what makes "phones use the same stepped selection"
 * literal rather than a parallel swipe implementation with its own thresholds.
 */
export function touchDeltaPx(previousX: number, currentX: number): number {
  return previousX - currentX
}

// ── keyboard / remote intents ───────────────────────────────────────────────

export type FocusIntent = 'prev' | 'next' | 'activate' | 'back' | null

/**
 * Key → intent, covering the keyboard and TV-remote halves of the cross-input
 * contract in one table.
 *
 * Both axes map to the same track: a surface built from the kit has one shelf
 * that owns focus, so Up/Down are the same movement as Left/Right rather than
 * dead keys. A remote's directional pad lands on the same four names.
 */
export function focusIntentForKey(key: string): FocusIntent {
  switch (key) {
    case 'ArrowLeft':
    case 'ArrowUp':
      return 'prev'
    case 'ArrowRight':
    case 'ArrowDown':
      return 'next'
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

// ── focus geometry ──────────────────────────────────────────────────────────

export interface FocusStep {
  index: number
  /**
   * -1 or +1 when the step ran off the end of this shelf. "Scroll moves focus
   * through items and then into the next collection or level" — a surface with
   * more than one shelf hands the overflow on; a single-shelf surface holds.
   */
  overflow: number
}

export function stepFocus(index: number, count: number, direction: number): FocusStep {
  if (count <= 0) return { index: 0, overflow: 0 }
  const target = index + Math.sign(direction)
  if (target < 0) return { index: 0, overflow: -1 }
  if (target > count - 1) return { index: count - 1, overflow: 1 }
  return { index: target, overflow: 0 }
}

/** A box on the horizontal axis. `getBoundingClientRect()` satisfies it. */
export interface Span {
  left: number
  width: number
}

/** Sub-pixel drift is not worth a scroll animation. */
export const CENTRE_EPSILON_PX = 1

/**
 * How far the track must scroll to centre `item` in `track`.
 *
 * Deliberately NOT scrollIntoView. That walks up and scrolls every scrollable
 * ancestor as well (browsers move overflow:hidden boxes for it too), which slid
 * the whole shell — backdrop, chrome and all — sideways on every step. See the
 * comment this replaces at pages/Library.tsx:816-820.
 */
export function centreScrollDelta(track: Span, item: Span): number {
  return item.left + item.width / 2 - (track.left + track.width / 2)
}

export function shouldCentre(delta: number): boolean {
  return Math.abs(delta) > CENTRE_EPSILON_PX
}

/**
 * Roving tabindex: exactly one option in the shelf is in the tab order, and
 * arrow keys move it. Exactly one is the whole point — a listbox where every
 * option is tabbable makes Tab walk the entire library.
 *
 * A shelf with nothing focused yet still has to be reachable, so the first
 * option holds the tab stop until focus lands somewhere real.
 */
export function rovingTabIndex(index: number, focusedIndex: number): 0 | -1 {
  return index === (focusedIndex < 0 ? 0 : focusedIndex) ? 0 : -1
}
