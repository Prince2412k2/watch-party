import { randomUUID } from 'crypto'
import { mkdir, writeFile } from 'fs/promises'
import { dirname, join, resolve } from 'path'
import { fileURLToPath } from 'url'

import express from 'express'

import { requireAuth } from './auth.js'
import { findSessionForMember, getSession, isMember } from './session.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const STORE_DIR = process.env.SUBTITLE_STORE_DIR || resolve(__dirname, '../../data/subtitles')
export const MAX_SUBTITLE_BYTES = 5 * 1024 * 1024

const ITEM_ID = /^[A-Za-z0-9-]{1,128}$/
const PARTY_ID = /^[A-F0-9]{8}$/
const UPLOAD_ID = /^[a-f0-9-]{36}$/
const ALLOWED_CONTENT_TYPES = new Set([
  '', 'application/octet-stream', 'application/x-subrip', 'text/plain',
  'text/srt', 'text/vtt', 'text/webvtt',
])

function filenameFrom(req) {
  const raw = req.get('X-Subtitle-Filename') || ''
  try { return decodeURIComponent(raw) } catch { return raw }
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

export function registerSubtitleRoutes(app) {
  app.post('/api/library/subtitles/upload', requireAuth, rawSubtitle, async (req, res) => {
    const userId = req.session.jellyfin.userId
    const mediaItemId = String(req.query.mediaItemId || '')
    const requestedPartyId = String(req.query.partyId || '').toUpperCase()
    const session = requestedPartyId ? getSession(requestedPartyId) : findSessionForMember(userId)
    if (!session) return res.status(404).json({ error: 'Party not found' })
    if (!isMember(session, userId)) return res.status(403).json({ error: 'You are not a member of this party' })
    const partyId = session.id
    if (!ITEM_ID.test(mediaItemId) || session.mediaItemId !== mediaItemId) {
      return res.status(409).json({ error: 'Subtitle does not match the party’s current media' })
    }

    const filename = filenameFrom(req)
    const ext = filename.match(/\.([^.]+)$/)?.[1]?.toLowerCase()
    const contentType = (req.get('content-type') || '').split(';', 1)[0].trim().toLowerCase()
    if (!['srt', 'vtt'].includes(ext) || !ALLOWED_CONTENT_TYPES.has(contentType)) {
      return res.status(415).json({ error: 'Only SRT and WebVTT subtitle files are supported' })
    }
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) return res.status(400).json({ error: 'Subtitle file is empty' })
    if (req.body.includes(0)) return res.status(400).json({ error: 'Subtitle file must be plain text' })

    const text = req.body.toString('utf8')
    if (text.includes('\uFFFD')) return res.status(400).json({ error: 'Subtitle file must use UTF-8 encoding' })
    const vtt = ext === 'srt' ? srtToVtt(text) : text.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n')
    if (!/^WEBVTT(?:\s|$)/.test(vtt)) return res.status(400).json({ error: 'Invalid WebVTT subtitle file' })

    const uploadId = randomUUID()
    const directory = join(STORE_DIR, partyId)
    try {
      await mkdir(directory, { recursive: true })
      await writeFile(join(directory, `${uploadId}.vtt`), vtt, { encoding: 'utf8', mode: 0o600, flag: 'wx' })
      res.status(201).json({
        url: `/api/library/subtitles/${partyId}/${uploadId}.vtt`,
        label: cleanLabel(filename),
      })
    } catch (err) {
      console.error('subtitle upload', err.message)
      res.status(500).json({ error: 'Could not store subtitle file' })
    }
  })

  app.get('/api/library/subtitles/:partyId/:uploadId.vtt', requireAuth, (req, res) => {
    const partyId = String(req.params.partyId || '').toUpperCase()
    const uploadId = String(req.params.uploadId || '').toLowerCase()
    const session = getSession(partyId)
    if (!PARTY_ID.test(partyId) || !UPLOAD_ID.test(uploadId) || !session) return res.status(404).end()
    if (!isMember(session, req.session.jellyfin.userId)) return res.status(403).end()
    res.set('Content-Type', 'text/vtt; charset=utf-8')
    res.set('Cache-Control', 'private, max-age=3600')
    res.sendFile(join(STORE_DIR, partyId, `${uploadId}.vtt`), (err) => {
      if (err && !res.headersSent) res.status(err.statusCode || 404).end()
    })
  })
}
