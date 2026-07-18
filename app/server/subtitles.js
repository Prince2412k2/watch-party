import express from 'express'

import { requireAuth, getJellyfin } from './auth.js'
import { BASE, getPlaybackInfo } from './jellyfin.js'
import { findSessionForMember, publicSession } from './session.js'
import { refreshPlayback } from './playback.js'

const ITEM_ID = /^[A-Za-z0-9-]{1,128}$/
const ALLOWED_CONTENT_TYPES = new Set([
  '', 'application/octet-stream', 'application/x-subrip', 'text/plain',
  'text/srt', 'text/vtt', 'text/webvtt',
])

const MAX_SUBTITLE_BYTES = 5 * 1024 * 1024
const SUBTITLE_POLL_DELAYS_MS = [0, 100, 250, 500, 1000, 1500, 2500, 2500]

function externalSubtitleStreams(playback, mediaSourceId = null) {
  const source = (playback?.MediaSources ?? []).find(candidate =>
    !mediaSourceId || candidate?.Id === mediaSourceId
  )
  return (source?.MediaStreams ?? []).filter(stream =>
    stream?.Type === 'Subtitle' && stream.IsExternal === true && Number.isSafeInteger(stream.Index)
  )
}

export function findNewExternalSubtitle(before, after, mediaSourceId = null) {
  const previousIndices = new Set(externalSubtitleStreams(before, mediaSourceId).map(stream => stream.Index))
  return externalSubtitleStreams(after, mediaSourceId).find(stream => !previousIndices.has(stream.Index)) ?? null
}

export async function pollForNewExternalSubtitle(loadPlayback, before, {
  mediaSourceId = null,
  delays = SUBTITLE_POLL_DELAYS_MS,
  wait = ms => new Promise(resolve => setTimeout(resolve, ms)),
} = {}) {
  let latest = null
  for (const delay of delays) {
    if (delay > 0) await wait(delay)
    latest = await loadPlayback()
    const stream = findNewExternalSubtitle(before, latest, mediaSourceId)
    if (stream) return { stream, playback: latest }
  }
  return { stream: null, playback: latest }
}

export function findExternalSubtitleStream(playback, index, mediaSourceId = null) {
  for (const source of playback?.MediaSources ?? []) {
    if (mediaSourceId && source?.Id !== mediaSourceId) continue
    const stream = source?.MediaStreams?.find(candidate =>
      candidate?.Type === 'Subtitle' &&
      candidate.Index === index &&
      candidate.IsExternal === true &&
      typeof candidate.DeliveryUrl === 'string' &&
      candidate.DeliveryUrl.length > 0
    )
    if (stream) return stream
  }
  return null
}

export function resolveJellyfinDeliveryUrl(deliveryUrl, token, base = BASE) {
  if (typeof deliveryUrl !== 'string' || !deliveryUrl) return null
  try {
    const configuredBase = new URL(base)
    const target = new URL(deliveryUrl, `${configuredBase.href.replace(/\/?$/, '/')}`)
    const basePath = configuredBase.pathname.replace(/\/$/, '')
    if (target.origin !== configuredBase.origin) return null
    if (basePath && target.pathname !== basePath && !target.pathname.startsWith(`${basePath}/`)) return null
    if (target.username || target.password) return null
    target.searchParams.delete('api_key')
    target.searchParams.set('api_key', token)
    target.hash = ''
    return target
  } catch {
    return null
  }
}

export function subtitleMutationError(status) {
  if (status === 400) return { status: 422, error: 'Jellyfin rejected the subtitle file' }
  if (status === 403) return { status: 403, error: 'Jellyfin denied subtitle changes' }
  if (status === 404) return { status: 404, error: 'Media item or subtitle was not found' }
  if (Number.isInteger(status) && status >= 500) return { status: 502, error: 'Jellyfin could not process the subtitle request' }
  return { status: 502, error: 'Jellyfin subtitle request failed' }
}

