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
//    verified signature is an equivalent proof of prior authentication.
export async function authorizeLiveKitUpgrade({ session, accessToken, tokenVerifier }) {
  if (session?.jellyfin) return true
  if (!accessToken || !tokenVerifier) return false
  try {
    await tokenVerifier.verify(accessToken)
    return true
  } catch {
    return false
  }
}
