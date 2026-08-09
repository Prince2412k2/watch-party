// The logic behind the two corner widgets, with no React and no DOM in it.
//
// Both widgets are icon-only, which moves a lot of weight onto things a
// component test in this repo could not see anyway: what each control *means*,
// which ones only the host may reach, and what may open a surface. Keeping all
// of that here as data means the accessible name of every control is a value
// that can be asserted, rather than a string typed inline next to an <svg> and
// hoped for.
//
// Two guardrails from docs/watchparty-design/analog-interface-reference.md are
// expressed as code here rather than as comments in a component:
//
//   "No hover-only controls."  -> `hover` is an event the tray machine ignores.
//   "No important action hidden behind gesture-only interaction."
//                              -> every control below is a button with a name.

import type { PartyRole, PartySession } from '../types.ts'

/**
 * Names drawn from `AN_ICONS` in icons.tsx. Spelled out rather than imported so
 * this module stays free of JSX and can run under `node --test`; the component
 * passing one of these to <AnIcon> is what makes tsc check the two agree.
 */
export type WidgetIcon =
  | 'user'
  | 'users'
  | 'update'
  | 'settings'
  | 'logout'
  | 'plus'
  | 'enter'
  | 'qr'
  | 'link'
  | 'check'
  | 'x'
  | 'lock'
  | 'unlock'
  | 'star'
  | 'power'
  | 'sound'
  | 'mute'

/**
 * One icon-only button.
 *
 * `label` is not decoration: with no text on the control it is the entire
 * accessible name and the entire tooltip, so a control without one is unusable
 * rather than merely untidy. `everyControlIsNamed` in the tests refuses to let
 * one through.
 */
export interface IconControl {
  id: string
  icon: WidgetIcon
  label: string
  /** Toggles report their state; plain actions leave this undefined. */
  pressed?: boolean
  /** Drawn with a dashed edge and an accent mark — see analogKit.css. */
  hostOnly?: boolean
  tone?: 'danger'
  disabled?: boolean
}

/** The suffix that makes a host-only control say so out loud. */
export const HOST_ONLY_SUFFIX = ' (host only)'

const hostOnly = (control: Omit<IconControl, 'hostOnly'>): IconControl => ({
  ...control,
  label: control.label + HOST_ONLY_SUFFIX,
  hostOnly: true,
})

// ── the tray / expansion machine ────────────────────────────────────────────

export type WidgetEvent =
  | { type: 'toggle' }
  | { type: 'open' }
  | { type: 'close' }
  | { type: 'escape' }
  | { type: 'pointerOutside' }
  | { type: 'pointerInside' }
  /** Pointer entered the trigger. Deliberately inert — see below. */
  | { type: 'hover' }
  /** A control inside the surface was used. `sticky` keeps the surface up. */
  | { type: 'action'; sticky?: boolean }

export interface WidgetState {
  open: boolean
  /**
   * Whether focus should be put back on the corner trigger after this
   * transition. True when the surface closed for a reason the user drove from
   * the keyboard or from inside the surface; false when they simply pointed
   * somewhere else, where stealing focus back would fight them.
   */
  returnFocus: boolean
}

export const closedWidget: WidgetState = { open: false, returnFocus: false }

const opened: WidgetState = { open: true, returnFocus: false }
const closedTo = (returnFocus: boolean): WidgetState => ({ open: false, returnFocus })

/**
 * The whole open/close contract for a corner widget.
 *
 * `hover` never changes anything. That is the "no hover-only controls"
 * guardrail: a tray that opened on hover would put update, settings and sign-out
 * behind a gesture that touch and keyboard users do not have, and it is the
 * obvious thing to reach for when the trigger is a bare icon.
 */
export function widgetNext(state: WidgetState, event: WidgetEvent): WidgetState {
  switch (event.type) {
    case 'hover':
      return state
    case 'open':
      return state.open ? state : opened
    case 'toggle':
      return state.open ? closedTo(true) : opened
    case 'close':
      return state.open ? closedTo(true) : state
    case 'escape':
      return state.open ? closedTo(true) : state
    case 'pointerOutside':
      return state.open ? closedTo(false) : state
    case 'pointerInside':
      return state
    case 'action':
      // A sticky action is one whose result is shown inside the surface — the
      // update check, the QR toggle — so closing over it would hide the answer.
      return event.sticky || !state.open ? state : closedTo(true)
  }
}

// ── profile tray ────────────────────────────────────────────────────────────

export type UpdateStatus = 'idle' | 'checking' | 'current' | 'available' | 'failed'

/**
 * What the update control shows. Icon-only, so the status has to survive being
 * compressed into one glyph plus one accessible name.
 */
