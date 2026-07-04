// Server-side proxy layer for the media-acquisition stack. Every route is gated
// by requireAuth and talks to the upstream service with the api key / session
// held ONLY on the server — no key or cookie ever reaches the client, in a
// response body or an error. Missing config degrades to a clean 503; a down or
// slow service maps to a 502/504 (bounded by the fetch timeout) — never a hang
// or crash. Wired into app/server/index.js via registerServarrRoutes(app).

import { requireAuth } from '../auth.js'
import { serviceConfig, configuredMap, SERVICES } from './config.js'
import {
  radarr, sonarr, prowlarr, bazarr, arrPing,
  radarrAddPayload, sonarrAddPayload, pickBestRelease,
  curatedPopular, CURATED_MOVIES, CURATED_SERIES,
  enrichTorrents, pickPosterImage, arrImageFetch,
  parseReleaseName, seasonEpisodeLabel, posterUrlFromImage, arrRating,
} from './arr.js'
import * as qbit from './qbittorrent.js'

// Map any thrown upstream/config error onto a clean JSON response. Logs
// server-side (message only — never the key) and strips upstream internals.
function fail(res, tag, err) {
  if (err?.notConfigured) {
    return res.status(503).json({ error: `${err.service} not configured` })
  }
  const status = err?.upstream ? (err.status || 502) : 500
  console.error(`servarr/${tag}`, err?.message || err)
  const msg = status === 504 ? 'service unreachable or timed out' : status >= 500 ? 'upstream service error' : 'request failed'
  res.status(status).json({ error: msg })
}

// Reject a route up front when its service has no env config.
function ensureConfigured(service, res) {
  if (serviceConfig(service).configured) return true
  res.status(503).json({ error: `${service} not configured` })
  return false
}

// ── Response shaping — strip upstream internals the client doesn't need ───────

const shapeProfile = (p) => ({ id: p.id, name: p.name })
const shapeRootFolder = (f) => ({ id: f.id, path: f.path, freeSpace: f.freeSpace, accessible: f.accessible })

const shapeMovieLookup = (m) => ({
  tmdbId: m.tmdbId, imdbId: m.imdbId, title: m.title, year: m.year,
  titleSlug: m.titleSlug, overview: m.overview, runtime: m.runtime,
  genres: Array.isArray(m.genres) ? m.genres : [], ratings: m.ratings ?? null,
  certification: m.certification ?? null, studio: m.studio ?? null,
  images: m.images, hasFile: !!m.hasFile, monitored: !!m.monitored, id: m.id ?? null,
})
const shapeMovie = (m) => ({
  id: m.id, tmdbId: m.tmdbId, title: m.title, year: m.year, hasFile: !!m.hasFile,
  monitored: !!m.monitored, sizeOnDisk: m.sizeOnDisk, status: m.status,
  qualityProfileId: m.qualityProfileId,
})

// One season row for the client's per-season chooser. `seasonNumber` 0 is
// "Specials". `monitored` reflects Sonarr's current state (meaningful for a
// series already in the library — a lookup echoes back the live flags). Episode
// counts come from `statistics`, which the lookup endpoint does NOT populate for
// a not-yet-added series (both null there); they fill in once Sonarr has the
// series, so the client shows a count only when it has one.
const shapeSeason = (s) => ({
  seasonNumber: s.seasonNumber,
  monitored: !!s.monitored,
  episodeCount: s.statistics?.episodeCount ?? null,
  totalEpisodeCount: s.statistics?.totalEpisodeCount ?? null,
})
const shapeSeriesLookup = (s) => ({
  tvdbId: s.tvdbId, imdbId: s.imdbId, title: s.title, year: s.year,
  titleSlug: s.titleSlug, overview: s.overview, network: s.network,
  genres: Array.isArray(s.genres) ? s.genres : [], ratings: s.ratings ?? null,
  runtime: s.runtime ?? null, certification: s.certification ?? null, status: s.status ?? null,
  images: s.images, seasonCount: s.seasons?.length ?? s.seasonCount, id: s.id ?? null,
  // Additive: the season list drives the client's per-season download chooser.
  seasons: Array.isArray(s.seasons) ? s.seasons.map(shapeSeason) : [],
})
const shapeSeries = (s) => ({
  id: s.id, tvdbId: s.tvdbId, title: s.title, year: s.year, status: s.status,
  monitored: !!s.monitored, seasonCount: s.statistics?.seasonCount ?? s.seasons?.length,
  sizeOnDisk: s.statistics?.sizeOnDisk, qualityProfileId: s.qualityProfileId,
})

const shapeIndexer = (i) => ({
  id: i.id, name: i.name, enable: !!i.enable, protocol: i.protocol,
  privacy: i.privacy, priority: i.priority,
})

// A single release from an interactive (`/api/v3/release`) search, flattened for
// the "choose a release" picker. `guid`+`indexerId` are the handle the grab
// endpoint needs; `seeders`/`leechers`/`size`/`quality` drive the row display;
// `rejected`+`rejections` let the client grey out (and explain) releases the
// auto-pick would skip. Nested quality name is flattened to a plain string.
const shapeRelease = (r) => ({
  guid: r.guid,
  indexerId: r.indexerId,
  title: r.title,
  seeders: typeof r.seeders === 'number' ? r.seeders : null,
  leechers: typeof r.leechers === 'number' ? r.leechers : null,
  size: typeof r.size === 'number' ? r.size : null,
  quality: r.quality?.quality?.name ?? null,
  indexer: r.indexer ?? null,
  protocol: r.protocol ?? null,
  rejected: !!r.rejected,
  rejections: Array.isArray(r.rejections) ? r.rejections : [],
})

// Shape + sort a release list for the picker: healthiest (most seeders) first so
// the best sources are on top. A missing seeder count (e.g. usenet) sorts as 0.
// Rejected releases are kept — shown greyed with their reason client-side — so
// the user can see (and understand) exactly what the auto-pick passed over.
function shapeReleases(releases) {
  return (Array.isArray(releases) ? releases : [])
    .filter((r) => r && r.guid && r.indexerId != null)
    .map(shapeRelease)
    .sort((a, b) => (b.seeders ?? 0) - (a.seeders ?? 0))
}

