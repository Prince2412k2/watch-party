import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { CSSProperties, FormEvent, ReactNode, SelectHTMLAttributes } from 'react'
import { useAuth } from '../context/AuthContext'
import { useIsMobile } from '../hooks/useIsMobile'
import { useTorrents } from '../hooks/useTorrents'
import { useFailingCount } from '../hooks/useFailingDownloads'
import { useLibraryViews } from '../hooks/useLibraryViews'
import { C, SANS, MONO, glassStyle, Ic, Icon, Sidebar, TopBar, Notice, Spinner } from '../lib/ui'
import { fmtSize, fmtSpeed, fmtEta, fmtRuntimeFromMinutes, stateInfo, isPausedState } from '../lib/format'
import { jget, jpost, jdelete } from '../lib/api'
import { apiJson, arrayOf, isRecord } from '../types/guards'

type Kind = 'movie' | 'series'
type Service = 'radarr' | 'sonarr'
type AddState = 'searching' | 'grabbed' | 'monitoring' | 'no_release' | 'search_failed' | 'added' | 'error' | undefined
type Image = { coverType?: string; remoteUrl?: string; url?: string }
type Rating = { value?: number; imdb?: { value?: number }; tmdb?: { value?: number } }
type CatalogItem = {
  id?: number; tmdbId?: number; tvdbId?: number; titleSlug?: string; title: string; originalTitle?: string
  year?: number; network?: string; status?: string; overview?: string; images?: Image[]; ratings?: Rating
  runtime?: number; genres?: string[]; certification?: string; seasonCount?: number; seasons?: Season[]
  monitored?: boolean; qualityProfileId?: number; rootFolderPath?: string; languageProfileId?: number
}
const isCatalogItem = (value: unknown): value is CatalogItem => isRecord(value) && typeof value.title === 'string'
const isProfile = (value: unknown): value is Profile => isRecord(value) && typeof value.id === 'number'
const isRootFolder = (value: unknown): value is RootFolder => isRecord(value) && typeof value.path === 'string'
const parseHealth = (value: unknown): Health => {
  if (!isRecord(value) || !isRecord(value.services)) return { services: {} }
  const service = (raw: unknown): HealthService | undefined => isRecord(raw) ? {
    configured: typeof raw.configured === 'boolean' ? raw.configured : undefined,
    reachable: typeof raw.reachable === 'boolean' ? raw.reachable : undefined,
  } : undefined
  return { services: { radarr: service(value.services.radarr), sonarr: service(value.services.sonarr), qbittorrent: service(value.services.qbittorrent) } }
}
const outcomeOf = (value: unknown): string | undefined => isRecord(value) && typeof value.outcome === 'string' ? value.outcome : undefined
type Torrent = {
  hash?: string; name?: string; title?: string; state?: string; progress?: number; dlspeed?: number; eta?: number
  numSeeds?: number; numLeechs?: number
}
type Season = { seasonNumber: number; monitored?: boolean; totalEpisodeCount?: number; statistics?: { episodeCount?: number; totalEpisodeCount?: number; percentOfEpisodes?: number } }
type Profile = { id: number; name?: string }
type RootFolder = { id?: number; path: string; freeSpace?: number }
type Metadata = { profiles: Profile[]; rootFolders: RootFolder[]; langProfiles: Profile[] }
type HealthService = { configured?: boolean; reachable?: boolean }
type Health = { services?: { radarr?: HealthService; sonarr?: HealthService; qbittorrent?: HealthService } }
type RequestOutcome = { outcome?: string }
type PopularData = { source: string; items: CatalogItem[] }
type Release = {
  guid: string; title?: string; indexer?: string; size?: number; age?: number; ageHours?: number
  seeders?: number; leechers?: number; protocol?: string; quality?: string; indexerId?: number
  rejected?: boolean; rejections?: string[]; downloadAllowed?: boolean
}
type OptionsResult = { ok?: boolean; outcome?: string; warn?: string; error?: string }
type ReleaseData = { movieId: number; createdByPicker?: boolean; searchFailed?: boolean; releases?: Release[] }
const isRelease = (value: unknown): value is Release => isRecord(value) && typeof value.guid === 'string'
function parseReleaseData(value: unknown): ReleaseData {
  if (!isRecord(value) || typeof value.movieId !== 'number') return { movieId: 0, releases: [] }
  return {
    movieId: value.movieId,
    createdByPicker: typeof value.createdByPicker === 'boolean' ? value.createdByPicker : undefined,
    searchFailed: typeof value.searchFailed === 'boolean' ? value.searchFailed : undefined,
    releases: arrayOf(value.releases, isRelease),
  }
}

/* Pick the best remote poster URL out of a catalog lookup `images` array.
 * Lookup results (not-yet-added) only have full URLs in `remoteUrl`; the local
 * `url` points at the internal instance and 404s for unadded items — so prefer
 * remoteUrl, then url. coverType 'poster' first, falling back to any image. */
function posterUrl(images?: Image[]) {
  if (!Array.isArray(images) || images.length === 0) return null
  const poster = images.find((i) => i.coverType === 'poster') || images[0]
  return poster?.remoteUrl || poster?.url || null
}
// Prefer a wide fanart/backdrop for the detail hero; fall back to the poster.
function backdropUrl(images?: Image[]) {
  if (!Array.isArray(images) || images.length === 0) return null
  const fan = images.find((i) => i.coverType === 'fanart') || images.find((i) => i.coverType === 'banner')
  return fan?.remoteUrl || fan?.url || posterUrl(images)
}

/* Remote poster with graceful fallback. These are remote catalog art URLs (not
 * the Jellyfin `Img` proxy), so we render <img> directly and swap to a
 * placeholder on error — one attempt per URL, no retry storm. */
function Poster({ images, alt, style, useBackdrop }: { images?: Image[]; alt?: string; style?: CSSProperties; useBackdrop?: boolean } = {}) {
  const url = (useBackdrop ? backdropUrl(images) : posterUrl(images))
  const [broken, setBroken] = useState(false)
  if (!url || broken) {
    return (
      <div style={{ ...style, display: 'grid', placeItems: 'center', background: C.surface2 }}>
        <Icon path={Ic.film} size={34} stroke={C.faint} sw={1.4} />
      </div>
    )
  }
  return <img src={url} alt={alt || ''} referrerPolicy="no-referrer" onError={() => setBroken(true)}
    style={{ ...style, objectFit: 'cover' }} />
}

/* An item is "already in the library" when the lookup echoes back a numeric id
 * (the catalog only sets `id` for titles it already tracks). */
const isAdded = (r: CatalogItem) => r.id != null
const keyOf = (kind: Kind, r: CatalogItem) => (kind === 'movie' ? `m:${r.tmdbId}` : `s:${r.tvdbId}`)

/* Map a server request outcome → the per-item card state. The movie request flow
 * is now server-authoritative (grab-or-remove), so the server hands back exactly
 * what happened and the client no longer has to guess:
 *   grabbed       → it's downloading (the live torrent match takes over)
 *   no_release    → search succeeded, nothing usable, entry removed → requestable
 *   search_failed → couldn't check right now (transient) → offer a retry
 *   monitoring    → series only: added + Sonarr is searching/monitoring
 *   exists        → already in the library */
function outcomeToState(outcome?: string): AddState {
  switch (outcome) {
    case 'grabbed': return 'grabbed'
    case 'no_release': return 'no_release'
    case 'search_failed': return 'search_failed'
    case 'monitoring': return 'monitoring'
    case 'exists': return 'added'
    default: return 'error'
  }
}

/* Pull a single 0–10 rating out of the varied ratings shapes the catalog
 * returns (newer: {imdb:{value}, tmdb:{value}}, older: {value}). null if none. */
function ratingOf(r: CatalogItem) {
  const rt = r?.ratings
  if (!rt) return null
  const v = (typeof rt.value === 'number' ? rt.value : null)
    ?? rt.imdb?.value ?? rt.tmdb?.value ?? null
  return typeof v === 'number' && v > 0 ? v : null
}
/* Normalize a title / torrent name to compare them. Lowercase, strip anything
 * non-alphanumeric to spaces, collapse. Torrent names look like
 * "The.Matrix.1999.1080p..." so a normalized substring match is a good
 * best-effort link between an active download and the title that spawned it. */
