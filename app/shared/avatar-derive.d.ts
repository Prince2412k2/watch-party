import type { HumationManifest } from '@humation/core'

/** What we store for a customised avatar: overrides only, in the vocabulary the
    asset set defines. Anything absent falls back to the derived default, so an
    older saved profile keeps working when the asset set grows a slot. */
export interface AvatarConfig {
  selections?: Record<string, string>
  colors?: Record<string, string>
  background?: string
}

export declare const PALETTES: Record<string, readonly string[]>
export declare function derivedColors(userId: string): Record<string, string>
export declare function derivedConfig(manifest: HumationManifest, userId: string): AvatarConfig
export declare function effectiveConfig(
  manifest: HumationManifest,
  userId: string,
  saved?: AvatarConfig | null,
): AvatarConfig
