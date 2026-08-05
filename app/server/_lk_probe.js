import { TokenVerifier } from 'livekit-server-sdk'

// '/livekit' upgrades are the only ones proxied here (see index.js); everything
// else on this http.Server's 'upgrade' event belongs to socket.io. Matching on
// the parsed pathname (not req.url.startsWith) is what stops '/livekitfoo'
// from sneaking past this filter the way a raw string prefix check would.
export function isLiveKitUpgradePath(pathname) {
  return pathname === '/livekit' || pathname.startsWith('/livekit/')
}

export function createLiveKitTokenVerifier(apiKey, apiSecret) {
  return apiKey && apiSecret ? new TokenVerifier(apiKey, apiSecret) : null
}

// Authorizes a LiveKit WebSocket upgrade. Two proofs are accepted because the
// two clients reach this proxy over different transports:
//  - the browser's WS upgrade carries the session cookie same-origin, so an
//    authenticated req.session (populated by running sessionMiddleware
//    against the raw upgrade request) is sufficient;
//  - the Flutter app's LiveKit socket is a native transport that doesn't share
//    the app's cookie jar and so never presents that cookie. Every LiveKit
//    client, browser or native, does attach the room/user-scoped access_token
//    as a query param (that's LiveKit's own protocol) — and that token only
//    exists because requireAuth on GET /api/livekit/token minted it. A
//    verified signature is an equivalent proof of prior authentication. Its
//    identity and room are still checked against current party state below.
export async function authorizeLiveKitUpgrade({
  session,
  accessToken,
  tokenVerifier,
  getParty,
  isPartyMember,
  isServiceIdentity = () => false,
  isTokenRevoked = () => false,
}) {
  if (!accessToken) return Boolean(session?.jellyfin)
  if (!tokenVerifier || !getParty || !isPartyMember) return false
  try {
    const claims = await tokenVerifier.verify(accessToken)
    const identity = claims.sub
    const room = claims.video?.room
    if (!identity || !room || claims.video?.roomJoin !== true) return false

    const party = getParty(room)
    if (!party) return false
    if (isTokenRevoked(party, identity, claims.nbf)) return false
    if (isPartyMember(party, identity)) {
      return !session?.jellyfin || session.jellyfin.userId === identity
    }
    return isServiceIdentity(identity, party)
  } catch {
    return false
  }
}
