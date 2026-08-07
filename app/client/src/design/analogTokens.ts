// GENERATED FILE — DO NOT EDIT.
//
// Source:    app/shared/design/analog-tokens.json
// Generator: node app/shared/design/generate.mjs
//
// Edit the JSON and regenerate. A parity test in each client re-runs the
// generator and compares against these bytes, so hand-edits fail the suite.

export const analogTokens = {
  /** Warm blacks and softly tinted neutrals — never pure black, never pure
   *  white. R > G > B on every neutral. */
  color: {
    stageVoid: "#070605",
    stageGround: "#0E0C0A",
    stageSurface: "#16130F",
    stageSurface2: "#201C18",
    stageSurface3: "#2B2621",
    ink: "#F4EFE6",
    inkDim: "#F4EFE6A3",
    inkFaint: "#F4EFE661",
    line: "#F4EFE61A",
    lineStrong: "#F4EFE62E",
    edgeLight: "#FFF6E83D",
    edgeShade: "#0000008C",
    shadowCast: "#120A0499",
    shadowCastStrong: "#120A04C4",
    backdropScrim: "#0E0C0AA6",
    backdropVignette: "#07060580",
    accent: "#F4EFE6",
    onAccent: "#0E0C0A",
    statusDanger: "#E0655E",
    statusSuccess: "#5AB98A",
    statusLive: "#E0655E",
    statusPartyLive: "#78C99F",
  },

  /** Fine, low-contrast film grain over the stage. Must never reduce text or
   *  artwork clarity. */
  grain: {
    opacityPct: 3.5,
    tilePx: 128,
    focusedBoostPct: 1.5,
  },

  /** Square, unrounded artwork at EVERY size — including skeletons,
   *  placeholders, season cards and selected states. radiusPx is 0 and is
   *  asserted by tests in both clients. */
  poster: {
    radiusPx: 0,
    aspectW: 2,
    aspectH: 3,
    framePx: 1,
    gapPx: 14,
    shelfPeekPx: 64,
  },

  /** Depth through scale, framing, light and position. No perspective tilt, no
   *  bounce. */
  selection: {
    restScale: 1,
    focusScale: 1.06,
    focusLiftPx: 6,
    focusBackdropDarkenPct: 22,
    sceneLightAngleDeg: 315,
  },

  /** Directional cast shadows keyed to sceneLightAngleDeg (light above-left =>
   *  shadow below-right). */
  elevation: {
    restBlurPx: 18,
    restOffsetXPx: 4,
    restOffsetYPx: 8,
    focusBlurPx: 34,
    focusOffsetXPx: 8,
    focusOffsetYPx: 18,
  },

  /** Material 3's state-layer model: a translucent wash of the ink colour over
   *  a control that has been reached, at a fixed opacity per state. Adopted
   *  because it is the one interaction primitive that scales - every control
   *  reads the same whatever its fill, so a chip, a menu row and an icon button
   *  respond identically without each hand-rolling a fill swap. The opacities
   *  are M3's; the colour washed over them is ours. */
  stateLayer: {
    hoverPct: 8,
    focusPct: 10,
    pressedPct: 10,
    selectedPct: 12,
    draggedPct: 16,
    disabledContentPct: 38,
    disabledContainerPct: 12,
  },

  /** Mechanical and weighty: short travel, clear detents. Chrome still uses
   *  Material 3's easing set - standard for buttons and plates,
   *  emphasized-decelerate for drawers - and none of those overshoot. The
   *  BROWSE RAIL is the deliberate exception: it settles past its mark and
   *  comes back, and the amount scales with how fast the row was moving. That
   *  was asked for directly, and it replaces an earlier blanket ban on
   *  overshoot. The distinction that keeps it coherent: things with mass
   *  overshoot, chrome does not. A row of posters being flung has momentum; a
   *  button does not. */
  motion: {
    focusStepMs: 170,
    focusStepEase: [0.05, 0.7, 0.1, 1],
    backdropCrossMs: 420,
    backdropCrossEase: [0.2, 0, 0, 1],
    chromeFadeMs: 160,
    chromeFadeEase: [0.2, 0, 0, 1],
    detentMs: 90,
    detentEase: [0.2, 0, 0, 1],
    drawerMs: 260,
    drawerEase: [0.05, 0.7, 0.1, 1],
    enterMs: 300,
    enterEase: [0.05, 0.7, 0.1, 1],
    exitMs: 200,
    exitEase: [0.3, 0, 0.8, 0.15],
    slotLagMs: 26,
    slotLagMaxMs: 130,
    settleMs: 380,
    settleEase: [0.22, 1.28, 0.36, 1],
    settleFastMs: 620,
    fastStepMs: 220,
    anticipationMs: 60,
    anticipationPct: 4,
    copySwapMs: 260,
    copyRisePx: 10,
    copySlidePct: 11,
    copySlideFastPct: 32,
    typeMassRefPx: 16,
    typeMassMaxPx: 52,
    typeMassSettleMinPct: 58,
    typeMassTravelMinPct: 55,
    typeMassTravelMaxPct: 145,
  },

  /** Timeline and volume are precision lines, not filled bars. The visible line
   *  is thin; the hit target is not. */
  hairline: {
    idlePx: 2,
    activePx: 4,
    hitPx: 24,
    handlePx: 10,
    handleFocusPx: 14,
    rangeGapPx: 2,
  },

  /** Behavioural constants fixed by the design references; the interaction
   *  cores in app/shared/design/interaction.json are driven by these same
   *  numbers. */
  timing: {
    chromeAutoHideMs: 3000,
    toastLifetimeMs: 4000,
    toastMaxStack: 3,
  },

  space: {
    xsPx: 4,
    smPx: 8,
    mdPx: 12,
    lgPx: 16,
    xlPx: 24,
    xxlPx: 32,
    stageGutterPx: 48,
    stageGutterPhonePx: 20,
  },

  /** Artwork is always square. These radii are for chrome only (buttons,
   *  sheets, toasts) and must never be applied to a poster, still, skeleton or
   *  placeholder. */
  radius: {
    chromePx: 4,
    sheetPx: 8,
    pillPx: 999,
  },

  type: {
    sans: "'Circular XX', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
    mono: "'JetBrains Mono', ui-monospace, monospace",
    sansFamily: "CircularXX",
    monoFamily: "JetBrains Mono",
  },

  /** Stage layering. The player owns its own bands; these are the browse shell. */
  z: {
    backdrop: 0,
    grain: 5,
    shelf: 10,
    nav: 20,
    toolbox: 30,
    scrim: 40,
    sheet: 50,
    toast: 60,
  },

  breakpoint: {
    phoneMaxPx: 719,
    tabletMaxPx: 1023,
  },
} as const

export type AnalogTokens = typeof analogTokens

/** `[x1, y1, x2, y2]` -> a CSS `cubic-bezier(...)` string. */
export const ease = (curve: readonly [number, number, number, number]): string =>
  `cubic-bezier(${curve.join(", ")})`
