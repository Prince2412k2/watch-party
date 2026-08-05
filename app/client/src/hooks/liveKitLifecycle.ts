/**
 * One attempt at "fetch a token, build a room, connect it".
 *
 * A LiveKit connect is a multi-await sequence, and React can tear the effect
 * down (unmount, party switch, `enabled` flip) at any await point. Without an
 * owner token for the attempt, the losing attempt still:
 *   - leaves its /api/livekit/token request running,
 *   - constructs a Room after cleanup and connects it (a leaked, live WebRTC
 *     session nobody will ever disconnect),
 *   - overwrites the ref the WINNING attempt just claimed, so camera/mic
 *     toggles drive the wrong room.
 *
 * A run bundles the AbortSignal with ownership of whatever it created, so the
 * cleanup path is a single `run.cancel()` and every post-await step can ask
 * `run.cancelled` before touching shared state.
 */
export interface LifecycleRun<T> {
  /** True once cancel() has been called — check after every await. */
  readonly cancelled: boolean
  /** Pass to fetch() so an in-flight token request dies with the run. */
  readonly signal: AbortSignal
  /** The resource this run owns, or null. Use for identity checks. */
  readonly resource: T | null
  /**
   * Hand a freshly created resource to the run. Returns false — after disposing
   * the resource — when the run is already over, which is the caller's signal
   * to stop and touch nothing else.
   */
  adopt: (resource: T) => boolean
  /** Abort the signal and dispose an adopted resource. Idempotent. */
  cancel: () => void
}

export function createLifecycleRun<T>({ dispose }: { dispose: (resource: T) => void }): LifecycleRun<T> {
  const controller = new AbortController()
  let cancelled = false
  let resource: T | null = null
  let disposed = false

  const disposeOnce = () => {
    if (disposed || resource == null) return
    disposed = true
    dispose(resource)
  }

  return {
    get cancelled() { return cancelled },
    get signal() { return controller.signal },
    get resource() { return resource },
    adopt(next: T) {
      if (cancelled) {
        // Lost the race: never publish it, never leave it connected.
        dispose(next)
        return false
      }
      resource = next
      return true
    },
    cancel() {
      if (cancelled) return
      cancelled = true
      controller.abort()
      disposeOnce()
    },
  }
}

/** True for the rejection an aborted fetch produces — our own doing, not an error to show. */
export function isAbortError(err: unknown): boolean {
  if (err == null || typeof err !== 'object') return false
  return (err as { name?: unknown }).name === 'AbortError'
}
