/**
 * Deliberate local transport commands, kept apart from observed media events.
 *
 * useSyncPlay's authoring guard (`applyingRef`) exists for exactly one purpose:
 * stop the media events that OUR OWN mutations fire from being re-authored as
 * fresh room intent. It says nothing about whether the user is allowed to issue
 * a command. The request* helpers used to check it anyway, which made every
 * deliberate command issued while the guard was held disappear silently — the
 * local currentTime moved and the room never heard about it:
 *
 *   - the imperative seek bridge (double-tap, gesture layer) held the guard
 *     BEFORE emitting, so it suppressed its own sync:seek 100% of the time;
 *   - a second double-tap / arrow-key press inside the previous command's
 *     250ms guard window was dropped, so the room lagged one step behind.
 *
 * `origin` makes the distinction explicit: 'local' is a command the user just
 * issued here (always authored), 'media-event' is an observation (authored only
 * when nothing is applying).
 */
export type CommandOrigin = 'local' | 'media-event'

export function mayAuthor(
  { origin, suppressed, canControl }: { origin: CommandOrigin; suppressed: boolean; canControl: boolean },
): boolean {
  if (!canControl) return false
  return origin === 'local' || !suppressed
}

/**
 * Clamp a seek target into the playable range. Stopping 0.5s short of the end
 * keeps HLS from landing past the last segment (which strands the player on a
 * stall instead of seeking).
 */
export function clampSeekTarget(time: number, duration?: number): number {
  const target = Number.isFinite(time) ? time : 0
  if (target < 0) return 0
  if (duration != null && Number.isFinite(duration) && duration > 0) {
    const max = Math.max(0, duration - 0.5)
    if (target > max) return max
  }
  return target
}

export interface CommandTarget {
  currentTime: number
  duration?: number
  paused: boolean
  play: () => Promise<void> | void
  pause: () => void
}

export interface LocalTransportDeps {
  /** Emit the shared command. Called exactly once per local command. */
  emitPlay: (positionTicks: number) => void
  emitPause: (positionTicks: number) => void
  emitSeek: (positionTicks: number) => void
  /** useSyncPlay's authoring guard. */
  hold: () => void
  release: () => void
  ticksPerSecond: number
  /** How long to suppress authoring while the local mutation's events settle. */
  guardMs?: number
  /**
   * "This player's position does not mean anything right now" — a source swap
   * mid-reload, or an in-flight buffer-aware catch-up. A command issued then
   * would author the room at a transient position (often 0), so it is dropped
   * rather than emitted. NOT the same thing as the authoring guard: that one
   * exists to ignore our own media events and must never eat a real command.
   */
  blocked?: () => boolean
  /** Injectable for tests; defaults to setTimeout. */
  schedule?: (fn: () => void, ms: number) => void
}

/**
 * The one place that sequences a deliberate local transport command:
 *
 *   1. emit the shared command ONCE (origin 'local', so the guard cannot eat it),
 *   2. hold the authoring guard,
 *   3. mutate the local media element,
 *   4. release the guard once the resulting media events have settled.
 *
 * Every caller (keyboard, watch:transport, double-tap seek bridge, native seek
 * bridge) used to inline its own copy of this dance, and the two seek bridges
 * had the order wrong — they held the guard before emitting, so their own
 * request never left the client.
 */
export function createLocalTransport(deps: LocalTransportDeps) {
  const guardMs = deps.guardMs ?? 250
  const schedule = deps.schedule ?? ((fn: () => void, ms: number) => { setTimeout(fn, ms) })
  const ticks = (seconds: number) => Math.round(seconds * deps.ticksPerSecond)

  const blocked = () => deps.blocked?.() === true

  function guarded(apply: () => void) {
    deps.hold()
    try { apply() } finally { schedule(deps.release, guardMs) }
  }

  function play(target: CommandTarget) {
    if (blocked()) return
    deps.emitPlay(ticks(target.currentTime || 0))
    // A blocked autoplay rejects; swallow it here rather than leaving an
    // unhandled rejection — the shared command has already been authored.
    guarded(() => { Promise.resolve(target.play()).catch(() => {}) })
  }

  function pause(target: CommandTarget) {
    if (blocked()) return
    deps.emitPause(ticks(target.currentTime || 0))
    guarded(() => target.pause())
  }

  /**
   * Absolute seek, clamped to the playable range. Returns the clamped target, or
   * null when the command was dropped because the position is untrustworthy.
   */
  function seekTo(target: CommandTarget, time: number) {
    if (blocked()) return null
    const to = clampSeekTarget(time, target.duration)
    deps.emitSeek(ticks(to))
    guarded(() => { target.currentTime = to })
    return to
  }

  /** Relative seek (±N seconds) from wherever the media currently is. */
  function seekBy(target: CommandTarget, delta: number) {
    return seekTo(target, (target.currentTime || 0) + delta)
  }

  return { play, pause, seekTo, seekBy }
}

export type LocalTransport = ReturnType<typeof createLocalTransport>
