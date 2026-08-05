import manifest from '@humation/assets-humation-1/manifest-json'
import { requireAuth } from './auth.js'
import { getProfile, saveProfile } from './profile-store.js'
import { findSessionForMember, publicSession } from './session.js'

// Roughly a real name or a short handle. Long enough not to truncate anyone in
// practice, short enough that a participant row and a camera-tile name stay one
// legible line.
export const DISPLAY_NAME_MAX = 32

// The asset set is the authority on what a valid avatar is, so the accepted
// vocabulary is derived from the installed manifest rather than written down
// here: an asset-set update widens or narrows it automatically.
const partsBySlot = new Map()
for (const part of manifest.parts) {
  if (!partsBySlot.has(part.selectionSlot)) partsBySlot.set(part.selectionSlot, new Set())
  partsBySlot.get(part.selectionSlot).add(part.id)
}
// `background` is a colour slot in the manifest but a separate option in the
// render API, so it stays a separate field here too instead of being a key in
// `colors` that behaves differently from its neighbours.
const backgroundSlot = manifest.colors.find(slot => slot.id === 'background')
const colorSlots = new Set(manifest.colors.map(slot => slot.id).filter(id => id !== 'background'))

const AVATAR_FIELDS = ['selections', 'colors', 'background']

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

// Stored without the '#', uppercase — the manifest's own convention for its
// defaults, and the renderer accepts either form.
function normalizeHex(value) {
  if (typeof value !== 'string') return null
  const hex = value.startsWith('#') ? value.slice(1) : value
  return /^[0-9A-Fa-f]{6}$/.test(hex) ? hex.toUpperCase() : null
}

export function validateDisplayName(value) {
  if (value === null || value === undefined) return { value: null }
  if (typeof value !== 'string') return { error: 'invalid displayName' }
  // Control characters are how a newline or a tab gets smuggled into what has
  // to render as a single row.
  const control = [...value].some(character => {
    const code = character.codePointAt(0)
    return code < 0x20 || code === 0x7f
  })
  if (control) return { error: 'displayName must be a single line' }
  const trimmed = value.trim()
  // Nothing left after trimming is a cleared name, not an error — the account
  // name takes over again.
  if (!trimmed) return { value: null }
  if ([...trimmed].length > DISPLAY_NAME_MAX) {
    return { error: `displayName must be ${DISPLAY_NAME_MAX} characters or fewer` }
  }
  return { value: trimmed }
}

export function validateAvatar(value) {
  if (value === null || value === undefined) return { value: null }
  if (!isPlainObject(value)) return { error: 'invalid avatar' }

  const unknownField = Object.keys(value).find(key => !AVATAR_FIELDS.includes(key))
  if (unknownField) return { error: `unknown avatar field: ${unknownField}` }

  const result = {}

  if (value.selections !== undefined) {
    if (!isPlainObject(value.selections)) return { error: 'invalid avatar.selections' }
    const selections = {}
    for (const [slot, partId] of Object.entries(value.selections)) {
      const parts = partsBySlot.get(slot)
      if (!parts) return { error: `unknown selection slot: ${slot}` }
      if (typeof partId !== 'string' || !parts.has(partId)) {
        return { error: `unknown part for ${slot}` }
      }
      selections[slot] = partId
    }
    if (Object.keys(selections).length) result.selections = selections
  }

  if (value.colors !== undefined) {
    if (!isPlainObject(value.colors)) return { error: 'invalid avatar.colors' }
    const colors = {}
    for (const [slot, hex] of Object.entries(value.colors)) {
      if (!colorSlots.has(slot)) return { error: `unknown colour slot: ${slot}` }
      const normalized = normalizeHex(hex)
      if (!normalized) return { error: `invalid colour for ${slot}` }
      colors[slot] = normalized
    }
    if (Object.keys(colors).length) result.colors = colors
  }

  if (value.background !== undefined) {
    if (value.background === 'transparent') {
      if (!backgroundSlot?.allowTransparent) return { error: 'transparent background not supported' }
      result.background = 'transparent'
    } else {
      const normalized = normalizeHex(value.background)
      if (!normalized) return { error: 'invalid avatar.background' }
      result.background = normalized
    }
  }

  // An avatar that overrides nothing is the derived default, so it is stored as
  // "nothing saved" rather than as an empty object that outranks it.
  return { value: Object.keys(result).length ? result : null }
}

export function registerProfileRoutes(app, io) {
  // Neither route takes a user parameter: the only profile addressable is the
  // caller's own, so there is no request that could read or write someone
  // else's (FR-004). Identity comes from the session, never from the body.
  app.get('/api/profile', requireAuth, (req, res) => {
    const { userId, name } = req.session.jellyfin
    const { displayName, avatar } = getProfile(userId)
    res.json({ userId, accountName: name, displayName, avatar })
  })

  app.put('/api/profile', requireAuth, (req, res) => {
    const displayName = validateDisplayName(req.body?.displayName)
    if (displayName.error) return res.status(400).json({ error: displayName.error })
    const avatar = validateAvatar(req.body?.avatar)
    if (avatar.error) return res.status(400).json({ error: avatar.error })

    const { userId, name } = req.session.jellyfin
    const saved = saveProfile(userId, { displayName: displayName.value, avatar: avatar.value })

    // The party payload carries every member's name and avatar, so re-sending
    // it is all the other participants need to redraw me — no reload, and no
    // second channel that could disagree with the party state.
    const session = findSessionForMember(userId)
    if (session) io.to(session.id).emit('party:state', publicSession(session))

    res.json({ userId, accountName: name, ...saved })
  })
}
