import { useAuth } from '../context/AuthContext'
import { useParty } from '../context/PartyContext'
import type { AvatarConfig } from '../lib/avatar'

/**
 * The saved avatar for someone in the current party: mine from my own profile,
 * everyone else's from party state (which the server refreshes whenever any
 * member saves, so this follows their edits without a reload).
 *
 * Null means they have never customised one — the caller draws their derived
 * default from the same `userId`, so a missing profile is never a missing face.
 */
export function useMemberAvatar(userId?: string): AvatarConfig | null {
  const { user, profile } = useAuth()
  const { session } = useParty()

  if (!userId) return null
  if (userId === user?.userId) return profile?.avatar ?? null
  if (session?.hostId === userId) return session.hostAvatar ?? null
  return session?.guests?.find(guest => guest.userId === userId)?.avatar ?? null
}