// A queue record whose `status` or `trackedDownloadStatus` isn't a plain "ok"
// is stuck somewhere between grab and import — dead indexer link, a download
// client rejection, a failed import (wrong file structure, no video found),
// etc. `statusMessages` carries the human-readable reason from the *arr app.
// 'error' is the most severe state (trackedDownloadStatus:'error', or a queue
// status:'error'/'failed') and MUST be surfaced in "needs attention".
const FAILING_STATUSES = new Set(['warning', 'error', 'failed'])
const shapeQueueItem = (service) => (q) => {
  const failing = FAILING_STATUSES.has(q.status) || FAILING_STATUSES.has(q.trackedDownloadStatus)
  return {
    id: q.id, service, title: q.title,
    status: q.status, trackedDownloadStatus: q.trackedDownloadStatus, trackedDownloadState: q.trackedDownloadState,
    size: q.size, sizeleft: q.sizeleft, indexer: q.indexer ?? null,
    errorMessage: q.errorMessage || null,
    statusMessages: Array.isArray(q.statusMessages)
      ? q.statusMessages.flatMap((m) => (Array.isArray(m.messages) ? m.messages : []))
      : [],
    added: q.added ?? null, failing,
  }
}

const shapeTorrent = (t) => ({
  hash: t.hash, name: t.name, state: t.state, progress: t.progress,
  size: t.size, downloaded: t.completed, dlspeed: t.dlspeed, upspeed: t.upspeed,
  eta: t.eta, numSeeds: t.num_seeds, numLeechs: t.num_leechs, category: t.category,
  savePath: t.save_path,
})

// ── Enriched downloads (qBittorrent ↔ *arr queue join) ────────────────────────
// The plain /qbittorrent/torrents route returns raw scene names; the enriched
// route joins each torrent to its Radarr/Sonarr queue record (hash==downloadId)
// to add a clean title/subtitle/poster. The join itself lives in arr.js
// (enrichTorrents); the pieces below are the stateful/network context it needs.

const QUEUE_CTX_TTL_MS = 2500                // share one queue snapshot across rapid polls
const POSTER_TTL_MS = 6 * 60 * 60 * 1000     // a title→poster mapping is stable
const POSTER_NEG_TTL_MS = 10 * 60 * 1000     // re-try a no-match title occasionally
let queueCtx = { at: 0, promise: null, radarr: [], sonarr: [] }
const posterCache = new Map()   // `${service}:${normTitle}` -> { at, url|null }
const posterInflight = new Set()

const normTitleKey = (s) => (s || '').toString().toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()

async function fetchQueueRecords(service, client) {
  if (!serviceConfig(service).configured) return []
  try {
    const data = await client.queue()
    return Array.isArray(data?.records) ? data.records : []
  } catch (err) {
    console.error(`servarr/downloads/enriched ${service} queue`, err?.message || err)
    return []
  }
}

// Cached Radarr+Sonarr queue snapshot, refreshed when older than the TTL. Each
// service is best-effort (a failure yields []), and a single in-flight refresh is
// shared so concurrent polls don't each hit the *arr APIs.
function getQueueCtx() {
  if (queueCtx.promise) return queueCtx.promise
  if (Date.now() - queueCtx.at < QUEUE_CTX_TTL_MS) {
    return Promise.resolve({ radarr: queueCtx.radarr, sonarr: queueCtx.sonarr })
  }
  const p = Promise.all([
    fetchQueueRecords('radarr', radarr),
    fetchQueueRecords('sonarr', sonarr),
  ]).then(([r, s]) => {
    queueCtx = { at: Date.now(), promise: null, radarr: r, sonarr: s }
    return { radarr: r, sonarr: s }
  }).catch((err) => {
    // Never poison the cache: drop the in-flight promise on rejection so the
    // next call retries instead of re-awaiting a settled, failed promise.
    if (queueCtx.promise === p) queueCtx.promise = null
    throw err
  })
  queueCtx.promise = p
  return p
}

// Resolve a poster for an "unknown" download the *arr queue couldn't map to a
// movie/series (still fetching torrent metadata, or a manual grab): look the
// parsed title up in Radarr/Sonarr and cache its public remoteUrl. The lookup runs
// in the BACKGROUND — a poll is never blocked by a live metadata lookup; the
// poster fills in on a later poll once cached. Returns the cached URL (or null).
function getCachedPoster(service, title) {
  const norm = normTitleKey(title)
  if (norm.length < 2) return null
  const key = `${service}:${norm}`
  const hit = posterCache.get(key)
  const fresh = hit && Date.now() - hit.at < (hit.url ? POSTER_TTL_MS : POSTER_NEG_TTL_MS)
  if (!fresh && !posterInflight.has(key) && serviceConfig(service).configured) {
    posterInflight.add(key)
    const lookup = service === 'radarr' ? radarr.lookup : sonarr.lookup
    Promise.resolve(lookup(title))
      .then((arr) => {
        const poster = pickPosterImage((Array.isArray(arr) ? arr[0] : null)?.images)
        const url = poster?.remoteUrl && /^https?:\/\//i.test(poster.remoteUrl) ? poster.remoteUrl : null
        posterCache.set(key, { at: Date.now(), url })
      })
      .catch(() => posterCache.set(key, { at: Date.now(), url: null }))
      .finally(() => posterInflight.delete(key))
  }
  return hit?.url || null
}

// ── Download detail (single active download → rich movie/series metadata) ─────
// Backs GET /api/servarr/downloads/:hash/detail. Resolves the download the same
// way the enriched list does — first by the *arr queue record whose downloadId
// equals the torrent hash, then (for an "unknown" queue item still fetching
// metadata, or a manual grab) by looking the parsed release name up in
// Radarr/Sonarr. Returns { title, subtitle, year, overview, genres, runtime,
// rating, certification, posterUrl, kind } — always something renderable, even
// when nothing resolves (falls back to the parsed release name).

const findByDownloadId = (records, key) =>
  (Array.isArray(records) ? records : []).find(
    (r) => r?.downloadId && String(r.downloadId).toLowerCase() === key,
  ) || null

const detailFromMovie = (mv) => ({
  kind: 'movie',
  title: mv.title,
  year: mv.year ?? null,
  subtitle: mv.year ? String(mv.year) : null,
  overview: mv.overview || null,
  genres: Array.isArray(mv.genres) ? mv.genres : [],
  runtime: typeof mv.runtime === 'number' && mv.runtime > 0 ? mv.runtime : null,
  rating: arrRating(mv.ratings),
  certification: mv.certification || null,
  network: null,
  status: mv.status || null,
  posterUrl: posterUrlFromImage('radarr', pickPosterImage(mv.images)),
})