function sendSubtitleMutationError(res, err, operation) {
  const mapped = subtitleMutationError(err?.status)
  console.error(`subtitle ${operation} failed`, { jellyfinStatus: err?.status ?? null, message: err?.message })
  res.status(mapped.status).json({ error: mapped.error })
}

function filenameFrom(req) {
  const raw = req.get('X-Subtitle-Filename') || ''
  try { return decodeURIComponent(raw) } catch { return raw }
}

function subtitleLanguageFrom(req) {
  return (req.get('X-Subtitle-Language') || 'eng').trim() || 'eng'
}

function cleanLabel(filename) {
  return filename.replace(/\.(srt|vtt)$/i, '').replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 100) || 'Uploaded subtitles'
}

export function srtToVtt(input) {
  const normalized = input.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n').trim()
  const body = normalized
    .replace(/(^|\n)(\d+)[ \t]*\n(?=\d{1,2}:\d{2}:\d{2}[,.]\d{3}\s*-->)/g, '$1')
    .replace(/(\d{1,2}:\d{2}:\d{2}),([0-9]{3})/g, '$1.$2')
  return `WEBVTT\n\n${body}\n`
}

export function subtitleTextToVtt(input) {
  const normalized = input.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n').trim()
  if (/^WEBVTT(?:\s|$)/i.test(normalized)) return `${normalized}\n`
  return srtToVtt(normalized)
}

function rawSubtitle(req, res, next) {
  express.raw({ type: () => true, limit: MAX_SUBTITLE_BYTES })(req, res, (err) => {
    if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'Subtitle file must be 5 MB or smaller' })
    next(err)
  })
}

function parseSubtitleUpload(req, res) {
  const filename = filenameFrom(req)
  const ext = filename.match(/\.([^.]+)$/)?.[1]?.toLowerCase()
  const contentType = (req.get('content-type') || '').split(';', 1)[0].trim().toLowerCase()
  if (!['srt', 'vtt'].includes(ext) || !ALLOWED_CONTENT_TYPES.has(contentType)) {
    res.status(415).json({ error: 'Only SRT and WebVTT subtitle files are supported' })
    return null
  }
  if (!Buffer.isBuffer(req.body) || req.body.length === 0) { res.status(400).json({ error: 'Subtitle file is empty' }); return null }
  if (req.body.includes(0)) { res.status(400).json({ error: 'Subtitle file must be plain text' }); return null }
  const text = req.body.toString('utf8')
  if (text.includes('\uFFFD')) { res.status(400).json({ error: 'Subtitle file must use UTF-8 encoding' }); return null }
  return {
    filename,
    ext,
    data: Buffer.from(text.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n'), 'utf8').toString('base64'),
  }
}

async function refreshSessionPlayback(io, session, { token, userId, subtitleStreamIndex = null }) {
  const selectedAudioIndex = session.playback?.selectedAudioIndex ?? null
  const playback = await refreshPlayback(session, {
    token,
    userId,
    itemId: session.mediaItemId,
    mediaSourceId: session.mediaSourceId,
    audioStreamIndex: Number.isInteger(selectedAudioIndex) ? selectedAudioIndex : null,
    subtitleStreamIndex,
    playSessionId: session.playback?.playSessionId ?? null,
  })
  io?.to(session.id).emit('party:state', publicSession(session))
  return playback
}

async function jellyfinSubtitleMutation({ token, deviceId, itemId, method, body, subtitleIndex = null }) {
  const path = subtitleIndex == null
    ? `/Videos/${encodeURIComponent(itemId)}/Subtitles`
    : `/Videos/${encodeURIComponent(itemId)}/Subtitles/${encodeURIComponent(String(subtitleIndex))}`
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Emby-Authorization': `MediaBrowser Client="Watchparty", Device="Server", DeviceId="${deviceId || 'watchparty-server'}", Version="1.0.0", Token="${token}"`,
    },
    body,
  })
  if (!res.ok) {
    const text = await res.text().catch(() => '')
    throw Object.assign(new Error(`Jellyfin ${method} subtitles → ${res.status}`), { status: res.status, body: text })
  }
  return res
}

