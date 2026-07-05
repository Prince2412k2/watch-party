// Shared client for the *arr v3-style REST APIs (Radarr/Sonarr/Prowlarr/Bazarr).
// They all authenticate with an `X-Api-Key` header and return JSON, so a single
// fetch helper (mirroring jellyfin.js's jfetch) covers every call. Every request
// is bounded by an AbortController timeout so a dead service can't hang a route.

import { serviceConfig } from './config.js'

const DEFAULT_TIMEOUT_MS = 8000

// Raised by callers when the service has no env config, so routes can map it to
// a clean 503 without leaking that a key was missing.
export class NotConfiguredError extends Error {
  constructor(service) {
    super(`${service} not configured`)
    this.name = 'NotConfiguredError'
    this.service = service
    this.notConfigured = true
  }
}

// Core fetch wrapper. `service` selects the base URL + key from env. Throws an
// Error with { status, body } on non-2xx (matching the jellyfin.js pattern), or
// a synthetic 504 on timeout / network failure. The api key never appears in
// any thrown message.
export async function arrFetch(service, path, { method = 'GET', body, query, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  const cfg = serviceConfig(service)
  if (!cfg.configured) throw new NotConfiguredError(service)

  let url = `${cfg.baseUrl.replace(/\/$/, '')}${path}`
  if (query) {
    const qs = new URLSearchParams()
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined && v !== null && v !== '') qs.set(k, String(v))
    }
    const s = qs.toString()
    if (s) url += (url.includes('?') ? '&' : '?') + s
  }

  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), timeoutMs)
  let res
  try {
    res = await fetch(url, {
      method,
      headers: {
        'X-Api-Key': cfg.apiKey,
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    })
  } catch (err) {
    clearTimeout(timer)
    const msg = err.name === 'AbortError' ? `${service} request timed out` : `${service} unreachable`
    throw Object.assign(new Error(msg), { status: 504, upstream: true })
  }
  clearTimeout(timer)

  if (!res.ok) {
    const text = await res.text().catch(() => '')
    throw Object.assign(new Error(`${service} ${method} ${path} → ${res.status}`), {
      status: res.status, body: text, upstream: true,
    })
  }
  const ct = res.headers.get('content-type') || ''
  return ct.includes('application/json') ? res.json() : res.text()
}

// Fetch a raw image (binary) from a local /MediaCover path with the api key added
// server-side — used by the poster proxy for *arr images that have no public
// remoteUrl. Returns { buffer, contentType }; throws like arrFetch on failure so
// the route maps it to a clean status. The key never appears in the response.
export async function arrImageFetch(service, path, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const cfg = serviceConfig(service)
  if (!cfg.configured) throw new NotConfiguredError(service)
  const url = `${cfg.baseUrl.replace(/\/$/, '')}${path}`
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), timeoutMs)
  let res
  try {
    res = await fetch(url, { headers: { 'X-Api-Key': cfg.apiKey }, signal: ctrl.signal })
  } catch (err) {
    clearTimeout(timer)
    const msg = err.name === 'AbortError' ? `${service} image timed out` : `${service} unreachable`
    throw Object.assign(new Error(msg), { status: 504, upstream: true })
  }
  clearTimeout(timer)
  if (!res.ok) {
    throw Object.assign(new Error(`${service} image ${path} → ${res.status}`), { status: res.status, upstream: true })
  }
  const buffer = Buffer.from(await res.arrayBuffer())
  return { buffer, contentType: res.headers.get('content-type') || 'image/jpeg' }
}

// ── Health ping ─────────────────────────────────────────────────────────────
// Radarr/Sonarr/Bazarr expose /api/v3/system/status; Prowlarr is v1. Returns
// { reachable, version? } and never throws (the health route must never fail).
const STATUS_PATH = {
  radarr: '/api/v3/system/status',
  sonarr: '/api/v3/system/status',
  bazarr: '/api/v3/system/status',
  prowlarr: '/api/v1/system/status',
}

export async function arrPing(service, timeoutMs = 4000) {
  try {
    const data = await arrFetch(service, STATUS_PATH[service], { timeoutMs })
    return { reachable: true, version: data?.version }
  } catch {
    return { reachable: false }
  }
}

