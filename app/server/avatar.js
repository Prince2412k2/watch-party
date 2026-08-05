import { createHash } from 'crypto'
import { createAvatar, createPartPreview, getPartsForSlot } from '@humation/core'
import { humation1 } from '@humation/assets-humation-1'
import { requireAuth } from './auth.js'
import { getProfile } from './profile-store.js'
import { PALETTES, effectiveConfig } from '../shared/avatar-derive.js'
import { validateAvatar } from './profile.js'
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

/**
 * Substitute the resolved colours into the drawing.
 *
 * The renderer leaves colours as `fill="var(--hm-skin, #FFFFFF)"` and sets the
 * real values as custom properties on the root element, which is right for a
 * browser. Native SVG renderers — flutter_svg among them — don't implement CSS
 * custom properties, so they'd paint every fallback instead: the asset set's
 * white skin and black hair on every single user. Inlining the values is what
 * makes the picture correct for a client that only understands plain SVG.
 */
function flattenColors(svg, colors) {
  const inlined = svg.replace(
    /var\(--hm-([A-Za-z0-9-]+),\s*([^)]*)\)/g,
    (_match, slot, fallback) => {
      const value = colors[slot]
      return value ? `#${String(value).replace('#', '')}` : fallback.trim()
    },
  )
  // The custom properties those references pointed at are now dead weight.
  return inlined.replace(/\sstyle="--hm-[^"]*"/, '')
}

function fingerprint(userId, config) {
  return createHash('sha1').update(`${userId}:${JSON.stringify(config)}`).digest('hex').slice(0, 16)
}

function renderAvatar(userId) {
  const { avatar } = getProfile(userId)
  const config = effectiveConfig(humation1, userId, avatar)
  const tag = fingerprint(userId, config)

  const hit = rendered.get(userId)
  if (hit && hit.tag === tag) return hit

  const svg = flattenColors(
    createAvatar(humation1, {
      selections: config.selections,
      colors: config.colors,
      background: config.background ?? humation1.defaults.background,
    }).toString(),
    config.colors,
  )

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

/** The editor's whole vocabulary in one response: which slots exist, what can
    go in them, which colours are adjustable and the swatches to offer. Read
    from the installed asset set, so a client that renders this never has a
    hardcoded list to fall out of date. */
function editorOptions() {
  const groups = [...humation1.uiGroups]
    .sort((a, b) => a.order - b.order)
    .map(group => ({
      id: group.id,
      label: group.label,
      slots: group.selectionSlots.map(slotId => {
        const slot = humation1.selectionSlots.find(candidate => candidate.id === slotId)
        return {
          id: slotId,
          label: slot?.label ?? slotId,
          parts: getPartsForSlot(humation1, slotId).map(part => ({
            id: part.id,
            name: part.name ?? part.id,
          })),
        }
      }),
    }))

  return {
    groups,
    colors: humation1.colors.map(slot => ({
      id: slot.id,
      label: slot.label,
      default: slot.default,
      allowTransparent: slot.allowTransparent === true,
    })),
    palettes: PALETTES,
    defaults: { background: humation1.defaults.background },
  }
}

/** Colour overrides from flat query parameters (`?skin=E8B98C&hair=4A3728`).
    Anything that isn't a colour slot of the asset set, or isn't a hex triple,
    is dropped rather than passed to the renderer. */
function colorsFromQuery(query) {
  const colors = {}
  for (const slot of humation1.colors) {
    const value = query[slot.id]
    if (typeof value === 'string' && /^[0-9A-Fa-f]{6}$/.test(value)) {
      colors[slot.id] = value.toUpperCase()
    }
  }
  return colors
}

export function registerAvatarRoutes(app) {
  // Static for the lifetime of the process — it only describes the installed
  // asset set — so it is built once and served from memory.
  const options = editorOptions()
  const optionsTag = `W/"${createHash('sha1').update(JSON.stringify(options)).digest('hex').slice(0, 16)}"`

  app.get('/api/avatar/options', requireAuth, (req, res) => {
    res.set('ETag', optionsTag)
    if (req.headers['if-none-match'] === optionsTag) return res.status(304).end()
    res.json(options)
  })

  // One part on its own, for an editor's thumbnail grid. Drawn in whatever
  // colours the caller currently has selected, so a hair swatch shows their
  // hair colour.
  app.get('/api/avatar/part/:partId.svg', requireAuth, (req, res) => {
    const part = humation1.parts.find(candidate => candidate.id === req.params.partId)
    if (!part) return res.status(404).json({ error: 'unknown part' })

    const colors = colorsFromQuery(req.query)
    const svg = flattenColors(
      createPartPreview(humation1, part, { colors, background: 'transparent' }).toString(),
      colors,
    )
    // A part drawn in a given set of colours never changes, so this one is
    // worth caching outright rather than revalidating.
    res.set('Cache-Control', 'private, max-age=86400')
    res.type('image/svg+xml').send(svg)
  })

  // Every part of one slot, drawn, in a single response. A thumbnail grid is
  // 86 little drawings; a native client fetching them one by one would spend
  // the whole editor open on round trips.
  app.get('/api/avatar/parts/:slotId', requireAuth, (req, res) => {
    const parts = getPartsForSlot(humation1, req.params.slotId)
    if (!parts.length) return res.status(404).json({ error: 'unknown slot' })

    const colors = colorsFromQuery(req.query)
    const previews = {}
    for (const part of parts) {
      previews[part.id] = flattenColors(
        createPartPreview(humation1, part, { colors, background: 'transparent' }).toString(),
        colors,
      )
    }
    res.set('Cache-Control', 'private, max-age=86400')
    res.json(previews)
  })

  // An unsaved configuration, drawn. This is what makes a native editor's
  // preview live: the client posts what it currently has and gets the picture
  // back, without needing the renderer itself.
  app.post('/api/avatar/preview.svg', requireAuth, (req, res) => {
    const avatar = validateAvatar(req.body?.avatar)
    if (avatar.error) return res.status(400).json({ error: avatar.error })

    const config = effectiveConfig(humation1, req.session.jellyfin.userId, avatar.value)
    const svg = flattenColors(
      createAvatar(humation1, {
        selections: config.selections,
        colors: config.colors,
        background: config.background ?? humation1.defaults.background,
      }).toString(),
      config.colors,
    )
    res.set('Cache-Control', 'no-store')
    res.type('image/svg+xml').send(svg)
  })

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
