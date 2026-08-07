// Volume + mute rules for the vertical hairline control.
//
// "The volume track follows the same hairline treatment and preserves mute,
// previous-volume restore, keyboard adjustment, and a sufficiently large touch
// target." — docs/watchparty-design/player-interface-reference.md
//
// Volume and mute are deliberately NOT gated on playback-control permission: a
// guest with no transport rights must still be able to unmute and set a level.
// Pure, so the restore rule is testable without a media element.

export interface VolumeState {
  /** The level the media element carries. Unchanged by muting. */
  volume: number
  muted: boolean
  /** What "unmute" comes back to when the level itself was dragged to zero. */
  restoreVolume: number
}

/** Matches the existing ↑/↓ keyboard step so the shortcut keeps its feel. */
export const VOLUME_STEP = 0.1

/** Unmuting a control that was dragged to silence has to produce audible sound. */
export const MIN_RESTORE_VOLUME = 0.1

export const clampVolume = (value: number): number =>
  !Number.isFinite(value) ? 0 : Math.min(1, Math.max(0, value))

export const newVolumeState = (volume = 1, muted = false): VolumeState => {
  const level = clampVolume(volume)
  return { volume: level, muted, restoreVolume: level > 0 ? level : MIN_RESTORE_VOLUME }
}

/**
 * Drag / set an explicit level.
 *
 * Above zero unmutes (this is how the old horizontal slider behaved and how
 * every player behaves); dragging to zero mutes and remembers the level to come
 * back to.
 */
export function setVolume(state: VolumeState, next: number): VolumeState {
  const level = clampVolume(next)
  if (level > 0) return { volume: level, muted: false, restoreVolume: level }
  return {
    volume: 0,
    muted: true,
    restoreVolume: state.volume > 0 ? state.volume : state.restoreVolume,
  }
}

export function toggleMute(state: VolumeState): VolumeState {
  if (state.muted) {
    const level = state.volume > 0 ? state.volume : Math.max(state.restoreVolume, MIN_RESTORE_VOLUME)
    return { volume: level, muted: false, restoreVolume: level }
  }
  return {
    volume: state.volume,
    muted: true,
    restoreVolume: state.volume > 0 ? state.volume : state.restoreVolume,
  }
}

/**
 * Keyboard adjustment (↑/↓).
 *
 * Raising the volume force-unmutes — that is the existing binding's behaviour
 * and the only way ↑ can do anything audible while muted. Lowering leaves the
 * mute flag alone, so ↓ to zero does not latch a mute the user never asked for.
 */
export function stepVolume(state: VolumeState, delta: number): VolumeState {
  const level = clampVolume(state.volume + delta)
  if (delta > 0) {
    return { volume: level, muted: false, restoreVolume: level > 0 ? level : state.restoreVolume }
  }
  return {
    volume: level,
    muted: state.muted,
    restoreVolume: level > 0 ? level : state.restoreVolume,
  }
}

/** What the hairline draws: a muted control reads as empty, not as its level. */
export const renderedLevel = (state: VolumeState): number => (state.muted ? 0 : state.volume)

export interface VerticalRect {
  top: number
  height: number
}

/** Vertical track: the top of the box is 1, the bottom is 0. */
export function volumeFromPointer(clientY: number, rect: VerticalRect): number {
  if (!rect || !Number.isFinite(rect.height) || rect.height <= 0) return 0
  return clampVolume(1 - (clientY - rect.top) / rect.height)
}

export const volumePercent = (state: VolumeState): number => renderedLevel(state) * 100
