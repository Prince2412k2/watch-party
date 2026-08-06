// Discover's query: what is in the URL, when a search fires, and what the stage
// says when there is nothing to show.
//
// The URL is the real state here. `/discover?q=dune&type=movie` has to survive a
// refresh, a share and the back button, and this app has a twenty-line history
// router rather than react-router — so the read and the write are both plain
// URLSearchParams work, and both are exactly the kind of thing that silently
// stops round-tripping. Hence: pure functions, tested.

import type { Kind, Service } from './catalog.ts'
import type { ServiceHealth } from '../../hooks/downloadsCore.ts'

/**
 * Long enough that typing a title does not fire a request per keystroke, short
 * enough that the results feel like they are following you. Paired with an
 * AbortController in the caller: the timer stops the request being *made*, the
 * controller stops an in-flight one from landing after a newer query.
 */
export const SEARCH_DEBOUNCE_MS = 400

export const DISCOVER_PATH = '/discover'

export interface DiscoverParams {
  kind: Kind
  term: string
}

/**
 * Read `?q=` and `?type=` off a search string.
 *
 * Anything that is not exactly `series` is a movie: a malformed or hand-edited
 * `type` must land on a working surface rather than an empty one.
 */
export function readDiscoverParams(search: string): DiscoverParams {
  const params = new URLSearchParams(search)
  return {
    kind: params.get('type') === 'series' ? 'series' : 'movie',
    term: params.get('q') || '',
  }
}

/**
 * The URL these params should produce, preserving any other query the page was
 * opened with.
 *
 * Returns null when nothing would change — the caller uses `replaceState`, and
 * replacing the entry with an identical one on every keystroke is both pointless
 * and enough to break scroll restoration in some browsers.
 */
export function nextDiscoverUrl(
  pathname: string,
  search: string,
  params: DiscoverParams,
): string | null {
  // Never rewrite another page's URL: this runs from an effect, and an effect
  // can fire one tick after a navigation away.
  if (pathname !== DISCOVER_PATH) return null

  const query = new URLSearchParams(search)
  query.set('type', params.kind)
  const term = params.term.trim()
  if (term) query.set('q', term)
  else query.delete('q')

  const rendered = query.toString()
  const next = `${pathname}${rendered ? `?${rendered}` : ''}`
  return next === `${pathname}${search}` ? null : next
}

export type SearchAction =
  /** A term worth sending. */
  | { action: 'search'; query: string }
  /** Nothing typed — show the discover feed instead, and cancel anything running. */
  | { action: 'clear' }

/**
 * Whether a term is a search.
 *
 * Whitespace is not: a trailing space while typing must not clear the results
 * that are already on screen, and a term of nothing but spaces must not send
 * `?term=%20%20` to the catalog.
 */
export function searchPlan(term: string): SearchAction {
  const query = term.trim()
  return query ? { action: 'search', query } : { action: 'clear' }
}

export const searchPath = (service: Service, query: string): string =>
  `/api/servarr/${service}/search?term=${encodeURIComponent(query)}`

export const discoverPath = (service: Service): string => `/api/servarr/${service}/discover?page=1`

// ── the dead ends ───────────────────────────────────────────────────────────

/**
 * A few real titles, so a Discover that cannot reach its feed is still a place
 * you can start rather than an empty box with a cursor in it.
 */
export const SUGGESTED_SEARCHES: Record<Kind, readonly string[]> = {
  movie: ['Inception', 'Dune', 'Parasite', 'Oppenheimer', 'The Matrix'],
  series: ['Breaking Bad', 'The Last of Us', 'Severance', 'Chernobyl', 'Arcane'],
}

/**
 * Why the feed is empty, in the user's terms.
 *
 * A missing TMDB key, an unreachable upstream and a lookup that matched nothing
 * are three different problems with three different answers, and collapsing them
 * into "nothing here" is what made the old row unactionable.
 */
export function discoverEmptyReason(status: number, service: Service): string {
  if (status === 503) {
    return `Discover needs ${service === 'radarr' ? 'Radarr' : 'Sonarr'} and a TMDB API key configured on the server.`
  }
  if (status === 502 || status === 504) return 'Discover could not reach the catalog. Try again in a moment.'
  if (status === 200) return 'The catalog returned trending titles, but none of them could be matched.'
  return 'Discover is unavailable right now.'
}

export interface UnavailableCopy {
  title: string
  body: string
  /** True when the service is set up but currently unreachable — it comes back. */
  transient: boolean
}

/**
 * "Not set up" and "set up but unreachable" read differently on purpose: one is
 * an admin's job and the other fixes itself, and telling someone to go configure
 * something that is already configured is worse than saying nothing.
 *
 * Neither names the underlying service — a member does not have a Radarr.
 */
export function unavailableCopy(kind: Kind, state?: ServiceHealth): UnavailableCopy {
  const transient = Boolean(state?.configured && !state?.reachable)
  if (transient) {
    return {
      transient,
      title: 'Discover is temporarily unavailable',
      body: `Discover is having trouble reaching the catalog right now. ${
        kind === 'movie' ? 'Movie' : 'Show'
      } search and downloads will come back on their own.`,
    }
  }
  return {
    transient,
    title: 'Discover isn’t set up yet',
    body: `Once Discover is configured, you can search ${
      kind === 'movie' ? 'movies' : 'series'
    } and add them to your library with a single tap.`,
  }
}

/** The heading over the rail, and the empty state under it. */
export interface RailCopy {
  label: string
  emptyTitle: string
  emptyHint: string
}

export function railCopy(input: {
  kind: Kind
  query: string
  searching: boolean
  searched: boolean
  resultCount: number
  feedLabel: string
  feedReason: string | null
}): RailCopy {
  const noun = input.kind === 'movie' ? 'movies' : 'series'

  if (input.query) {
    return {
      label: input.searching
        ? `Searching “${input.query}”`
        : `${input.resultCount} ${input.resultCount === 1 ? 'result' : 'results'} for “${input.query}”`,
      emptyTitle: input.searched ? `No ${noun} matched “${input.query}”` : 'Searching…',
      emptyHint: input.searched
        ? 'Check the spelling, or try one of the suggestions above.'
        : 'Looking through the catalog.',
    }
  }

  return {
    label: input.feedLabel,
    emptyTitle: 'Nothing to show yet',
    emptyHint: input.feedReason ?? `Search ${noun} by title to add something to your library.`,
  }
}