// ── Radarr (movies, /api/v3) ──────────────────────────────────────────────────

// A live interactive release search can be genuinely slow — Radarr queries every
// indexer in real time — so it needs a far longer ceiling than a normal API
// call. The grab hand-off is quicker but still talks to the download client,
// so give it some room too.
const RELEASE_SEARCH_TIMEOUT_MS = 45000
const GRAB_TIMEOUT_MS = 30000

export const radarr = {
  lookup: (term) => arrFetch('radarr', '/api/v3/movie/lookup', { query: { term } }),
  library: () => arrFetch('radarr', '/api/v3/movie'),
  // Re-fetch a single movie by id — used by the interactive picker's cancel path
  // to double-check `hasFile` before removing a browsing-only entry, so a movie
  // that actually downloaded/imported is never deleted.
  get: (id) => arrFetch('radarr', `/api/v3/movie/${id}`),
  qualityProfiles: () => arrFetch('radarr', '/api/v3/qualityprofile'),
  rootFolders: () => arrFetch('radarr', '/api/v3/rootfolder'),
  add: (payload) => arrFetch('radarr', '/api/v3/movie', { method: 'POST', body: payload }),
  // Live interactive release search for an already-added movie. This is the same
  // endpoint the Radarr UI's "interactive search" uses: it queries indexers now
  // and returns a definitive list, each release carrying guid / indexerId /
  // seeders and Radarr's own `rejected` + `rejections` (year/quality/seed/etc.).
  releaseSearch: (movieId, timeoutMs = RELEASE_SEARCH_TIMEOUT_MS) =>
    arrFetch('radarr', '/api/v3/release', { query: { movieId }, timeoutMs }),
  // Discover feed aggregated from the admin's configured import lists (e.g. a
  // "TMDb Popular" or "Trakt Trending" list). This is the genuine popularity
  // source when one is set up — the /popular route prefers it and degrades to a
  // curated seed otherwise. Empty array when no list is configured. Given a list
  // may query TMDb/Trakt live, allow a longer ceiling than a plain API call.
  discover: (timeoutMs = 15000) => arrFetch('radarr', '/api/v3/importlist/movie', { timeoutMs }),
  // Hand a chosen release to the download client. guid+indexerId reference the
  // release Radarr just cached from releaseSearch above.
  grabRelease: ({ guid, indexerId }, timeoutMs = GRAB_TIMEOUT_MS) =>
    arrFetch('radarr', '/api/v3/release', { method: 'POST', body: { guid, indexerId }, timeoutMs }),
  // Remove a movie from Radarr. In the grab-or-remove flow this is only ever
  // called after a search SUCCEEDED but found nothing usable: deleteFiles=false
  // (nothing was downloaded) and addImportExclusion=false (so the user can
  // request the same title again later).
  remove: (id, { deleteFiles = false, addImportExclusion = false } = {}) =>
    arrFetch('radarr', `/api/v3/movie/${id}`, { method: 'DELETE', query: { deleteFiles, addImportExclusion } }),
  // The queue is where a grab lives between "found a release" and "imported into
  // the library" — this is where dead links, rejected downloads, and failed
  // imports actually surface (they may never reach the download client at all).
  // includeMovie embeds the matched `movie` object (title/year/images) so the
  // download list can be enriched without a second lookup per record.
  queue: () => arrFetch('radarr', '/api/v3/queue', { query: { includeUnknownMovieItems: true, includeMovie: true, pageSize: 50 } }),
  removeQueueItem: (id, { removeFromClient = true, blocklist = false } = {}) =>
    arrFetch('radarr', `/api/v3/queue/${id}`, { method: 'DELETE', query: { removeFromClient, blocklist } }),
}

