import { requireAuth, getJellyfin } from './auth.js'
import { isJellyfinId } from './library.js'
import {
  getPlaybackInfo, normalizePlaybackInfo,
  reportPlaybackStart, reportPlaybackProgress, reportPlaybackStopped,
} from './jellyfin.js'

function pickSource(response, mediaSourceId) {
  const sources = Array.isArray(response?.MediaSources) ? response.MediaSources : []
  if (!sources.length) return null
  if (mediaSourceId) return sources.find(source => source?.Id === mediaSourceId) ?? sources[0]
  return sources[0]
}

function defaultIndex(streams) {
  return streams.find(stream => stream?.isDefault)?.index ?? streams[0]?.index ?? null
}

export async function refreshPlayback(session, {
  token,
  userId,
  itemId,
  mediaSourceId = session?.mediaSourceId ?? null,
  audioStreamIndex,
  subtitleStreamIndex,
  playSessionId = session?.playback?.playSessionId ?? null,
} = {}) {
  const response = await getPlaybackInfo(token, userId, itemId, {
    mediaSourceId,
    audioStreamIndex,
    subtitleStreamIndex,
    playSessionId,
  })

  const source = pickSource(response, mediaSourceId)
  const audioStreams = (source?.MediaStreams ?? []).filter(stream => stream?.Type === 'Audio')
  const subtitleStreams = (source?.MediaStreams ?? []).filter(stream => stream?.Type === 'Subtitle')
  const playback = normalizePlaybackInfo(response, {
    itemId,
    selectedAudioIndex: Number.isInteger(audioStreamIndex)
      ? audioStreamIndex
      : defaultIndex(audioStreams),
    selectedSubtitleIndex: Number.isInteger(subtitleStreamIndex)
      ? subtitleStreamIndex
      : (defaultIndex(subtitleStreams) ?? -1),
  })

  session.mediaSourceId = playback.mediaSourceId ?? session.mediaSourceId ?? null
  session.playback = {
    ...playback,
    sourceId: playback.mediaSourceId ?? null,
    streamUrl: playback.transcodingUrl || playback.directStreamUrl || null,
  }
  return session.playback
}

// ── Watch history ───────────────────────────────────────────────────────────
// Three routes the player calls as it plays: started / progress / stopped.
// They forward to Jellyfin on the CALLER'S own token, which is what makes the
// history theirs — the session names the user, the body never does. A body that
// could name a user would let any member rewrite anyone else's history.
//
// Positions are Jellyfin ticks (100-nanosecond units) throughout, because that
// is what Jellyfin stores and what `UserData.PlaybackPositionTicks` hands back
// on the way in. Converting at one end only — the client multiplies its
// microseconds by 10 — keeps a unit mix-up from silently landing a position 10x
// off, which reads as a resume point in the wrong scene rather than as an error.

const MAX_TICKS = 24 * 60 * 60 * 10_000_000   // 24h, well past any real runtime

function ticksOf(value) {
  const n = Number(value)
  if (!Number.isFinite(n) || n < 0 || n > MAX_TICKS) return null
  return Math.round(n)
}

// The shape all three Jellyfin endpoints take. `PlaySessionId` ties the three
// calls into one session so Jellyfin does not treat every tick as a new play;
// it comes from the PlaybackInfo response the client already fetched.
//
// [requirePosition] is the difference between "start playing this" and "I am
// HERE" — and it is not a formality. JSON has no NaN, so a client bug that
// computes one sends `null`, and a null quietly read as 0 reports the viewer at
// the beginning: Jellyfin then wipes a real resume point and the film reopens
// from the top. Started may default to 0 because that is what starting means;
// progress and stopped must say where they are or be refused.
function reportBody(req, { requirePosition }) {
  const { itemId, mediaSourceId, playSessionId, positionTicks, isPaused } = req.body ?? {}
  if (!isJellyfinId(itemId)) return null
  if (mediaSourceId != null && !isJellyfinId(mediaSourceId)) return null
  if (requirePosition && positionTicks == null) return null
  const ticks = ticksOf(positionTicks ?? 0)
  if (ticks === null) return null
  return {
    ItemId: itemId,
    MediaSourceId: mediaSourceId ?? itemId,
    PositionTicks: ticks,
    IsPaused: isPaused === true,
    // True to what actually happens: `native.js` hands mpv the untouched file
    // off Jellyfin's own /Videos/:id/stream?static=true. Nothing is transcoded.
    PlayMethod: 'DirectPlay',
    CanSeek: true,
    ...(typeof playSessionId === 'string' && playSessionId
      ? { PlaySessionId: playSessionId }
      : {}),
  }
}

export function registerPlaybackRoutes(app) {
  const report = (tag, send, { requirePosition = true } = {}) => async (req, res) => {
    const body = reportBody(req, { requirePosition })
    if (!body) return res.status(400).json({ error: 'itemId and positionTicks required' })
    const { token } = getJellyfin(req)
    try {
      await send(token, body)
      res.json({ ok: true })
    } catch (err) {
      // A history write is never worth failing playback over: the player has
      // already moved on by the time this answers, and the next tick carries a
      // newer position anyway. Logged, reported as 502, and the client is built
      // to shrug it off.
      console.error(`playback/${tag}`, err.message)
      res.status(502).json({ error: 'could not report playback' })
    }
  }

  app.post(
    '/api/playback/started',
    requireAuth,
    report('started', reportPlaybackStart, { requirePosition: false }),
  )
  app.post('/api/playback/progress', requireAuth, report('progress', reportPlaybackProgress))
  app.post('/api/playback/stopped', requireAuth, report('stopped', reportPlaybackStopped))
}