const detailFromSeries = (sr, label, parsed) => ({
  kind: 'series',
  title: sr.title,
  year: sr.year ?? null,
  subtitle: label
    || (parsed?.episode != null ? `S${parsed.season}E${parsed.episode}`
      : parsed?.season != null ? `Season ${parsed.season}`
      : sr.year ? String(sr.year) : null),
  overview: sr.overview || null,
  genres: Array.isArray(sr.genres) ? sr.genres : [],
  runtime: typeof sr.runtime === 'number' && sr.runtime > 0 ? sr.runtime : null,
  rating: arrRating(sr.ratings),
  certification: sr.certification || null,
  network: sr.network || null,
  status: sr.status || null,
  posterUrl: posterUrlFromImage('sonarr', pickPosterImage(sr.images)),
})

// Resolve detail by parsing the release name and looking it up in the catalog —
// the fallback for a queue record with no matched movie/series (or no record at
// all). Returns the shaped detail, or a bare parsed-name shape if the lookup
// yields nothing (so the detail view still has a title + kind).
async function detailByLookup(service, rawName, label) {
  const kind = service === 'radarr' ? 'movie' : 'series'
  const parsed = parseReleaseName(rawName)
  const term = parsed.title || rawName
  let hit = null
  try {
    const lookup = service === 'radarr' ? radarr.lookup : sonarr.lookup
    const arr = await lookup(term)
    hit = (Array.isArray(arr) && arr[0]) || null
  } catch { /* fall through to the bare parsed-name shape */ }
  if (hit) return kind === 'movie' ? detailFromMovie(hit) : detailFromSeries(hit, label, parsed)
  return {
    kind, title: term, year: parsed.year ?? null,
    subtitle: kind === 'series'
      ? (label || (parsed.episode != null ? `S${parsed.season}E${parsed.episode}` : parsed.season != null ? `Season ${parsed.season}` : null))
      : (parsed.year ? String(parsed.year) : null),
    overview: null, genres: [], runtime: null, rating: null, certification: null,
    network: null, status: null, posterUrl: null,
  }
}

async function resolveDownloadDetail(torrent, ctx) {
  const key = String(torrent.hash || '').toLowerCase()

  const mrec = findByDownloadId(ctx.radarr, key)
  if (mrec) {
    const movieId = mrec.movieId ?? mrec.movie?.id
    let mv = mrec.movie
    if (movieId) { try { mv = await radarr.get(movieId) } catch { /* keep embedded */ } }
    if (mv && mv.title) return detailFromMovie(mv)
    return detailByLookup('radarr', mrec.title || torrent.name)
  }

  const srec = findByDownloadId(ctx.sonarr, key)
  if (srec) {
    const seriesId = srec.seriesId ?? srec.series?.id
    const label = seasonEpisodeLabel(srec)
    let sr = srec.series
    if (seriesId) { try { sr = await sonarr.get(seriesId) } catch { /* keep embedded */ } }
    if (sr && sr.title) return detailFromSeries(sr, label)
    return detailByLookup('sonarr', srec.title || torrent.name, label)
  }

  // No queue record — a manual/untracked torrent. Category is the only hint at
  // movie vs series; lookup the parsed name in that service.
  const cat = (torrent.category || '').toLowerCase()
  const service = cat.includes('radarr') || cat.includes('movie') ? 'radarr'
    : cat.includes('sonarr') || cat.includes('tv') ? 'sonarr' : null
  if (service) return detailByLookup(service, torrent.name)

  const parsed = parseReleaseName(torrent.name)
  return {
    kind: null, title: parsed.title || torrent.name, year: parsed.year ?? null,
    subtitle: parsed.year ? String(parsed.year) : null,
    overview: null, genres: [], runtime: null, rating: null, certification: null,
    network: null, status: null, posterUrl: null,
  }
}

// Cross-service reconciliation: a torrent deleted straight from the download
// client leaves its Radarr/Sonarr queue record dangling — it lingers as a stuck
// "warning" item because the download it tracked has vanished, forcing the user
// to remove the same thing twice (once in the download list, again in "needs
// attention"). After a client-side delete we find any *arr queue records whose
// downloadId matches a removed hash and drop them too, so a delete in one place
// clears the download from every surface. Best-effort and never throws: the qbit
// delete already succeeded, so a failure here must not turn into a user error.
const ARR_QUEUE_CLIENTS = [['radarr', radarr], ['sonarr', sonarr]]
async function reconcileArrQueues(hashes) {
  const wanted = new Set(
    String(hashes).split('|').map((h) => h.trim().toLowerCase()).filter(Boolean),
  )
  if (wanted.size === 0) return
  await Promise.all(ARR_QUEUE_CLIENTS.map(async ([name, client]) => {
    if (!serviceConfig(name).configured) return
    try {
      const data = await client.queue()
      const records = Array.isArray(data?.records) ? data.records : []
      const matches = records.filter((r) => r.downloadId && wanted.has(String(r.downloadId).toLowerCase()))
      // removeFromClient:false — the torrent is already gone; we only drop the
      // now-orphaned tracking record. blocklist:false — a user-initiated remove
      // isn't a "bad release" to avoid forever.
      await Promise.all(matches.map((r) =>
        client.removeQueueItem(r.id, { removeFromClient: false, blocklist: false }).catch(() => {})))
    } catch { /* best-effort reconciliation */ }
  }))
}

// ── Discover / "popular" rail ─────────────────────────────────────────────────
// Serves the tap-to-request rail shown when there's no active search. Prefers a
// genuine source (the admin's configured import lists) and degrades to a curated
// seed run through the real catalog lookup — see arr.js for the honesty note.
// The seed is static and the import feed changes slowly, so results are cached
// in memory (per service, 6h) to avoid re-running ~14 catalog lookups per visit.
const POPULAR_TTL_MS = 6 * 60 * 60 * 1000
const popularCache = {}   // service -> { at, payload }

async function buildRadarrPopular() {
  // 1) Prefer the genuine popularity feed: the admin's configured import lists
  //    (TMDb Popular / Trakt Trending / etc.). Best-effort — empty or erroring
  //    (e.g. none configured) just falls through to the curated seed.
  try {
    const list = await radarr.discover()
    if (Array.isArray(list) && list.length) {
      return { source: 'importlist', items: list.slice(0, 24).map(shapeMovieLookup) }
    }
  } catch (err) {
    console.error('servarr/radarr/popular importlist', err?.message || err)
  }
  // 2) Degrade gracefully to a curated seed resolved through the real lookup.
  const items = await curatedPopular(radarr.lookup, CURATED_MOVIES, 'tmdbId')
  return { source: 'curated', items: items.map(shapeMovieLookup) }
}

