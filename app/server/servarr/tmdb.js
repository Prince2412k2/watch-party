import { tmdbConfig } from './config.js'
import { NotConfiguredError } from './arr.js'

const TMDB_ORIGIN = 'https://api.themoviedb.org'
const TIMEOUT_MS = 8000

export async function tmdbDiscover(kind, page) {
  const { apiKey, configured } = tmdbConfig()
  if (!configured) throw new NotConfiguredError('tmdb')

  const mediaType = kind === 'movie' ? 'movie' : 'tv'
  const url = new URL(`/3/trending/${mediaType}/week`, TMDB_ORIGIN)
  url.searchParams.set('api_key', apiKey)
  url.searchParams.set('page', String(page))

  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS)
  try {
    const response = await fetch(url, { signal: ctrl.signal })
    if (!response.ok) {
      throw Object.assign(new Error(`tmdb discover -> ${response.status}`), {
        status: response.status,
        upstream: true,
      })
    }
    return response.json()
  } catch (err) {
    if (err?.upstream) throw err
    const message = err.name === 'AbortError' ? 'tmdb request timed out' : 'tmdb unreachable'
    throw Object.assign(new Error(message), { status: 504, upstream: true })
  } finally {
    clearTimeout(timer)
  }
}