const normTitle = (s?: string) => (s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
const isAbortError = (error: unknown) => typeof error === 'object' && error !== null && 'name' in error && error.name === 'AbortError'
/* Works for both qBittorrent torrents (`.name`) and *arr queue records
 * (`.title`) — both carry the release name, e.g. "The.Matrix.1999.1080p...". */
function matchTorrent(title: string, torrents?: Torrent[] | null) {
  const n = normTitle(title)
  if (!n || n.length < 2 || !Array.isArray(torrents)) return null
  return torrents.find((t) => normTitle(t.name || t.title).includes(n)) || null
}

/* Session-scoped cache of profiles + folders so the one-tap path is instant
 * after the first add. Keyed by service; a single in-flight promise is shared. */
const metaCache: Partial<Record<Service, Promise<Metadata>>> = {}
function loadMeta(service: Service): Promise<Metadata> {
  if (metaCache[service]) return metaCache[service]
  const reqs = [
    jget(`/api/servarr/${service}/quality-profiles`),
    jget(`/api/servarr/${service}/root-folders`),
  ]
  if (service === 'sonarr') reqs.push(jget('/api/servarr/sonarr/language-profiles'))
  const p = Promise.all(reqs).then(async (rs) => {
    for (const r of rs) if (!r.ok) throw new Error('meta')
    const [profiles, rootFolders, langProfiles] = await Promise.all(rs.map(apiJson))
    return { profiles: arrayOf(profiles, isProfile), rootFolders: arrayOf(rootFolders, isRootFolder), langProfiles: arrayOf(langProfiles, isProfile) }
  }).catch((e) => { delete metaCache[service]; throw e })   // don't cache a failure
  metaCache[service] = p
  return p
}

/* The Browse tab keeps its search query + active tab in the URL (?q= / ?type=)
 * so the page is deep-linkable and survives a refresh / back button. This app
 * uses a tiny custom history router (see router.js), not react-router, so we
 * read + write window.location search params directly instead of via
 * react-router's useSearchParams (which isn't installed). */
function readBrowseParams() {
  const p = new URLSearchParams(window.location.search)
  return {
    kind: (p.get('type') === 'series' ? 'series' : 'movie') as Kind,
    term: p.get('q') || '',
  }
}

/* Session-scoped cache of the discover ("popular") rail per service, so flipping
 * between search and the empty state — or toggling Movies/Series and back — is
 * instant and doesn't refetch. A single in-flight promise is shared. Empty
 * results (a transient lookup outage) aren't cached, so a later visit retries. */
const popularCache: Partial<Record<Service, Promise<PopularData>>> = {}
function loadPopular(service: Service): Promise<PopularData> {
  if (popularCache[service]) return popularCache[service]
  const p = jget(`/api/servarr/${service}/popular`)
    .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
    .then((d: unknown) => {
      const data = d as { source?: string; items?: CatalogItem[] } | null
      const val = { source: data?.source || 'curated', items: Array.isArray(data?.items) ? data.items : [] }
      if (!val.items.length) delete popularCache[service]   // don't pin a transient empty
      return val
    })
    .catch((e) => { delete popularCache[service]; throw e })
  popularCache[service] = p
  return p
}

export default function Browse() {
  const { user, logout } = useAuth()
  const mobile = useIsMobile()
  const sidebarW = mobile ? 62 : 236

  const [kind, setKind] = useState(() => readBrowseParams().kind)  // 'movie' | 'series'
  const [term, setTerm] = useState(() => readBrowseParams().term)
  const [results, setResults] = useState<CatalogItem[]>([])
  // Start in the loading state when we mount with a deep-linked query, so the
  // popular rail doesn't flash before the debounced search for it fires.
  const [loading, setLoading] = useState(() => !!readBrowseParams().term.trim())
  const [searchError, setSearchError] = useState('')
  const [hasSearched, setHasSearched] = useState(false)

  // Health drives the generic unconfigured state. null = still checking.
  const [health, setHealth] = useState<Health | null>(null)
  const [healthLoading, setHealthLoading] = useState(true)

  const [selected, setSelected] = useState<CatalogItem | null>(null)     // detail view item (or null)
  const [optionsItem, setOptionsItem] = useState<CatalogItem | null>(null) // "Options" dialog target
  const [pickerItem, setPickerItem] = useState<CatalogItem | null>(null)  // "Choose a release" picker target (movies)

  // Per-item request state so cards/detail flip without a re-search. Keyed by
  // tmdbId/tvdbId → 'searching' | 'grabbed' | 'no_release' | 'search_failed'
  // | 'monitoring' | 'added' | 'error'.
  const [addState, setAddState] = useState<Record<string, AddState>>(() => ({}))

  const service = kind === 'movie' ? 'radarr' : 'sonarr'
  const svcState = health?.services?.[service]
  const svcReady = svcState?.configured && svcState?.reachable

  // Live downloads — one poller for the whole page (cards + queue reuse it).
  const dl = useTorrents(!!health?.services?.qbittorrent?.configured && !!health?.services?.qbittorrent?.reachable)
  const failingCount = useFailingCount(
    (!!health?.services?.radarr?.configured && !!health?.services?.radarr?.reachable)
    || (!!health?.services?.sonarr?.configured && !!health?.services?.sonarr?.reachable)
  )
  const views = useLibraryViews()

  useEffect(() => {
    setHealthLoading(true)
    jget('/api/servarr/health')
      .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
      .then((value: unknown) => setHealth(parseHealth(value)))
      .catch(() => setHealth({ services: {} }))
      .finally(() => setHealthLoading(false))
  }, [])

  // ── URL ⇄ state. Reflect the query + active tab into ?q= / ?type= with
  // replaceState (so typing doesn't spam the history stack), keeping the page
  // deep-linkable and refresh-safe. The pathname guard avoids ever rewriting the
  // URL of another page mid-navigation.
  useEffect(() => {
    if (window.location.pathname !== '/discover') return
    const p = new URLSearchParams(window.location.search)
    p.set('type', kind)
    const q = term.trim()
    if (q) p.set('q', q); else p.delete('q')
    const qs = p.toString()
    const next = `${window.location.pathname}${qs ? `?${qs}` : ''}`
    if (next !== `${window.location.pathname}${window.location.search}`) {
      window.history.replaceState(window.history.state, '', next)
    }
  }, [term, kind])

  // Re-read the params on back/forward so a popped history entry restores the
  // matching search + tab (the custom router dispatches popstate on navigate,
  // and the browser dispatches it on back/forward).
  useEffect(() => {
    const onPop = () => {
      if (window.location.pathname !== '/discover') return
      const next = readBrowseParams()
      setKind(next.kind)
      setTerm(next.term)
    }
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  // ── Debounced search. A fresh keystroke / toggle flip cancels the in-flight
  // request (AbortController) and restarts the 400ms timer. Blank term clears. ─
  const abortRef = useRef<AbortController | null>(null)
  const runSearch = useCallback((q: string, k: Kind) => {
    const query = q.trim()
    abortRef.current?.abort()
    if (!query) { setResults([]); setLoading(false); setHasSearched(false); setSearchError(''); return }
    const svc = k === 'movie' ? 'radarr' : 'sonarr'
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setLoading(true); setSearchError('')
    fetch(`/api/servarr/${svc}/search?term=${encodeURIComponent(query)}`, { credentials: 'include', signal: ctrl.signal })
      .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
      .then((data: unknown) => { setResults(arrayOf(data, isCatalogItem)); setHasSearched(true) })
      .catch((e: unknown) => { if (!isAbortError(e)) { setResults([]); setHasSearched(true); setSearchError('Something went wrong. Try again.') } })
      .finally(() => { if (abortRef.current === ctrl) setLoading(false) })
  }, [])

  useEffect(() => {
    if (!svcReady) return
    const t = setTimeout(() => runSearch(term, kind), 400)
    return () => clearTimeout(t)
  }, [term, kind, svcReady, runSearch])

  const initials = user?.name?.split(' ').map((w) => w[0]).join('').toUpperCase().slice(0, 2) || '?'

  const stateFor = (r: CatalogItem): AddState | null => (isAdded(r) ? 'added' : addState[keyOf(kind, r)]) || null

  // One-tap request: pull cached meta, pick sensible defaults, POST to the
  // server-authoritative request endpoint. That single call does the add + live
  // interactive search + grab-or-remove and returns a definitive outcome, so we
  // just flip the card to whatever the server decided — no client-side polling.
  // (The request can take up to ~45s while the server searches indexers live; the
  // 'searching' state shows a "finding a release…" spinner until it resolves.)
  const oneTapAdd = useCallback((r: CatalogItem) => {
    const key = keyOf(kind, r)
    const svc = kind === 'movie' ? 'radarr' : 'sonarr'
    setAddState((s) => ({ ...s, [key]: 'searching' }))
    loadMeta(svc)
      .then((meta) => {
        const qualityProfileId = meta.profiles[0]?.id
        const rootFolderPath = meta.rootFolders[0]?.path
        const languageProfileId = meta.langProfiles[0]?.id
        if (qualityProfileId == null || !rootFolderPath) throw new Error('meta')
        const body = kind === 'movie'
          ? { movie: r, qualityProfileId, rootFolderPath }
          : { series: r, qualityProfileId, languageProfileId, rootFolderPath, monitor: true, searchNow: true }
        return jpost(`/api/servarr/${svc}/request`, body).then((res) => (res.ok ? apiJson(res) : Promise.reject(res)))
      })
      .then((out: unknown) => setAddState((s) => ({ ...s, [key]: outcomeToState(outcomeOf(out)) })))
      .catch(() => setAddState((s) => ({ ...s, [key]: 'error' })))
  }, [kind])

  // Options dialog already ran the request and knows the outcome — reflect it.
  const onOptionsAdded = (r: CatalogItem, outcome?: string) => {
    const key = keyOf(kind, r)
    setOptionsItem(null)
    setAddState((s) => ({ ...s, [key]: outcomeToState(outcome) }))
  }

  // Release picker grabbed a specific release → the card behaves exactly like a
  // one-tap grab from here (the live torrent match takes over the progress UI).
  const onReleaseGrabbed = (r: CatalogItem) => {
    const key = keyOf(kind, r)
    setPickerItem(null)
    setAddState((s) => ({ ...s, [key]: 'grabbed' }))
  }

  return (
    <div style={{ position: 'fixed', inset: 0, background: C.bg, color: C.text, fontFamily: SANS, overflow: 'hidden' }}>
      <Sidebar mobile={mobile} width={sidebarW} views={views} downloadCount={dl.activeCount} failingCount={failingCount} current="browse" />

      <div style={{
        position: 'absolute', top: mobile ? 8 : 12, right: mobile ? 8 : 12, bottom: mobile ? 8 : 12,
        left: sidebarW + (mobile ? 8 : 12), borderRadius: mobile ? 14 : 20, overflow: 'hidden auto',
      }}>
        <TopBar mobile={mobile} initials={initials} logout={logout} title="Browse"
          detail={!!selected} onBack={() => setSelected(null)} />

        {selected ? (
          <DetailView
            mobile={mobile} kind={kind} item={selected}
            state={stateFor(selected)} torrents={dl.torrents}
            onDownload={() => oneTapAdd(selected)} onOptions={() => setOptionsItem(selected)}
            onPickRelease={() => setPickerItem(selected)}
            onRemove={async () => {
              const path = kind === 'movie' ? `radarr/movie/${selected.id}` : `sonarr/series/${selected.id}`
              await jdelete(`/api/servarr/${path}?deleteFiles=true`)
              setSelected(null)
            }}
          />
        ) : (
          <div style={{ padding: mobile ? '4px 16px 100px' : '8px 34px 100px', maxWidth: 1400, margin: '0 auto' }}>
            <SearchBar
              mobile={mobile} kind={kind} setKind={setKind}
              term={term} setTerm={setTerm} loading={loading}
              disabled={!svcReady} onSubmit={() => runSearch(term, kind)}
            />

            {/* Body: gated on health, then loading/empty/error/results */}
            {healthLoading ? (
              <ResultsSkeleton mobile={mobile} />
            ) : !svcReady ? (
              <NotAvailable kind={kind} state={svcState} />
            ) : searchError ? (
              <Notice icon={Ic.alert} tone="error" title={searchError} />
            ) : loading ? (
              <ResultsSkeleton mobile={mobile} />
            ) : !hasSearched ? (
              <PopularRail mobile={mobile} kind={kind} torrents={dl.torrents}
                stateFor={stateFor} onOpen={setSelected} onDownload={oneTapAdd} onPick={setTerm} />
            ) : results.length === 0 ? (
              <Notice icon={Ic.search} title="No matches" body={`Nothing found for “${term.trim()}”. Try a different title.`} />
            ) : (
              <ResultGrid mobile={mobile} results={results} kind={kind} torrents={dl.torrents}
                stateFor={stateFor} onOpen={setSelected} onDownload={oneTapAdd} />
            )}
          </div>
        )}
      </div>

      {optionsItem && (
        <OptionsDialog
          kind={kind} item={optionsItem}
          onClose={() => setOptionsItem(null)}
          onAdded={onOptionsAdded}
        />
      )}

      {pickerItem && (
        <ReleasePicker
          item={pickerItem}
          onClose={() => setPickerItem(null)}
          onGrabbed={onReleaseGrabbed}
        />
      )}
    </div>
  )
}

/* ── Discover / "popular" rail — shown when there's no active search query ────
 * Fetches the server discover feed (genuine import-list source when the admin
 * has one configured, otherwise a curated seed run through the real catalog
 * lookup) and renders it with the exact same cards as search results, so every
 * tile opens / requests / tracks downloads identically. `source` drives an
 * honest heading: a real live list reads "Popular right now", the curated
 * fallback reads "Popular picks". Failure / empty degrades to a suggested-search
 * prompt rather than a dead end. */
function PopularRail({ mobile, kind, torrents, stateFor, onOpen, onDownload, onPick }: {
  mobile: boolean; kind: Kind; torrents?: Torrent[] | null; stateFor: (item: CatalogItem) => AddState | null
  onOpen: (item: CatalogItem) => void; onDownload: (item: CatalogItem) => void; onPick: (term: string) => void
}) {
  const service = kind === 'movie' ? 'radarr' : 'sonarr'
  const [state, setState] = useState<{ loading: boolean; error: boolean; items: CatalogItem[]; source: string }>({ loading: true, error: false, items: [], source: 'curated' })

  useEffect(() => {
    let cancel = false
    setState((s) => ({ ...s, loading: true, error: false }))
    loadPopular(service)
      .then((d) => { if (!cancel) setState({ loading: false, error: false, items: d.items, source: d.source }) })
      .catch(() => { if (!cancel) setState({ loading: false, error: true, items: [], source: 'curated' }) })
    return () => { cancel = true }
  }, [service])

  if (state.loading) return <ResultsSkeleton mobile={mobile} />
  if (state.error || state.items.length === 0) return <SuggestedSearches kind={kind} onPick={onPick} />

  const label = state.source === 'importlist' ? 'Popular right now' : 'Popular picks'
  return (
    <div style={{ animation: 'up .4s ease both' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 16 }}>
        <h2 style={{ fontSize: mobile ? 20 : 22, fontWeight: 800, letterSpacing: '-.02em', margin: 0 }}>{label}</h2>
        <span style={{ fontFamily: MONO, fontSize: 12.5, color: C.faint }}>{kind === 'movie' ? 'Movies' : 'Series'}</span>
      </div>
      <ResultGrid mobile={mobile} results={state.items} kind={kind} torrents={torrents}
        stateFor={stateFor} onOpen={onOpen} onDownload={onDownload} />
    </div>
  )
}

/* Degraded empty state: a few tappable title chips seed the search box so the
 * tab is never a dead end when the discover feed can't be reached. */
const SUGGESTED_SEARCHES = {
  movie: ['Inception', 'Dune', 'Parasite', 'Oppenheimer', 'The Matrix'],
  series: ['Breaking Bad', 'The Last of Us', 'Severance', 'Chernobyl', 'Arcane'],
}
function SuggestedSearches({ kind, onPick }: { kind: Kind; onPick: (term: string) => void }) {
  const list = SUGGESTED_SEARCHES[kind] || []
  return (
    <div style={{ marginTop: 8, padding: '46px 28px', borderRadius: 18, ...glassStyle, animation: 'up .4s ease both',
      display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
      <div style={{ width: 56, height: 56, borderRadius: 16, display: 'grid', placeItems: 'center', marginBottom: 16,
        background: 'rgba(255,255,255,.04)', border: `1px solid ${C.line}` }}>
        <Icon path={Ic.search} size={26} stroke={C.dim} sw={1.7} />
      </div>
      <h2 style={{ fontSize: 20, fontWeight: 800, margin: 0 }}>Find something to watch</h2>
      <p style={{ color: C.dim, fontSize: 14.5, lineHeight: 1.6, maxWidth: 420, marginTop: 8 }}>
        Search {kind === 'movie' ? 'movies' : 'series'} by title, or start with one of these.
      </p>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 9, justifyContent: 'center', marginTop: 18 }}>
        {list.map((t) => (
          <button key={t} onClick={() => onPick(t)}
            style={{ padding: '9px 16px', borderRadius: 999, cursor: 'pointer', fontFamily: SANS, fontSize: 13.5,
              fontWeight: 600, color: C.text, ...glassStyle, background: C.glass }}>{t}</button>
        ))}
      </div>
    </div>
  )
}

/* ── Search bar with Movies / Series segmented toggle ─────────────────────── */
function SearchBar({ mobile, kind, setKind, term, setTerm, loading, disabled, onSubmit }: {
  mobile: boolean; kind: Kind; setKind: (kind: Kind) => void; term: string; setTerm: (term: string) => void
  loading: boolean; disabled?: boolean; onSubmit: () => void
}) {
  const seg = (val: Kind, label: string, icon: string) => {
    const active = kind === val
    return (
      <button onClick={() => setKind(val)} disabled={disabled}
        style={{
          display: 'inline-flex', alignItems: 'center', gap: 7, padding: '0 14px', height: 40, border: 'none',
          borderRadius: 999, cursor: disabled ? 'default' : 'pointer', fontFamily: SANS, fontSize: 13.5, fontWeight: 700,
          color: active ? C.onAccent : C.dim, background: active ? C.accent : 'transparent',
          opacity: disabled ? 0.5 : 1, transition: 'background .15s, color .15s',
        }}>
        <Icon path={icon} size={16} sw={active ? 2 : 1.7} />{label}
      </button>
    )
  }
  return (
    <div style={{ display: 'flex', gap: 12, flexDirection: mobile ? 'column' : 'row', alignItems: mobile ? 'stretch' : 'center', marginBottom: 26 }}>
      <div style={{ display: 'inline-flex', gap: 4, padding: 4, borderRadius: 999, ...glassStyle, alignSelf: mobile ? 'flex-start' : 'center' }}>
        {seg('movie', 'Movies', Ic.film)}
        {seg('series', 'Series', Ic.tv)}
      </div>
      <form onSubmit={(e) => { e.preventDefault(); onSubmit() }} style={{ flex: 1, position: 'relative', display: 'flex', alignItems: 'center' }}>
        <span style={{ position: 'absolute', left: 16, display: 'grid', placeItems: 'center', color: C.faint, pointerEvents: 'none' }}>
          <Icon path={Ic.search} size={18} />
        </span>
        <input
          value={term} onChange={(e) => setTerm(e.target.value)} disabled={disabled}
          placeholder={disabled ? 'Browsing is unavailable right now' : `Search ${kind === 'movie' ? 'movies' : 'series'} by title…`}
          style={{
            width: '100%', height: 48, padding: '0 44px 0 44px', borderRadius: 14, outline: 'none',
            color: C.text, fontFamily: SANS, fontSize: 15, ...glassStyle,
            opacity: disabled ? 0.6 : 1, cursor: disabled ? 'not-allowed' : 'text',
          }} />
        {loading && (
          <span style={{ position: 'absolute', right: 16 }}><Spinner size={18} /></span>
        )}
      </form>
    </div>
  )
}

/* ── Result grid + card ───────────────────────────────────────────────────── */
function ResultGrid({ mobile, results, kind, torrents, stateFor, onOpen, onDownload }: {
  mobile: boolean; results: CatalogItem[]; kind: Kind; torrents?: Torrent[] | null
  stateFor: (item: CatalogItem) => AddState | null; onOpen: (item: CatalogItem) => void; onDownload: (item: CatalogItem) => void
}) {
  return (
    <div style={{ display: 'grid', gap: mobile ? 12 : 18, gridTemplateColumns: `repeat(auto-fill, minmax(${mobile ? 150 : 200}px, 1fr))`, animation: 'up .4s ease both' }}>
      {results.map((r, i) => (
        <ResultCard key={(r.tmdbId || r.tvdbId || r.titleSlug || i) + ''} r={r}
          state={stateFor(r)} torrent={matchTorrent(r.title, torrents)}
          onOpen={() => onOpen(r)} onDownload={() => onDownload(r)} />
      ))}
    </div>
  )
}
function ResultCard({ r, state, torrent, onOpen, onDownload }: {
  r: CatalogItem; state: AddState | null; torrent?: Torrent | null; onOpen: () => void; onDownload: () => void
}) {
  const [h, setH] = useState(false)
  const active = torrent && !isPausedState(torrent.state)
  const pct = torrent ? Math.max(0, Math.min(100, Math.round((torrent.progress || 0) * 100))) : 0
  const torrentDownloading = active && pct < 100
  const downloading = state === 'grabbed' || torrentDownloading
  const searching = state === 'searching' && !torrentDownloading
  const monitoring = state === 'monitoring' && !torrentDownloading
  const noRelease = state === 'no_release' && !torrentDownloading
  const searchFailed = state === 'search_failed' && !torrentDownloading
  const rating = ratingOf(r)

  return (
    <div onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} style={{ display: 'flex', flexDirection: 'column' }}>
      <button onClick={onOpen} aria-label={r.title}
        style={{ position: 'relative', aspectRatio: '2/3', borderRadius: 14, overflow: 'hidden', background: C.surface,
          border: 'none', padding: 0, cursor: 'pointer', textAlign: 'left',
          boxShadow: h ? '0 18px 40px rgba(0,0,0,.55)' : '0 8px 22px rgba(0,0,0,.4)',
          transform: h ? 'translateY(-3px)' : 'none', transition: 'transform .25s, box-shadow .25s' }}>
        <Poster images={r.images} alt={r.title} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%',
          transform: h ? 'scale(1.05)' : 'scale(1)', transition: 'transform .4s' }} />

        {rating != null && (
          <div style={{ position: 'absolute', top: 8, left: 8, display: 'inline-flex', alignItems: 'center', gap: 4,
            padding: '2px 8px', borderRadius: 8, fontFamily: MONO, fontSize: 12, fontWeight: 700, color: C.text,
            background: 'rgba(0,0,0,.7)' }}>
            <Icon path={Ic.star} size={12} fill={C.text} stroke="none" />{rating.toFixed(1)}
          </div>
        )}

        {/* Hover reveal: overview + primary Download (or state) */}
        <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
          padding: 12, opacity: h || downloading || searching || monitoring || noRelease || searchFailed || state === 'added' ? 1 : 0, transition: 'opacity .2s',
          background: 'linear-gradient(0deg, rgba(0,0,0,.92) 8%, rgba(0,0,0,.35) 55%, transparent)' }}>
          {r.overview && h && !downloading && !searching && !monitoring && !noRelease && !searchFailed && state !== 'added' && (
            <p style={{ fontSize: 12, lineHeight: 1.45, color: 'rgba(255,255,255,.86)', margin: '0 0 10px',
              display: '-webkit-box', WebkitLineClamp: 4, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{r.overview}</p>
          )}

          {downloading ? (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontFamily: MONO, fontSize: 11.5, fontWeight: 700, color: C.text, marginBottom: 6 }}>
                <span style={{ width: 7, height: 7, borderRadius: '50%', background: C.live, boxShadow: `0 0 6px ${C.live}`, animation: 'pulse 1.6s ease-in-out infinite' }} />
                {active ? `Downloading · ${pct}%` : 'Starting…'}
              </div>
              <div style={{ height: 5, borderRadius: 999, background: 'rgba(255,255,255,.14)', overflow: 'hidden' }}>
                <div style={{ width: active ? `${pct}%` : '18%', height: '100%', borderRadius: 999,
                  background: C.text, transition: 'width .4s ease' }} />
              </div>
            </div>
          ) : searching ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontFamily: MONO, fontSize: 11.5, fontWeight: 700, color: C.dim }}>
              <span style={{ width: 7, height: 7, borderRadius: '50%', background: C.text, animation: 'pulse 1.6s ease-in-out infinite' }} />
              Finding a release…
            </div>
          ) : monitoring ? (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontFamily: SANS, fontSize: 12.5, fontWeight: 700, color: C.text }}>
                <Icon path={Ic.spark} size={13} sw={2} />Added — monitoring
              </div>
              <div style={{ fontSize: 11, color: C.dim, marginTop: 3, lineHeight: 1.35 }}>
                Episodes download on their own as they appear.
              </div>
            </div>
          ) : noRelease ? (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontFamily: SANS, fontSize: 12.5, fontWeight: 700, color: C.red, marginBottom: 8 }}>
                <Icon path={Ic.alert} size={13} sw={2} />No release available right now
              </div>
              <button onClick={(e) => { e.stopPropagation(); onDownload() }}
                style={{ display: 'inline-flex', alignItems: 'center', gap: 7, alignSelf: 'flex-start', padding: '8px 14px',
                  borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 700,
                  background: C.accent, color: C.onAccent }}>
                <Icon path={Ic.download} size={15} sw={2.4} />Try again
              </button>
            </div>
          ) : searchFailed ? (
            <div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontFamily: SANS, fontSize: 12.5, fontWeight: 700, color: C.red, marginBottom: 8 }}>
                <Icon path={Ic.alert} size={13} sw={2} />Couldn’t check — try again
              </div>
              <button onClick={(e) => { e.stopPropagation(); onDownload() }}
                style={{ display: 'inline-flex', alignItems: 'center', gap: 7, alignSelf: 'flex-start', padding: '8px 14px',
                  borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 700,
                  background: C.accent, color: C.onAccent }}>
                <Icon path={Ic.download} size={15} sw={2.4} />Retry
              </button>
            </div>
          ) : state === 'added' ? (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, alignSelf: 'flex-start',
              padding: '7px 12px', borderRadius: 999, fontSize: 12.5, fontWeight: 700, background: 'rgba(255,255,255,.1)',
              color: C.text, border: `1px solid ${C.line2}` }}>
              <Icon path={Ic.check} size={14} sw={2.4} />In library
            </span>
          ) : state === 'error' ? (
            <button onClick={(e) => { e.stopPropagation(); onDownload() }}
              style={{ display: 'inline-flex', alignItems: 'center', gap: 7, alignSelf: 'flex-start', padding: '8px 14px',
                borderRadius: 999, border: `1px solid rgba(224,101,94,.35)`, cursor: 'pointer', fontFamily: SANS,
                fontSize: 13, fontWeight: 700, background: 'rgba(224,101,94,.12)', color: C.red }}>
              <Icon path={Ic.alert} size={14} sw={2} />Retry
            </button>
          ) : (
            <button onClick={(e) => { e.stopPropagation(); onDownload() }}
              style={{ display: 'inline-flex', alignItems: 'center', gap: 7, alignSelf: 'flex-start', padding: '8px 14px',
                borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 700,
                background: C.accent, color: C.onAccent }}>
              <Icon path={Ic.download} size={15} sw={2.4} />Download
            </button>
          )}
        </div>

        {state === 'added' && !downloading && (
          <div style={{ position: 'absolute', top: 8, right: 8, width: 24, height: 24, borderRadius: '50%',
            display: 'grid', placeItems: 'center', background: 'rgba(0,0,0,.7)', border: `1px solid ${C.line2}` }}>
            <Icon path={Ic.check} size={14} stroke={C.text} sw={3} />
          </div>
        )}
      </button>
      <div style={{ marginTop: 9, fontSize: 14, fontWeight: 600, color: C.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.title}</div>
      <div style={{ fontFamily: MONO, fontSize: 12, color: C.faint, marginTop: 2 }}>
        {[r.year, r.network].filter(Boolean).join(' · ') || '—'}
      </div>
    </div>
  )
}

