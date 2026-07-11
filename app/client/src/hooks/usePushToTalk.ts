import { useCallback, useEffect, useRef, useState } from 'react'

// Push-to-talk: hold a key (desktop) or a button (phone) to temporarily open the
// mic, releasing returns it to muted. This pairs with default-mute-on-movie-start
// so the room stays quiet (no movie-audio echo) and people talk only in bursts.
//
// Key choice: **T** ("talk"). The watch screen's other shortcuts are space/k
// (play), arrows (seek/volume), l/j (seek), m (mute video), f (fullscreen),
// c (chat) — 't' collides with none of them.
//
// Semantics:
//  • PTT *temporarily overrides* the muted state and returns to whatever it was.
//  • If the user has MANUALLY unmuted, PTT is a no-op — start() bails when the
//    mic is already on, so release never surprises them by muting.
//  • Guards key-repeat (both `e.repeat` and an active-hold ref) so a held key
//    doesn't spam enableMic.
//  • keyup AND window blur both release, so the mic is never left stuck open if
//    focus leaves mid-hold (alt-tab, clicking a devtools panel, etc.).
//  • Ignores keystrokes while typing in an input/textarea/contentEditable, the
//    same guard the transport-key handler uses.
export function usePushToTalk({ micOn, enableMic, enabled = true }) {
  const [talking, setTalking] = useState(false)
  // Refs so the window listeners always read fresh values without re-binding.
  const micOnRef = useRef(micOn)
  micOnRef.current = micOn
  const enableMicRef = useRef(enableMic)
  enableMicRef.current = enableMic
  // True while PTT is holding the mic open — distinguishes a PTT-driven unmute
  // from a manual one, and doubles as the key-repeat guard.
  const holdingRef = useRef(false)

  const start = useCallback(() => {
    if (!enabled) return
    if (holdingRef.current) return    // already talking (guards key-repeat spam)
    if (micOnRef.current) return      // manually unmuted → PTT is a no-op
    holdingRef.current = true
    setTalking(true)
    enableMicRef.current(true)
  }, [enabled])

  const stop = useCallback(() => {
    if (!holdingRef.current) return   // wasn't a PTT hold → leave manual state alone
    holdingRef.current = false
    setTalking(false)
    enableMicRef.current(false)       // return to muted (the PTT default state)
  }, [])

  useEffect(() => {
    if (!enabled) return
    const isTyping = (t) => t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)
    const onKeyDown = (e) => {
      if (e.repeat) return                                    // key-repeat guard
      if (e.key.toLowerCase() !== 't') return
      if (e.ctrlKey || e.metaKey || e.altKey) return          // don't hijack shortcuts
      if (isTyping(e.target)) return
      start()
    }
    const onKeyUp = (e) => { if (e.key.toLowerCase() === 't') stop() }
    // Losing focus mid-hold means we'll never see keyup — force-release so the
    // mic can't get stuck open.
    const onBlur = () => stop()
    window.addEventListener('keydown', onKeyDown)
    window.addEventListener('keyup', onKeyUp)
    window.addEventListener('blur', onBlur)
    return () => {
      window.removeEventListener('keydown', onKeyDown)
      window.removeEventListener('keyup', onKeyUp)
      window.removeEventListener('blur', onBlur)
      stop()   // unmount cleanup: never leave the mic held open
    }
  }, [enabled, start, stop])

  // `start`/`stop` are also returned for the phone press-and-hold button.
  return { talking, start, stop }
}
