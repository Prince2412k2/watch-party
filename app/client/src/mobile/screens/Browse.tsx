import { useCallback, useEffect, useRef, useState } from 'react'
import { glass } from '../../glass'
import { navigate } from '../../router'
import { useTorrents, isPausedState } from '../../hooks/useTorrents'
import { T, SANS, MONO, R, EASE, TYPE, SP } from '../theme'
import { Icon, Ic } from '../ui/Icon'
import { Sheet } from '../ui/Sheet'
import { PosterSkeleton } from '../ui/Skeleton'

/**
 * Mobile Browse / Discover (MOBILE-SPEC §3.3). A search-first sticky header
 * (16px field → debounced /search + a Movies/Series segmented toggle) over a
 * poster grid. Tapping a poster opens a detail bottom-sheet; movies get one-tap
 * request + a release picker (nested sheet view), series get the season chooser.
 * Live per-card download status comes from the shared useTorrents poller.
 *
 * Reuses the FindDownload logic/endpoints VERBATIM (search, popular, meta,
 * request, request-season, releases/grab/cancel, downloads/enriched) but is a
 * fresh phone-native presentation — the desktop FindDownload is untouched. The
 * catalog art is REMOTE (TMDB/TVDB), so posters render <img> directly rather
 * than the shell's same-origin Jellyfin <Poster>.
 */

// Warning + monitoring glyphs the shared Ic dictionary doesn't carry (kept local
// so the shared ui/Icon.jsx stays untouched). Same paths the desktop page used.
const P_ALERT = 'M12 9v4m0 4h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z'
const P_SPARK = 'M12 2v4M12 18v4M4.9 4.9l2.8 2.8M16.3 16.3l2.8 2.8M2 12h4M18 12h4M4.9 19.1l2.8-2.8M16.3 7.7l2.8-2.8'

const jget = (url, opts) => fetch(url, { credentials: 'include', ...opts })
const jpost = (url, body) => fetch(url, {
  method: 'POST', credentials: 'include',
  headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
})