// From a release-search result, pick the best *acceptable* release to grab, or
// null if none are acceptable. "Acceptable" is Radarr's/Sonarr's own `rejected`
// flag being false — their rejection logic already encodes year mismatch,
// quality-profile, minimum-seeders and every other rule, so we trust it as the
// source of truth rather than hand-rolling a heuristic. Among the acceptable
// releases we then prefer the most seeders: the diagnosed failure mode was
// releases that were technically present but had 0 seeders and would never
// finish. Ties (and usenet releases with no seeder count) keep Radarr's original
// ordering, which already reflects its quality scoring.
export function pickBestRelease(releases) {
  const acceptable = (Array.isArray(releases) ? releases : []).filter((r) => r && !r.rejected)
  if (acceptable.length === 0) return null
  return acceptable
    .map((r, i) => ({ r, i }))
    .sort((a, b) => ((b.r.seeders ?? 0) - (a.r.seeders ?? 0)) || (a.i - b.i))[0].r
}

// Build a Radarr add-movie payload from a lookup result + chosen profile/folder,
// monitoring it and kicking off a search immediately.
export function radarrAddPayload(lookupItem, { qualityProfileId, rootFolderPath, monitor = true, searchNow = true }) {
  return {
    title: lookupItem.title,
    tmdbId: lookupItem.tmdbId,
    year: lookupItem.year,
    titleSlug: lookupItem.titleSlug,
    images: lookupItem.images ?? [],
    qualityProfileId,
    rootFolderPath,
    monitored: monitor,
    minimumAvailability: 'released',
    addOptions: { searchForMovie: searchNow, monitor: monitor ? 'movieOnly' : 'none' },
  }
}

// ── Sonarr (series, /api/v3) ──────────────────────────────────────────────────

export const sonarr = {
  lookup: (term) => arrFetch('sonarr', '/api/v3/series/lookup', { query: { term } }),
  library: () => arrFetch('sonarr', '/api/v3/series'),
  // Re-fetch a single series by id — the season-request flow GETs the full object,
  // flips only the chosen seasons' `monitored` flag, and PUTs it straight back
  // (Sonarr's PUT replaces the whole record, so we must round-trip the full object).
  get: (id) => arrFetch('sonarr', `/api/v3/series/${id}`),
  qualityProfiles: () => arrFetch('sonarr', '/api/v3/qualityprofile'),
  languageProfiles: () => arrFetch('sonarr', '/api/v3/languageprofile'),
  rootFolders: () => arrFetch('sonarr', '/api/v3/rootfolder'),
  add: (payload) => arrFetch('sonarr', '/api/v3/series', { method: 'POST', body: payload }),
  // Replace a series record — used only to change season monitoring. Pass the full
  // object fetched via get() with the chosen seasons' `monitored` toggled.
  update: (id, payload) => arrFetch('sonarr', `/api/v3/series/${id}`, { method: 'PUT', body: payload }),
  // Fire a Sonarr command (e.g. SeasonSearch). The command is queued and runs in
  // the background, so this returns quickly with the started command record — a
  // normal API timeout is plenty (unlike Radarr's blocking interactive search).
  command: (body) => arrFetch('sonarr', '/api/v3/command', { method: 'POST', body }),
  // includeSeries/includeEpisode embed the matched `series` (title/images) and
  // `episode` (season/episode) so the download list can show a clean title +
  // "Season 1"/"S1E3" label + poster without a per-record lookup.
  queue: () => arrFetch('sonarr', '/api/v3/queue', { query: { includeUnknownSeriesItems: true, includeSeries: true, includeEpisode: true, pageSize: 50 } }),
  removeQueueItem: (id, { removeFromClient = true, blocklist = false } = {}) =>
    arrFetch('sonarr', `/api/v3/queue/${id}`, { method: 'DELETE', query: { removeFromClient, blocklist } }),
}