export function updateControl(status: UpdateStatus): IconControl {
  switch (status) {
    case 'checking':
      return { id: 'update', icon: 'update', label: 'Checking for updates', disabled: true }
    case 'current':
      return { id: 'update', icon: 'check', label: 'Up to date — check again' }
    case 'available':
      return { id: 'update', icon: 'update', label: 'Update available — reload now' }
    case 'failed':
      return { id: 'update', icon: 'x', label: 'Update check failed — try again', tone: 'danger' }
    case 'idle':
      return { id: 'update', icon: 'update', label: 'Check for updates' }
  }
}

export type ProfileTrayAction = 'update' | 'sound' | 'settings' | 'signOut'

/**
 * What slides out of the corner, left to right.
 *
 * The sound toggle is here because "optional subtle interface sound and
 * platform haptics, always user-controllable" is a guardrail, and the shelf's
 * detent cue (analog/cue.ts, played from AnalogShelf) has no other switch
 * anywhere in the client. It is a toggle rather than a row of words, so it
 * costs one glyph.
 */
export function profileTrayControls(status: UpdateStatus, soundOn: boolean): IconControl[] {
  return [
    updateControl(status),
    {
      id: 'sound',
      icon: soundOn ? 'sound' : 'mute',
      label: soundOn ? 'Turn interface sound off' : 'Turn interface sound on',
      pressed: soundOn,
    },
    { id: 'settings', icon: 'settings', label: 'Settings and profile' },
    { id: 'signOut', icon: 'logout', label: 'Sign out', tone: 'danger' },
  ]
}

/** Only a resolved check-result is worth clearing when the tray closes. */
export const isSettledUpdate = (status: UpdateStatus): boolean =>
  status === 'current' || status === 'failed'

// ── update check ────────────────────────────────────────────────────────────

