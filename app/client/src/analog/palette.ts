/**
 * The fuzzy finder behind `/` and Ctrl/Cmd-K.
 *
 * Deliberately the same matcher as the desktop client's (`ui/command_palette.dart`
 * `_fuzzyScore`), because two clients ranking the same query differently would
 * make the shortcut feel unreliable rather than fast.
 *
 * Free of React so it can be tested directly.
 */

export interface PaletteItem {
  id: string
  label: string
  /** Right-aligned readout — a year, typically. */
  trailing?: string | null
  /** Artwork for the preview pane. */
  imageUrl?: string | null
  kind?: string | null
}

/** How many library matches the list shows before it stops being a list. */
export const PALETTE_LIMIT = 20

/**
 * Rank one candidate against a query. Lower is better; null is no match.
 *
 * A substring hit scores by position, so a prefix beats a mention in the middle.
 * A subsequence hit — every query character present, in order, with gaps —
 * scores above every substring hit, so "the thing you typed part of" always
 * sorts ahead of "the thing whose letters happen to appear in order".
 *
 * An empty query matches everything, equally.
 */
export function fuzzyScore(query: string, target: string): number | null {
  if (query.length === 0) return 0
  const q = query.toLowerCase()
  const t = target.toLowerCase()

  const index = t.indexOf(q)
  if (index >= 0) return index

  let cursor = 0
  let gaps = 0
  for (const character of q) {
    const found = t.indexOf(character, cursor)
    if (found < 0) return null
    gaps += found - cursor
    cursor = found + 1
  }
  return 1000 + gaps
}

/**
 * The matches for [query], best first, capped at [PALETTE_LIMIT].
 *
 * Ties keep their original order — the library arrives sorted (recently watched
 * first, then alphabetical), and a stable sort means an empty query shows that
 * order rather than an arbitrary one.
 */
export function rankPalette<T extends PaletteItem>(
  items: readonly T[],
  query: string,
  limit = PALETTE_LIMIT,
): T[] {
  const trimmed = query.trim()
  const scored: Array<{ item: T; score: number; index: number }> = []
  items.forEach((item, index) => {
    const score = fuzzyScore(trimmed, item.label)
    if (score !== null) scored.push({ item, score, index })
  })
  scored.sort((a, b) => (a.score - b.score) || (a.index - b.index))
  return scored.slice(0, limit).map(entry => entry.item)
}

/**
 * Where the highlight lands after moving by [delta].
 *
 * Wraps in both directions: at the bottom of a short list, Down is far more
 * likely to mean "back to the top" than "do nothing".
 */
export function moveHighlight(current: number, delta: number, count: number): number {
  if (count <= 0) return 0
  return ((current + delta) % count + count) % count
}

/** Whether a keystroke should open the palette. */
export function opensPalette(
  key: string,
  modifiers: { ctrl?: boolean; meta?: boolean },
  editing: boolean,
): boolean {
  // '/' is a single key, so it must not fire while someone is typing into a
  // field — chat, a search box, a name. The modified binding always may.
  if (key === 'k' && (modifiers.ctrl || modifiers.meta)) return true
  return key === '/' && !editing && !modifiers.ctrl && !modifiers.meta
}
