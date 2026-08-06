// Types for generate.mjs, which is plain JS so it can run under `node` with no
// build step. Mirrors the app/shared/avatar-derive.js + .d.ts pairing.

/** Repo-relative paths of the three checked-in generated files. */
export declare const OUTPUTS: {
  readonly ts: string
  readonly css: string
  readonly dart: string
}

/** Parsed analog-tokens.json. */
export declare function readTokens(): Record<string, Record<string, unknown>>

export declare function renderTs(tokens?: Record<string, unknown>): string
export declare function renderCss(tokens?: Record<string, unknown>): string
export declare function renderDart(tokens?: Record<string, unknown>): string

/** Every generated file keyed by its repo-relative path. */
export declare function renderAll(
  tokens?: Record<string, unknown>,
): Record<string, string>
