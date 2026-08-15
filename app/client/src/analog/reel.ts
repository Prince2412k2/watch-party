/**
 * The reel's strobe engine — a port of `ui/widgets/reel_animation.dart`, which
 * is itself a port of the original `reel.svg`.
 *
 * The illusion is not scripted. The reel is given a real angular velocity with
 * real inertia and then only *looked at* once per shutter interval. Because the
 * ring is eight-fold symmetric the shutter cannot tell a 45° jump from standing
 * still: just under that rate the seats crawl forward, just over it they crawl
 * backwards. Sweeping the speed up and down through sync plays the whole
 * "speeds up, stalls, runs backwards" cycle in the right order, forever, with
 * nothing sequencing it.
 *
 * People board only while the strobe has the ring crawling, and step off the
 * moment it picks up — so the room fills when the reel looks slow enough to
 * step onto, which is the joke.
 *
 * Free of React and of the DOM: this is arithmetic, and it is the part worth
 * testing.
 */

export const SEAT_COUNT = 8

/** 20 frames/sec gate. */
export const SHUTTER = 1 / 20

/** 45° — one seat. */
export const SEAT_STEP = 360 / SEAT_COUNT

/** The speed, in deg/s, that reads as frozen under the shutter. */
export const SYNC_RATE = SEAT_STEP / SHUTTER

/** ±4% of lock: the slow see-saw people ride. */
const SWAY = 0.04
const SEESAW_SECONDS = 7
/** Peak of a surge, and how often one comes. */
const OVERSPEED = 1.3
const SURGE_CYCLE = 22
/** Higher = briefer surge, still smooth. */
const SURGE_SHARPNESS = 6

/** The reel cannot reach a new speed faster than this. */
export const SPIN_TAU = 1.6
/** The ring cannot change apparent direction faster than this. */
export const RING_TAU = 0.4

/** Boarding gates in apparent deg/s, with hysteresis so occupancy cannot
    chatter while the rate hovers on the boundary. */
export const BOARD_BELOW = 40
export const CLEAR_ABOVE = 78

/**
 * Frame-rate independent exponential approach: what keeps anything from
 * happening abruptly.
 */
export function approach(current: number, target: number, tau: number, dt: number): number {
  return current + (target - current) * (1 - Math.exp(-dt / tau))
}

/**
 * The speed program: one smooth function of time, no stages and no switches.
 *
 * `sway` is the gentle straddle of sync; the raised cosine is a rare, smooth
 * swell past it — near zero for most of the cycle with a soft shoulder either
 * side, so there is no ramp start and no ramp end to sequence.
 */
export function targetSpeed(t: number): number {
  const sway = SWAY * Math.sin((2 * Math.PI * t) / SEESAW_SECONDS)
  const bump = Math.pow(0.5 - 0.5 * Math.cos((2 * Math.PI * t) / SURGE_CYCLE), SURGE_SHARPNESS)
  return SYNC_RATE * (1 + sway + (OVERSPEED - 1) * bump)
}

/**
 * What a shutter SHOWS of [omega]: the turn between exposures folded into one
 * seat-width, signed toward the nearest seat.
 *
 * Turn 44° between exposures and the ring reads as crawling backwards 1°; turn
 * 46 and it creeps forward 1.
 */
export function apparentRate(omega: number): number {
  const perExposure = omega * SHUTTER
  let folded = ((perExposure % SEAT_STEP) + SEAT_STEP) % SEAT_STEP
  if (folded > SEAT_STEP / 2) folded -= SEAT_STEP
  return folded / SHUTTER
}

/**
 * Whether the ring is slow enough to step onto, given whether it was before.
 *
 * Hysteresis, not a threshold: one number would have people boarding and
 * leaving several times a second while the rate sat on it.
 */
export function boardingOpen(apparent: number, wasOpen: boolean): boolean {
  const speed = Math.abs(apparent)
  if (speed < BOARD_BELOW) return true
  if (speed > CLEAR_ABOVE) return false
  return wasOpen
}
