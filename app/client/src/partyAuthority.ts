import type { PartyRole, PartySession } from './types'

export function partyRoleForUser(session: PartySession, userId?: string): PartyRole {
  if (!userId) return null
  if (session.hostId === userId) return 'host'
  return session.guests?.some(guest => guest.userId === userId) ? 'guest' : null
}

export function shouldOpenPartyPlayer(session: PartySession, role: PartyRole, pathname: string): boolean {
  if (role !== 'host' && role !== 'guest') return false
  if (pathname.startsWith('/party/')) return false
  // The shared browser is started from the popcorn widget, which lives in the
  // home shell — so the party surface is NOT open when the activity changes.
  // Without this, the host would press the button on the home screen and nothing
  // visible would happen, and guests would never be pulled in at all.
  if (session.stage === 'browser') return true
  return session.stage === 'watching' && typeof session.mediaItemId === 'string'
}

export function canManagePartyMedia(role: PartyRole): boolean {
  return role === 'host'
}

/** The sentinel target for /party/new — WatchRoute never routes it as an id. */
export const NEW_PARTY_TARGET = 'new'

export type PartyJoinAction =
  | { kind: 'idle' }
  | { kind: 'create'; target: string; leavePrevious: boolean }
  | { kind: 'join'; target: string; leavePrevious: boolean }

/**
 * What the Party surface must do for the URL it is currently pointed at.
 *
 * App.jsx renders ONE mount-stable <Party> element for every /party/* URL (so a
 * rotation cannot tear down a live session), which means navigating straight
 * from /party/AAA to /party/BBB only changes a prop. The old latch was a plain
 * boolean "already joined", so that navigation kept the AAA session — AAA's
 * LiveKit room, AAA's schedule — under a URL that said BBB. Keying the latch on
 * the target instead makes the second navigation a real leave + join.
 */
export function partyJoinTransition(
  { joinedFor, partyId, isNew }: { joinedFor: string | null; partyId?: string; isNew?: boolean },
): PartyJoinAction {
  const target = isNew ? NEW_PARTY_TARGET : partyId
  if (!target) return { kind: 'idle' }
  // Same target as the last run: React StrictMode's double-invoke and any
  // unrelated re-render must not create or join twice.
  if (joinedFor === target) return { kind: 'idle' }
  const leavePrevious = joinedFor !== null
  return { kind: isNew ? 'create' : 'join', target, leavePrevious }
}
