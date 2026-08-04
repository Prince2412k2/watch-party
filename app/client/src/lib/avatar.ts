import { createAvatar } from '@humation/core'
import { humation1 } from '@humation/assets-humation-1'
import type { HumationManifest } from '@humation/core'

/** What we store for a customised avatar: overrides only, in the vocabulary the
    asset set defines. Anything absent falls back to the derived default, so an
    older saved profile keeps working when the asset set grows a slot. */
export interface AvatarConfig {
  selections?: Record<string, string>
  colors?: Record<string, string>
  background?: string
}

export const assets: HumationManifest = humation1

/* ── derived defaults ───────────────────────────────────────────────────────
   Nobody should have to visit a settings page before they stop being a pair of
   grey initials, so every account gets a plausible avatar derived from the one
   identifier every client already knows about them: the Jellyfin user id.

   The asset set picks parts from a seed itself, but leaves colour at its own
   defaults — which are pure white skin and black hair for every single user. So
   parts come from the library's seeding and colours come from the palettes
   below, drawn from the same id.

   These palettes are part of the contract: reordering one changes the default
   avatar of every user who hasn't customised theirs. Append, don't reorder. */

// Light to deep. Chosen to be unremarkable rather than expressive — a default
// nobody has to correct, not a statement about anyone.
const SKIN = [
  'FFE0CC', 'F8D5B8', 'EFC2A2', 'E3AA84',
  'C98F62', 'A97048', '875532', '623C22',
] as const

const HAIR = [
  '1B1512', '2E2320', '4A3728', '6B4A2F',
  '8C6239', 'B08D57', '7A7A7A', '241F2E',
] as const

// Garment tones that read as clothes rather than as UI: muted, low-chroma.
const CLOTHES = [
  'ECEAE5', 'D3D7DC', 'A8B2BE', '7C8896',
  '55606E', 'B0705C', '7C8A5C', '8A7098',
] as const

const BOTTOM = [
  '2B2F36', '3C444E', '555C66', '6B5A48',
  '1F2227', '46505C', '7A5F4B', '8A8F97',
] as const

// Line art and plates. The drawing style is black-on-light, so these are the
// few variations of it that still look like the same asset set.
const STROKE = ['000000', '2A2A2A', '3A2E28', '20242E'] as const
const BACKGROUND = ['F6F5F4', 'E8E6E1', 'DCE1E6', 'C9CDD4', '3C444E', '1F2227'] as const

/** The same tones the defaults are drawn from, offered in the editor as one-tap
    swatches. A slot missing here still gets a full colour picker. */
export const PALETTES: Record<string, readonly string[]> = {
  skin: SKIN,
  hair: HAIR,
  clothes: CLOTHES,
  bottom: BOTTOM,
  stroke: STROKE,
  background: BACKGROUND,
}

/** 32-bit string hash (xmur3). Deterministic across engines because it only
    uses integer arithmetic — the same id seeds the same avatar everywhere. */
function seedFrom(text: string) {
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

function pick<T>(options: readonly T[], next: () => number): T {
  return options[next() % options.length]
}

/** The colours a user gets before they choose any. Stroke is deliberately left
    at the asset set's black line art: it is the drawing style, not a feature of
    the person. */
export function derivedColors(userId: string): Record<string, string> {
  const next = seedFrom(userId)
  return {
    skin: pick(SKIN, next),
    hair: pick(HAIR, next),
    clothes: pick(CLOTHES, next),
    bottom: pick(BOTTOM, next),
  }
}

/** The full avatar a user has before customising: seeded parts plus derived
    colours, resolved to concrete ids so the editor can show what is selected. */
export function derivedConfig(userId: string): AvatarConfig {
  const resolved = createAvatar(assets, { seed: userId, colors: derivedColors(userId) }).toJSON()
  // Only our own three fields — `template` and `crop` are the asset set's
  // business and the server rejects anything it did not ask for.
  return { selections: { ...resolved.selections }, colors: { ...resolved.colors } }
}

/** What to actually draw for someone: their saved customisation layered over
    their derived default, per slot. A saved avatar wins; a slot they never
    touched keeps the derived value. */
export function effectiveConfig(userId: string, saved?: AvatarConfig | null): AvatarConfig {
  const derived = derivedConfig(userId)
  if (!saved) return derived
  return {
    selections: { ...derived.selections, ...saved.selections },
    colors: { ...derived.colors, ...saved.colors },
    ...(saved.background === undefined ? null : { background: saved.background }),
  }
}

/* The asset set draws black line art, which disappears on our dark surfaces
   without something behind it, so an avatar keeps a light plate by default
   rather than going transparent. It is the same neutral for everyone — identity
   comes from the drawing, not from a per-user background tint. */
export const DEFAULT_BACKGROUND = assets.defaults.background
