/**
 * When a room has been lost, and what to say about it.
 *
 * A dropped party used to be silent on both clients: chat stopped arriving,
 * playback stopped following the host, and nothing on screen said so. Socket.IO
 * reconnects its transport by itself and PartyContext re-resumes the session
 * when it does, so the retrying was already happening — what was missing was
 * anyone being told, and a way to stop waiting and leave.
 *
 * The same rules as `flutter_app/lib/state/party_connection_provider.dart`.
 * Free of React so it can be tested directly.
 */

import type { PartyUser } from '../types.ts'

/**
 * Whether the reconnect surface belongs on screen.
 *
 * Holding a party is the whole condition. The socket being down on its own
 * means nothing — there is no room to be cut off from — and a party is only
 * ever held because the socket was up to join it.
 */
export function shouldShowReconnect(inParty: boolean, connected: boolean): boolean {
  return inParty && !connected
}

/**
 * The status line.
 *
 * The attempt count only appears once a drop has outlived being a blip.
 * Leading with "attempt 1" makes an outage of no consequence look like a fault.
 */
export function reconnectLabel(attempt: number): string {
  return attempt > 2 ? `Reconnecting… (attempt ${attempt})` : 'Reconnecting…'
}

/** Everyone in the room, host first. */
export function orderFaces(
  participants: readonly PartyUser[],
  hostId: string | undefined,
): PartyUser[] {
  const host = participants.filter(p => p.userId === hostId)
  const rest = participants.filter(p => p.userId !== hostId)
  return [...host, ...rest]
}

/**
 * How long to wait before the nth retry: 1s, 2s, 4s, 8s, then every 15s.
 *
 * Socket.IO owns the actual schedule here; this exists so the surface can count
 * attempts on the same curve the desktop client retries on, and so the two
 * cannot silently diverge.
 */
export function retryBackoffMs(attempt: number): number {
  if (attempt <= 0) return 1000
  return Math.min(15, 1 << Math.min(attempt, 4)) * 1000
}