async function buildSonarrPopular() {
  // Sonarr in this deployment exposes no import-list preview (/importlist/series
  // → 404) and there's no external popularity API, so the series rail is always
  // the curated seed resolved through the real series lookup.
  const items = await curatedPopular(sonarr.lookup, CURATED_SERIES, 'tvdbId')
  return { source: 'curated', items: items.map(shapeSeriesLookup) }
}

function servePopular(service, builder) {
  return async (_req, res) => {
    if (!ensureConfigured(service, res)) return
    const hit = popularCache[service]
    if (hit && Date.now() - hit.at < POPULAR_TTL_MS) return res.json(hit.payload)
    try {
      const payload = await builder()
      // Only cache a non-empty result: an empty rail almost always means a
      // transient lookup outage, and we don't want to pin that for 6h.
      if (payload.items.length) popularCache[service] = { at: Date.now(), payload }
      res.json(payload)
    } catch (err) { fail(res, `${service}/popular`, err) }
  }
}

// Mark the chosen seasons monitored on a Sonarr series and PUT it back. This is
// additive — it only flips `monitored` to true on the wanted seasons (and the
// series), never unmonitoring one the user already had. Sonarr replaces the whole
// record on PUT, so we GET the current object, mutate, and PUT it whole.
//
// A freshly-added series is mid-RefreshSeries (Sonarr re-syncs metadata right
// after an add), and that refresh can clobber a PUT that lands during it — the
// season silently reverts to unmonitored (confirmed live). So when `settle` is
// set we re-read AFTER a short delay and retry until the monitoring persists past
// the refresh window. For a series already in the library there's no in-flight
// refresh, so a single GET→PUT is enough (settle:false). Returns the final object.
async function sonarrMonitorSeasons(seriesId, wantedSet, { settle = false } = {}) {
  const attempts = settle ? 4 : 1
  let full
  for (let i = 0; i < attempts; i++) {
    full = await sonarr.get(seriesId)
    full.monitored = true
    full.seasons = (full.seasons || []).map(
      (s) => (wantedSet.has(s.seasonNumber) ? { ...s, monitored: true } : s),
    )
    await sonarr.update(seriesId, full)
    if (!settle) break
    // Let any in-flight post-add refresh finish, then confirm the PUT survived it.
    await new Promise((r) => setTimeout(r, 800))
    const check = await sonarr.get(seriesId)
    const chosen = (check.seasons || []).filter((s) => wantedSet.has(s.seasonNumber))
    if (chosen.length && chosen.every((s) => s.monitored)) return check
    full = check
  }
  return full
}

