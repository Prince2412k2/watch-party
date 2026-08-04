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
