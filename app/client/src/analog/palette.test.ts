// The fuzzy finder's ranking, and the keys that open it.
//
// The matcher is deliberately the same one the desktop client uses; two clients
// ranking the same query differently would make the shortcut feel unreliable
// rather than fast, which is the whole point of a fuzzy finder.

import test from 'node:test'
import assert from 'node:assert/strict'
import {
  PALETTE_LIMIT,
  fuzzyScore,
  moveHighlight,
  opensPalette,
  rankPalette,
  type PaletteItem,
} from './palette.ts'

const item = (label: string): PaletteItem => ({ id: label, label })

test('a prefix beats a mention further in', () => {
  const prefix = fuzzyScore('blade', 'Blade Runner')
  const middle = fuzzyScore('blade', 'The Blade')
  assert.equal(prefix, 0)
  assert.ok(middle !== null && prefix !== null && prefix < middle)
})

test('a subsequence matches, and always sorts below every substring', () => {
  // "br" is in "Blade Runner" only as scattered letters.
  const scattered = fuzzyScore('br', 'Blade Runner')
  assert.ok(scattered !== null && scattered >= 1000)
  // Even the worst substring hit beats the best scattered one, so typing part
  // of a title never loses to a coincidence of letters.
  const worstSubstring = fuzzyScore('runner', 'Blade Runner')
  assert.ok(worstSubstring !== null && worstSubstring < scattered)
})

test('letters out of order do not match', () => {
  assert.equal(fuzzyScore('rb', 'Blade Runner'), null)
  assert.equal(fuzzyScore('zzz', 'Blade Runner'), null)
})

test('matching ignores case', () => {
  assert.equal(fuzzyScore('BLADE', 'blade runner'), 0)
  assert.equal(fuzzyScore('blade', 'BLADE RUNNER'), 0)
})

test('an empty query matches everything, in the order it arrived', () => {
  const items = [item('Dune'), item('Arrival'), item('Heat')]
  // The library arrives recently-watched-first; an empty query must not
  // re-sort it alphabetically behind the user's back.
  assert.deepEqual(rankPalette(items, '').map(i => i.label), ['Dune', 'Arrival', 'Heat'])
  assert.deepEqual(rankPalette(items, '   ').map(i => i.label), ['Dune', 'Arrival', 'Heat'])
})

test('ranking puts the best match first and drops the rest', () => {
  const items = [item('The Blade'), item('Blade Runner'), item('Braveheart')]
  const ranked = rankPalette(items, 'blade')
  assert.deepEqual(ranked.map(i => i.label), ['Blade Runner', 'The Blade'])
})

test('the list is capped', () => {
  const items = Array.from({ length: PALETTE_LIMIT + 30 }, (_, i) => item(`Film ${i}`))
  assert.equal(rankPalette(items, 'film').length, PALETTE_LIMIT)
  assert.equal(rankPalette(items, 'film', 5).length, 5)
})

test('the highlight wraps both ways', () => {
  // At the bottom of a short list, Down almost always means "back to the top".
  assert.equal(moveHighlight(2, 1, 3), 0)
  assert.equal(moveHighlight(0, -1, 3), 2)
  assert.equal(moveHighlight(0, 1, 3), 1)
  // An empty list has nowhere to go rather than a negative index.
  assert.equal(moveHighlight(0, 1, 0), 0)
})

test('slash opens the palette only when nobody is typing', () => {
  assert.equal(opensPalette('/', {}, false), true)
  // Chat, a search box, a name field: a bare '/' there is a character.
  assert.equal(opensPalette('/', {}, true), false)
  // The modified binding is always live, editing or not.
  assert.equal(opensPalette('k', { ctrl: true }, true), true)
  assert.equal(opensPalette('k', { meta: true }, true), true)
  assert.equal(opensPalette('k', {}, false), false)
})
