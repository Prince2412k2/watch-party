import { createHash } from 'node:crypto'
import { Readable } from 'node:stream'
import { requireAuth, getJellyfin } from './auth.js'
import { isJellyfinId } from './library.js'
import { BASE, getItemDetail } from './jellyfin.js'

export function browserSource(item, requested) {
  const sources = item?.MediaSources ?? []
  const source = requested
    ? sources.find((s) => s.Id === requested)
    : sources[0]
  if (!source)
    throw Object.assign(new Error('Media source not found'), { status: 404 })
  const streams = source.MediaStreams ?? item.MediaStreams ?? []
  const video = streams.find((s) => s.Type === 'Video' && !s.IsAttachedPic)
  const audio = streams.filter((s) => s.Type === 'Audio')
  const defaultAudio = audio.find((s) => s.IsDefault) ?? audio[0]
  const compatible =
    source.Container?.toLowerCase() === 'mp4' &&
    video?.Codec === 'h264' &&
    (!video.BitDepth || video.BitDepth === 8) &&
    (!video.PixelFormat ||
      ['yuv420p', 'yuvj420p'].includes(video.PixelFormat)) &&
    !['smpte2084', 'arib-std-b67'].includes(video.ColorTransfer) &&
    audio.every((s) => s.Codec === 'aac' && (!s.Profile || s.Profile === 'LC'))
  if (!compatible)
    throw Object.assign(
      new Error(
        'This title needs conversion to H.264/AAC MP4 before it can be saved.'
      ),
      { status: 409 }
    )
  if (!isJellyfinId(source.Id))
    throw Object.assign(new Error('Invalid source'), { status: 502 })
  return { source, streams, defaultAudio }
}

export function registerOfflineRoutes(
  app,
  { detail = getItemDetail, upstreamFetch = fetch } = {}
) {
  const snapshots = new Map()
  const snapshotKey = (req) => {
    const auth = getJellyfin(req)
    return createHash('sha256')
      .update(
        `${auth.userId}:${auth.token}:${req.params.itemId}:${req.query.source || ''}`
      )
      .digest('hex')
  }
  const inspectFile = async (req) => {
    if (
      !isJellyfinId(req.params.itemId) ||
      (req.query.source && !isJellyfinId(req.query.source))
    )
      throw Object.assign(new Error('Invalid media ID'), { status: 400 })
    const auth = getJellyfin(req)
    const item = await detail(auth.token, auth.userId, req.params.itemId)
    const { source, streams, defaultAudio } = browserSource(
      item,
      req.query.source
    )
    const url = new URL(`${BASE}/Videos/${req.params.itemId}/stream.mp4`)
    url.searchParams.set('static', 'true')
    url.searchParams.set('mediaSourceId', source.Id)
    const headers = { 'X-Emby-Token': auth.token }
    const probe = await upstreamFetch(url, { method: 'HEAD', headers })
    if (!probe.ok)
      throw Object.assign(new Error('Could not inspect media file'), {
        status: 502
      })
    const size = Number(probe.headers.get('content-length'))
    const etag = probe.headers.get('etag') || ''
    const modified = probe.headers.get('last-modified') || ''
    if (
      !Number.isSafeInteger(size) ||
      size <= 0 ||
      ((!etag || etag.startsWith('W/')) && !modified)
    )
      throw Object.assign(
        new Error(
          'Media server must provide file size and a version validator'
        ),
        { status: 409 }
      )
    const revision = createHash('sha256')
      .update(`${source.Id}:${size}:${etag}:${modified}`)
      .digest('hex')
    const info = {
      owner: auth.userId,
      itemId: req.params.itemId,
      sourceId: source.Id,
      revision,
      size,
      etag,
      modified,
      title: item.Name,
      posterItemId: item.SeriesId || req.params.itemId,
      series: item.SeriesName || '',
      season: item.ParentIndexNumber,
      episode: item.IndexNumber,
      duration:
        Number(source.RunTimeTicks ?? item.RunTimeTicks ?? 0) / 10_000_000,
      audioIndex: defaultAudio?.Index ?? null,
      subtitles: streams
        .filter((s) => s.Type === 'Subtitle')
        .filter((s) =>
          [
            'subrip',
            'srt',
            'ass',
            'ssa',
            'mov_text',
            'webvtt',
            'vtt',
            'text'
          ].includes(s.Codec)
        )
        .map((s) => ({
          index: s.Index,
          language: s.Language,
          displayTitle: s.DisplayTitle || s.Language || `Subtitle ${s.Index}`
        }))
    }
    return { info, url, headers }
  }
  const inspect = (req, refresh = false) => {
    const key = snapshotKey(req),
      now = Date.now(),
      cached = snapshots.get(key)
    if (!refresh && cached && cached.expires > now) return cached.value
    // Share concurrent probes, and bound memory without retaining expired tokens.
    for (const [id, entry] of snapshots)
      if (entry.expires <= now) snapshots.delete(id)
    if (snapshots.size >= 256) snapshots.delete(snapshots.keys().next().value)
    const value = inspectFile(req).catch((error) => {
      if (snapshots.get(key)?.value === value) snapshots.delete(key)
      throw error
    })
    snapshots.set(key, { value, expires: now + 60_000 })
    return value
  }
  app.get('/api/offline/:itemId/info', requireAuth, async (req, res) => {
    try {
      const { info } = await inspect(req, true)
      res.set('Cache-Control', 'no-store').json(info)
    } catch (err) {
      res.status(err.status || 502).json({ error: err.message })
    }
  })
  app.get('/api/offline/:itemId/media', requireAuth, async (req, res) => {
    const abort = new AbortController()
    res.on('close', () => abort.abort())
    try {
      let snapshot = await inspect(req)
      if (req.query.revision !== snapshot.info.revision)
        snapshot = await inspect(req, true)
      const { info, url, headers } = snapshot
      if (req.query.revision !== info.revision)
        return res
          .status(409)
          .json({ error: 'The media file changed. Save the new version.' })
      const range = req.get('range')
      if (!range || !/^bytes=\d+-\d*$/.test(range))
        return res
          .status(400)
          .json({ error: 'A single byte range is required' })
      const upstream = await upstreamFetch(url, {
        headers: {
          ...headers,
          Range: range,
          'If-Range':
            info.etag && !info.etag.startsWith('W/') ? info.etag : info.modified
        },
        signal: abort.signal
      })
      // Never feed an unversioned full response into a partial cached file.
      const strongEtag = info.etag && !info.etag.startsWith('W/')
      if (
        upstream.status !== 206 ||
        (strongEtag && upstream.headers.get('etag') !== info.etag) ||
        (!strongEtag && upstream.headers.get('last-modified') !== info.modified)
      ) {
        snapshots.delete(snapshotKey(req))
        await upstream.body?.cancel()
        return res.status(409).json({
          error: 'Media changed or the server cannot serve byte ranges'
        })
      }
      res.status(206).set('Cache-Control', 'no-store')
      for (const header of [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
        'etag',
        'last-modified'
      ]) {
        const value = upstream.headers.get(header)
        if (value) res.set(header, value)
      }
      if (!upstream.body) return res.end()
      const body = Readable.fromWeb(upstream.body)
      body.on('error', () => res.destroy())
      res.on('close', () => body.destroy())
      body.pipe(res)
    } catch (err) {
      if (!res.headersSent && !abort.signal.aborted)
        res.status(err.status || 502).json({ error: err.message })
    }
  })
}
