import { randomBytes } from 'crypto'

export const MAX_TORRENT_BYTES = 2 * 1024 * 1024
const TORRENT_TTL_MS = 2 * 60 * 1000
const uploads = new Map()

export function parseManualSubmission(input) {
  const service = String(input.service || '').trim().toLowerCase()
  const title = String(input.title || '').trim()
  const targetId = Number(input.targetId)
  const seasonNumber = input.seasonNumber === undefined ? null : Number(input.seasonNumber)
  const episodeNumber = input.episodeNumber === undefined ? null : Number(input.episodeNumber)

  if (service !== 'radarr' && service !== 'sonarr') return { error: 'service must be radarr or sonarr' }
  if (!title || title.length > 500) return { error: 'title is required and must not exceed 500 characters' }
  if (!Number.isInteger(targetId) || targetId <= 0) return { error: 'targetId must be a positive integer' }
  if (service === 'radarr' && (seasonNumber !== null || episodeNumber !== null)) {
    return { error: 'episode fields are valid only for sonarr' }
  }
  if (seasonNumber !== null && (!Number.isInteger(seasonNumber) || seasonNumber < 0)) {
    return { error: 'seasonNumber must be a non-negative integer' }
  }
  if (episodeNumber !== null && (!Number.isInteger(episodeNumber) || episodeNumber <= 0 || seasonNumber === null)) {
    return { error: 'episodeNumber requires a seasonNumber and must be a positive integer' }
  }
  return { value: { service, title, targetId, seasonNumber, episodeNumber } }
}

export function parseMagnet(value) {
  if (typeof value !== 'string' || value.length > 8192) return null
  let uri
  try { uri = new URL(value) } catch { return null }
  if (uri.protocol !== 'magnet:' || !uri.searchParams.getAll('xt').some((xt) => /^urn:btih:[a-z0-9]{32,40}$/i.test(xt))) return null
  return uri.href
}

export function storeTorrent(buffer) {
  const token = randomBytes(32).toString('hex')
  const expiresAt = Date.now() + TORRENT_TTL_MS
  uploads.set(token, { buffer, expiresAt })
  setTimeout(() => uploads.delete(token), TORRENT_TTL_MS).unref()
  return token
}

export function takeTorrent(token) {
  const upload = uploads.get(token)
  uploads.delete(token)
  if (!upload || upload.expiresAt < Date.now()) return null
  return upload.buffer
}

export function torrentCallbackUrl(token) {
  const configured = String(process.env.SERVARR_TORRENT_CALLBACK_URL || '').trim()
  if (!configured) return null
  let base
  try { base = new URL(configured) } catch { return null }
  if (base.protocol !== 'http:' && base.protocol !== 'https:') return null
  return new URL(`/api/servarr/manual/torrents/${token}`, base).href
}
