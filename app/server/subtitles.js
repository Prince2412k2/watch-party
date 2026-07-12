import express from 'express'

import { requireAuth, getJellyfin } from './auth.js'
import { BASE } from './jellyfin.js'
import { findSessionForMember, publicSession } from './session.js'
import { refreshPlayback } from './playback.js'

const ITEM_ID = /^[A-Za-z0-9-]{1,128}$/
const ALLOWED_CONTENT_TYPES = new Set([
  '', 'application/octet-stream', 'application/x-subrip', 'text/plain',
  'text/srt', 'text/vtt', 'text/webvtt',
])

const MAX_SUBTITLE_BYTES = 5 * 1024 * 1024

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
    .replace(/(\d{1,2}:\d{2}:\d{2}),([0-9]{3})(?=\s*-->)/g, '$1.$2')
    .replace(/(-- >|-->\s*\d{1,2}:\d{2}:\d{2}),([0-9]{3})/g, '$1.$2')
    .replace(/(-->\s*\d{1,2}:\d{2}:\d{2}),([0-9]{3})/g, '$1.$2')
  return `WEBVTT\n\n${body}\n`
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
  // Library detail management. Unlike the party routes below, these are scoped
  // to the authenticated Jellyfin user and can be used before playback starts.
  app.post('/api/library/items/:itemId/subtitles', requireAuth, rawSubtitle, async (req, res) => {
    const mediaItemId = String(req.params.itemId || '')
    if (!ITEM_ID.test(mediaItemId)) return res.status(400).json({ error: 'Invalid media item' })
    const upload = parseSubtitleUpload(req, res)
    if (!upload) return
    const { token, deviceId } = getJellyfin(req)
    try {
      await jellyfinSubtitleMutation({
        token, deviceId, itemId: mediaItemId, method: 'POST',
        body: JSON.stringify({ Language: subtitleLanguageFrom(req), Format: upload.ext, IsForced: false, IsHearingImpaired: false, Data: upload.data }),
      })
      res.status(201).json({ ok: true, label: cleanLabel(upload.filename) })
    } catch (err) {
      console.error('library subtitle upload', err.message)
      res.status(500).json({ error: 'Could not store subtitle file' })
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
      console.error('library subtitle delete', err.message)
      res.status(500).json({ error: 'Could not delete subtitle file' })
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
      await refreshSessionPlayback(io, session, {
        token,
        userId,
        subtitleStreamIndex: session.playback?.selectedSubtitleIndex ?? null,
      })
      res.status(201).json({
        ok: true,
        label: cleanLabel(upload.filename),
        session: publicSession(session),
        playback: session.playback,
      })
    } catch (err) {
      console.error('subtitle upload', err.message)
      res.status(500).json({ error: 'Could not store subtitle file' })
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
      console.error('subtitle delete', err.message)
      res.status(500).json({ error: 'Could not delete subtitle file' })
    }
  })
}
