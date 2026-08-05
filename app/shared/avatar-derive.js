import { createAvatar } from '@humation/core'

/**
 * How an account becomes a face, shared verbatim by the web client and the
 * server.
 *
 * It has to live in one file: the web client draws avatars locally, the server
 * draws them for the Flutter clients, and "the same account looks the same
 * everywhere" only holds while both use the same palettes and the same seeding.
 * Plain JavaScript so `app/server` (node) and `app/client` (vite) can both
 * import it; the types are alongside in avatar-derive.d.ts.
 *
 * These palettes are part of the contract: reordering one changes the default
 * avatar of every user who hasn't customised theirs. Append, don't reorder.
 */

// Light to deep. Chosen to be unremarkable rather than expressive — a default
// nobody has to correct, not a statement about anyone.
const SKIN = [
  'FFE0CC', 'F8D5B8', 'EFC2A2', 'E3AA84',
  'C98F62', 'A97048', '875532', '623C22',
]

const HAIR = [
  '1B1512', '2E2320', '4A3728', '6B4A2F',
  '8C6239', 'B08D57', '7A7A7A', '241F2E',
]

// Garment tones that read as clothes rather than as UI: muted, low-chroma.
const CLOTHES = [
  'ECEAE5', 'D3D7DC', 'A8B2BE', '7C8896',
  '55606E', 'B0705C', '7C8A5C', '8A7098',
]

const BOTTOM = [
  '2B2F36', '3C444E', '555C66', '6B5A48',
  '1F2227', '46505C', '7A5F4B', '8A8F97',
]

// Line art and plates. The drawing style is black-on-light, so these are the
// few variations of it that still look like the same asset set.
const STROKE = ['000000', '2A2A2A', '3A2E28', '20242E']
const BACKGROUND = ['F6F5F4', 'E8E6E1', 'DCE1E6', 'C9CDD4', '3C444E', '1F2227']

/** The same tones the defaults are drawn from, offered in the editor as one-tap
    swatches. A slot missing here still gets a full colour picker. */
export const PALETTES = {
  skin: SKIN,
  hair: HAIR,
  clothes: CLOTHES,
  bottom: BOTTOM,
  stroke: STROKE,
  background: BACKGROUND,
}

/** 32-bit string hash (xmur3). Deterministic across engines because it only
    uses integer arithmetic — the same id seeds the same avatar everywhere. */
function seedFrom(text) {
  let h = 1779033703 ^ text.length
  for (let i = 0; i < text.length; i++) {
    h = Math.imul(h ^ text.charCodeAt(i), 3432918353)
    h = (h << 13) | (h >>> 19)
  }
  return () => {
    h = Math.imul(h ^ (h >>> 16), 2246822507)
    h = Math.imul(h ^ (h >>> 13), 3266489909)
    h ^= h >>> 16
    return h >>> 0
  }
}

function pick(options, next) {
  return options[next() % options.length]
}

/** The colours a user gets before they choose any. Stroke is deliberately left
    at the asset set's black line art: it is the drawing style, not a feature of
    the person. */
export function derivedColors(userId) {
  const next = seedFrom(userId)
  return {
    skin: pick(SKIN, next),
    hair: pick(HAIR, next),
    clothes: pick(CLOTHES, next),
    bottom: pick(BOTTOM, next),
  }
}

/** The full avatar a user has before customising: seeded parts plus derived
    colours, resolved to concrete ids so an editor can show what is selected. */
export function derivedConfig(manifest, userId) {
  const resolved = createAvatar(manifest, { seed: userId, colors: derivedColors(userId) }).toJSON()
  // Only our own three fields — `template` and `crop` are the asset set's
  // business and the server rejects anything it did not ask for.
  return { selections: { ...resolved.selections }, colors: { ...resolved.colors } }
}

/** What to actually draw for someone: their saved customisation layered over
    their derived default, per slot. A saved avatar wins; a slot they never
    touched keeps the derived value. */
export function effectiveConfig(manifest, userId, saved) {
  const derived = derivedConfig(manifest, userId)
  if (!saved) return derived
  return {
    selections: { ...derived.selections, ...saved.selections },
    colors: { ...derived.colors, ...saved.colors },
    ...(saved.background === undefined ? null : { background: saved.background }),
  }
}