/* ── Detail view — native title page (mirrors Library's Details layout) ─────── */
function DetailView({ mobile, kind, item, state, torrents, onDownload, onOptions, onPickRelease, onRemove }: {
  mobile: boolean; kind: Kind; item: CatalogItem; state: AddState | null; torrents?: Torrent[] | null
  onDownload: () => void; onOptions: () => void; onPickRelease: () => void; onRemove?: () => Promise<void>
}) {
  const [confirmRemove, setConfirmRemove] = useState(false)
  const [removing, setRemoving] = useState(false)
  const rating = ratingOf(item)
  const runtime = fmtRuntimeFromMinutes(item.runtime)
  const genres = item.genres || []
  const torrent = matchTorrent(item.title, torrents)
  const active = torrent && !isPausedState(torrent.state)
  const pct = torrent ? Math.max(0, Math.min(100, Math.round((torrent.progress || 0) * 100))) : 0
  const torrentDownloading = active && pct < 100
  const downloading = state === 'grabbed' || torrentDownloading
  const searching = state === 'searching' && !torrentDownloading
  const monitoring = state === 'monitoring' && !torrentDownloading
  const noRelease = state === 'no_release' && !torrentDownloading
  const searchFailed = state === 'search_failed' && !torrentDownloading

  const infoLine = [
    item.year,
    runtime,
    item.certification,
    kind === 'series' && item.seasonCount != null ? `${item.seasonCount} season${item.seasonCount === 1 ? '' : 's'}` : null,
    kind === 'series' ? item.network : null,
    kind === 'series' ? item.status : null,
  ].filter(Boolean)

  return (
    <div style={{ paddingBottom: 100, animation: 'up .35s ease both' }}>
      {/* Blurred hero backdrop */}
      <div style={{ position: 'relative', minHeight: mobile ? 'auto' : 'min(70vh, 560px)', display: 'flex', alignItems: 'flex-end' }}>
        <div style={{ position: 'absolute', inset: 0, overflow: 'hidden' }}>
          <Poster images={item.images} useBackdrop alt={item.title}
            style={{ width: '100%', height: '100%', objectPosition: 'top center', transform: 'scale(1.03)' }} />
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(0deg, ${C.bg} 4%, rgba(0,0,0,.55) 48%, rgba(0,0,0,.25) 100%)` }} />
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(90deg, rgba(0,0,0,.72) 0%, rgba(0,0,0,.35) 45%, transparent 82%)` }} />
        </div>

        <div style={{ position: 'relative', width: '100%', padding: mobile ? '120px 16px 20px' : '0 34px 34px',
          display: 'flex', gap: mobile ? 16 : 26, alignItems: 'flex-end' }}>
          {!mobile && (
            <div style={{ width: 190, flexShrink: 0, aspectRatio: '2/3', borderRadius: 16, overflow: 'hidden',
              background: C.surface, boxShadow: '0 20px 50px rgba(0,0,0,.6)' }}>
              <Poster images={item.images} alt={item.title} style={{ width: '100%', height: '100%' }} />
            </div>
          )}

          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: MONO, fontSize: 12, color: C.faint, marginBottom: 8, letterSpacing: '.06em' }}>
              {kind === 'movie' ? 'MOVIE' : 'SERIES'}
            </div>
            <h1 style={{ fontSize: mobile ? 28 : 40, fontWeight: 800, letterSpacing: '-.02em', margin: 0, lineHeight: 1.05 }}>{item.title}</h1>

            {/* Rating + genres row */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap', marginTop: 14, fontSize: 15, fontWeight: 600 }}>
              {rating != null && (
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: C.text }}>
                  <Icon path={Ic.star} size={16} fill={C.text} stroke="none" />{rating.toFixed(1)}
                </span>
              )}
              {genres.slice(0, 3).map((g) => <span key={g} style={{ color: C.dim }}>{g}</span>)}
            </div>

            {/* Info line */}
            {infoLine.length > 0 && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', marginTop: 10, fontFamily: MONO, fontSize: 13, color: C.dim }}>
                {infoLine.map((v, i) => <span key={i}>{v}</span>)}
              </div>
            )}

            {/* Primary action. Series get a per-season download chooser (add +
                monitor + search a chosen season); movies keep the one-tap
                grab-or-remove plus the interactive release picker below. */}
            {kind === 'series' ? (
              <SeasonChooser item={item} mobile={mobile} onWholeSeriesFallback={onDownload} />
            ) : (
            <>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 22, flexWrap: 'wrap' }}>
              {downloading ? (
                <div style={{ minWidth: mobile ? '100%' : 320, maxWidth: 420 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 7, fontFamily: MONO, fontSize: 12.5, fontWeight: 700, color: C.text, marginBottom: 8 }}>
                    <span style={{ width: 8, height: 8, borderRadius: '50%', background: C.live, boxShadow: `0 0 7px ${C.live}`, animation: 'pulse 1.6s ease-in-out infinite' }} />
                    {active ? `Downloading · ${pct}%` : 'Starting download…'}
                  </div>
                  <div style={{ height: 8, borderRadius: 999, background: 'rgba(255,255,255,.12)', overflow: 'hidden' }}>
                    <div style={{ width: active ? `${pct}%` : '15%', height: '100%', borderRadius: 999,
                      background: C.text, transition: 'width .4s ease' }} />
                  </div>
                  {active && (
                    <div style={{ display: 'flex', gap: 14, marginTop: 8, fontFamily: MONO, fontSize: 12.5, color: C.dim, flexWrap: 'wrap' }}>
                      <span>↓ {fmtSpeed(torrent.dlspeed)}</span>
                      <span>ETA {pct >= 100 ? '—' : fmtEta(torrent.eta)}</span>
                      <span>Seeds: {torrent.numSeeds ?? 0} · Peers: {torrent.numLeechs ?? 0}</span>
                    </div>
                  )}
                </div>
              ) : searching ? (
                <div style={{ minWidth: mobile ? '100%' : 320, maxWidth: 460 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 9, fontFamily: SANS, fontSize: 15, fontWeight: 700, color: C.text }}>
                    <span style={{ width: 9, height: 9, borderRadius: '50%', background: C.text, animation: 'pulse 1.6s ease-in-out infinite' }} />
                    Added — finding a release…
                  </div>
                  <p style={{ fontSize: 13.5, color: C.dim, lineHeight: 1.55, marginTop: 8, maxWidth: 460 }}>
                    It’s in your library. We’re looking for a release to download right now.
                  </p>
                </div>
              ) : monitoring ? (
                <div style={{ minWidth: mobile ? '100%' : 320, maxWidth: 480 }}>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 9, padding: '13px 22px', borderRadius: 999,
                    fontSize: 14.5, fontWeight: 700, background: C.surface2, color: C.text, border: `1px solid ${C.line2}` }}>
                    <Icon path={Ic.spark} size={17} sw={2} />Added — monitoring
                  </span>
                  <p style={{ fontSize: 13.5, color: C.dim, lineHeight: 1.6, marginTop: 12, maxWidth: 480 }}>
                    It’s in your library and being monitored — episodes download on their own as they become available. Check back a little later.
                  </p>
                </div>
              ) : noRelease ? (
                <div style={{ minWidth: mobile ? '100%' : 320, maxWidth: 480 }}>
                  <button onClick={onDownload} style={{ display: 'inline-flex', alignItems: 'center', gap: 11, padding: '15px 32px',
                    border: 'none', borderRadius: 999, background: C.accent, color: C.onAccent, fontFamily: SANS, fontSize: 16, fontWeight: 700, cursor: 'pointer',
                    boxShadow: '0 10px 30px rgba(0,0,0,.4)' }}>
                    <Icon path={Ic.download} size={19} sw={2.2} />Try again
                  </button>
                  <p style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13.5, color: C.red, lineHeight: 1.6, marginTop: 14, maxWidth: 480, fontWeight: 600 }}>
                    <Icon path={Ic.alert} size={16} sw={2} />No release available right now — try again later.
                  </p>
                </div>
              ) : searchFailed ? (
                <div style={{ minWidth: mobile ? '100%' : 320, maxWidth: 480 }}>
                  <button onClick={onDownload} style={{ display: 'inline-flex', alignItems: 'center', gap: 11, padding: '15px 32px',
                    border: 'none', borderRadius: 999, background: C.accent, color: C.onAccent, fontFamily: SANS, fontSize: 16, fontWeight: 700, cursor: 'pointer',
                    boxShadow: '0 10px 30px rgba(0,0,0,.4)' }}>
                    <Icon path={Ic.download} size={19} sw={2.2} />Retry
                  </button>
                  <p style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13.5, color: C.red, lineHeight: 1.6, marginTop: 14, maxWidth: 480, fontWeight: 600 }}>
                    <Icon path={Ic.alert} size={16} sw={2} />Couldn’t check for a release right now. Please try again.
                  </p>
                </div>
              ) : state === 'added' ? (
                <>
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 9, padding: '14px 26px', borderRadius: 999,
                    fontSize: 15, fontWeight: 700, background: C.surface2, color: C.text, border: `1px solid ${C.line2}` }}>
                    <Icon path={Ic.check} size={18} sw={2.4} />In library
                  </span>
                  {onRemove && (
                    <button onClick={() => setConfirmRemove(true)} title="Remove from library"
                      style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '14px 20px', borderRadius: 999,
                        cursor: 'pointer', fontSize: 14, fontWeight: 700, color: C.red, ...glassStyle, background: 'rgba(20,24,30,.5)' }}>
                      <Icon path={Ic.trash} size={17} sw={2} />Remove
                    </button>
                  )}
                  {confirmRemove && (
                    <div onClick={() => !removing && setConfirmRemove(false)} style={{ position: 'fixed', inset: 0, zIndex: 100,
                      display: 'grid', placeItems: 'center', background: 'rgba(0,0,0,.6)', backdropFilter: 'blur(2px)' }}>
                      <div onClick={(e) => e.stopPropagation()} style={{ width: 'min(380px, 90vw)', borderRadius: 18, padding: 24,
                        ...glassStyle, background: 'rgba(20,24,30,.92)' }}>
                        <h2 style={{ fontSize: 18, fontWeight: 800, margin: 0 }}>Remove from library?</h2>
                        <p style={{ fontSize: 14, color: C.dim, lineHeight: 1.55, marginTop: 10 }}>
                          This deletes the {kind === 'movie' ? 'movie' : 'series'} and its downloaded files, and
                          stops it from being auto-redownloaded. This can't be undone.
                        </p>
                        <div style={{ display: 'flex', gap: 10, marginTop: 20 }}>
                          <button onClick={() => setConfirmRemove(false)} disabled={removing} style={{ flex: 1, height: 46, borderRadius: 13,
                            border: `1px solid ${C.line2}`, background: 'transparent', color: C.text, fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
                            Cancel
                          </button>
                          <button onClick={async () => { setRemoving(true); try { await onRemove?.() } finally { setRemoving(false); setConfirmRemove(false) } }}
                            disabled={removing} style={{ flex: 1, height: 46, borderRadius: 13, border: 'none',
                              background: C.red, color: C.text, fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
                            {removing ? 'Removing…' : 'Remove'}
                          </button>
                        </div>
                      </div>
                    </div>
                  )}
                </>
              ) : (
                <>
                  <button onClick={onDownload} style={{ display: 'inline-flex', alignItems: 'center', gap: 11, padding: '15px 32px',
                    border: 'none', borderRadius: 999, background: state === 'error' ? 'rgba(224,101,94,.14)' : C.accent,
                    color: state === 'error' ? C.red : C.onAccent, fontFamily: SANS, fontSize: 16, fontWeight: 700, cursor: 'pointer',
                    boxShadow: '0 10px 30px rgba(0,0,0,.4)', transition: 'transform .15s' }}
                    onMouseEnter={(e) => e.currentTarget.style.transform = 'scale(1.02)'} onMouseLeave={(e) => e.currentTarget.style.transform = 'none'}>
                    <Icon path={state === 'error' ? Ic.alert : Ic.download} size={19} sw={2.2} />
                    {state === 'error' ? 'Retry download' : 'Download'}
                  </button>
                  <button onClick={onOptions} title="Download options" style={{ width: 52, height: 52, borderRadius: '50%',
                    display: 'grid', placeItems: 'center', cursor: 'pointer', ...glassStyle, background: 'rgba(20,24,30,.5)', color: C.text }}>
                    <Icon path={Ic.gear} size={21} sw={1.7} />
                  </button>
                </>
              )}
            </div>

            {/* Secondary: browse every release + seed counts and pick one manually.
                Movies only (Sonarr picker is out of scope). Hidden while a grab is
                already in flight (downloading/searching) — nothing to pick then. */}
            {kind === 'movie' && !downloading && !searching && (
              <button onClick={onPickRelease} title="See every source with seed counts and choose one"
                style={{ display: 'inline-flex', alignItems: 'center', gap: 8, marginTop: 16, padding: '10px 16px',
                  borderRadius: 999, cursor: 'pointer', fontFamily: SANS, fontSize: 13.5, fontWeight: 700,
                  color: C.text, ...glassStyle, background: 'rgba(20,24,30,.5)' }}
                onMouseEnter={(e) => e.currentTarget.style.background = C.glassHi}
                onMouseLeave={(e) => e.currentTarget.style.background = 'rgba(20,24,30,.5)'}>
                <Icon path={Ic.search} size={16} sw={1.9} />
                {state === 'added' ? 'Choose a release' : 'See all sources'}
              </button>
            )}
            </>
            )}

            {/* Overview */}
            {item.overview && (
              <p style={{ fontSize: 15, lineHeight: 1.6, color: 'rgba(241,243,246,.85)', maxWidth: 720, marginTop: 22,
                display: '-webkit-box', WebkitLineClamp: 6, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
                {item.overview}
              </p>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

/* ── Season chooser (series only) — pick and download individual seasons ──────
 * TV availability is partial and spread over time, so a season request is
 * monitor-only: it adds the show to Sonarr on first use (server side), flips the
 * chosen season(s) to monitored, and fires a SeasonSearch — episodes then
 * download as they're found (progress lives in the Downloads tab). Seasons Sonarr
 * already monitors are shown as such; "Specials" (season 0) is listed last and is
 * never part of "All seasons". Episode counts are shown only when Sonarr has them
 * (a not-yet-added series has none until it's in the library). */
function SeasonChooser({ item, mobile, onWholeSeriesFallback }: { item: CatalogItem; mobile: boolean; onWholeSeriesFallback: () => void }) {
  const seasons = Array.isArray(item.seasons) ? item.seasons : []
  const real = seasons.filter((s) => s.seasonNumber >= 1).sort((a, b) => a.seasonNumber - b.seasonNumber)
  const specials = seasons.filter((s) => s.seasonNumber === 0)
  // A season's `monitored` flag only means "already tracked in your library" when
  // the series is actually added. A not-yet-added lookup echoes TVDB's default
  // (usually every season monitored:true), which must NOT read as already-added.
  const added = isAdded(item)

  const [meta, setMeta] = useState({ loading: true, error: '' })
  // Per-season session state: seasonNumber → 'requesting' | 'requested' | 'error'.
  const [req, setReq] = useState<Record<number, string>>({})

  useEffect(() => {
    let cancel = false
    setMeta({ loading: true, error: '' })
    loadMeta('sonarr')
      .then((m) => {
        if (cancel) return
        const ok = m.profiles?.[0]?.id != null && !!m.rootFolders?.[0]?.path
        setMeta({ loading: false, error: ok ? '' : 'Download options are unavailable right now.' })
      })
      .catch(() => { if (!cancel) setMeta({ loading: false, error: 'Download options are unavailable right now.' }) })
    return () => { cancel = true }
  }, [])

  const request = (nums: number[]) => {
    if (!nums.length) return
    setReq((s) => { const n = { ...s }; for (const k of nums) n[k] = 'requesting'; return n })
    loadMeta('sonarr')
      .then((m) => {
        const qualityProfileId = m.profiles?.[0]?.id
        const rootFolderPath = m.rootFolders?.[0]?.path
        const languageProfileId = m.langProfiles?.[0]?.id
        if (qualityProfileId == null || !rootFolderPath) throw new Error('meta')
        return jpost('/api/servarr/sonarr/request-season',
          { series: item, seasons: nums, qualityProfileId, languageProfileId, rootFolderPath })
      })
      .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
      .then(() => setReq((s) => { const n = { ...s }; for (const k of nums) n[k] = 'requested'; return n }))
      .catch(() => setReq((s) => { const n = { ...s }; for (const k of nums) n[k] = 'error'; return n }))
  }

  const stateOf = (s: Season) => req[s.seasonNumber] || (added && s.monitored ? 'monitored' : 'idle')
  const anyRequesting = Object.values(req).some((v) => v === 'requesting')

  // No season list at all → fall back to the whole-series request so the button
  // is never a dead end (shouldn't occur now that the shaper always emits seasons).
  if (real.length === 0 && specials.length === 0) {
    return (
      <div style={{ marginTop: 22 }}>
        <button onClick={onWholeSeriesFallback} style={{ display: 'inline-flex', alignItems: 'center', gap: 11, padding: '15px 32px',
          border: 'none', borderRadius: 999, background: C.accent, color: C.onAccent, fontFamily: SANS, fontSize: 16, fontWeight: 700,
          cursor: 'pointer', boxShadow: '0 10px 30px rgba(0,0,0,.4)' }}>
          <Icon path={Ic.download} size={19} sw={2.2} />Download series
        </button>
      </div>
    )
  }

  if (meta.loading) {
    return <div style={{ marginTop: 22, display: 'flex', alignItems: 'center', gap: 10, color: C.dim, fontSize: 14 }}>
      <Spinner size={18} />Loading seasons…
    </div>
  }
  if (meta.error) {
    return <div style={{ maxWidth: 520 }}><Notice icon={Ic.alert} tone="error" title={meta.error} compact /></div>
  }

  const allReal = real.map((s) => s.seasonNumber)
  const allMonitored = real.length > 0 && real.every((s) => stateOf(s) === 'monitored' || stateOf(s) === 'requested')

  return (
    <div style={{ marginTop: 22, maxWidth: 560 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', marginBottom: 14 }}>
        <div style={{ fontFamily: SANS, fontSize: 15, fontWeight: 800, letterSpacing: '-.01em' }}>Choose seasons</div>
        <div style={{ flex: 1 }} />
        {real.length > 1 && (
          <button onClick={() => request(allReal)} disabled={anyRequesting || allMonitored}
            title="Monitor and search every season"
            style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '9px 16px', borderRadius: 999,
              border: allMonitored ? `1px solid ${C.line2}` : 'none',
              cursor: anyRequesting || allMonitored ? 'default' : 'pointer', fontFamily: SANS, fontSize: 13.5, fontWeight: 700,
              background: allMonitored ? C.surface2 : C.accent, color: allMonitored ? C.text : C.onAccent,
              opacity: anyRequesting && !allMonitored ? 0.6 : 1, transition: 'opacity .15s' }}>
            {allMonitored
              ? <><Icon path={Ic.check} size={15} sw={2.4} />All seasons</>
              : <><Icon path={Ic.download} size={15} sw={2.2} />All seasons</>}
          </button>
        )}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {real.map((s) => (
          <SeasonRow key={s.seasonNumber} season={s} state={stateOf(s)} disabled={anyRequesting}
            onRequest={() => request([s.seasonNumber])} />
        ))}
      </div>

      {specials.length > 0 && (
        <div style={{ marginTop: 14 }}>
          <div style={{ fontFamily: MONO, fontSize: 11.5, color: C.faint, letterSpacing: '.06em', marginBottom: 8 }}>SPECIALS</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {specials.map((s) => (
              <SeasonRow key={s.seasonNumber} season={s} state={stateOf(s)} disabled={anyRequesting} specials
                onRequest={() => request([s.seasonNumber])} />
            ))}
          </div>
        </div>
      )}

      <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 14, fontSize: 12.5, color: C.faint, lineHeight: 1.5 }}>
        <Icon path={Ic.spark} size={14} sw={1.8} stroke={C.faint} />
        A requested season is monitored and searched — episodes download on their own as they’re found.
      </div>
    </div>
  )
}

/* One season row: label + episode count on the left, a per-season Download (or
 * its current monitor/search state) on the right. Specials render dimmer. */
function SeasonRow({ season, state, disabled, specials, onRequest }: {
  season: Season; state: string; disabled?: boolean; specials?: boolean; onRequest: () => void
}) {
  const [h, setH] = useState(false)
  const label = season.seasonNumber === 0 ? 'Specials' : `Season ${season.seasonNumber}`
  const count = season.totalEpisodeCount != null && season.totalEpisodeCount > 0
    ? `${season.totalEpisodeCount} episode${season.totalEpisodeCount === 1 ? '' : 's'}` : null

  const right = (() => {
    if (state === 'requesting') {
      return <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, fontFamily: SANS, fontSize: 13, fontWeight: 700, color: C.dim }}>
        <Spinner size={15} />Requesting…
      </span>
    }
    if (state === 'requested') {
      return <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '7px 13px', borderRadius: 999, fontSize: 12.5,
        fontWeight: 700, background: C.surface2, color: C.text, border: `1px solid ${C.line2}` }}>
        <Icon path={Ic.spark} size={13} sw={2} />Searching…
      </span>
    }
    if (state === 'monitored') {
      return (
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '7px 13px', borderRadius: 999, fontSize: 12.5,
            fontWeight: 700, background: C.surface2, color: C.text, border: `1px solid ${C.line2}` }}>
            <Icon path={Ic.check} size={13} sw={2.6} />Monitoring
          </span>
          <button onClick={onRequest} disabled={disabled} title="Search this season again"
            style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '7px 11px', borderRadius: 999, cursor: disabled ? 'default' : 'pointer',
              fontFamily: SANS, fontSize: 12.5, fontWeight: 700, color: C.text, ...glassStyle, background: 'rgba(20,24,30,.5)', opacity: disabled ? 0.5 : 1 }}>
            <Icon path={Ic.search} size={13} sw={2} />Search
          </button>
        </span>
      )
    }
    if (state === 'error') {
      return <button onClick={onRequest} disabled={disabled}
        style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 14px', borderRadius: 999,
          border: '1px solid rgba(224,101,94,.35)', cursor: disabled ? 'default' : 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 700,
          background: 'rgba(224,101,94,.12)', color: C.red, opacity: disabled ? 0.6 : 1 }}>
        <Icon path={Ic.alert} size={14} sw={2} />Retry
      </button>
    }
    return <button onClick={onRequest} disabled={disabled}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 15px', borderRadius: 999, border: 'none',
        cursor: disabled ? 'default' : 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 700, background: C.accent, color: C.onAccent,
        opacity: disabled ? 0.6 : 1, transition: 'opacity .15s' }}>
      <Icon path={Ic.download} size={15} sw={2.4} />Download
    </button>
  })()

  return (
    <div onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 14px', borderRadius: 12, border: `1px solid ${C.line}`,
        background: h ? 'rgba(255,255,255,.06)' : 'rgba(255,255,255,.03)', opacity: specials ? 0.82 : 1, transition: 'background .15s' }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: SANS, fontSize: 14.5, fontWeight: 700, color: C.text }}>{label}</div>
        <div style={{ fontFamily: MONO, fontSize: 12, color: C.faint, marginTop: 2 }}>{count || (specials ? 'Extras & one-offs' : '—')}</div>
      </div>
      <div style={{ flexShrink: 0 }}>{right}</div>
    </div>
  )
}

