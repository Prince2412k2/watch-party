import { AccessToken } from 'livekit-server-sdk'
import { requireAuth, getJellyfin } from './auth.js'
import { getSession, isMember } from './session.js'

export function registerLiveKitRoutes(app) {
  app.get('/api/livekit/token', requireAuth, async (req, res) => {
    const { partyId } = req.query
    const { userId } = getJellyfin(req)

    const session = getSession(partyId)
    if (!session) return res.status(404).json({ error: 'party not found' })
    if (!isMember(session, userId) && session.hostId !== userId) {
      return res.status(403).json({ error: 'not a party member' })
    }

    const token = new AccessToken(
      process.env.LIVEKIT_API_KEY,
      process.env.LIVEKIT_API_SECRET,
      { identity: userId, name: req.session.jellyfin.name }
    )
    token.addGrant({ roomJoin: true, room: partyId, canPublish: true, canSubscribe: true })

    // The URL handed to the BROWSER must be browser-reachable — NOT the internal
    // container address (LIVEKIT_URL=ws://livekit:7880 is server-side only).
    // LIVEKIT_PUBLIC_URL is either a published host address (ws://host:7880) or,
    // behind HTTPS, the app-origin signaling proxy (wss://<host>/livekit).
    res.json({
      token: await token.toJwt(),
      url: process.env.LIVEKIT_PUBLIC_URL || process.env.LIVEKIT_URL || 'ws://localhost:7880',
    })
  })
}