export function registerSubtitleRoutes(app, io) {
  app.get('/api/library/items/:itemId/subtitles/:index/content', requireAuth, async (req, res) => {
    const mediaItemId = String(req.params.itemId || '')
    const indexText = String(req.params.index || '')
    const index = /^\d+$/.test(indexText) ? Number(indexText) : -1
    const mediaSourceId = typeof req.query.mediaSourceId === 'string' ? req.query.mediaSourceId : null
    if (!ITEM_ID.test(mediaItemId) || !Number.isSafeInteger(index) || index < 0) {
      return res.status(400).json({ error: 'Invalid subtitle' })
    }

    const { token, userId } = getJellyfin(req)
    try {
      const playback = await getPlaybackInfo(token, userId, mediaItemId, { mediaSourceId })
      const stream = findExternalSubtitleStream(playback, index, mediaSourceId)
      if (!stream) return res.status(404).json({ error: 'External subtitle was not found' })
      const target = resolveJellyfinDeliveryUrl(stream.DeliveryUrl, token)
      if (!target) {
        console.error('subtitle content rejected unsafe DeliveryUrl', { itemId: mediaItemId, index })
        return res.status(502).json({ error: 'Jellyfin returned an invalid subtitle URL' })
      }

      const upstream = await fetch(target, {
        headers: { 'X-Emby-Token': token },
        redirect: 'error',
      })
      if (!upstream.ok) {
        console.error('subtitle content fetch failed', { itemId: mediaItemId, index, jellyfinStatus: upstream.status })
        if (upstream.status === 403 || upstream.status === 404) return res.status(upstream.status).json({ error: 'Subtitle content is unavailable' })
        return res.status(502).json({ error: 'Could not fetch subtitle content' })
      }
      const text = await upstream.text()
      res.set('Content-Type', 'text/vtt; charset=utf-8')
      res.set('Cache-Control', 'private, max-age=300')
      res.send(subtitleTextToVtt(text))
    } catch (err) {
      console.error('subtitle content failed', { jellyfinStatus: err?.status ?? null, message: err?.message })
      res.status(502).json({ error: 'Could not fetch subtitle content' })
    }
  })

  // Library detail management. Unlike the party routes below, these are scoped
  // to the authenticated Jellyfin user and can be used before playback starts.
  app.post('/api/library/items/:itemId/subtitles', requireAuth, rawSubtitle, async (req, res) => {
    const mediaItemId = String(req.params.itemId || '')
    if (!ITEM_ID.test(mediaItemId)) return res.status(400).json({ error: 'Invalid media item' })
    const upload = parseSubtitleUpload(req, res)
    if (!upload) return
    const { token, userId, deviceId } = getJellyfin(req)
    try {
      const before = await getPlaybackInfo(token, userId, mediaItemId)
      const mediaSourceId = before?.MediaSources?.[0]?.Id ?? null
      await jellyfinSubtitleMutation({
        token, deviceId, itemId: mediaItemId, method: 'POST',
        body: JSON.stringify({ Language: subtitleLanguageFrom(req), Format: upload.ext, IsForced: false, IsHearingImpaired: false, Data: upload.data }),
      })
      const result = await pollForNewExternalSubtitle(
        () => getPlaybackInfo(token, userId, mediaItemId, { mediaSourceId }),
        before,
        { mediaSourceId },
      )
      if (!result.stream) return res.status(504).json({ error: 'Subtitle was uploaded but Jellyfin did not publish the new track in time' })
      res.status(201).json({ ok: true, label: cleanLabel(upload.filename), subtitleStreamIndex: result.stream.Index })
    } catch (err) {
      sendSubtitleMutationError(res, err, 'library upload')
    }
  })

  app.delete('/api/library/items/:itemId/subtitles/:index', requireAuth, async (req, res) => {
    const mediaItemId = String(req.params.itemId || '')
    const index = Number.parseInt(String(req.params.index || ''), 10)
    if (!ITEM_ID.test(mediaItemId) || !Number.isInteger(index) || index < 0) return res.status(400).json({ error: 'Invalid subtitle' })
    const { token, deviceId } = getJellyfin(req)
    try {
      await jellyfinSubtitleMutation({ token, deviceId, itemId: mediaItemId, method: 'DELETE', subtitleIndex: index })
      res.json({ ok: true })
    } catch (err) {
      sendSubtitleMutationError(res, err, 'library delete')
    }
  })

  app.post('/api/library/subtitles/upload', requireAuth, rawSubtitle, async (req, res) => {
    const userId = req.session.jellyfin.userId
    const { token, deviceId } = getJellyfin(req)
    const session = findSessionForMember(userId)
    if (!session) return res.status(404).json({ error: 'Party not found' })
    if (session.hostId !== userId) return res.status(403).json({ error: 'Only the host can manage subtitles' })

    const mediaItemId = String(req.query.mediaItemId || '')
    if (!ITEM_ID.test(mediaItemId) || session.mediaItemId !== mediaItemId) {
      return res.status(409).json({ error: 'Subtitle does not match the party’s current media' })
    }
    const upload = parseSubtitleUpload(req, res)
    if (!upload) return

    try {
      const before = await getPlaybackInfo(token, userId, mediaItemId, { mediaSourceId: session.mediaSourceId })
      await jellyfinSubtitleMutation({
        token,
        deviceId,
        itemId: mediaItemId,
        method: 'POST',
        body: JSON.stringify({
          Language: subtitleLanguageFrom(req),
          Format: upload.ext,
          IsForced: false,
          IsHearingImpaired: false,
          Data: upload.data,
        }),
      })
      const result = await pollForNewExternalSubtitle(
        () => getPlaybackInfo(token, userId, mediaItemId, { mediaSourceId: session.mediaSourceId }),
        before,
        { mediaSourceId: session.mediaSourceId },
      )
      if (!result.stream) return res.status(504).json({ error: 'Subtitle was uploaded but Jellyfin did not publish the new track in time' })
      await refreshSessionPlayback(io, session, {
        token,
        userId,
        subtitleStreamIndex: result.stream.Index,
      })
      res.status(201).json({
        ok: true,
        label: cleanLabel(upload.filename),
        subtitleStreamIndex: result.stream.Index,
        session: publicSession(session),
        playback: session.playback,
      })
    } catch (err) {
      sendSubtitleMutationError(res, err, 'party upload')
    }
  })

  app.delete('/api/library/subtitles/:itemId/:index', requireAuth, async (req, res) => {
    const userId = req.session.jellyfin.userId
    const { token, deviceId } = getJellyfin(req)
    const session = findSessionForMember(userId)
    if (!session) return res.status(404).json({ error: 'Party not found' })
    if (session.hostId !== userId) return res.status(403).json({ error: 'Only the host can manage subtitles' })

    const mediaItemId = String(req.params.itemId || '')
    const index = Number.parseInt(String(req.params.index || ''), 10)
    if (!ITEM_ID.test(mediaItemId) || !Number.isInteger(index) || index < 0) return res.status(400).json({ error: 'Invalid subtitle index' })
    if (session.mediaItemId !== mediaItemId) return res.status(409).json({ error: 'Subtitle does not match the party’s current media' })

    try {
      await jellyfinSubtitleMutation({
        token,
        deviceId,
        itemId: mediaItemId,
        method: 'DELETE',
        subtitleIndex: index,
      })
      await refreshSessionPlayback(io, session, {
        token,
        userId,
        subtitleStreamIndex: null,
      })
      res.json({ ok: true, session: publicSession(session), playback: session.playback })
    } catch (err) {
      sendSubtitleMutationError(res, err, 'party delete')
    }
  })
}
