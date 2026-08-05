import { humation1 } from '@humation/assets-humation-1'
import type { HumationManifest } from '@humation/core'
import {
  PALETTES,
  derivedColors as deriveColors,
  derivedConfig as deriveConfig,
  effectiveConfig as resolveConfig,
} from '../../../shared/avatar-derive.js'
import type { AvatarConfig } from '../../../shared/avatar-derive.js'

/**
 * The web client's view of the shared avatar rules. Derivation itself lives in
 * `app/shared/avatar-derive.js` because the server draws the same faces for the
 * Flutter clients, and both have to agree on what an account looks like. This
 * file binds those rules to the asset set the browser bundles.
 */

// The embedded asset set carries its artwork inline, so avatars render without
// a request and still appear on a degraded connection or offline.
export const assets: HumationManifest = humation1

export type { AvatarConfig }
export { PALETTES }

export const derivedColors = (userId: string) => deriveColors(userId)
export const derivedConfig = (userId: string) => deriveConfig(assets, userId)
export const effectiveConfig = (userId: string, saved?: AvatarConfig | null) =>
  resolveConfig(assets, userId, saved)

/* The asset set draws black line art, which disappears on our dark surfaces
   without something behind it, so an avatar keeps a light plate by default
   rather than going transparent. It is the same neutral for everyone — identity
   comes from the drawing, not from a per-user background tint. */
export const DEFAULT_BACKGROUND = assets.defaults.background