export function sonarrAddPayload(lookupItem, { qualityProfileId, languageProfileId, rootFolderPath, monitor = true, searchNow = true }) {
  const payload = {
    title: lookupItem.title,
    tvdbId: lookupItem.tvdbId,
    year: lookupItem.year,
    titleSlug: lookupItem.titleSlug,
    images: lookupItem.images ?? [],
    // Normalize to the two fields Sonarr's Season model cares about — the client
    // shape now also carries episode counts (see shapeSeriesLookup), which we
    // must not forward. An empty array is fine: Sonarr fills seasons from the
    // TVDB metadata, and addOptions.monitor then applies the monitoring policy.
    // The per-season `monitored` flags MUST agree with addOptions.monitor: when
    // we add with monitor:'none' (the season-request shell add relies on this to
    // leave EVERY season unmonitored, then flips only the chosen ones), a
    // `monitored:true` echoed back by the lookup would override the policy and
    // monitor the whole series. So force every season unmonitored unless we're
    // adding the series monitored.
    seasons: Array.isArray(lookupItem.seasons)
      ? lookupItem.seasons.map((s) => ({ seasonNumber: s.seasonNumber, monitored: monitor ? !!s.monitored : false }))
      : [],
    qualityProfileId,
    rootFolderPath,
    monitored: monitor,
    seasonFolder: true,
    addOptions: { searchForMissingEpisodes: searchNow, monitor: monitor ? 'all' : 'none' },
  }
  // languageProfileId only exists on older Sonarr (v3); newer versions dropped it.
  if (languageProfileId !== undefined && languageProfileId !== null) {
    payload.languageProfileId = languageProfileId
  }
  return payload
}

// ── Prowlarr (indexers, /api/v1) ──────────────────────────────────────────────

export const prowlarr = {
  indexers: () => arrFetch('prowlarr', '/api/v1/indexer'),
  indexerStatus: () => arrFetch('prowlarr', '/api/v1/indexerstatus'),
  search: (query, opts = {}) => arrFetch('prowlarr', '/api/v1/search', { query: { query, ...opts } }),
}

// ── Bazarr (subtitles, /api/v3) ───────────────────────────────────────────────
// Kept minimal — just the "wanted" queues the later UI surfaces.

export const bazarr = {
  wantedMovies: () => arrFetch('bazarr', '/api/v3/movies/wanted'),
  wantedSeries: () => arrFetch('bazarr', '/api/v3/episodes/wanted'),
}

// ── Discover / "popular" rail — curated fallback ──────────────────────────────
// No external popularity API (no TMDb key) is configured, and the *arr import
// lists that WOULD provide a live trending feed are empty in this deployment, so
// the discover rail falls back to a curated seed of broadly well-known titles.
// Each seed is resolved through the SAME catalog lookup that powers search, so
// every card is a real, fully-populated, requestable result (poster, overview,
// ratings, ids) — we surface real metadata, we don't fabricate popularity, and
// the /popular route labels this as "picks" rather than live trending.
export const CURATED_MOVIES = [
  'Inception', 'The Dark Knight', 'Interstellar', 'Parasite', 'Dune',
  'Oppenheimer', 'The Matrix', 'Everything Everywhere All at Once',
  'Spider-Man: Into the Spider-Verse', 'Mad Max: Fury Road', 'The Godfather',
  'Gladiator', 'Whiplash', 'Blade Runner 2049',
]
export const CURATED_SERIES = [
  'Breaking Bad', 'Game of Thrones', 'The Last of Us', 'Stranger Things',
  'The Wire', 'Chernobyl', 'The Bear', 'Succession', 'Better Call Saul',
  'The Boys', 'Severance', 'Arcane', 'Fargo', 'Peaky Blinders',
]

// Resolve a curated title list into lookup results: run every title through the
// given lookup fn (radarr.lookup / sonarr.lookup) in parallel, keep the top hit
// for each, dedup by the id key (tmdbId / tvdbId), and drop misses. A single
// title's lookup failing just drops that title — never the whole rail.
export async function curatedPopular(lookupFn, titles, idKey) {
  const results = await Promise.all(
    titles.map((t) => lookupFn(t).then((arr) => (Array.isArray(arr) && arr[0]) || null).catch(() => null)),
  )
  const seen = new Set()
  const out = []
  for (const r of results) {
    const id = r?.[idKey]
    if (!r || id == null || seen.has(id)) continue
    seen.add(id)
    out.push(r)
  }
  return out
}

