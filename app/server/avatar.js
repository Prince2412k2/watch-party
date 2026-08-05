import { createHash } from 'crypto'
import { createAvatar } from '@humation/core'
import { humation1 } from '@humation/assets-humation-1'
import { requireAuth } from './auth.js'
import { getProfile } from './profile-store.js'
import { effectiveConfig } from '../shared/avatar-derive.js'
import { allSessions } from './session.js'

/**
 * Avatars as SVG, for clients that can't run the renderer themselves.
 *
 * The web client draws its own from the asset package in its bundle. Flutter
 * can't: humation is a JavaScript renderer with embedded SVG artwork. So the
 * server — which is JavaScript, and already has the asset set — draws the same
 * face and hands it over as an image. Same shared derivation module as the web
 * client, so an account looks identical on both.
 *
 * This is the embedded asset set (artwork inline) rather than the plain
 * manifest the validator uses, because composing an actual drawing needs the
 * artwork, not just the part ids.
 */

// A drawn avatar for a given account is a pure function of their profile, so it
// is worth not re-composing it for every participant on every screen refresh.
// Keyed by account and invalidated by the profile's own fingerprint, so a save
// is picked up immediately rather than aging out.
const rendered = new Map()
const CACHE_LIMIT = 500

function fingerprint(userId, config) {
  return createHash('sha1').update(`${userId}:${JSON.stringify(config)}`).digest('hex').slice(0, 16)
}

function renderAvatar(userId) {
  const { avatar } = getProfile(userId)
  const config = effectiveConfig(humation1, userId, avatar)
  const tag = fingerprint(userId, config)

  const hit = rendered.get(userId)
  if (hit && hit.tag === tag) return hit

  const svg = createAvatar(humation1, {
    selections: config.selections,
    colors: config.colors,
    background: config.background ?? humation1.defaults.background,
  }).toString()

  const entry = { tag, svg }
  // Plain insertion-order eviction: this is a small bound on a big room, not a
  // hit-rate optimisation.
  if (rendered.size >= CACHE_LIMIT) rendered.delete(rendered.keys().next().value)
  rendered.set(userId, entry)
  return entry
}

/** Whether `viewer` currently shares a party with `subject`. Profiles are not
    public: you can see the face of someone you are in a room with, and your
    own, and that is the whole of it. Waiting users count in both directions —
    the host is looking at a join request from them. */
function sharesParty(viewerId, subjectId) {
  for (const session of allSessions()) {
    const members = [
      session.hostId,
      ...session.guests.map(guest => guest.userId),
      ...session.waiting.map(waiter => waiter.userId),
    ]
    if (members.includes(viewerId) && members.includes(subjectId)) return true
  }
  return false
}

export function registerAvatarRoutes(app) {
  app.get('/api/avatar/:userId.svg', requireAuth, (req, res) => {
    const viewerId = req.session.jellyfin.userId
    const subjectId = req.params.userId

    if (subjectId !== viewerId && !sharesParty(viewerId, subjectId)) {
      return res.status(403).json({ error: 'not in a party with that user' })
    }

    const { tag, svg } = renderAvatar(subjectId)
    const etag = `W/"${tag}"`
    res.set('ETag', etag)
    // Revalidate every time rather than caching blind: a profile edit has to
    // show up, and a 304 costs a header exchange.
    res.set('Cache-Control', 'private, no-cache')
    if (req.headers['if-none-match'] === etag) return res.status(304).end()

    res.type('image/svg+xml').send(svg)
  })
}
