import { tmdbConfig } from './config.js'
import { NotConfiguredError } from './arr.js'

const TMDB_ORIGIN = 'https://api.themoviedb.org'
// Public image CDN — no key, no auth, so the client loads these directly. Sized
// once here rather than letting every caller invent its own width.
const TMDB_IMAGE_ORIGIN = 'https://image.tmdb.org/t/p'
const image = (path, size) => (path ? `${TMDB_IMAGE_ORIGIN}/${size}${path}` : null)
const TIMEOUT_MS = 8000

export async function tmdbDiscover(kind, page) {
  const mediaType = kind === 'movie' ? 'movie' : 'tv'
  return tmdbGet(`/3/trending/${mediaType}/week`, { page })
}

// ── Episodes ─────────────────────────────────────────────────────────────────
// Sonarr's series lookup returns SEASONS only — no episode names, overviews,
// stills or air dates — and Sonarr can only list episodes for a series that has
// already been added. TMDB supplies all of it for a series we are merely
// browsing, so the show stage can render its episode row without writing
// anything to the library.

async function tmdbGet(path, params = {}) {
  const { apiKey, configured } = tmdbConfig()
  if (!configured) throw new NotConfiguredError('tmdb')

  const url = new URL(path, TMDB_ORIGIN)
  url.searchParams.set('api_key', apiKey)
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v))
  }

  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS)
  try {
    const response = await fetch(url, { signal: ctrl.signal })
    if (!response.ok) {
      throw Object.assign(new Error(`tmdb ${path} -> ${response.status}`), {
        status: response.status,
        upstream: true,
      })
    }
    return response.json()
  } catch (err) {
    if (err?.upstream || err?.notConfigured) throw err
    const message = err.name === 'AbortError' ? 'tmdb request timed out' : 'tmdb unreachable'
    throw Object.assign(new Error(message), { status: 504, upstream: true })
  } finally {
    clearTimeout(timer)
  }
}

// Resolve a TMDB series id from a TVDB id, which is the identifier Sonarr's
// lookup always carries (its tmdbId is often absent). Returns null when TMDB
// knows nothing about it — callers degrade to season-level actions.
export async function tmdbSeriesIdFromTvdb(tvdbId) {
  const found = await tmdbGet(`/3/find/${encodeURIComponent(tvdbId)}`, {
    external_source: 'tvdb_id',
  })
  const first = Array.isArray(found?.tv_results) ? found.tv_results[0] : null
  return first?.id ?? null
}

export async function tmdbSeasonEpisodes(seriesId, seasonNumber) {
  const season = await tmdbGet(`/3/tv/${encodeURIComponent(seriesId)}/season/${encodeURIComponent(seasonNumber)}`)
  const episodes = Array.isArray(season?.episodes) ? season.episodes : []
  return {
    seasonNumber: season?.season_number ?? Number(seasonNumber),
    name: season?.name ?? null,
    overview: season?.overview || null,
    // The season's own art, so the stage backdrop can follow the season.
    poster: image(season?.poster_path, 'w780'),
    episodes: episodes.map((e) => ({
      episodeNumber: e.episode_number,
      name: e.name || null,
      overview: e.overview || null,
      still: image(e.still_path, 'w780'),
      airDate: e.air_date || null,
      runtime: e.runtime ?? null,
      rating: e.vote_average ?? null,
    })),
  }
}