// ── Downloads enrichment: join qBittorrent torrents ↔ *arr queue records ──────
// The user sees qBittorrent's raw torrent list, whose names are scene releases
// ("Fleabag.S01.1080p.BluRay.x264-SHORTBREHD"). Every torrent Radarr/Sonarr
// grabbed has a queue record whose `downloadId` equals the torrent HASH
// (case-insensitive) and — with includeMovie / includeSeries+includeEpisode —
// carries the clean movie/series title, poster images and season/episode. Joining
// them lets the UI show a human title + poster. A torrent with NO matching queue
// record (a manual add) falls back to matched:false and keeps its raw name.

// The proxy route that key-adds local /MediaCover images (see index.js).
const IMAGE_PROXY_BASE = '/api/servarr/image'

// Turn an *arr image object into a browser-loadable URL WITHOUT exposing the api
// key: prefer the public remoteUrl (TMDb/TVDB https the browser loads directly);
// if only a local /MediaCover/... path exists, route it through the key-adding
// image proxy. Anything else → null (client shows a placeholder).
export function posterUrlFromImage(service, image) {
  if (!image) return null
  if (typeof image.remoteUrl === 'string' && /^https?:\/\//i.test(image.remoteUrl)) return image.remoteUrl
  const local = image.url
  if (typeof local === 'string' && local.startsWith('/MediaCover/')) {
    return `${IMAGE_PROXY_BASE}?service=${encodeURIComponent(service)}&path=${encodeURIComponent(local)}`
  }
  return null
}

// Pick the best cover from an *arr images[] array — poster first, fanart as a
// last resort.
export function pickPosterImage(images) {
  const arr = Array.isArray(images) ? images : []
  return arr.find((i) => i && i.coverType === 'poster') || arr.find((i) => i && i.coverType === 'fanart') || null
}

// Normalize the varied *arr ratings shapes into a single 0–10 number (rounded to
// one decimal), or null. Sonarr returns { votes, value }; Radarr returns a nested
// map { imdb:{value}, tmdb:{value}, ... } with no top-level value. Mirror the
// client's ratingOf precedence so the download detail reads the same as Browse.
export function arrRating(ratings) {
  if (!ratings || typeof ratings !== 'object') return null
  const v = (typeof ratings.value === 'number' ? ratings.value : null)
    ?? ratings.imdb?.value ?? ratings.tmdb?.value ?? null
  return typeof v === 'number' && v > 0 ? Math.round(v * 10) / 10 : null
}

// Human "S1E3" / "Season 1" label from a Sonarr queue record's episode data.
// includeEpisode populates `episode` for a single grab; a season pack has no
// single episode but carries seasonNumber (and/or an episodes[] list). Returns
// null when there's no episode/season info (e.g. still fetching metadata).
export function seasonEpisodeLabel(record) {
  const eps = Array.isArray(record?.episodes) ? record.episodes : []
  const single = record?.episode || (eps.length === 1 ? eps[0] : null)
  if (single && single.seasonNumber != null && single.episodeNumber != null) {
    return `S${single.seasonNumber}E${single.episodeNumber}`
  }
  const season = record?.seasonNumber ?? single?.seasonNumber ?? (eps.length ? eps[0]?.seasonNumber : null)
  if (eps.length > 1 && season != null) return `Season ${season}`
  if (eps.length > 1) return `${eps.length} episodes`
  if (season != null) return `Season ${season}`
  return null
}

// Parse a scene release name into a human title + optional season/episode/year.
// Best-effort — used ONLY to improve on the raw torrent name when the queue record
// has no clean movie/series object (an "unknown" item still resolving, or a manual
// grab). Cuts the title at the first structural token (SxxExx, a season SNN, a
// 19xx/20xx year, or a quality/source tag) and tidies the separators.
export function parseReleaseName(name) {
  const raw = (name || '').toString().trim()
  if (!raw) return { title: '', season: null, episode: null, year: null }
  // Drop a trailing bracket/paren group, e.g. " [S01 One Complete]" / " (2016)".
  const s = raw.replace(/\s*[[(][^\])]*[\])]\s*$/g, '').trim()

  const se = s.match(/\bS(\d{1,2})E(\d{1,3})\b/i)          // S01E02
  const seasonOnly = s.match(/\bS(\d{1,2})\b(?!\s*E\d)/i)  // S01 (season pack)
  const year = s.match(/\b(19\d{2}|20\d{2})\b/)
  const qual = s.match(/\b(2160p|1080p|720p|480p|4k|bluray|blu-ray|web-?dl|web-?rip|hdtv|dvdrip|x264|x265|h\.?264|h\.?265|hevc|remux|amzn|dsnp)\b/i)

  const cuts = []
  if (se) cuts.push(se.index)
  else if (seasonOnly) cuts.push(seasonOnly.index)
  if (year) cuts.push(year.index)
  if (qual) cuts.push(qual.index)
  const cut = cuts.length ? Math.min(...cuts) : s.length

  let title = s.slice(0, cut).replace(/[._]+/g, ' ').replace(/\s+/g, ' ').trim()
  title = title.replace(/[-–—\s]+$/, '').trim()

  return {
    title: title || raw,
    season: se ? Number(se[1]) : (seasonOnly ? Number(seasonOnly[1]) : null),
    episode: se ? Number(se[2]) : null,
    year: year ? Number(year[1]) : null,
  }
}