export function registerServarrRoutes(app) {
  // ── Health: which services are configured + reachable. Never throws. ────────
  app.get('/api/servarr/health', requireAuth, async (_req, res) => {
    const configured = configuredMap()
    const services = {}
    await Promise.all(SERVICES.map(async (s) => {
      if (!configured[s]) { services[s] = { configured: false, reachable: false }; return }
      const ping = s === 'qbittorrent' ? await qbit.qbitPing() : await arrPing(s)
      services[s] = { configured: true, ...ping }
    }))
    res.json({ services })
  })

  // ── Radarr ──────────────────────────────────────────────────────────────────
  app.get('/api/servarr/radarr/search', requireAuth, async (req, res) => {
    if (!ensureConfigured('radarr', res)) return
    const term = (req.query.term || '').toString().trim()
    if (!term) return res.status(400).json({ error: 'term required' })
    try {
      const data = await radarr.lookup(term)
      res.json((Array.isArray(data) ? data : []).map(shapeMovieLookup))
    } catch (err) { fail(res, 'radarr/search', err) }
  })

  // Discover rail for the Browse tab's no-query state (movies).
  app.get('/api/servarr/radarr/popular', requireAuth, servePopular('radarr', buildRadarrPopular))

  app.get('/api/servarr/radarr/movies', requireAuth, async (_req, res) => {
    if (!ensureConfigured('radarr', res)) return
    try {
      const data = await radarr.library()
      res.json((Array.isArray(data) ? data : []).map(shapeMovie))
    } catch (err) { fail(res, 'radarr/movies', err) }
  })

  app.get('/api/servarr/radarr/quality-profiles', requireAuth, async (_req, res) => {
    if (!ensureConfigured('radarr', res)) return
    try {
      const data = await radarr.qualityProfiles()
      res.json((Array.isArray(data) ? data : []).map(shapeProfile))
    } catch (err) { fail(res, 'radarr/quality-profiles', err) }
  })

  app.get('/api/servarr/radarr/root-folders', requireAuth, async (_req, res) => {
    if (!ensureConfigured('radarr', res)) return
    try {
      const data = await radarr.rootFolders()
      res.json((Array.isArray(data) ? data : []).map(shapeRootFolder))
    } catch (err) { fail(res, 'radarr/root-folders', err) }
  })

  app.post('/api/servarr/radarr/add', requireAuth, async (req, res) => {
    if (!ensureConfigured('radarr', res)) return
    const { movie, qualityProfileId, rootFolderPath, monitor, searchNow } = req.body || {}
    if (!movie?.tmdbId || !qualityProfileId || !rootFolderPath) {
      return res.status(400).json({ error: 'movie (with tmdbId), qualityProfileId and rootFolderPath required' })
    }
    try {
      const payload = radarrAddPayload(movie, { qualityProfileId, rootFolderPath, monitor, searchNow })
      const added = await radarr.add(payload)
      res.status(201).json(shapeMovie(added))
    } catch (err) { fail(res, 'radarr/add', err) }
  })

  // Server-authoritative "request a movie" — deterministic grab-or-remove.
  //   1. Add the movie WITHOUT an auto-search, so nothing happens async/uncontrolled.
  //   2. Run one live interactive release search (slow — bounded ~45s).
  //   3. If a search SUCCEEDS and finds an acceptable (non-rejected) release, grab
  //      the best one → { outcome: 'grabbed' }. If it SUCCEEDS but nothing is
  //      usable, delete the movie so no fileless orphan is left → { outcome: 'no_release' }.
  //   4. SAFETY: if the search itself errors/times out (or the grab / delete
  //      fails), we do NOT know the title has no release — leave the entry in
  //      place and return { outcome: 'search_failed' }. Never discard a wanted
  //      movie on a transient blip.
  app.post('/api/servarr/radarr/request', requireAuth, async (req, res) => {
    if (!ensureConfigured('radarr', res)) return
    const { movie, qualityProfileId, rootFolderPath } = req.body || {}
    if (!movie?.tmdbId || !qualityProfileId || !rootFolderPath) {
      return res.status(400).json({ error: 'movie (with tmdbId), qualityProfileId and rootFolderPath required' })
    }

    // 1) Add, monitored but with NO auto-search — the request drives search itself.
    let added
    try {
      const payload = radarrAddPayload(movie, { qualityProfileId, rootFolderPath, monitor: true, searchNow: false })
      added = await radarr.add(payload)
    } catch (err) {
      // Already in Radarr? Never run grab-or-remove on an entry we didn't just
      // create — it may be a real, file-backed library movie. Report it benignly.
      if (err?.status === 400 && /already|exist/i.test(err.body || '')) {
        return res.json({ outcome: 'exists' })
      }
      return fail(res, 'radarr/request/add', err)
    }
    const movieId = added.id

    // 2) Live interactive release search.
    let releases
    try {
      releases = await radarr.releaseSearch(movieId)
    } catch (searchErr) {
      // 4) TRANSIENT-FAILURE GUARD: the search never completed, so we can't claim
      // there's no release. Leave the (monitored) entry and let the user retry.
      console.error('servarr/radarr/request search', searchErr?.message || searchErr)
      return res.json({ outcome: 'search_failed', movieId, title: added.title })
    }

    // 3) Decide from a search that genuinely SUCCEEDED. A search that returned
    // NO releases at all is inconclusive: Radarr answers 200 with an empty list
    // when its indexers are unreachable (VPN/indexer outage), which we cannot
    // tell apart from a title that truly has none. Treat empty (or a malformed
    // non-array response) as a transient failure and KEEP the entry — we only
    // remove on a search that positively returned releases yet found none usable
    // (all rejected), which proves the indexers actually responded.
    if (!Array.isArray(releases) || releases.length === 0) {
      console.error('servarr/radarr/request search', 'empty release list — treating as transient, keeping entry')
      return res.json({ outcome: 'search_failed', movieId, title: added.title })
    }
    const best = pickBestRelease(releases)
    if (!best) {
      // Indexers responded with releases but none are acceptable — a confirmed
      // no-usable-release. Leave nothing behind.
      try {
        await radarr.remove(movieId, { deleteFiles: false, addImportExclusion: false })
      } catch (delErr) {
        // Couldn't remove it — don't claim "no release" while an orphan lingers;
        // report a retryable failure instead.
        console.error('servarr/radarr/request delete', delErr?.message || delErr)
        return res.json({ outcome: 'search_failed', movieId, title: added.title })
      }
      return res.json({ outcome: 'no_release', title: added.title })
    }

    // An acceptable release exists → grab the best one (hands off to the client).
    try {
      await radarr.grabRelease({ guid: best.guid, indexerId: best.indexerId })
    } catch (grabErr) {
      // The release existed but the hand-off failed — keep the entry and let the
      // user retry rather than deleting a movie that has a real release.
      console.error('servarr/radarr/request grab', grabErr?.message || grabErr)
      return res.json({ outcome: 'search_failed', movieId, title: added.title })
    }
    return res.json({ outcome: 'grabbed', movieId, title: added.title })
  })

  // ── Interactive "choose a release" picker (movies) ────────────────────────────
  // An OPTIONAL, user-driven alternative to the one-tap grab-or-remove above: it
  // lists every release for a title (with seed counts) and lets the user grab a
  // specific one. Three routes cooperate so browsing releases never pollutes the
  // Radarr DB with orphan entries:
  //
  //   POST /radarr/releases  — open the picker. releaseSearch needs a movieId, so
  //       if the title isn't in Radarr yet we add it (monitored, NO auto-search)
  //       purely to run the live search, and flag `createdByPicker:true`. The
  //       client keeps `movieId`+`createdByPicker` for its lifetime.
  //   POST /radarr/grab      — the user picked a row: hand that exact release to
  //       the download client and KEEP the entry.
  //   POST /radarr/releases/cancel — the user closed the picker without grabbing:
  //       if THIS picker created the entry, remove it so nothing is left behind.
  //
  // Deletion is tied solely to the explicit cancel path (never to a search error),
  // and is guarded so a title that actually downloaded — or one the picker didn't
  // create — is never removed.

  // Open the picker. Body is either { movieId } for a title already in Radarr, or
  // { movie, qualityProfileId, rootFolderPath } for a lookup result we must add
  // first. Returns { movieId, createdByPicker, releases, searchFailed }. A failed
  // live search is reported (searchFailed:true) WITHOUT deleting anything — the
  // client still holds movieId so closing the picker can clean up if we created it.
  app.post('/api/servarr/radarr/releases', requireAuth, async (req, res) => {
    if (!ensureConfigured('radarr', res)) return
    const { movieId: bodyMovieId, movie, qualityProfileId, rootFolderPath } = req.body || {}

    let movieId = Number.isFinite(Number(bodyMovieId)) ? Number(bodyMovieId) : null
    let createdByPicker = false

    // No movieId → this is a not-yet-added lookup result. Add it monitored with no
    // auto-search (the picker drives the search itself), so browsing can proceed.
    if (movieId == null) {
      if (!movie?.tmdbId || !qualityProfileId || !rootFolderPath) {
        return res.status(400).json({ error: 'movieId, or movie (with tmdbId) + qualityProfileId + rootFolderPath, required' })
      }
      try {
        const payload = radarrAddPayload(movie, { qualityProfileId, rootFolderPath, monitor: true, searchNow: false })
        const added = await radarr.add(payload)
        movieId = added.id
        createdByPicker = true
      } catch (err) {
        // Already present? Fall back to the existing library entry (we did NOT
        // create it, so the picker must never remove it on cancel).
        if (err?.status === 400 && /already|exist/i.test(err.body || '')) {
          try {
            const lib = await radarr.library()
            const found = (Array.isArray(lib) ? lib : []).find((m) => m.tmdbId === movie.tmdbId)
            if (found) { movieId = found.id; createdByPicker = false }
          } catch { /* fall through to the error below */ }
          if (movieId == null) return fail(res, 'radarr/releases/add', err)
        } else {
          return fail(res, 'radarr/releases/add', err)
        }
      }
    }

    // Live interactive release search (slow — bounded ~45s by arr.js).
    try {
      const releases = await radarr.releaseSearch(movieId)
      return res.json({ movieId, createdByPicker, searchFailed: false, releases: shapeReleases(releases) })
    } catch (searchErr) {
      // Do NOT delete on a search error — leave the (possibly picker-created)
      // entry so closing the picker takes the single, guarded cleanup path.
      console.error('servarr/radarr/releases search', searchErr?.message || searchErr)
      return res.json({ movieId, createdByPicker, searchFailed: true, releases: [] })
    }
  })

  // Grab one specific release the user chose in the picker, keeping the entry.
  app.post('/api/servarr/radarr/grab', requireAuth, async (req, res) => {
    if (!ensureConfigured('radarr', res)) return
    const { guid, indexerId } = req.body || {}
    if (!guid || indexerId == null) return res.status(400).json({ error: 'guid and indexerId required' })
    try {
      await radarr.grabRelease({ guid, indexerId })
      return res.json({ outcome: 'grabbed' })
    } catch (err) { fail(res, 'radarr/grab', err) }
  })

  // Clean up a browsing-only entry when the picker closes without a grab. Only
  // acts when the client says THIS picker created the entry, and only after
  // re-checking the movie is safe to drop: it must still exist, have no imported
  // file, and have nothing in the download queue (an in-flight grab). Anything
  // else → leave it. Always best-effort: a cleanup failure never surfaces as an
  // error to the user (the worst case is one harmless fileless entry, not a
  // wrongly-deleted title).
  app.post('/api/servarr/radarr/releases/cancel', requireAuth, async (req, res) => {
    if (!ensureConfigured('radarr', res)) return
    const movieId = Number(req.body?.movieId)
    const createdByPicker = req.body?.createdByPicker === true
    if (!Number.isFinite(movieId)) return res.status(400).json({ error: 'movieId required' })
    if (!createdByPicker) return res.json({ ok: true, removed: false }) // never touch entries we didn't create

    try {
      const mv = await radarr.get(movieId)
      if (mv?.hasFile) return res.json({ ok: true, removed: false }) // real file imported — keep it

      // A record in the queue means a grab is already in flight — don't nuke it.
      let inQueue = false
      try {
        const q = await radarr.queue()
        const records = Array.isArray(q?.records) ? q.records : []
        inQueue = records.some((r) => r.movieId === movieId)
      } catch { /* queue check is best-effort; fall back to the hasFile guard */ }
      if (inQueue) return res.json({ ok: true, removed: false })

      await radarr.remove(movieId, { deleteFiles: false, addImportExclusion: false })
      return res.json({ ok: true, removed: true })
    } catch (err) {
      console.error('servarr/radarr/releases/cancel', err?.message || err)
      return res.json({ ok: true, removed: false }) // swallow — cleanup is not user-facing
    }
  })

  app.get('/api/servarr/radarr/queue', requireAuth, async (_req, res) => {
    if (!ensureConfigured('radarr', res)) return
    try {
      const data = await radarr.queue()
      const records = Array.isArray(data?.records) ? data.records : []
      res.json(records.map(shapeQueueItem('radarr')))
    } catch (err) { fail(res, 'radarr/queue', err) }
  })

  app.delete('/api/servarr/radarr/queue/:id', requireAuth, async (req, res) => {
    if (!ensureConfigured('radarr', res)) return
    const id = Number(req.params.id)
    if (!Number.isFinite(id)) return res.status(400).json({ error: 'invalid id' })
    try {
      await radarr.removeQueueItem(id, { removeFromClient: true, blocklist: !!req.body?.blocklist })
      res.json({ ok: true })
    } catch (err) { fail(res, 'radarr/queue/delete', err) }
  })

  // ── Sonarr ──────────────────────────────────────────────────────────────────
  app.get('/api/servarr/sonarr/search', requireAuth, async (req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    const term = (req.query.term || '').toString().trim()
    if (!term) return res.status(400).json({ error: 'term required' })
    try {
      const data = await sonarr.lookup(term)
      res.json((Array.isArray(data) ? data : []).map(shapeSeriesLookup))
    } catch (err) { fail(res, 'sonarr/search', err) }
  })

  // Discover rail for the Browse tab's no-query state (series).
  app.get('/api/servarr/sonarr/popular', requireAuth, servePopular('sonarr', buildSonarrPopular))

  app.get('/api/servarr/sonarr/series', requireAuth, async (_req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    try {
      const data = await sonarr.library()
      res.json((Array.isArray(data) ? data : []).map(shapeSeries))
    } catch (err) { fail(res, 'sonarr/series', err) }
  })

  app.get('/api/servarr/sonarr/quality-profiles', requireAuth, async (_req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    try {
      const data = await sonarr.qualityProfiles()
      res.json((Array.isArray(data) ? data : []).map(shapeProfile))
    } catch (err) { fail(res, 'sonarr/quality-profiles', err) }
  })

  app.get('/api/servarr/sonarr/language-profiles', requireAuth, async (_req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    try {
      const data = await sonarr.languageProfiles()
      res.json((Array.isArray(data) ? data : []).map(shapeProfile))
    } catch (err) { fail(res, 'sonarr/language-profiles', err) }
  })

  app.get('/api/servarr/sonarr/root-folders', requireAuth, async (_req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    try {
      const data = await sonarr.rootFolders()
      res.json((Array.isArray(data) ? data : []).map(shapeRootFolder))
    } catch (err) { fail(res, 'sonarr/root-folders', err) }
  })

  app.post('/api/servarr/sonarr/add', requireAuth, async (req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    const { series, qualityProfileId, languageProfileId, rootFolderPath, monitor, searchNow } = req.body || {}
    if (!series?.tvdbId || !qualityProfileId || !rootFolderPath) {
      return res.status(400).json({ error: 'series (with tvdbId), qualityProfileId and rootFolderPath required' })
    }
    try {
      const payload = sonarrAddPayload(series, { qualityProfileId, languageProfileId, rootFolderPath, monitor, searchNow })
      const added = await sonarr.add(payload)
      res.status(201).json(shapeSeries(added))
    } catch (err) { fail(res, 'sonarr/add', err) }
  })

  // "Request a series" — the safe analog of the movie grab-or-remove flow.
  //
  // We deliberately do NOT apply grab-or-remove to series. A show is many
  // episodes across many seasons with partial, over-time availability: deleting
  // the whole series because a single full-season pack isn't grabbable right now
  // would wrongly discard a title whose individual episodes are (or will become)
  // available. Monitoring is the *correct* behaviour for TV. So we add the series
  // monitored, let Sonarr run its own search + grab whatever exists now, and keep
  // watching for the rest — we never delete. Returns { outcome: 'monitoring' }
  // (any episodes it grabs surface via the live download list, same as movies).
  // A fully-correct series grab-or-remove (per-episode release search with
  // partial-availability accounting) is intentionally out of scope here.
  app.post('/api/servarr/sonarr/request', requireAuth, async (req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    const { series, qualityProfileId, languageProfileId, rootFolderPath, monitor, searchNow } = req.body || {}
    if (!series?.tvdbId || !qualityProfileId || !rootFolderPath) {
      return res.status(400).json({ error: 'series (with tvdbId), qualityProfileId and rootFolderPath required' })
    }
    try {
      const payload = sonarrAddPayload(series, {
        qualityProfileId, languageProfileId, rootFolderPath,
        monitor: monitor !== false, searchNow: searchNow !== false,
      })
      const added = await sonarr.add(payload)
      return res.json({ outcome: 'monitoring', seriesId: added.id, title: added.title })
    } catch (err) {
      if (err?.status === 400 && /already|exist/i.test(err.body || '')) {
        return res.json({ outcome: 'exists' })
      }
      return fail(res, 'sonarr/request', err)
    }
  })

  // "Request specific season(s)" — the per-season analog of /request.
  //
  // TV availability is partial and spread over time, so (as with /request) we
  // never delete: a season request means "monitor these season(s) and search for
  // them now". Whatever exists is grabbed; the rest is picked up as it appears.
  // The client sends the chosen season numbers (one for a single season, the full
  // set for an "All seasons" request) plus the lookup `series` (and profile/folder
  // for a first add) or an existing `seriesId`.
  //
  // Flow (add-if-needed → monitor chosen seasons → search):
  //   1. Resolve the seriesId. If the show isn't in Sonarr yet, add a shell with
  //      addOptions.monitor:'none' + no search — verified live, this leaves EVERY
  //      season unmonitored regardless of the payload's `seasons`, so it can't
  //      accidentally pull the whole series. An "already exists" race falls back
  //      to the library id.
  //   2. GET the full series, flip ONLY the chosen seasons' `monitored` to true
  //      (additive — never unmonitors a season the user already had), mark the
  //      series monitored, and PUT the whole object back. Sonarr cascades season
  //      monitoring down to that season's episodes (verified).
  //   3. Fire a SeasonSearch command per chosen season (background; returns a
  //      command id). Best-effort: the durable part is the monitoring PUT, so a
  //      search that fails to queue still leaves Sonarr watching the season.
  // Returns { outcome: 'season_searching', seriesId, title, seasons: [...] }.
  app.post('/api/servarr/sonarr/request-season', requireAuth, async (req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    const { series, qualityProfileId, languageProfileId, rootFolderPath } = req.body || {}

    // Chosen season numbers, deduped and sane (>= 0; 0 = Specials).
    const wanted = [...new Set(
      (Array.isArray(req.body?.seasons) ? req.body.seasons : [])
        .map(Number).filter((n) => Number.isInteger(n) && n >= 0),
    )]
    if (!wanted.length) return res.status(400).json({ error: 'seasons (array of season numbers) required' })

    // A lookup echoes `id: null` for a not-yet-added series — Number(null) is 0
    // (finite!), so guard against null/undefined explicitly and require a real id.
    const rawId = req.body?.seriesId ?? series?.id
    const givenId = rawId == null ? null : Number(rawId)
    const haveId = givenId != null && Number.isInteger(givenId) && givenId > 0
    if (!haveId && (!series?.tvdbId || !qualityProfileId || !rootFolderPath)) {
      return res.status(400).json({ error: 'series (with tvdbId) + qualityProfileId + rootFolderPath, or a seriesId, required' })
    }

    try {
      // 1) Resolve the seriesId — add a monitor-nothing shell if it isn't present.
      let seriesId = haveId ? givenId : null
      let freshlyAdded = false
      if (seriesId == null) {
        try {
          const payload = sonarrAddPayload(series, {
            qualityProfileId, languageProfileId, rootFolderPath, monitor: false, searchNow: false,
          })
          const added = await sonarr.add(payload)
          seriesId = added.id
          freshlyAdded = true
        } catch (err) {
          if (err?.status === 400 && /already|exist/i.test(err.body || '')) {
            const lib = await sonarr.library()
            const found = (Array.isArray(lib) ? lib : []).find((s) => s.tvdbId === series?.tvdbId)
            if (!found) return fail(res, 'sonarr/request-season/add', err)
            seriesId = found.id
          } else {
            return fail(res, 'sonarr/request-season/add', err)
          }
        }
      }

      // 2) Monitor the chosen seasons (additive). `settle` guards the fresh-add
      //    race where the post-add refresh would otherwise clobber the PUT.
      const wantedSet = new Set(wanted)
      const full = await sonarrMonitorSeasons(seriesId, wantedSet, { settle: freshlyAdded })
      const present = new Set((full.seasons || []).map((s) => s.seasonNumber))

      // 3) SeasonSearch each chosen season that actually exists on the series.
      const searched = wanted.filter((n) => present.has(n))
      await Promise.all(searched.map((seasonNumber) =>
        sonarr.command({ name: 'SeasonSearch', seriesId, seasonNumber })
          .catch((e) => console.error('servarr/sonarr/request-season search', seasonNumber, e?.message || e)),
      ))

      return res.json({ outcome: 'season_searching', seriesId, title: full.title, seasons: searched })
    } catch (err) {
      return fail(res, 'sonarr/request-season', err)
    }
  })

  app.get('/api/servarr/sonarr/queue', requireAuth, async (_req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    try {
      const data = await sonarr.queue()
      const records = Array.isArray(data?.records) ? data.records : []
      res.json(records.map(shapeQueueItem('sonarr')))
    } catch (err) { fail(res, 'sonarr/queue', err) }
  })

  app.delete('/api/servarr/sonarr/queue/:id', requireAuth, async (req, res) => {
    if (!ensureConfigured('sonarr', res)) return
    const id = Number(req.params.id)
    if (!Number.isFinite(id)) return res.status(400).json({ error: 'invalid id' })
    try {
      await sonarr.removeQueueItem(id, { removeFromClient: true, blocklist: !!req.body?.blocklist })
      res.json({ ok: true })
    } catch (err) { fail(res, 'sonarr/queue/delete', err) }
  })

  // ── Prowlarr ──────────────────────────────────────────────────────────────────
  app.get('/api/servarr/prowlarr/indexers', requireAuth, async (_req, res) => {
    if (!ensureConfigured('prowlarr', res)) return
    try {
      const data = await prowlarr.indexers()
      res.json((Array.isArray(data) ? data : []).map(shapeIndexer))
    } catch (err) { fail(res, 'prowlarr/indexers', err) }
  })

  app.get('/api/servarr/prowlarr/search', requireAuth, async (req, res) => {
    if (!ensureConfigured('prowlarr', res)) return
    const query = (req.query.query || '').toString().trim()
    if (!query) return res.status(400).json({ error: 'query required' })
    try {
      const data = await prowlarr.search(query)
      const items = Array.isArray(data) ? data : []
      res.json(items.map((r) => ({
        title: r.title, indexer: r.indexer, size: r.size, seeders: r.seeders,
        leechers: r.leechers, protocol: r.protocol, publishDate: r.publishDate,
      })))
    } catch (err) { fail(res, 'prowlarr/search', err) }
  })

  // ── Bazarr ──────────────────────────────────────────────────────────────────
  app.get('/api/servarr/bazarr/wanted/movies', requireAuth, async (_req, res) => {
    if (!ensureConfigured('bazarr', res)) return
    try {
      res.json(await bazarr.wantedMovies())
    } catch (err) { fail(res, 'bazarr/wanted/movies', err) }
  })

  app.get('/api/servarr/bazarr/wanted/series', requireAuth, async (_req, res) => {
    if (!ensureConfigured('bazarr', res)) return
    try {
      res.json(await bazarr.wantedSeries())
    } catch (err) { fail(res, 'bazarr/wanted/series', err) }
  })

  // ── qBittorrent ───────────────────────────────────────────────────────────────
  app.get('/api/servarr/qbittorrent/torrents', requireAuth, async (_req, res) => {
    if (!ensureConfigured('qbittorrent', res)) return
    try {
      const data = await qbit.torrentsInfo()
      res.json((Array.isArray(data) ? data : []).map(shapeTorrent))
    } catch (err) { fail(res, 'qbittorrent/torrents', err) }
  })

  // Enriched download list: qBittorrent torrents joined to the Radarr/Sonarr queue
  // so each carries a clean displayTitle/subtitle/posterUrl (+ kind + matched). A
  // superset of /qbittorrent/torrents — same items and fields, plus enrichment —
  // so existing consumers keep working. Enrichment is best-effort: if the *arr
  // queues are slow/unavailable the (unmatched) torrent list still returns, so
  // download controls never hinge on Radarr/Sonarr being reachable.
  app.get('/api/servarr/downloads/enriched', requireAuth, async (_req, res) => {
    if (!ensureConfigured('qbittorrent', res)) return
    let torrents
    try {
      const data = await qbit.torrentsInfo()
      torrents = (Array.isArray(data) ? data : []).map(shapeTorrent)
    } catch (err) { return fail(res, 'downloads/enriched', err) }
    let ctx = { radarr: [], sonarr: [] }
    try { ctx = await getQueueCtx() } catch { /* best-effort → items stay matched:false */ }
    res.json(enrichTorrents(torrents, ctx, getCachedPoster))
  })

  // Rich detail for a single active download (the download-detail view). Resolves
  // the matched movie/series by queue downloadId==hash, or by the same parsed-name
  // catalog lookup the enriched list uses for unknown items. Key-safe: any poster
  // is a public remoteUrl or the /api/servarr/image proxy — the key never reaches
  // the client. Graceful: an unresolved item still returns the parsed release name.
  app.get('/api/servarr/downloads/:hash/detail', requireAuth, async (req, res) => {
    if (!ensureConfigured('qbittorrent', res)) return
    const hash = String(req.params.hash || '').trim().toLowerCase()
    if (!/^[a-f0-9]{6,64}$/.test(hash)) return res.status(400).json({ error: 'invalid hash' })

    let torrent
    try {
      const data = await qbit.torrentsInfo()
      torrent = (Array.isArray(data) ? data : []).map(shapeTorrent)
        .find((t) => String(t.hash || '').toLowerCase() === hash)
    } catch (err) { return fail(res, 'downloads/detail', err) }
    if (!torrent) return res.status(404).json({ error: 'download not found' })

    let ctx = { radarr: [], sonarr: [] }
    try { ctx = await getQueueCtx() } catch { /* best-effort → detail resolves via lookup */ }

    try {
      res.json(await resolveDownloadDetail(torrent, ctx))
    } catch (err) { return fail(res, 'downloads/detail', err) }
  })

  // Key-adding poster proxy for the rare *arr image that has only a local
  // /MediaCover path (no public remoteUrl). The api key is attached server-side
  // and NEVER reaches the browser; the path is constrained to /MediaCover/ (and
  // rejects "..") so this can't be turned into an open proxy / SSRF.
  app.get('/api/servarr/image', requireAuth, async (req, res) => {
    const service = (req.query.service || '').toString()
    const path = (req.query.path || '').toString()
    if (service !== 'radarr' && service !== 'sonarr') return res.status(400).json({ error: 'invalid service' })
    if (!path.startsWith('/MediaCover/') || path.includes('..')) return res.status(400).json({ error: 'invalid path' })
    if (!ensureConfigured(service, res)) return
    try {
      const { buffer, contentType } = await arrImageFetch(service, path)
      res.set('Content-Type', contentType)
      res.set('Cache-Control', 'private, max-age=86400')
      res.send(buffer)
    } catch (err) { fail(res, `${service}/image`, err) }
  })

  app.post('/api/servarr/qbittorrent/pause', requireAuth, async (req, res) => {
    if (!ensureConfigured('qbittorrent', res)) return
    const hashes = (req.body?.hashes || '').toString().trim()
    if (!hashes) return res.status(400).json({ error: 'hashes required' })
    try {
      await qbit.pause(hashes)
      res.json({ ok: true })
    } catch (err) { fail(res, 'qbittorrent/pause', err) }
  })

  app.post('/api/servarr/qbittorrent/resume', requireAuth, async (req, res) => {
    if (!ensureConfigured('qbittorrent', res)) return
    const hashes = (req.body?.hashes || '').toString().trim()
    if (!hashes) return res.status(400).json({ error: 'hashes required' })
    try {
      await qbit.resume(hashes)
      res.json({ ok: true })
    } catch (err) { fail(res, 'qbittorrent/resume', err) }
  })

  app.post('/api/servarr/qbittorrent/delete', requireAuth, async (req, res) => {
    if (!ensureConfigured('qbittorrent', res)) return
    const hashes = (req.body?.hashes || '').toString().trim()
    if (!hashes) return res.status(400).json({ error: 'hashes required' })
    try {
      await qbit.remove(hashes, !!req.body?.deleteFiles)
      // Keep the *arr queues consistent with the client (skip the "all" wildcard
      // — reconciling every queue on a bulk wipe isn't a targeted match).
      if (hashes !== 'all') await reconcileArrQueues(hashes)
      res.json({ ok: true })
    } catch (err) { fail(res, 'qbittorrent/delete', err) }
  })
}