/* ── Options dialog: change quality profile / root folder before adding ─────── */
function OptionsDialog({ kind, item, onClose, onAdded }: {
  kind: Kind; item: CatalogItem; onClose: () => void; onAdded: (item: CatalogItem, outcome?: string) => void
}) {
  const mobile = useIsMobile()
  const service = kind === 'movie' ? 'radarr' : 'sonarr'

  const [profiles, setProfiles] = useState<Profile[] | null>(null)
  const [rootFolders, setRootFolders] = useState<RootFolder[] | null>(null)
  const [langProfiles, setLangProfiles] = useState<Profile[] | null>(null)
  const [meta, setMeta] = useState({ loading: true, error: '' })

  const [qualityProfileId, setQualityProfileId] = useState<number | null>(null)
  const [rootFolderPath, setRootFolderPath] = useState<string | null>(null)
  const [languageProfileId, setLanguageProfileId] = useState<number | null>(null)
  const [monitor, setMonitor] = useState(true)
  const [searchNow, setSearchNow] = useState(true)

  const [submitting, setSubmitting] = useState(false)
  const [result, setResult] = useState<OptionsResult | null>(null)

  useEffect(() => {
    let cancel = false
    setMeta({ loading: true, error: '' })
    loadMeta(service)
      .then((m) => {
        if (cancel) return
        setProfiles(m.profiles); setRootFolders(m.rootFolders); setLangProfiles(m.langProfiles)
        setQualityProfileId(m.profiles?.[0]?.id ?? null)
        setRootFolderPath(m.rootFolders?.[0]?.path ?? null)
        setLanguageProfileId(m.langProfiles?.[0]?.id ?? null)
        setMeta({ loading: false, error: '' })
      })
      .catch(() => { if (!cancel) setMeta({ loading: false, error: 'Download options are unavailable right now.' }) })
    return () => { cancel = true }
  }, [service])

  const submit = () => {
    if (submitting || qualityProfileId == null || !rootFolderPath) return
    setSubmitting(true); setResult(null)
    // Movies go through the server-authoritative grab-or-remove request; series
    // still carry the monitor / search toggles (Sonarr searches + monitors).
    const body = kind === 'movie'
      ? { movie: item, qualityProfileId, rootFolderPath }
      : { series: item, qualityProfileId, languageProfileId, rootFolderPath, monitor, searchNow }
    jpost(`/api/servarr/${service}/request`, body)
      .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
      .then((out: unknown) => {
        const outcome = outcomeOf(out)
        if (outcome === 'grabbed' || outcome === 'monitoring' || outcome === 'exists') {
          // Definitive success — reflect it on the card and close the dialog.
          setResult({ ok: true, outcome }); setTimeout(() => onAdded(item, outcome), 900)
        } else if (outcome === 'no_release') {
          setResult({ warn: 'No release available right now — try again later.' })
        } else {
          setResult({ error: 'Couldn’t check for a release right now. Please try again.' })
        }
        setSubmitting(false)
      })
      .catch(() => { setResult({ error: 'Couldn’t start the request. Please try again.' }); setSubmitting(false) })
  }

  const canSubmit = !meta.loading && !meta.error && qualityProfileId != null && rootFolderPath && !submitting && !result?.ok

  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 100, display: 'grid', placeItems: 'center',
      padding: 16, background: 'rgba(6,8,11,.66)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)', animation: 'up .2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{
        width: 'min(560px, 100%)', maxHeight: '86vh', overflow: 'auto', borderRadius: 20, padding: mobile ? 18 : 26,
        ...glassStyle, background: 'rgba(22,25,30,.92)', boxShadow: '0 30px 80px rgba(0,0,0,.6)' }}>
        <div style={{ display: 'flex', gap: 16, marginBottom: 20 }}>
          <div style={{ width: 74, flexShrink: 0, aspectRatio: '2/3', borderRadius: 10, overflow: 'hidden', background: C.surface }}>
            <Poster images={item.images} alt={item.title} style={{ width: '100%', height: '100%' }} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 12, fontFamily: MONO, color: C.faint, marginBottom: 4 }}>{kind === 'movie' ? 'MOVIE' : 'SERIES'}</div>
            <h2 style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-.01em', margin: 0, lineHeight: 1.2 }}>{item.title}</h2>
            <div style={{ fontFamily: MONO, fontSize: 12.5, color: C.faint, marginTop: 4 }}>
              {[item.year, kind === 'series' && item.seasonCount != null ? `${item.seasonCount} seasons` : null].filter(Boolean).join(' · ')}
            </div>
          </div>
          <button onClick={onClose} title="Close" style={{ width: 34, height: 34, borderRadius: 999, border: 'none', cursor: 'pointer',
            background: 'rgba(255,255,255,.06)', color: C.dim, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
            <Icon path={Ic.x} size={18} />
          </button>
        </div>

        {meta.loading ? (
          <div style={{ padding: '30px 0', display: 'grid', placeItems: 'center' }}><Spinner size={26} /></div>
        ) : meta.error ? (
          <Notice icon={Ic.alert} tone="error" title={meta.error} compact />
        ) : (
          <>
            <Field label="Quality">
              <Select value={qualityProfileId ?? ''} onChange={(e) => setQualityProfileId(Number(e.target.value))}>
                {(profiles || []).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </Select>
            </Field>
            <Field label="Save to">
              <Select value={rootFolderPath ?? ''} onChange={(e) => setRootFolderPath(e.target.value)}>
                {(rootFolders || []).map((f) => (
                  <option key={f.id ?? f.path} value={f.path}>
                    {f.path}{f.freeSpace ? `  (${Math.round(f.freeSpace / 1e9)} GB free)` : ''}
                  </option>
                ))}
              </Select>
            </Field>
            {kind === 'series' && langProfiles && langProfiles.length > 0 && (
              <Field label="Language">
                <Select value={languageProfileId ?? ''} onChange={(e) => setLanguageProfileId(Number(e.target.value))}>
                  {langProfiles.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                </Select>
              </Field>
            )}

            {/* Series still monitor + search over time; a movie request is a single
                deterministic grab-or-remove, so it has no monitor/search toggles. */}
            {kind === 'series' && (
              <>
                <Toggle label="Keep monitoring" hint="Monitor all episodes" on={monitor} set={setMonitor} />
                <Toggle label="Search now" hint="Start looking for a release immediately" on={searchNow} set={setSearchNow} />
              </>
            )}

            {result?.error && <Notice icon={Ic.alert} tone="error" title={result.error} compact />}
            {result?.warn && <Notice icon={Ic.alert} tone="warn" title={result.warn} compact />}
            {result?.ok && (
              <Notice icon={Ic.check} tone="ok" compact
                title={result.outcome === 'grabbed' ? 'Downloading — added to your library'
                  : result.outcome === 'monitoring' ? 'Added — monitoring for releases'
                  : 'Already in your library'} />
            )}

            <button onClick={submit} disabled={!canSubmit}
              style={{ width: '100%', marginTop: 18, height: 48, borderRadius: 14, border: 'none',
                cursor: canSubmit ? 'pointer' : 'default', fontFamily: SANS, fontSize: 15, fontWeight: 700,
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 9,
                background: result?.ok ? C.surface3 : C.accent, color: result?.ok ? C.text : C.onAccent,
                opacity: canSubmit || result?.ok ? 1 : 0.55, transition: 'opacity .15s' }}>
              {submitting ? <><Spinner size={17} dark />{kind === 'movie' ? 'Finding a release…' : 'Adding…'}</>
                : result?.ok ? <><Icon path={Ic.check} size={17} sw={2.4} />Done</>
                : <><Icon path={Ic.download} size={17} sw={2} />{result?.warn ? 'Try again' : 'Download'}</>}
            </button>
          </>
        )}
      </div>
    </div>
  )
}

/* ── Release picker: browse every source with seed counts and grab a chosen one ─
 * Optional companion to the one-tap auto-grab (movies only). Lifecycle keeps the
 * Radarr DB clean:
 *   open  → POST /radarr/releases  (adds the title monitored+no-search if it
 *           isn't in Radarr yet, then runs the live interactive search)
 *   pick  → POST /radarr/grab      (hand that release to the client, KEEP entry)
 *   close → POST /radarr/releases/cancel (remove the entry ONLY if this picker
 *           created it — server re-checks it's file-less + not in the queue)
 * The cancel fires on every close path (X / backdrop / Cancel) and on unmount
 * (e.g. navigating Back mid-browse), guarded so it runs at most once and never
 * after a successful grab. */
function ReleasePicker({ item, onClose, onGrabbed }: { item: CatalogItem; onClose: () => void; onGrabbed: (item: CatalogItem) => void }) {
  const mobile = useIsMobile()
  const [meta, setMeta] = useState({ loading: true, error: '' })
  const [data, setData] = useState<ReleaseData | null>(null)        // { movieId, createdByPicker, searchFailed, releases }
  const [nonce, setNonce] = useState(0)          // bump to retry the search
  const [grabbing, setGrabbing] = useState<string | null>(null) // guid currently being grabbed
  const [grabError, setGrabError] = useState('')

  // Cleanup handle kept in a ref so an unmount can still cancel exactly once.
  const life = useRef<{ movieId: number | null; createdByPicker: boolean; settled: boolean }>({ movieId: null, createdByPicker: false, settled: false })
  const cleanup = useCallback(() => {
    const { movieId, createdByPicker, settled } = life.current
    if (settled) return
    life.current.settled = true
    if (createdByPicker && movieId != null) {
      jpost('/api/servarr/radarr/releases/cancel', { movieId, createdByPicker: true }).catch(() => {})
    }
  }, [])

  // Open / retry: reuse an existing movieId (retry keeps the same entry so we
  // never add twice or lose the createdByPicker flag), else use the library id,
  // else add-then-search via a lookup item + default profile/folder.
  useEffect(() => {
    let cancelled = false
    setMeta({ loading: true, error: '' }); setGrabError('')
    ;(async () => {
      const existing = life.current.movieId
      let createdByPicker = life.current.createdByPicker
      let body
      if (existing != null) {
        body = { movieId: existing }
      } else if (isAdded(item)) {
        body = { movieId: item.id }; createdByPicker = false
      } else {
        const m = await loadMeta('radarr')
        const qualityProfileId = m.profiles?.[0]?.id
        const rootFolderPath = m.rootFolders?.[0]?.path
        if (qualityProfileId == null || !rootFolderPath) throw new Error('meta')
        body = { movie: item, qualityProfileId, rootFolderPath }
      }
      const res = await jpost('/api/servarr/radarr/releases', body)
      if (!res.ok) throw new Error('releases')
      const d = parseReleaseData(await apiJson(res))
      // When we passed a movieId the server reports createdByPicker:false, but we
      // must keep our own flag so a retried browse still cleans up on close.
      return { d, createdByPicker: existing != null ? createdByPicker : !!d.createdByPicker }
    })()
      .then(({ d, createdByPicker }) => {
        if (cancelled) {
          // Unmounted mid-search — still remove an entry we just created.
          if (createdByPicker && d?.movieId != null) {
            jpost('/api/servarr/radarr/releases/cancel', { movieId: d.movieId, createdByPicker: true }).catch(() => {})
          }
          return
        }
        life.current = { movieId: d.movieId, createdByPicker, settled: false }
        setData(d)
        setMeta({ loading: false, error: '' })
      })
      .catch(() => { if (!cancelled) setMeta({ loading: false, error: 'Couldn’t load sources right now. Please try again.' }) })
    return () => { cancelled = true }
  }, [item, nonce])

  // Fire cleanup on unmount too (Back button etc.) — no-op if already settled.
  useEffect(() => cleanup, [cleanup])

  const doClose = () => { cleanup(); onClose() }

  const grab = (rel: Release) => {
    if (grabbing) return
    setGrabbing(rel.guid); setGrabError('')
    jpost('/api/servarr/radarr/grab', { movieId: data?.movieId, guid: rel.guid, indexerId: rel.indexerId })
      .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
      .then(() => { life.current.settled = true; onGrabbed(item) })   // keep the entry; parent flips card to downloading
      .catch(() => { setGrabbing(null); setGrabError('Couldn’t start that download. Try another source.') })
  }

  const releases = data?.releases || []

  return (
    <div onClick={doClose} style={{ position: 'fixed', inset: 0, zIndex: 100, display: 'grid', placeItems: 'center',
      padding: 16, background: 'rgba(6,8,11,.66)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)', animation: 'up .2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{
        width: 'min(640px, 100%)', maxHeight: '86vh', display: 'flex', flexDirection: 'column', borderRadius: 20, padding: mobile ? 18 : 24,
        ...glassStyle, background: 'rgba(22,25,30,.92)', boxShadow: '0 30px 80px rgba(0,0,0,.6)' }}>
        {/* Header */}
        <div style={{ display: 'flex', gap: 14, marginBottom: 16 }}>
          <div style={{ width: 62, flexShrink: 0, aspectRatio: '2/3', borderRadius: 10, overflow: 'hidden', background: C.surface }}>
            <Poster images={item.images} alt={item.title} style={{ width: '100%', height: '100%' }} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 12, fontFamily: MONO, color: C.faint, marginBottom: 4 }}>CHOOSE A RELEASE</div>
            <h2 style={{ fontSize: 19, fontWeight: 800, letterSpacing: '-.01em', margin: 0, lineHeight: 1.2 }}>{item.title}</h2>
            <div style={{ fontFamily: MONO, fontSize: 12.5, color: C.faint, marginTop: 4 }}>
              {[item.year, meta.loading ? null : `${releases.length} source${releases.length === 1 ? '' : 's'}`].filter(Boolean).join(' · ')}
            </div>
          </div>
          <button onClick={doClose} title="Close" style={{ width: 34, height: 34, borderRadius: 999, border: 'none', cursor: 'pointer',
            background: 'rgba(255,255,255,.06)', color: C.dim, display: 'grid', placeItems: 'center', flexShrink: 0, alignSelf: 'flex-start' }}>
            <Icon path={Ic.x} size={18} />
          </button>
        </div>

        {meta.loading ? (
          <div style={{ padding: '34px 0', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
            <Spinner size={28} />
            <div style={{ fontSize: 13.5, color: C.dim, textAlign: 'center', maxWidth: 340, lineHeight: 1.5 }}>
              Searching every source for the healthiest release. This can take up to a minute.
            </div>
          </div>
        ) : meta.error ? (
          <div>
            <Notice icon={Ic.alert} tone="error" title={meta.error} compact />
            <RetryBtn onClick={() => setNonce((n) => n + 1)} />
          </div>
        ) : data?.searchFailed ? (
          <div>
            <Notice icon={Ic.alert} tone="warn" compact title="Couldn’t reach the sources just now. Please try again." />
            <RetryBtn onClick={() => setNonce((n) => n + 1)} />
          </div>
        ) : releases.length === 0 ? (
          <Notice icon={Ic.search} tone="warn" compact title="No sources found for this title right now." />
        ) : (
          <>
            {grabError && <Notice icon={Ic.alert} tone="error" title={grabError} compact />}
            <div style={{ overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 8, marginTop: grabError ? 12 : 2, paddingRight: 2 }}>
              {releases.map((rel) => (
                <ReleaseRow key={rel.guid} rel={rel} grabbing={grabbing} onGrab={() => grab(rel)} />
              ))}
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 12, fontSize: 12, color: C.faint }}>
              <Icon path={Ic.alert} size={13} sw={1.8} stroke={C.faint} />
              Greyed rows were skipped by the auto-picker for the reason shown.
            </div>
          </>
        )}
      </div>
    </div>
  )
}