const MODULE_SCRIPT = /<script[^>]*\btype=["']module["'][^>]*\bsrc=["']([^"']+)["']/gi

/**
 * Whether a module script is part of the build rather than the dev server.
 *
 * Vite serves `/@vite/client` and friends only while developing, and they come
 * and go independently of the app's own bundle. Counting them would make the
 * check report an update on every dev reload.
 */
export const isAppModule = (src: string): boolean => src.length > 0 && !src.startsWith('/@')

/**
 * The hashed entry modules named by a copy of index.html.
 *
 * This is how "check for updates" works on the web client: the served
 * index.html is re-fetched past the cache and its entry script compared with
 * the one this document is running. A deploy changes the hash in that filename,
 * so a difference means a newer build exists — and no version endpoint, service
 * worker or build-time constant has to be introduced to find out.
 */
export function entryModules(html: string): string[] {
  const found: string[] = []
  for (const match of html.matchAll(MODULE_SCRIPT)) {
    if (isAppModule(match[1])) found.push(match[1])
  }
  return found
}

/**
 * `failed` rather than `current` when either side is empty: an index.html we
 * could not read anything out of is an unknown answer, and reporting unknown as
 * "up to date" is the one wrong answer this control can give.
 */
export function updateOutcome(
  loaded: readonly string[],
  latest: readonly string[],
): Exclude<UpdateStatus, 'idle' | 'checking'> {
  if (loaded.length === 0 || latest.length === 0) return 'failed'
  const same =
    loaded.length === latest.length && loaded.every((src, index) => src === latest[index])
  return same ? 'current' : 'available'
}

// ── join codes ──────────────────────────────────────────────────────────────

export const JOIN_CODE_PATTERN = /^[0-9A-F]{8}$/

/**
 * Whatever was typed or pasted, reduced to the thing the server accepts.
 *
 * Pasting the invite link is the obvious mistake to make when the widget's own
 * copy-link button is the control right next to the field, so a URL is reduced
 * to its last path segment rather than rejected.
 */
export function normalizeJoinCode(raw: string): string {
  const path = raw.trim().split(/[?#]/)[0]
  const segments = path.split('/').filter((part) => part.length > 0)
  const candidate = segments.length > 0 ? segments[segments.length - 1] : path
  return candidate.toUpperCase()
}

export const isJoinCode = (raw: string): boolean => JOIN_CODE_PATTERN.test(normalizeJoinCode(raw))

/** What the invite QR encodes and the copy button copies. */
export const inviteUrl = (origin: string, partyId: string): string =>
  `${origin.replace(/\/$/, '')}/party/${partyId}`

// ── watch-party widget ──────────────────────────────────────────────────────

export type PartyWidgetMode = 'idle' | 'joining' | 'live'

/** One person in the room, with whatever this viewer may do about them. */
export interface RosterEntry {
  userId: string
  name: string
  host: boolean
  waiting: boolean
  actions: IconControl[]
}

export interface PartyWidgetView {
  mode: PartyWidgetMode
  /** Accessible name for the corner trigger itself. */
  triggerLabel: string
  live: boolean
  /** Approvals only the host can answer; 0 for everyone else. */
  alerts: number
  controls: IconControl[]
  roster: RosterEntry[]
}

export interface PartyWidgetInput {
  session: PartySession | null
  role: PartyRole
  /** The code field is showing instead of the create/join pair. */
  joining?: boolean
  showQr?: boolean
  showRoster?: boolean
  /** The invite link went to the clipboard a moment ago. */
  copied?: boolean
  /** A create or join request is in flight. */
  busy?: boolean
}

function memberCount(session: PartySession): number {
  return 1 + (session.guests?.length ?? 0)
}

function rosterFor(session: PartySession, isHost: boolean): RosterEntry[] {
  const host: RosterEntry = {
    userId: session.hostId,
    name: session.hostName || 'Host',
    host: true,
    waiting: false,
    actions: [],
  }

  const guests = (session.guests ?? []).map<RosterEntry>((guest) => ({
    userId: guest.userId,
    name: guest.name,
    host: false,
    waiting: false,
    actions: isHost
      ? [
          hostOnly({ id: `promote:${guest.userId}`, icon: 'star', label: `Make ${guest.name} host` }),
          hostOnly({
            id: `kick:${guest.userId}`,
            icon: 'x',
            label: `Remove ${guest.name} from the party`,
            tone: 'danger',
          }),
        ]
      : [],
  }))

  // Waiting members are the host's alone: a guest is not shown a queue it can
  // do nothing about.
  const waiting = isHost
    ? (session.waiting ?? []).map<RosterEntry>((person) => ({
        userId: person.userId,
        name: person.name,
        host: false,
        waiting: true,
        actions: [
          hostOnly({ id: `approve:${person.userId}`, icon: 'check', label: `Let ${person.name} in` }),
          hostOnly({
            id: `reject:${person.userId}`,
            icon: 'x',
            label: `Turn ${person.name} away`,
            tone: 'danger',
          }),
        ],
      }))
    : []

  return [host, ...guests, ...waiting]
}

/**
 * Everything the lower-right widget draws, for the state it is actually in.
 *
 * Outside a party that is create and join-by-code; inside one it is the room
 * controls, with the host's extras marked so the component cannot render them
 * as though every participant had them.
 */
export function partyWidgetView({
  session,
  role,
  joining = false,
  showQr = false,
  showRoster = false,
  copied = false,
  busy = false,
}: PartyWidgetInput): PartyWidgetView {
  if (!session) {
    const controls: IconControl[] = joining
      ? [
          { id: 'joinSubmit', icon: 'enter', label: 'Join this party', disabled: busy },
          { id: 'joinCancel', icon: 'x', label: 'Cancel joining' },
        ]
      : [
          { id: 'create', icon: 'plus', label: 'Start a watch party', disabled: busy },
          { id: 'join', icon: 'enter', label: 'Join a party with a code' },
        ]
    return {
      mode: joining ? 'joining' : 'idle',
      triggerLabel: 'Watch party',
      live: false,
      alerts: 0,
      controls,
      roster: [],
    }
  }

  const isHost = role === 'host'
  const waiting = isHost ? (session.waiting ?? []).length : 0
  const controls: IconControl[] = [
    {
      id: 'qr',
      icon: 'qr',
      label: showQr ? 'Hide the invite code' : 'Show the invite code',
      pressed: showQr,
    },
    {
      id: 'copy',
      icon: copied ? 'check' : 'link',
      label: copied ? 'Invite link copied' : 'Copy the invite link',
    },
    {
      id: 'roster',
      icon: 'users',
      label: showRoster ? 'Hide who is here' : 'Show who is here',
      pressed: showRoster,
    },
  ]

  if (isHost) {
    const collaborative = session.collaborativeControl === true
    controls.push(
      hostOnly({
        id: 'collaborative',
        icon: collaborative ? 'unlock' : 'lock',
        label: collaborative ? 'Stop guests browsing' : 'Let guests browse',
        pressed: collaborative,
      }),
    )
  }

  controls.push(
    isHost
      ? hostOnly({ id: 'end', icon: 'power', label: 'End the party for everyone', tone: 'danger' })
      : { id: 'leave', icon: 'logout', label: 'Leave the party', tone: 'danger' },
  )

  return {
    mode: 'live',
    triggerLabel: `Watch party — ${memberCount(session)} here`,
    live: true,
    alerts: waiting,
    controls,
    roster: rosterFor(session, isHost),
  }
}

/** Every button the widget can render in this state, roster actions included. */
export const allPartyControls = (view: PartyWidgetView): IconControl[] => [
  ...view.controls,
  ...view.roster.flatMap((entry) => entry.actions),
]