/* ── Pure helpers (ported from FindDownload) ──────────────────────────────── */
function posterUrl(images) {
  if (!Array.isArray(images) || images.length === 0) return null
  const p = images.find((i) => i.coverType === 'poster') || images[0]
  return p?.remoteUrl || p?.url || null
}
function backdropUrl(images) {
  if (!Array.isArray(images) || images.length === 0) return null
  const f = images.find((i) => i.coverType === 'fanart') || images.find((i) => i.coverType === 'banner')
  return f?.remoteUrl || f?.url || posterUrl(images)
}
const isAdded = (r) => r?.id != null
const keyOf = (kind, r) => (kind === 'movie' ? `m:${r.tmdbId}` : `s:${r.tvdbId}`)
function outcomeToState(o) {
  switch (o) {
    case 'grabbed': return 'grabbed'
    case 'no_release': return 'no_release'
    case 'search_failed': return 'search_failed'
    case 'monitoring': return 'monitoring'
    case 'exists': return 'added'
    default: return 'error'
  }
}
function ratingOf(r) {
  const rt = r?.ratings
  if (!rt) return null
  const v = (typeof rt.value === 'number' ? rt.value : null) ?? rt.imdb?.value ?? rt.tmdb?.value ?? null
  return typeof v === 'number' && v > 0 ? v : null
}
function fmtMins(m) {
  if (!m || !Number.isFinite(m) || m <= 0) return null
  const h = Math.floor(m / 60)
  return h > 0 ? `${h}h ${m % 60}m` : `${m}m`
}
const normTitle = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
function matchTorrent(title, torrents) {
  const n = normTitle(title)
  if (!n || n.length < 2 || !Array.isArray(torrents)) return null
  return torrents.find((t) => normTitle(t.name || t.title).includes(n)) || null
}
function fmtSize(bytes) {
  if (bytes == null || !Number.isFinite(bytes) || bytes <= 0) return '—'
  const u = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0, n = bytes
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
  return `${n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)} ${u[i]}`
}
const fmtSpeed = (bps) => (bps == null || !Number.isFinite(bps) || bps <= 0) ? '0 B/s' : `${fmtSize(bps)}/s`
function fmtEta(secs) {
  if (secs == null || !Number.isFinite(secs) || secs < 0 || secs >= 8640000) return '∞'
  if (secs === 0) return '—'
  const d = Math.floor(secs / 86400), h = Math.floor((secs % 86400) / 3600)
  const m = Math.floor((secs % 3600) / 60), s = Math.floor(secs % 60)
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m`
  return `${s}s`
}

/* Session caches (screens remount on tab switch — cache in module scope so the
 * popular feed + profile/folder meta survive a re-entry). One in-flight promise
 * per key; transient failures/empties aren't pinned. Mirrors FindDownload. */
const metaCache = {}
function loadMeta(service) {
  if (metaCache[service]) return metaCache[service]
  const reqs = [
    jget(`/api/servarr/${service}/quality-profiles`),
    jget(`/api/servarr/${service}/root-folders`),
  ]
  if (service === 'sonarr') reqs.push(jget('/api/servarr/sonarr/language-profiles'))
  const p = Promise.all(reqs).then(async (rs) => {
    for (const r of rs) if (!r.ok) throw new Error('meta')
    const [profiles, rootFolders, langProfiles] = await Promise.all(rs.map((r) => r.json()))
    return { profiles: profiles || [], rootFolders: rootFolders || [], langProfiles: langProfiles || [] }
  }).catch((e) => { delete metaCache[service]; throw e })
  metaCache[service] = p
  return p
}
const popularCache = {}
function loadPopular(service) {
  if (popularCache[service]) return popularCache[service]
  const p = jget(`/api/servarr/${service}/popular`)
    .then((r) => (r.ok ? r.json() : Promise.reject(r)))
    .then((d) => {
      const val = { source: d?.source || 'curated', items: Array.isArray(d?.items) ? d.items : [] }
      if (!val.items.length) delete popularCache[service]
      return val
    })
    .catch((e) => { delete popularCache[service]; throw e })
  popularCache[service] = p
  return p
}

// Deep-linkable ?q=/?type= (custom router → read/write location directly).
function readParams() {
  const p = new URLSearchParams(window.location.search)
  return { kind: p.get('type') === 'series' ? 'series' : 'movie', term: p.get('q') || '' }
}

/* ── Screen ────────────────────────────────────────────────────────────────*/
export default function Browse() {
  const [kind, setKind] = useState(() => readParams().kind)
  const [term, setTerm] = useState(() => readParams().term)
  const [results, setResults] = useState([])
  const [loading, setLoading] = useState(() => !!readParams().term.trim())
  const [searchError, setSearchError] = useState('')
  const [hasSearched, setHasSearched] = useState(false)

  const [health, setHealth] = useState(null)
  const [healthLoading, setHealthLoading] = useState(true)

  // One detail sheet, two modes: 'detail' | 'releases' (movie release picker).
  const [detail, setDetail] = useState(null)   // retained through the close anim
  const [sheetOpen, setSheetOpen] = useState(false)
  const [mode, setMode] = useState('detail')

  // Per-item request state so cards/detail flip without a re-search.
  const [addState, setAddState] = useState({})

  const service = kind === 'movie' ? 'radarr' : 'sonarr'
  const svcState = health?.services?.[service]
  const svcReady = svcState?.configured && svcState?.reachable

  const qbReady = !!health?.services?.qbittorrent?.configured && !!health?.services?.qbittorrent?.reachable
  const dl = useTorrents(qbReady)
  const torrents = dl.list

  useEffect(() => {
    setHealthLoading(true)
    jget('/api/servarr/health')
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then(setHealth)
      .catch(() => setHealth({ services: {} }))
      .finally(() => setHealthLoading(false))
  }, [])

  // Reflect query + tab into the URL (replaceState — typing must not spam history).
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

  // Debounced search with AbortController; blank term clears to the popular feed.
  const abortRef = useRef(null)
  const runSearch = useCallback((q, k) => {
    const query = q.trim()
    abortRef.current?.abort()
    if (!query) { setResults([]); setLoading(false); setHasSearched(false); setSearchError(''); return }
    const svc = k === 'movie' ? 'radarr' : 'sonarr'
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setLoading(true); setSearchError('')
    fetch(`/api/servarr/${svc}/search?term=${encodeURIComponent(query)}`, { credentials: 'include', signal: ctrl.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then((data) => { setResults(Array.isArray(data) ? data : []); setHasSearched(true) })
      .catch((e) => { if (e?.name !== 'AbortError') { setResults([]); setHasSearched(true); setSearchError('Something went wrong. Try again.') } })
      .finally(() => { if (abortRef.current === ctrl) setLoading(false) })
  }, [])

  useEffect(() => {
    if (!svcReady) return
    const t = setTimeout(() => runSearch(term, kind), 400)
    return () => clearTimeout(t)
  }, [term, kind, svcReady, runSearch])

  const stateFor = (r) => (isAdded(r) ? 'added' : addState[keyOf(kind, r)]) || null

  // One-tap request — cached-meta defaults → server-authoritative grab-or-remove.
  const oneTapAdd = useCallback((r) => {
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
        return jpost(`/api/servarr/${svc}/request`, body).then((res) => (res.ok ? res.json() : Promise.reject(res)))
      })
      .then((out) => setAddState((s) => ({ ...s, [key]: outcomeToState(out?.outcome) })))
      .catch(() => setAddState((s) => ({ ...s, [key]: 'error' })))
  }, [kind])

  const openDetail = (r) => { setDetail(r); setMode('detail'); setSheetOpen(true) }
  const closeSheet = () => setSheetOpen(false)  // keep `detail` for the exit anim

  // Release picker grabbed a specific release → behaves like a one-tap grab.
  const onReleaseGrabbed = (r) => {
    setAddState((s) => ({ ...s, [keyOf(kind, r)]: 'grabbed' }))
    setSheetOpen(false)
  }

  const sheetTitle = mode === 'releases' ? 'Choose a release' : (detail?.title || '')

  return (
    <>
      <Header
        kind={kind} setKind={setKind} term={term} setTerm={setTerm}
        loading={loading} disabled={!svcReady && !healthLoading}
        onSubmit={() => runSearch(term, kind)}
      />

      <div style={{ padding: `${SP.md}px 16px 8px` }}>
        {healthLoading ? (
          <SkeletonGrid />
        ) : !svcReady ? (
          <NotAvailable kind={kind} state={svcState} />
        ) : searchError ? (
          <StateCard icon={P_ALERT} tone="error" title={searchError} />
        ) : loading ? (
          <SkeletonGrid />
        ) : !hasSearched ? (
          <PopularSection kind={kind} torrents={torrents} stateFor={stateFor} onOpen={openDetail} onPick={setTerm} />
        ) : results.length === 0 ? (
          <StateCard icon={Ic.search} title="No matches" body={`Nothing found for “${term.trim()}”. Try a different title.`} />
        ) : (
          <Grid results={results} kind={kind} torrents={torrents} stateFor={stateFor} onOpen={openDetail} />
        )}
      </div>

      <Sheet open={sheetOpen} onClose={closeSheet} title={sheetTitle}>
        {detail && (mode === 'releases' ? (
          <ReleasePickerBody item={detail} onBack={() => setMode('detail')} onGrabbed={onReleaseGrabbed} />
        ) : (
          <DetailBody
            item={detail} kind={kind} state={stateFor(detail)} torrents={torrents}
            onDownload={() => oneTapAdd(detail)}
            onSeeSources={() => setMode('releases')}
          />
        ))}
      </Sheet>
    </>
  )
}

/* ── Sticky search header (title + segmented toggle, then the 16px field) ──── */
function Header({ kind, setKind, term, setTerm, loading, disabled, onSubmit }) {
  const [focus, setFocus] = useState(false)
  return (
    <header
      style={{
        ...glass('medium', { refract: true }),
        position: 'sticky', top: 0, zIndex: 20,
        borderRadius: 0, borderLeft: 'none', borderRight: 'none', borderTop: 'none',
        paddingTop: `calc(var(--sa-t) + 10px)`, paddingBottom: 12,
        paddingLeft: `calc(var(--sa-l) + 16px)`, paddingRight: `calc(var(--sa-r) + 16px)`,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, minHeight: 44 }}>
        <div style={{ ...TYPE.title, color: T.text, flex: 1, minWidth: 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          Browse
        </div>
        <Segmented kind={kind} setKind={setKind} />
      </div>

      <form
        onSubmit={(e) => { e.preventDefault(); e.currentTarget.querySelector('input')?.blur(); onSubmit() }}
        style={{ position: 'relative', display: 'flex', alignItems: 'center', marginTop: 12 }}
      >
        <span style={{ position: 'absolute', left: 14, display: 'grid', placeItems: 'center', color: focus ? T.text : T.faint, pointerEvents: 'none', transition: `color .15s ${EASE}` }}>
          <Icon path={Ic.search} size={19} />
        </span>
        <input
          value={term}
          onChange={(e) => setTerm(e.target.value)}
          onFocus={() => setFocus(true)}
          onBlur={() => setFocus(false)}
          disabled={disabled}
          type="text" inputMode="search" enterKeyHint="search"
          autoCapitalize="none" autoCorrect="off" spellCheck={false}
          placeholder={disabled ? 'Search is unavailable right now' : `Search ${kind === 'movie' ? 'movies' : 'series'}…`}
          style={{
            width: '100%', height: 48, padding: '0 46px', borderRadius: R.md, outline: 'none',
            color: T.text, background: 'rgba(255,255,255,.05)',
            border: `1px solid ${focus ? T.text : T.line}`,
            boxShadow: focus ? '0 0 0 3px rgba(255,255,255,.12)' : 'none',
            transition: `border .15s ${EASE}, box-shadow .15s ${EASE}`,
            opacity: disabled ? 0.55 : 1, ...TYPE.input,
          }}
        />
        {loading ? (
          <span style={{ position: 'absolute', right: 15 }}><Spinner size={18} /></span>
        ) : term ? (
          <button
            type="button" aria-label="Clear search" className="mob-press"
            onClick={() => setTerm('')}
            style={{
              position: 'absolute', right: 6, width: 40, height: 40, borderRadius: 999, border: 'none',
              background: 'transparent', color: T.dim, display: 'grid', placeItems: 'center', cursor: 'pointer',
            }}
          >
            <Icon path={Ic.close} size={18} sw={2} />
          </button>
        ) : null}
      </form>
    </header>
  )
}

// Movies / Series segmented control — white active pill (Sen-Player primary).
function Segmented({ kind, setKind }) {
  const seg = (val, label, icon) => {
    const active = kind === val
    return (
      <button
        onClick={() => setKind(val)} aria-pressed={active} className="mob-press"
        style={{
          display: 'inline-flex', alignItems: 'center', gap: 6, height: 40, padding: '0 12px',
          border: 'none', borderRadius: 999, cursor: 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 700,
          color: active ? T.onLight : T.dim, background: active ? T.primary : 'transparent',
          transition: `background .18s ${EASE}, color .18s ${EASE}`,
        }}
      >
        <Icon path={icon} size={15} sw={active ? 2.2 : 1.8} />{label}
      </button>
    )
  }
  return (
    <div style={{ display: 'inline-flex', gap: 3, padding: 3, borderRadius: 999, background: 'rgba(255,255,255,.05)', border: `1px solid ${T.line}`, flex: '0 0 auto' }}>
      {seg('movie', 'Movies', Ic.film)}
      {seg('series', 'Series', Ic.tv)}
    </div>
  )
}

/* ── Remote catalog poster (TMDB/TVDB art — direct <img>, graceful fallback) ── */
function RemotePoster({ images, alt, style, useBackdrop, radius }) {
  const url = useBackdrop ? backdropUrl(images) : posterUrl(images)
  const [broken, setBroken] = useState(false)
  if (!url || broken) {
    return (
      <div style={{ ...style, display: 'grid', placeItems: 'center', background: T.surface2, borderRadius: radius }}>
        <Icon path={Ic.film} size={30} stroke={T.faint} sw={1.4} />
      </div>
    )
  }
  return (
    <img src={url} alt={alt || ''} referrerPolicy="no-referrer" loading="lazy"
      onError={() => setBroken(true)} style={{ ...style, objectFit: 'cover', borderRadius: radius }} />
  )
}

/* ── Poster grid + card ──────────────────────────────────────────────────── */
function Grid({ results, kind, torrents, stateFor, onOpen }) {
  return (
    <div style={{ display: 'grid', gap: 14, gridTemplateColumns: 'repeat(auto-fill, minmax(118px, 1fr))', animation: 'up .4s ease both' }}>
      {results.map((r, i) => (
        <Card key={(r.tmdbId || r.tvdbId || r.titleSlug || i) + ''} r={r} kind={kind}
          state={stateFor(r)} torrent={matchTorrent(r.title, torrents)} onOpen={() => onOpen(r)} />
      ))}
    </div>
  )
}

function Card({ r, state, torrent, onOpen }) {
  const active = torrent && !isPausedState(torrent.state)
  const pct = torrent ? Math.max(0, Math.min(100, Math.round((torrent.progress || 0) * 100))) : 0
  const torrentDownloading = active && pct < 100
  const downloading = state === 'grabbed' || torrentDownloading
  const searching = state === 'searching' && !torrentDownloading
  const monitoring = state === 'monitoring' && !torrentDownloading
  const added = state === 'added' && !downloading
  const rating = ratingOf(r)
  const showOverlay = downloading || searching || monitoring

  return (
    <button
      onClick={onOpen} aria-label={r.title} className="mob-press"
      style={{ display: 'flex', flexDirection: 'column', gap: 8, border: 'none', background: 'transparent', padding: 0, textAlign: 'left', cursor: 'pointer', color: T.text }}
    >
      <div style={{ position: 'relative', width: '100%', aspectRatio: '2 / 3', borderRadius: R.md, overflow: 'hidden', background: T.surface, border: `1px solid ${T.line}`, boxShadow: '0 8px 22px rgba(0,0,0,.4)' }}>
        <RemotePoster images={r.images} alt={r.title} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }} />

        {rating != null && (
          <div style={{ position: 'absolute', top: 7, left: 7, display: 'inline-flex', alignItems: 'center', gap: 4, padding: '2px 7px', borderRadius: 8, fontFamily: MONO, fontSize: 11, fontWeight: 700, color: '#fff', background: 'rgba(0,0,0,.6)' }}>
            <Icon path={Ic.star} size={11} fill="#f5c518" stroke="none" />{rating.toFixed(1)}
          </div>
        )}

        {added && (
          <div style={{ position: 'absolute', top: 7, right: 7, width: 24, height: 24, borderRadius: '50%', display: 'grid', placeItems: 'center', background: 'rgba(0,0,0,.6)' }}>
            <Icon path={Ic.check} size={14} stroke={T.text} sw={3} />
          </div>
        )}

        {showOverlay && (
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: 9, background: 'linear-gradient(0deg, rgba(0,0,0,.92) 12%, rgba(0,0,0,.35) 60%, transparent)' }}>
            {downloading ? (
              <>
                <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontFamily: MONO, fontSize: 10.5, fontWeight: 700, color: T.text, marginBottom: 5 }}>
                  <LiveDot color={T.brand} size={6} />{active ? `${pct}%` : 'Starting'}
                </div>
                <div style={{ height: 4, borderRadius: 999, background: 'rgba(255,255,255,.16)', overflow: 'hidden' }}>
                  <div style={{ width: active ? `${pct}%` : '18%', height: '100%', borderRadius: 999, background: T.text, transition: 'width .4s ease' }} />
                </div>
              </>
            ) : searching ? (
              <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontFamily: MONO, fontSize: 10.5, fontWeight: 700, color: T.dim }}>
                <span style={{ width: 6, height: 6, borderRadius: '50%', background: T.faint, flexShrink: 0 }} />Finding…
              </div>
            ) : (
              <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 11, fontWeight: 700, color: T.dim }}>
                <Icon path={P_SPARK} size={12} sw={2} />Monitoring
              </div>
            )}
          </div>
        )}
      </div>

      <div style={{ minWidth: 0 }}>
        <div style={{ ...TYPE.body, fontWeight: 700, color: T.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.title}</div>
        <div style={{ fontFamily: MONO, fontSize: 11, color: T.faint, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {[r.year, r.network].filter(Boolean).join(' · ') || '—'}
        </div>
      </div>
    </button>
  )
}

/* ── Popular feed (shown when there's no query) ──────────────────────────── */
const SUGGESTED = {
  movie: ['Inception', 'Dune', 'Parasite', 'Oppenheimer', 'The Matrix'],
  series: ['Breaking Bad', 'The Last of Us', 'Severance', 'Chernobyl', 'Arcane'],
}
function PopularSection({ kind, torrents, stateFor, onOpen, onPick }) {
  const service = kind === 'movie' ? 'radarr' : 'sonarr'
  const [state, setState] = useState({ loading: true, error: false, items: [], source: 'curated' })

  useEffect(() => {
    let cancel = false
    setState((s) => ({ ...s, loading: true, error: false }))
    loadPopular(service)
      .then((d) => { if (!cancel) setState({ loading: false, error: false, items: d.items, source: d.source }) })
      .catch(() => { if (!cancel) setState({ loading: false, error: true, items: [], source: 'curated' }) })
    return () => { cancel = true }
  }, [service])

  if (state.loading) return <SkeletonGrid />
  if (state.error || state.items.length === 0) return <SuggestedSearches kind={kind} onPick={onPick} />

  const label = state.source === 'importlist' ? 'Popular right now' : 'Popular picks'
  return (
    <div style={{ animation: 'up .4s ease both' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 9, marginBottom: SP.md }}>
        <h2 style={{ ...TYPE.title, color: T.text, margin: 0 }}>{label}</h2>
        <span style={{ fontFamily: MONO, fontSize: 11.5, color: T.faint, letterSpacing: '.06em' }}>{kind === 'movie' ? 'MOVIES' : 'SERIES'}</span>
      </div>
      <Grid results={state.items} kind={kind} torrents={torrents} stateFor={stateFor} onOpen={onOpen} />
    </div>
  )
}
function SuggestedSearches({ kind, onPick }) {
  const list = SUGGESTED[kind] || []
  return (
    <div style={{ marginTop: 4, padding: '40px 24px', borderRadius: R.lg, border: `1px solid ${T.line}`, background: 'rgba(255,255,255,.02)', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', animation: 'up .4s ease both' }}>
      <span style={{ width: 54, height: 54, borderRadius: 16, display: 'grid', placeItems: 'center', marginBottom: 14, background: T.surface, color: T.dim, border: `1px solid ${T.line}` }}>
        <Icon path={Ic.search} size={26} />
      </span>
      <h2 style={{ ...TYPE.title, color: T.text, margin: 0 }}>Find something to watch</h2>
      <p style={{ ...TYPE.body, color: T.dim, maxWidth: 340, marginTop: 8 }}>
        Search {kind === 'movie' ? 'movies' : 'series'} by title, or start with one of these.
      </p>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'center', marginTop: 16 }}>
        {list.map((t) => (
          <button key={t} onClick={() => onPick(t)} className="mob-press"
            style={{ minHeight: 40, padding: '0 16px', borderRadius: 999, cursor: 'pointer', fontFamily: SANS, fontSize: 13.5, fontWeight: 600, color: T.text, background: 'rgba(255,255,255,.05)', border: `1px solid ${T.line}` }}>
            {t}
          </button>
        ))}
      </div>
    </div>
  )
}

/* ── Detail sheet body ───────────────────────────────────────────────────── */
function DetailBody({ item, kind, state, torrents, onDownload, onSeeSources }) {
  const rating = ratingOf(item)
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
    fmtMins(item.runtime),
    item.certification,
    kind === 'series' && item.seasonCount != null ? `${item.seasonCount} season${item.seasonCount === 1 ? '' : 's'}` : null,
    kind === 'series' ? item.network : null,
    kind === 'series' ? item.status : null,
  ].filter(Boolean)

  return (
    <div style={{ paddingBottom: 8 }}>
      {/* Full-bleed backdrop (counter the sheet's 16px side padding) */}
      <div style={{ position: 'relative', margin: '0 -16px 16px', height: 176, overflow: 'hidden' }}>
        <RemotePoster images={item.images} useBackdrop alt={item.title}
          style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectPosition: 'top center' }} />
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(0deg, rgba(0,0,0,.9) 2%, rgba(0,0,0,.3) 55%, transparent)' }} />
        <div style={{ position: 'absolute', left: 16, right: 16, bottom: 12 }}>
          <div style={{ fontFamily: MONO, fontSize: 10.5, color: T.dim, letterSpacing: '.14em', marginBottom: 5 }}>{kind === 'movie' ? 'MOVIE' : 'SERIES'}</div>
          <h1 style={{ ...TYPE.display, fontSize: 25, color: '#fff', margin: 0 }}>{item.title}</h1>
        </div>
      </div>

      {/* Rating + genres */}
      {(rating != null || genres.length > 0) && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', marginBottom: 8, fontSize: 14, fontWeight: 600 }}>
          {rating != null && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: T.text }}>
              <Icon path={Ic.star} size={15} fill="#f5c518" stroke="none" />{rating.toFixed(1)}
            </span>
          )}
          {genres.slice(0, 3).map((g) => <span key={g} style={{ color: T.dim }}>{g}</span>)}
        </div>
      )}

      {infoLine.length > 0 && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap', marginBottom: 14, fontFamily: MONO, fontSize: 12, color: T.dim }}>
          {infoLine.map((v, i) => <span key={i}>{v}</span>)}
        </div>
      )}

      {/* Primary action area */}
      {kind === 'series' ? (
        <SeasonChooserBody item={item} onWholeSeriesFallback={onDownload} />
      ) : downloading ? (
        <DownloadProgress torrent={torrent} active={active} pct={pct} />
      ) : searching ? (
        <StatusLine tone={T.dim} title="Added — finding a release…"
          body="It’s in your library. We’re looking for a release to download right now." />
      ) : noRelease ? (
        <ActionState tone={T.dim} icon={P_ALERT} title="No release available right now" note="Try again in a little while." onAction={onDownload} actionLabel="Try again" />
      ) : searchFailed ? (
        <ActionState tone={T.dim} icon={P_ALERT} title="Couldn’t check right now" note="Please try again." onAction={onDownload} actionLabel="Retry" />
      ) : state === 'added' ? (
        <div>
          <InLibraryChip />
          <SecondaryBtn icon={Ic.search} label="Choose a release" onClick={onSeeSources} style={{ marginTop: 12 }} />
        </div>
      ) : state === 'error' ? (
        <ActionState tone={T.red} icon={P_ALERT} title="Something went wrong" note="Please try the download again." onAction={onDownload} actionLabel="Retry download" />
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <PrimaryBtn icon={Ic.download} label="Download" onClick={onDownload} />
          <SecondaryBtn icon={Ic.search} label="See all sources" onClick={onSeeSources} />
        </div>
      )}

      {item.overview && (
        <p style={{ ...TYPE.body, color: 'rgba(241,243,246,.85)', marginTop: 18, display: '-webkit-box', WebkitLineClamp: 8, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
          {item.overview}
        </p>
      )}
    </div>
  )
}

function DownloadProgress({ torrent, active, pct }) {
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 7, fontFamily: MONO, fontSize: 12.5, fontWeight: 700, color: T.text, marginBottom: 8 }}>
        <LiveDot color={T.brand} size={8} />{active ? `Downloading · ${pct}%` : 'Starting download…'}
      </div>
      <div style={{ height: 8, borderRadius: 999, background: 'rgba(255,255,255,.12)', overflow: 'hidden' }}>
        <div style={{ width: active ? `${pct}%` : '15%', height: '100%', borderRadius: 999, background: T.text, transition: 'width .4s ease' }} />
      </div>
      {active && (
        <div style={{ display: 'flex', gap: 14, marginTop: 8, fontFamily: MONO, fontSize: 12, color: T.dim, flexWrap: 'wrap' }}>
          <span>↓ {fmtSpeed(torrent.dlspeed)}</span>
          <span>ETA {pct >= 100 ? '—' : fmtEta(torrent.eta)}</span>
          <span>Seeds {torrent.numSeeds ?? 0}</span>
        </div>
      )}
      <SecondaryBtn icon={Ic.download} label="Track in Downloads" onClick={() => navigate('/downloads')} style={{ marginTop: 14 }} />
    </div>
  )
}

/* ── Season chooser (series) ─────────────────────────────────────────────── */
function SeasonChooserBody({ item, onWholeSeriesFallback }) {
  const seasons = Array.isArray(item.seasons) ? item.seasons : []
  const real = seasons.filter((s) => s.seasonNumber >= 1).sort((a, b) => a.seasonNumber - b.seasonNumber)
  const specials = seasons.filter((s) => s.seasonNumber === 0)
  const added = isAdded(item)

  const [meta, setMeta] = useState({ loading: true, error: '' })
  const [req, setReq] = useState({})

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
  }, [item])

  const request = (nums) => {
    if (!nums.length) return
    setReq((s) => { const n = { ...s }; for (const k of nums) n[k] = 'requesting'; return n })
    loadMeta('sonarr')
      .then((m) => {
        const qualityProfileId = m.profiles?.[0]?.id
        const rootFolderPath = m.rootFolders?.[0]?.path
        const languageProfileId = m.langProfiles?.[0]?.id
        if (qualityProfileId == null || !rootFolderPath) throw new Error('meta')
        return jpost('/api/servarr/sonarr/request-season', { series: item, seasons: nums, qualityProfileId, languageProfileId, rootFolderPath })
      })
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then(() => setReq((s) => { const n = { ...s }; for (const k of nums) n[k] = 'requested'; return n }))
      .catch(() => setReq((s) => { const n = { ...s }; for (const k of nums) n[k] = 'error'; return n }))
  }

  const stateOf = (s) => req[s.seasonNumber] || (added && s.monitored ? 'monitored' : 'idle')
  const anyRequesting = Object.values(req).some((v) => v === 'requesting')

  if (real.length === 0 && specials.length === 0) {
    return <PrimaryBtn icon={Ic.download} label="Download series" onClick={onWholeSeriesFallback} />
  }
  if (meta.loading) {
    return <div style={{ display: 'flex', alignItems: 'center', gap: 10, color: T.dim, ...TYPE.body }}><Spinner size={18} />Loading seasons…</div>
  }
  if (meta.error) {
    return <ActionState tone={T.dim} icon={P_ALERT} title={meta.error} />
  }

  const allReal = real.map((s) => s.seasonNumber)
  const allMonitored = real.length > 0 && real.every((s) => stateOf(s) === 'monitored' || stateOf(s) === 'requested')

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12 }}>
        <div style={{ ...TYPE.headline, color: T.text, flex: 1 }}>Choose seasons</div>
        {real.length > 1 && (
          <button onClick={() => request(allReal)} disabled={anyRequesting || allMonitored} className="mob-press"
            style={{ display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 40, padding: '0 15px', borderRadius: 999, border: 'none',
              cursor: anyRequesting || allMonitored ? 'default' : 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 700,
              background: allMonitored ? 'rgba(255,255,255,.12)' : T.primary, color: allMonitored ? T.text : T.onLight, opacity: anyRequesting && !allMonitored ? 0.6 : 1 }}>
            <Icon path={allMonitored ? Ic.check : Ic.download} size={15} sw={2.3} />All seasons
          </button>
        )}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {real.map((s) => <SeasonRow key={s.seasonNumber} season={s} state={stateOf(s)} disabled={anyRequesting} onRequest={() => request([s.seasonNumber])} />)}
      </div>

      {specials.length > 0 && (
        <div style={{ marginTop: 12 }}>
          <div style={{ fontFamily: MONO, fontSize: 10.5, color: T.faint, letterSpacing: '.14em', marginBottom: 8 }}>SPECIALS</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {specials.map((s) => <SeasonRow key={s.seasonNumber} season={s} state={stateOf(s)} disabled={anyRequesting} specials onRequest={() => request([s.seasonNumber])} />)}
          </div>
        </div>
      )}

      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 7, marginTop: 14, fontSize: 12, color: T.faint, lineHeight: 1.5 }}>
        <Icon path={P_SPARK} size={14} sw={1.8} stroke={T.faint} style={{ flexShrink: 0, marginTop: 1 }} />
        A requested season is monitored and searched — episodes download on their own as they’re found.
      </div>
    </div>
  )
}
function SeasonRow({ season, state, disabled, specials, onRequest }) {
  const label = season.seasonNumber === 0 ? 'Specials' : `Season ${season.seasonNumber}`
  const count = season.totalEpisodeCount > 0 ? `${season.totalEpisodeCount} episode${season.totalEpisodeCount === 1 ? '' : 's'}` : null

  const right = (() => {
    if (state === 'requesting') return <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, fontSize: 12.5, fontWeight: 700, color: T.dim }}><Spinner size={15} />Requesting…</span>
    if (state === 'requested') return <Pill icon={P_SPARK} label="Searching…" />
    if (state === 'monitored') return (
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
        <Pill icon={Ic.check} label="Monitoring" />
        <IconBtn onClick={onRequest} disabled={disabled} label="Search this season again"><Icon path={Ic.search} size={16} sw={2} /></IconBtn>
      </span>
    )
    if (state === 'error') return (
      <button onClick={onRequest} disabled={disabled} className="mob-press"
        style={{ display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 40, padding: '0 14px', borderRadius: 999, border: `1px solid rgba(255,107,107,.5)`, cursor: disabled ? 'default' : 'pointer', fontFamily: SANS, fontSize: 12.5, fontWeight: 700, background: 'rgba(220,60,60,.14)', color: T.red, opacity: disabled ? 0.6 : 1 }}>
        <Icon path={P_ALERT} size={14} sw={2} />Retry
      </button>
    )
    return (
      <button onClick={onRequest} disabled={disabled} className="mob-press"
        style={{ display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 40, padding: '0 15px', borderRadius: 999, border: 'none', cursor: disabled ? 'default' : 'pointer', fontFamily: SANS, fontSize: 12.5, fontWeight: 700, background: T.primary, color: T.onLight, opacity: disabled ? 0.6 : 1 }}>
        <Icon path={Ic.download} size={15} sw={2.3} />Get
      </button>
    )
  })()

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 14px', borderRadius: R.sm, border: `1px solid ${T.line}`, background: 'rgba(255,255,255,.03)', opacity: specials ? 0.82 : 1 }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: SANS, fontSize: 14, fontWeight: 700, color: T.text }}>{label}</div>
        <div style={{ fontFamily: MONO, fontSize: 11.5, color: T.faint, marginTop: 2 }}>{count || (specials ? 'Extras & one-offs' : '—')}</div>
      </div>
      <div style={{ flexShrink: 0 }}>{right}</div>
    </div>
  )
}

/* ── Release picker (movies) — sheet sub-view ────────────────────────────── */
function ReleasePickerBody({ item, onBack, onGrabbed }) {
  const [meta, setMeta] = useState({ loading: true, error: '' })
  const [data, setData] = useState(null)
  const [nonce, setNonce] = useState(0)
  const [grabbing, setGrabbing] = useState(null)
  const [grabError, setGrabError] = useState('')

  const life = useRef({ movieId: null, createdByPicker: false, settled: false })
  const cleanup = useCallback(() => {
    const { movieId, createdByPicker, settled } = life.current
    if (settled) return
    life.current.settled = true
    if (createdByPicker && movieId != null) jpost('/api/servarr/radarr/releases/cancel', { movieId, createdByPicker: true }).catch(() => {})
  }, [])

  useEffect(() => {
    let cancelled = false
    setMeta({ loading: true, error: '' }); setGrabError('')
    ;(async () => {
      const existing = life.current.movieId
      let createdByPicker = life.current.createdByPicker
      let body
      if (existing != null) body = { movieId: existing }
      else if (isAdded(item)) { body = { movieId: item.id }; createdByPicker = false }
      else {
        const m = await loadMeta('radarr')
        const qualityProfileId = m.profiles?.[0]?.id
        const rootFolderPath = m.rootFolders?.[0]?.path
        if (qualityProfileId == null || !rootFolderPath) throw new Error('meta')
        body = { movie: item, qualityProfileId, rootFolderPath }
      }
      const res = await jpost('/api/servarr/radarr/releases', body)
      if (!res.ok) throw new Error('releases')
      const d = await res.json()
      return { d, createdByPicker: existing != null ? createdByPicker : !!d.createdByPicker }
    })()
      .then(({ d, createdByPicker }) => {
        if (cancelled) {
          if (createdByPicker && d?.movieId != null) jpost('/api/servarr/radarr/releases/cancel', { movieId: d.movieId, createdByPicker: true }).catch(() => {})
          return
        }
        life.current = { movieId: d.movieId, createdByPicker, settled: false }
        setData(d); setMeta({ loading: false, error: '' })
      })
      .catch(() => { if (!cancelled) setMeta({ loading: false, error: 'Couldn’t load sources right now. Please try again.' }) })
    return () => { cancelled = true }
  }, [item, nonce])

  useEffect(() => cleanup, [cleanup])

  const grab = (rel) => {
    if (grabbing) return
    setGrabbing(rel.guid); setGrabError('')
    jpost('/api/servarr/radarr/grab', { movieId: data?.movieId, guid: rel.guid, indexerId: rel.indexerId })
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then(() => { life.current.settled = true; onGrabbed(item) })
      .catch(() => { setGrabbing(null); setGrabError('Couldn’t start that download. Try another source.') })
  }

  const releases = data?.releases || []

  return (
    <div style={{ paddingBottom: 8 }}>
      <button onClick={onBack} className="mob-press"
        style={{ display: 'inline-flex', alignItems: 'center', gap: 7, minHeight: 40, padding: '0 4px', marginBottom: 10, border: 'none', background: 'transparent', color: T.dim, fontFamily: SANS, fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>
        <Icon path={Ic.chevL} size={18} sw={2} />Back
      </button>
      <div style={{ ...TYPE.body, color: T.dim, marginBottom: 12 }}>{item.title}{item.year ? ` · ${item.year}` : ''}</div>

      {meta.loading ? (
        <div style={{ padding: '30px 0', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
          <Spinner size={26} />
          <div style={{ ...TYPE.body, color: T.dim, textAlign: 'center', maxWidth: 300 }}>Searching every source for the healthiest release. This can take up to a minute.</div>
        </div>
      ) : meta.error ? (
        <ActionState tone={T.red} icon={P_ALERT} title={meta.error} onAction={() => setNonce((n) => n + 1)} actionLabel="Try again" />
      ) : data?.searchFailed ? (
        <ActionState tone={T.dim} icon={P_ALERT} title="Couldn’t reach the sources just now." note="Please try again." onAction={() => setNonce((n) => n + 1)} actionLabel="Try again" />
      ) : releases.length === 0 ? (
        <ActionState tone={T.dim} icon={Ic.search} title="No sources found for this title right now." />
      ) : (
        <>
          {grabError && <div style={{ marginBottom: 10 }}><ActionState tone={T.red} icon={P_ALERT} title={grabError} /></div>}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {releases.map((rel) => <ReleaseRow key={rel.guid} rel={rel} grabbing={grabbing} onGrab={() => grab(rel)} />)}
          </div>
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 7, marginTop: 12, fontSize: 12, color: T.faint, lineHeight: 1.5 }}>
            <Icon path={P_ALERT} size={13} sw={1.8} stroke={T.faint} style={{ flexShrink: 0, marginTop: 1 }} />
            Greyed rows were skipped by the auto-picker for the reason shown.
          </div>
        </>
      )}
    </div>
  )
}
function ReleaseRow({ rel, grabbing, onGrab }) {
  const busy = grabbing === rel.guid
  const anyBusy = !!grabbing
  const rejected = rel.rejected
  const seeds = rel.seeders
  const seedColor = seeds == null ? T.faint : seeds > 0 ? T.text : T.red
  const reason = rejected ? (rel.rejections?.[0] || 'Skipped by the quality profile') : null

  return (
    <div style={{ padding: '11px 13px', borderRadius: R.sm, border: `1px solid ${T.line}`, background: rejected ? 'rgba(255,255,255,.02)' : 'rgba(255,255,255,.03)', opacity: rejected ? 0.6 : 1 }}>
      <div title={rel.title} style={{ fontFamily: MONO, fontSize: 12, color: T.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{rel.title}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap', marginTop: 6, fontFamily: MONO, fontSize: 11.5 }}>
        {rel.quality && <span style={{ padding: '2px 8px', borderRadius: 7, background: 'rgba(255,255,255,.07)', color: T.dim, fontWeight: 700 }}>{rel.quality}</span>}
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: seedColor, fontWeight: 700 }}>
          <span style={{ width: 7, height: 7, borderRadius: '50%', background: seedColor }} />
          {seeds == null ? '—' : seeds} seed{seeds === 1 ? '' : 's'}
        </span>
        <span style={{ color: T.dim }}>{fmtSize(rel.size)}</span>
        {rel.indexer && <span title={rel.indexer} style={{ color: T.faint, maxWidth: 130, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{rel.indexer}</span>}
      </div>
      {reason ? (
        <div title={rel.rejections?.join(' · ')} style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 8, fontSize: 12, color: T.dim, fontWeight: 600 }}>
          <Icon path={P_ALERT} size={13} sw={2} /><span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{reason}</span>
        </div>
      ) : (
        <button onClick={onGrab} disabled={anyBusy} className="mob-press"
          style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7, width: '100%', minHeight: 44, marginTop: 10, borderRadius: R.sm, border: 'none', cursor: anyBusy ? 'default' : 'pointer', fontFamily: SANS, fontSize: 14, fontWeight: 700, background: T.primary, color: T.onLight, opacity: anyBusy && !busy ? 0.45 : 1 }}>
          {busy ? <Spinner size={16} dark /> : <Icon path={Ic.download} size={16} sw={2.3} />}{busy ? 'Starting…' : 'Download this'}
        </button>
      )}
    </div>
  )
}

/* ── Shared bits ─────────────────────────────────────────────────────────── */
function PrimaryBtn({ icon, label, onClick }) {
  return (
    <button onClick={onClick} className="mob-press"
      style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 10, width: '100%', minHeight: 52, borderRadius: R.md, border: 'none', cursor: 'pointer', fontFamily: SANS, fontSize: 16, fontWeight: 700, background: T.primary, color: T.onLight, boxShadow: '0 10px 26px rgba(0,0,0,.4)' }}>
      <Icon path={icon} size={19} sw={2.2} />{label}
    </button>
  )
}
function SecondaryBtn({ icon, label, onClick, style }) {
  return (
    <button onClick={onClick} className="mob-press"
      style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 9, width: '100%', minHeight: 48, borderRadius: R.md, cursor: 'pointer', fontFamily: SANS, fontSize: 14.5, fontWeight: 700, color: T.text, background: 'rgba(255,255,255,.05)', border: `1px solid ${T.line}`, ...style }}>
      <Icon path={icon} size={17} sw={1.9} />{label}
    </button>
  )
}
function IconBtn({ children, onClick, disabled, label }) {
  return (
    <button onClick={onClick} disabled={disabled} aria-label={label} className="mob-press"
      style={{ width: 40, height: 40, borderRadius: 999, display: 'grid', placeItems: 'center', cursor: disabled ? 'default' : 'pointer', color: T.text, background: 'rgba(255,255,255,.05)', border: `1px solid ${T.line}`, opacity: disabled ? 0.5 : 1 }}>
      {children}
    </button>
  )
}
function Pill({ icon, label }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 32, padding: '0 12px', borderRadius: 999, fontSize: 12.5, fontWeight: 700, color: T.text, background: 'rgba(255,255,255,.08)', border: `1px solid ${T.line2}` }}>
      <Icon path={icon} size={13} sw={2.4} />{label}
    </span>
  )
}
function InLibraryChip() {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, minHeight: 44, padding: '0 18px', borderRadius: 999, fontSize: 14.5, fontWeight: 700, background: 'rgba(255,255,255,.08)', color: T.text, border: `1px solid ${T.line2}` }}>
      <Icon path={Ic.check} size={17} sw={2.4} />In library
    </span>
  )
}
function StatusLine({ tone, title, body }) {
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, ...TYPE.headline, color: tone }}>
        <LiveDot color={tone} size={9} />{title}
      </div>
      {body && <p style={{ ...TYPE.body, color: T.dim, marginTop: 8 }}>{body}</p>}
    </div>
  )
}
function ActionState({ tone, icon, title, note, onAction, actionLabel }) {
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, ...TYPE.headline, color: tone }}>
        <Icon path={icon} size={18} sw={2} />{title}
      </div>
      {note && <p style={{ ...TYPE.body, color: T.dim, marginTop: 6 }}>{note}</p>}
      {onAction && (
        <div style={{ marginTop: 14 }}>
          <PrimaryBtn icon={Ic.download} label={actionLabel} onClick={onAction} />
        </div>
      )}
    </div>
  )
}
function LiveDot({ color, size = 8 }) {
  return <span style={{ width: size, height: size, borderRadius: '50%', background: color, animation: 'pulse 1.6s ease-in-out infinite', flexShrink: 0 }} />
}
function Spinner({ size = 18, dark }) {
  return <span style={{ display: 'inline-block', width: size, height: size, borderRadius: '50%', border: `2px solid ${dark ? 'rgba(10,11,13,.25)' : 'rgba(255,255,255,.22)'}`, borderTopColor: dark ? T.onLight : T.text, animation: 'spin .7s linear infinite' }} />
}

function NotAvailable({ kind, state }) {
  const unreachable = state?.configured && !state?.reachable
  return (
    <div style={{ marginTop: 4, padding: '44px 24px', borderRadius: R.lg, border: `1px solid ${T.line}`, background: 'rgba(255,255,255,.02)', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', animation: 'up .4s ease both' }}>
      <span style={{ width: 60, height: 60, borderRadius: 18, display: 'grid', placeItems: 'center', marginBottom: 16, background: T.surface, color: T.dim, border: `1px solid ${T.line}` }}>
        <Icon path={unreachable ? P_ALERT : Ic.compass} size={28} sw={1.7} />
      </span>
      <h2 style={{ ...TYPE.title, color: T.text, margin: 0 }}>{unreachable ? 'Browse is temporarily unavailable' : 'Browsing isn’t set up yet'}</h2>
      <p style={{ ...TYPE.body, color: T.dim, maxWidth: 340, marginTop: 10 }}>
        {unreachable
          ? `Having trouble reaching the catalog right now. ${kind === 'movie' ? 'Movie' : 'Series'} search and downloads will come back on their own.`
          : `Once browsing is configured, you can search ${kind === 'movie' ? 'movies' : 'series'} and add them with a single tap.`}
      </p>
    </div>
  )
}
function StateCard({ icon, title, body, tone }) {
  const color = tone === 'error' ? T.red : T.text
  return (
    <div style={{ marginTop: 4, padding: '44px 24px', borderRadius: R.lg, border: `1px solid ${T.line}`, background: 'rgba(255,255,255,.02)', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', animation: 'up .4s ease both' }}>
      <span style={{ width: 54, height: 54, borderRadius: 16, display: 'grid', placeItems: 'center', marginBottom: 14, background: T.surface, color: tone === 'error' ? T.red : T.dim, border: `1px solid ${T.line}` }}>
        <Icon path={icon} size={26} sw={1.7} />
      </span>
      <h2 style={{ ...TYPE.title, color, margin: 0 }}>{title}</h2>
      {body && <p style={{ ...TYPE.body, color: T.dim, maxWidth: 340, marginTop: 8 }}>{body}</p>}
    </div>
  )
}
function SkeletonGrid() {
  return (
    <div style={{ display: 'grid', gap: 14, gridTemplateColumns: 'repeat(auto-fill, minmax(118px, 1fr))' }}>
      {Array.from({ length: 9 }).map((_, i) => (
        <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <PosterSkeleton />
          <span style={{ height: 11, width: '72%', borderRadius: 6, background: T.surface }} />
        </div>
      ))}
    </div>
  )
}