/* One source row: quality, size, prominent seeders, peers, indexer + a per-row
 * Download. Rejected releases render greyed and un-grabbable with their reason. */
function ReleaseRow({ rel, grabbing, onGrab }: { rel: Release; grabbing: string | null; onGrab: () => void }) {
  const [h, setH] = useState(false)
  const busy = grabbing === rel.guid
  const anyBusy = !!grabbing
  const rejected = rel.rejected
  const seeds = rel.seeders
  const seedColor = seeds == null ? C.faint : seeds > 0 ? C.text : C.red
  const reason = rejected ? (rel.rejections?.[0] || 'Skipped by the quality profile') : null

  return (
    <div onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ padding: '11px 13px', borderRadius: 12, border: `1px solid ${C.line}`,
        background: rejected ? 'rgba(255,255,255,.02)' : (h ? 'rgba(255,255,255,.06)' : 'rgba(255,255,255,.03)'),
        opacity: rejected ? 0.6 : 1, transition: 'background .15s' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div title={rel.title} style={{ fontFamily: MONO, fontSize: 12.5, color: C.text,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{rel.title}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap', marginTop: 6, fontFamily: MONO, fontSize: 12 }}>
            {rel.quality && (
              <span style={{ padding: '2px 8px', borderRadius: 7, background: 'rgba(255,255,255,.07)', color: C.dim, fontWeight: 700 }}>{rel.quality}</span>
            )}
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: seedColor, fontWeight: 700 }}>
              <span style={{ width: 7, height: 7, borderRadius: '50%', background: seedColor,
                boxShadow: 'none' }} />
              {seeds == null ? '—' : seeds} seed{seeds === 1 ? '' : 's'}
            </span>
            <span style={{ color: C.faint }}>{rel.leechers == null ? '—' : rel.leechers} peers</span>
            <span style={{ color: C.dim }}>{fmtSize(rel.size)}</span>
            {rel.indexer && (
              <span title={rel.indexer} style={{ color: C.faint, maxWidth: 150, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{rel.indexer}</span>
            )}
          </div>
          {reason && (
            <div title={rel.rejections?.join(' · ')} style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 7,
              fontSize: 12, color: C.dim, fontWeight: 600 }}>
              <Icon path={Ic.alert} size={13} sw={2} />
              <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{reason}</span>
            </div>
          )}
        </div>
        {!rejected && (
          <button onClick={onGrab} disabled={anyBusy}
            style={{ flexShrink: 0, display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 14px', borderRadius: 999, border: 'none',
              cursor: anyBusy ? 'default' : 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 700,
              background: C.accent, color: C.onAccent, opacity: anyBusy && !busy ? 0.45 : 1, transition: 'opacity .15s' }}>
            {busy ? <Spinner size={14} dark /> : <Icon path={Ic.download} size={15} sw={2.4} />}
            {busy ? 'Starting…' : 'Download'}
          </button>
        )}
      </div>
    </div>
  )
}

