// The player chrome's auto-hide, as a React hook over `playerCore`.
//
// Before this existed the watch screen ran its own `setTimeout(…, 3000)` in
// Party.tsx with a single blocker (an open settings menu, ORed in by each bar
// locally). That timer knew nothing about playback state and nothing about
// whether the user was mid-interaction, so it could fade the chrome out from
// under a scrub in progress and kept counting down over a paused frame.
//
// Everything the hook decides is decided by the shared core; it owns only the
// clock and the timeout.
//
// The core's state lives in a ref rather than in `useState`, and only `visible`
// is React state. That is deliberate: every pointer move restarts the timer, so
// a `useState` holding the whole (always-new) state object would re-render the
// entire watch tree — player, skin, camera tiles — sixty times a second while
// the mouse moves. `setVisible` with an unchanged boolean is a no-op React bails
// out of, which is exactly the old behaviour's cost.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  holdControls,
  newAutoHideState,
  noteInput,
  releaseControls,
  setPlaying,
  tickAutoHide,
  type AutoHideState,
  type PlayerInputKind,
} from '../playerCore.ts'
import { hideNow, msUntilAutoHide } from './autoHideWiring.ts'

export interface AutoHideControls {
  /** Whether the chrome is up. */
  visible: boolean
  /** Relevant input: reveal and restart the three seconds. */
  note: (kind?: PlayerInputKind) => void
  /** Pin the chrome open for as long as `reason` is held. */
  hold: (reason: string) => void
  release: (reason: string) => void
  /** Phone tap-to-dismiss. Still refused while a hold is taken or paused. */
  hide: () => void
  /** Tap semantics: hide if up, reveal if down. */
  toggle: () => void
  /** Paused playback pins the chrome open. */
  setPlaybackPlaying: (playing: boolean) => void
}

export function useAutoHideControls({ playing = true }: { playing?: boolean } = {}): AutoHideControls {
  const [visible, setVisible] = useState(true)
  const stateRef = useRef<AutoHideState>(newAutoHideState(Date.now(), playing))
  const timerRef = useRef<number | null>(null)

  // Named function expression so the timeout can re-enter it without depending
  // on the identity of a `const` from any particular render.
  const apply = useCallback(function apply(next: AutoHideState) {
    stateRef.current = next
    setVisible(next.visible)
    if (timerRef.current != null) window.clearTimeout(timerRef.current)
    timerRef.current = null
    const delay = msUntilAutoHide(next, Date.now())
    if (delay == null) return
    timerRef.current = window.setTimeout(() => {
      timerRef.current = null
      apply(tickAutoHide(stateRef.current, Date.now()))
    }, delay)
  }, [])

  useEffect(() => {
    apply(stateRef.current)   // arm on mount, exactly as the old poke() did
    return () => { if (timerRef.current != null) window.clearTimeout(timerRef.current) }
  }, [apply])

  const note = useCallback((kind: PlayerInputKind = 'pointer') => {
    apply(noteInput(stateRef.current, kind, Date.now()))
  }, [apply])

  const hold = useCallback((reason: string) => {
    apply(holdControls(stateRef.current, reason))
  }, [apply])

  const release = useCallback((reason: string) => {
    apply(releaseControls(stateRef.current, reason, Date.now()))
  }, [apply])

  const hide = useCallback(() => {
    apply(hideNow(stateRef.current, Date.now()))
  }, [apply])

  const toggle = useCallback(() => {
    const now = Date.now()
    const current = stateRef.current
    apply(current.visible ? hideNow(current, now) : noteInput(current, 'tap', now))
  }, [apply])

  const setPlaybackPlaying = useCallback((next: boolean) => {
    apply(setPlaying(stateRef.current, next, Date.now()))
  }, [apply])

  useEffect(() => { setPlaybackPlaying(playing) }, [playing, setPlaybackPlaying])

  return useMemo(
    () => ({ visible, note, hold, release, hide, toggle, setPlaybackPlaying }),
    [visible, note, hold, release, hide, toggle, setPlaybackPlaying],
  )
}
