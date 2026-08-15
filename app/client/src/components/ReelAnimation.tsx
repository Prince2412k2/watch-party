import { useEffect, useRef, useState } from 'react'
import {
  RING_TAU,
  SEAT_COUNT,
  SEAT_STEP,
  SPIN_TAU,
  apparentRate,
  approach,
  boardingOpen,
  targetSpeed,
} from '../analog/reel.ts'

/**
 * The reel: a film disc spinning under a shutter, with people boarding the
 * seats whenever it looks slow enough to step onto.
 *
 * The desktop client draws this on the login page; here it stands beside a room
 * that is being reconnected, which is the same moment — the app is doing
 * something on your behalf and there is nothing for you to do but see that it
 * is happening.
 *
 * The strobe arithmetic is in `analog/reel.ts`, with its own tests. This holds
 * the frame loop and the shapes: the streak rings are drawn at the TRUE angle
 * and the seat ring at the SAMPLED one, and their disagreement is the point —
 * it reads as far too fast to follow even while the seats appear to crawl.
 */
export default function ReelAnimation() {
  const [ring, setRing] = useState(0)
  const [spin, setSpin] = useState(0)
  const [seats, setSeats] = useState<boolean[]>(() => Array(SEAT_COUNT).fill(false))

  // Everything the loop mutates lives in a ref: this runs at frame rate, and
  // routing it through state would re-render the whole tree sixty times a
  // second to move two numbers.
  const engine = useRef({
    trueAngle: 0,
    ringAngle: 0,
    omega: 0,
    ringRate: 0,
    clock: 0,
    last: 0,
    open: false,
    target: 3 + Math.floor(Math.random() * 5),
    nextTick: 0.4,
    seats: Array(SEAT_COUNT).fill(false) as boolean[],
  })

  useEffect(() => {
    // Respect a viewer who has asked for less motion: the reel is decoration,
    // and its whole character is movement.
    const reduced = window.matchMedia?.('(prefers-reduced-motion: reduce)')
    if (reduced?.matches) {
      setSeats(Array(SEAT_COUNT).fill(true).map((_, i) => i % 3 !== 0))
      return
    }

    let frame = 0
    const tick = (now: number) => {
      const state = engine.current
      const dt = state.last === 0 ? 0 : Math.min((now - state.last) / 1000, 0.1)
      state.last = now
      if (dt > 0) {
        state.clock += dt
        // The reel chases its target speed but never snaps to it. This is the
        // inertia, and it is why nothing lurches.
        state.omega = approach(state.omega, targetSpeed(state.clock), SPIN_TAU, dt)
        // The fold is a sawtooth — cross a half-seat and it flips sign
        // instantly. Physically honest, and it lands as a jolt, so the apparent
        // rate eases toward it instead: the reversal survives, it just takes
        // RING_TAU to swing through.
        state.ringRate = approach(state.ringRate, apparentRate(state.omega), RING_TAU, dt)
        state.trueAngle += state.omega * dt
        state.ringAngle += state.ringRate * dt
        state.open = boardingOpen(state.ringRate, state.open)

        if (state.clock >= state.nextTick) {
          board(state)
          setSeats([...state.seats])
        }
        setRing(state.ringAngle)
        setSpin(state.trueAngle)
      }
      frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [])

  return (
    <svg className="an-reel" viewBox="0 0 600 600" aria-hidden>
      <g transform="translate(300 300)">
        <circle r="205" fill="#FD2C3F" />
        <circle r="205" fill="none" stroke="#D91F31" strokeWidth="9" />

        {/* Drawn at the TRUE angle: far too fast to follow, and disagreeing
            with the seats on purpose. */}
        <g transform={`rotate(${spin})`}>
          {STREAKS.map((streak, index) => (
            <circle
              key={index}
              r={streak.radius}
              fill="none"
              stroke="#2E1B2C"
              strokeOpacity={streak.opacity}
              strokeWidth={streak.width}
              strokeDasharray={`${streak.dash} ${streak.gap}`}
              transform={`rotate(${spin * (streak.rate - 1)})`}
            />
          ))}
        </g>

        {/* Drawn at the SAMPLED angle: what the shutter lets you see. */}
        <g transform={`rotate(${ring})`}>
          {seats.map((occupied, index) => {
            const angle = (index * SEAT_STEP * Math.PI) / 180
            const x = Math.cos(angle) * ORBIT
            const y = Math.sin(angle) * ORBIT
            return (
              <g key={index} transform={`translate(${x} ${y})`}>
                <circle r={HOLE / 2} fill="#2E1B2C" />
                <circle
                  r={HEAD / 2}
                  fill="#FAF2E4"
                  opacity={occupied ? 1 : 0}
                  style={{ transition: 'opacity 300ms ease' }}
                />
              </g>
            )
          })}
        </g>

        <circle r="70" fill="#2E1B2C" />
        <circle r="46" fill="#FAF2E4" />
      </g>
    </svg>
  )
}

const ORBIT = 160
const HOLE = 36
const HEAD = 31

/** Rates deliberately unrelated, so the rings never beat together into a
    readable pattern — that would kill the smear. */
const STREAKS = [
  { radius: 88, width: 12, opacity: 0.1, dash: 3, gap: 26, rate: 1.0 },
  { radius: 102, width: 7, opacity: 0.16, dash: 6, gap: 20, rate: -0.78 },
  { radius: 114, width: 3, opacity: 0.34, dash: 24, gap: 12, rate: 1.34 },
  { radius: 200, width: 4, opacity: 0.3, dash: 14, gap: 10, rate: 1.7 },
]

/**
 * Who gets on and who gets off.
 *
 * Deliberately off the shutter beat, so joins and leaves read as their own
 * events rather than as something the reel is doing to them.
 */
function board(state: {
  clock: number
  open: boolean
  target: number
  nextTick: number
  seats: boolean[]
}) {
  const empty: number[] = []
  const taken: number[] = []
  state.seats.forEach((occupied, index) => (occupied ? taken : empty).push(index))
  const pick = (list: number[]) => list[Math.floor(Math.random() * list.length)]

  if (!state.open) {
    // Moving too fast to board — everyone steps off, one at a time.
    if (taken.length > 0) state.seats[pick(taken)] = false
    state.nextTick = state.clock + 0.17 + Math.random() * 0.16
    return
  }

  if (taken.length < state.target && empty.length > 0) {
    state.seats[pick(empty)] = true
  } else if (Math.random() < 0.45 && taken.length > 0) {
    state.seats[pick(taken)] = false
  } else if (empty.length > 0) {
    state.seats[pick(empty)] = true
  }
  state.nextTick = state.clock + 0.3 + Math.random() * 0.5
}