function RetryBtn({ onClick }: { onClick: () => void }) {
  return (
    <button onClick={onClick} style={{ display: 'inline-flex', alignItems: 'center', gap: 8, marginTop: 14, padding: '10px 18px',
      borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: SANS, fontSize: 14, fontWeight: 700, background: C.accent, color: C.onAccent }}>
      <Icon path={Ic.search} size={15} sw={2.2} />Try again
    </button>
  )
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label style={{ display: 'block', marginBottom: 14 }}>
      <div style={{ fontSize: 12.5, fontWeight: 700, color: C.dim, marginBottom: 6, letterSpacing: '.01em' }}>{label}</div>
      {children}
    </label>
  )
}
function Select({ children, ...rest }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select {...rest} style={{
      width: '100%', height: 44, padding: '0 14px', borderRadius: 12, color: C.text, fontFamily: SANS, fontSize: 14,
      background: C.surface2, border: `1px solid ${C.line2}`, outline: 'none', cursor: 'pointer', appearance: 'none' }}>
      {children}
    </select>
  )
}
function Toggle({ label, hint, on, set }: { label: string; hint?: string; on: boolean; set: (value: boolean) => void }) {
  return (
    <button onClick={() => set(!on)} style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 12,
      padding: '11px 14px', marginBottom: 10, borderRadius: 12, border: `1px solid ${C.line}`, cursor: 'pointer',
      background: 'rgba(255,255,255,.03)', textAlign: 'left' }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>{label}</div>
        {hint && <div style={{ fontSize: 12, color: C.faint, marginTop: 2 }}>{hint}</div>}
      </div>
      <span style={{ width: 42, height: 24, borderRadius: 999, background: on ? C.text : 'rgba(255,255,255,.14)',
        position: 'relative', transition: 'background .18s', flexShrink: 0 }}>
        <span style={{ position: 'absolute', top: 3, left: on ? 21 : 3, width: 18, height: 18, borderRadius: '50%',
          background: on ? C.onAccent : C.text, transition: 'left .18s' }} />
      </span>
    </button>
  )
}