// Build a downloadId→record index (lowercased key) from a queue record list.
function indexByDownloadId(records) {
  const m = new Map()
  for (const r of (Array.isArray(records) ? records : [])) {
    if (r && r.downloadId) m.set(String(r.downloadId).toLowerCase(), r)
  }
  return m
}

// Resolve the enrichment fields for a single torrent from the queue indexes.
// `lookupPoster(service, title)` is injected (see index.js) to resolve a poster
// for "unknown" items via a cached lookup — kept out of this pure join.
function enrichOne(torrent, radarrById, sonarrById, lookupPoster) {
  const key = String(torrent.hash || '').toLowerCase()

  const mrec = key && radarrById.get(key)
  if (mrec) {
    const movie = mrec.movie
    if (movie && movie.title) {
      return {
        matched: true, kind: 'movie',
        displayTitle: movie.title,
        subtitle: movie.year ? String(movie.year) : null,
        posterUrl: posterUrlFromImage('radarr', pickPosterImage(movie.images)),
      }
    }
    const p = parseReleaseName(mrec.title || torrent.name)
    return {
      matched: true, kind: 'movie',
      displayTitle: p.title || torrent.name,
      subtitle: p.year ? String(p.year) : null,
      posterUrl: lookupPoster('radarr', p.title),
    }
  }

  const srec = key && sonarrById.get(key)
  if (srec) {
    const series = srec.series
    const label = seasonEpisodeLabel(srec)
    if (series && series.title) {
      return {
        matched: true, kind: 'series',
        displayTitle: series.title,
        subtitle: label,
        posterUrl: posterUrlFromImage('sonarr', pickPosterImage(series.images)),
      }
    }
    const p = parseReleaseName(srec.title || torrent.name)
    const sub = label
      || (p.episode != null ? `S${p.season}E${p.episode}` : (p.season != null ? `Season ${p.season}` : null))
    return {
      matched: true, kind: 'series',
      displayTitle: p.title || torrent.name,
      subtitle: sub,
      posterUrl: lookupPoster('sonarr', p.title),
    }
  }

  // No queue record — a manually-added / untracked torrent. Keep the raw name
  // (displayTitle:null → client falls back to torrent.name); category is a weak
  // hint at movie vs series for the placeholder icon.
  const cat = (torrent.category || '').toLowerCase()
  const kind = cat.includes('radarr') || cat.includes('movie') ? 'movie'
    : cat.includes('sonarr') || cat.includes('tv') ? 'series' : null
  return { matched: false, kind, displayTitle: null, subtitle: null, posterUrl: null }
}

// Join a (shaped) torrent list to Radarr/Sonarr queue records on hash==downloadId,
// merging { matched, kind, displayTitle, subtitle, posterUrl } onto each torrent.
export function enrichTorrents(torrents, { radarr = [], sonarr = [] } = {}, lookupPoster = () => null) {
  const rById = indexByDownloadId(radarr)
  const sById = indexByDownloadId(sonarr)
  return (Array.isArray(torrents) ? torrents : [])
    .map((t) => ({ ...t, ...enrichOne(t, rById, sById, lookupPoster) }))
}
