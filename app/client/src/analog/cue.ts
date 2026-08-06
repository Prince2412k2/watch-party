// The detent cue — a short mechanical tick as focus steps from one poster to
// the next, plus a haptic pulse where the platform has one.
//
// "Optional subtle interface sound and platform haptics, always
// user-controllable." The existing poster cue (pages/Library.tsx:80-98) has no
// off switch at all, so the preference is the point of moving it here rather
// than the oscillator.

const STORAGE_KEY = 'watchparty-analog-cue'

export function cueEnabled(): boolean {
  try {
    return window.localStorage.getItem(STORAGE_KEY) !== 'off'
  } catch {
    // Private mode / storage blocked. Sound on by default is the same answer.
    return true
  }
}

export function setCueEnabled(enabled: boolean): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, enabled ? 'on' : 'off')
  } catch {
    // Preference is best-effort; the cue still respects it for this session.
  }
}

let context: AudioContext | null = null

/** A single detent. Short, quiet, and pitched down — a click, not a chime. */
export function playDetentCue(): void {
  if (!cueEnabled()) return
  try {
    const audio = (context ??= new AudioContext())
    const oscillator = audio.createOscillator()
    const gain = audio.createGain()
    const now = audio.currentTime
    oscillator.type = 'sine'
    oscillator.frequency.setValueAtTime(460, now)
    oscillator.frequency.exponentialRampToValueAtTime(360, now + 0.045)
    gain.gain.setValueAtTime(0.018, now)
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.055)
    oscillator.connect(gain).connect(audio.destination)
    oscillator.start(now)
    oscillator.stop(now + 0.06)
  } catch {
    // Audio feedback is optional when Web Audio is unavailable or blocked.
  }
  try {
    navigator.vibrate?.(6)
  } catch {
    // Haptics are equally optional.
  }
}