/* ── States: unavailable, notices, skeletons, spinner ─────────────────────── */
function NotAvailable({ kind, state }: { kind: Kind; state?: HealthService }) {
  // Generic copy — never names the underlying service. `state` distinguishes
  // "not set up at all" from "set up but currently unreachable".
  const unreachable = state?.configured && !state?.reachable
  return (
    <div style={{ marginTop: 8, padding: '46px 28px', borderRadius: 18, ...glassStyle,
      display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', animation: 'up .4s ease both' }}>
      <div style={{ width: 64, height: 64, borderRadius: 18, display: 'grid', placeItems: 'center', marginBottom: 18,
        background: 'rgba(255,255,255,.04)', border: `1px solid ${C.line}` }}>
        <Icon path={unreachable ? Ic.alert : Ic.compass} size={30} stroke={C.dim} sw={1.7} />
      </div>
      <h2 style={{ fontSize: 21, fontWeight: 800, margin: 0 }}>
        {unreachable ? 'Browse is temporarily unavailable' : 'Browsing isn’t set up yet'}
      </h2>
      <p style={{ color: C.dim, fontSize: 14.5, lineHeight: 1.6, maxWidth: 440, marginTop: 10 }}>
        {unreachable
          ? `Browsing is having trouble reaching the catalog right now. ${kind === 'movie' ? 'Movie' : 'Series'} search and downloads will come back on their own.`
          : `Once browsing is configured, you can search ${kind === 'movie' ? 'movies' : 'series'} and add them to your library with a single tap.`}
      </p>
    </div>
  )
}
function ResultsSkeleton({ mobile }: { mobile: boolean }) {
  return (
    <div style={{ display: 'grid', gap: mobile ? 12 : 18, gridTemplateColumns: `repeat(auto-fill, minmax(${mobile ? 150 : 200}px, 1fr))` }}>
      {Array.from({ length: 10 }).map((_, i) => (
        <div key={i}>
          <div style={{ aspectRatio: '2/3', borderRadius: 14, background: C.surface, animation: 'shim 1.3s linear infinite',
            backgroundImage: `linear-gradient(100deg, ${C.surface} 30%, ${C.surface2} 50%, ${C.surface} 70%)`, backgroundSize: '200% 100%' }} />
          <div style={{ height: 12, width: '70%', borderRadius: 6, marginTop: 10, background: C.surface }} />
        </div>
      ))}
    </div>
  )
}
