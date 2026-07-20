import type { PartyRole, PartySession } from './types'

export function partyRoleForUser(session: PartySession, userId?: string): PartyRole {
  if (!userId) return null
  if (session.hostId === userId) return 'host'
  return session.guests?.some(guest => guest.userId === userId) ? 'guest' : null
}

export function shouldOpenPartyPlayer(session: PartySession, role: PartyRole, pathname: string): boolean {
  if (!(role === 'host' || role === 'guest') || pathname.startsWith('/party/')) return false
  // A remote-browser activity has its own full-screen view (RemoteBrowser),
  // reached through the same party-player route as watching.
  if (session.activity === 'remote-browser') return true
  return session.stage === 'watching' && typeof session.mediaItemId === 'string'
}

export function canManagePartyMedia(role: PartyRole): boolean {
  return role === 'host'
}
