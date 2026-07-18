import type { PartyRole, PartySession } from './types'

export function partyRoleForUser(session: PartySession, userId?: string): PartyRole {
  if (!userId) return null
  if (session.hostId === userId) return 'host'
  return session.guests?.some(guest => guest.userId === userId) ? 'guest' : null
}

export function shouldOpenPartyPlayer(session: PartySession, role: PartyRole, pathname: string): boolean {
  return (role === 'host' || role === 'guest') && session.stage === 'watching' &&
    typeof session.mediaItemId === 'string' && !pathname.startsWith('/party/')
}

export function canManagePartyMedia(role: PartyRole): boolean {
  return role === 'host'
}
