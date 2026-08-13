import { useCallback, useEffect, useMemo, useRef, useState, type WheelEvent as ReactWheelEvent } from 'react'
import '../analog/analogKit.css'
import '../analog/discover/discover.css'
import { useAuth } from '../context/AuthContext.tsx'
import { useDownloadsHub } from '../context/DownloadsContext.tsx'
import { navigate } from '../router.ts'
import { apiJson, arrayOf } from '../types/guards.ts'
import { jget, jpost, jdelete } from '../lib/api.ts'
import { serviceReady } from '../hooks/downloadsCore.ts'
import { AnalogStage } from '../analog/AnalogStage.tsx'
import { AnalogNav } from '../analog/AnalogNav.tsx'
import { AnalogProfileTray } from '../analog/AnalogProfileTray.tsx'
import { AnalogPartyWidget } from '../analog/AnalogPartyWidget.tsx'
import { AnalogRail, type AnalogRailItem } from '../analog/AnalogRail.tsx'
import { useStageMetrics } from '../analog/useStageMetrics.ts'
import { useArtworkWarm } from '../analog/useArtworkWarm.ts'
import { newSteppedScrollState, steppedScroll } from '../analog/browseCore.ts'
import { wheelDeltaPx } from '../analog/stageCore.ts'
import { playDetentCue } from '../analog/cue.ts'
import { railCursor, railMetrics, stepRailSelection } from '../analog/movieRail.ts'
import { planForSurface, rememberSurfaceFocus, shelfSnapshot, surfaceId } from '../analog/surface.ts'
import type { StageIntent } from '../analog/movieBrowse.ts'
import {
  backdropUrl,
  defaultAddOptions,
  feedLabel,
  isCatalogItem,
  isQualityProfile,
  isRootFolder,
  keyOf,
  matchTorrent,
  outcomeOf,
  parseDiscoverFeed,
  posterUrl,
  ratingLabel,
  removePath,
  requestBody,
  serviceFor,
  stepKind,
  type CatalogItem,
  type CatalogMetadata,
  type Kind,
  type Service,
} from '../analog/discover/catalog.ts'
import { outcomeToState, titleState, type RequestState } from '../analog/discover/cardState.ts'
import {
  DISCOVER_PATH,
  SEARCH_DEBOUNCE_MS,
  discoverEmptyReason,
  discoverPath,
  nextDiscoverUrl,
  railCopy,
  readDiscoverParams,
  searchPath,
  searchPlan,
  unavailableCopy,
} from '../analog/discover/query.ts'
import { hasSeasonList } from '../analog/discover/seasons.ts'
import { DiscoverKindSlider, DiscoverSearch, SuggestedSearches } from '../analog/discover/DiscoverControls.tsx'
import { DiscoverDetails } from '../analog/discover/DiscoverDetails.tsx'
import { SeasonSheet } from '../analog/discover/SeasonSheet.tsx'
import { ReleaseSheet } from '../analog/discover/ReleaseSheet.tsx'
import { OptionsSheet } from '../analog/discover/OptionsSheet.tsx'
import { ManualSheet } from '../analog/discover/ManualSheet.tsx'
import { RemoveSheet } from '../analog/discover/RemoveSheet.tsx'

/**
 * Discover, on the analog stage.
 *
 * The surface this replaces was a scrolling grid of poster cards inside the old
 * web shell — which meant Discover shipped a second bottom nav, and the app
 * showed two different tab systems at once. It also hid the overview and the
 * Download button behind `:hover` on the card, putting the primary action of the
 * whole screen out of reach of touch, keyboard and remote.
 *
 * The stage model answers all of that without inventing anything new for it:
 *
 * 1. **The results ARE the rail.** Search results, or the discover feed when
 *    there is no query, become the bottom row of small posters. The same
 *    geometry as Movies — `railCursor` over the shared `railWindow` — so the
 *    cursor stays pinned to the first slot and the row translates underneath it.
 * 2. **The focused title's details are the stage.** Synopsis, rating, year and
 *    acquisition state render at rest, and every action is a labelled button.
 *    Nothing is behind a hover, and the per-title state also rides on the rail
 *    poster as a badge and a progress hairline, so it is legible without focus.
 * 3. **Movies ⇄ Shows is the right rail.** The same position-on-a-slider the
 *    Movies stage uses for Singles/Collections, driven by Up/Down and by a
 *    stepped scroll outside the rail — not a segmented control floating above a
 *    search box.
 * 4. **The four decisions are sheets.** Seasons, releases, options and a manual
 *    source are not browse steps, so they open over the stage rather than
 *    pushing a level onto it.
 *
 * The download hub is read, never mounted: `useTorrents`/`useFailingQueue` have
 * exactly one importer by test, and a second poller on this screen is the bug
 * DownloadsContext exists to have fixed.
 */

// ── session caches ──────────────────────────────────────────────────────────

/**
 * Profiles and root folders, once per service per session, so the one-tap path
 * is instant after the first add. A single in-flight promise is shared, and a
 * failure is not cached — the next attempt retries rather than inheriting it.
 */
const metaCache: Partial<Record<Service, Promise<CatalogMetadata>>> = {}

function loadMeta(service: Service): Promise<CatalogMetadata> {
  const cached = metaCache[service]
  if (cached) return cached

  const requests = [
    jget(`/api/servarr/${service}/quality-profiles`),
    jget(`/api/servarr/${service}/root-folders`),
  ]
  if (service === 'sonarr') requests.push(jget('/api/servarr/sonarr/language-profiles'))

  const pending = Promise.all(requests)
    .then(async (responses) => {
      for (const response of responses) if (!response.ok) throw new Error('meta')
      const [profiles, rootFolders, langProfiles] = await Promise.all(responses.map(apiJson))
      return {
        profiles: arrayOf(profiles, isQualityProfile),
        rootFolders: arrayOf(rootFolders, isRootFolder),
        langProfiles: arrayOf(langProfiles, isQualityProfile),
      }
    })
    .catch((failure) => {
      delete metaCache[service]
      throw failure
    })

  metaCache[service] = pending
  return pending
}

interface FeedResult {
  status: number
  source: string
  items: CatalogItem[]
}

/**
 * The discover feed per service, cached for the session so flipping between
 * search and the feed — or between Movies and Shows and back — is instant. An
 * empty result is NOT pinned: that is usually a transient lookup outage and a
 * later visit should retry rather than inherit an empty rail for the session.
 */
const feedCache: Partial<Record<Service, Promise<FeedResult>>> = {}

function loadFeed(service: Service): Promise<FeedResult> {
  const cached = feedCache[service]
  if (cached) return cached

  const pending = jget(discoverPath(service))
    .then(async (response) => {
      if (!response.ok) {
        delete feedCache[service]
        return { status: response.status, source: 'curated', items: [] }
      }
      const feed = parseDiscoverFeed(await apiJson(response))
      if (feed.items.length === 0) delete feedCache[service]
      return { status: 200, source: feed.source, items: feed.items }
    })
    .catch((failure) => {
      delete feedCache[service]
      throw failure
    })

  feedCache[service] = pending
  return pending
}

const isAbortError = (value: unknown): boolean =>
  typeof value === 'object' && value !== null && 'name' in value && value.name === 'AbortError'

export default function DiscoverStage() {
  const { user, logout, profile } = useAuth()
  const hub = useDownloadsHub()
  const { layout, motion, viewportWidthPx } = useStageMetrics()

  const [kind, setKind] = useState(() => readDiscoverParams(window.location.search).kind)
  const [term, setTerm] = useState(() => readDiscoverParams(window.location.search).term)
  const [results, setResults] = useState<CatalogItem[]>([])
  // Mounting on a deep-linked query starts in the loading state, or the feed
  // flashes for one frame before the debounced search for it fires.
  const [searching, setSearching] = useState(() => readDiscoverParams(window.location.search).term.trim() !== '')
  const [searched, setSearched] = useState(false)
  const [searchError, setSearchError] = useState('')

  const [feed, setFeed] = useState<FeedResult | null>(null)
  const [feedLoading, setFeedLoading] = useState(true)

  const [selection, setSelection] = useState(0)
  const [requests, setRequests] = useState<Record<string, RequestState | undefined>>({})
  const [sheet, setSheet] = useState<'seasons' | 'releases' | 'options' | 'manual' | 'remove' | null>(null)

  const service = serviceFor(kind)
  const svcState = hub.health?.services?.[service]
  const svcReady = serviceReady(hub.health, service)
  const unavailable = !hub.healthLoading && !svcReady
  const query = term.trim()

  const meta = useCallback(() => loadMeta(service), [service])

  // ── URL ⇄ state ───────────────────────────────────────────────────────────

  // replaceState, not push: typing must not bury the previous page under a
  // history entry per keystroke.
  useEffect(() => {
    const next = nextDiscoverUrl(window.location.pathname, window.location.search, { kind, term })
    if (next) window.history.replaceState(window.history.state, '', next)
  }, [term, kind])

  // Back/forward restores the search it was taken with. The custom router
  // dispatches popstate on navigate and the browser dispatches it on the
  // buttons, so one listener covers both.
  useEffect(() => {
    const onPop = () => {
      if (window.location.pathname !== DISCOVER_PATH) return
      const next = readDiscoverParams(window.location.search)
      setKind(next.kind)
      setTerm(next.term)
    }
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  // ── search ────────────────────────────────────────────────────────────────

  const abort = useRef<AbortController | null>(null)

  const runSearch = useCallback((rawTerm: string, forKind: Kind) => {
    const plan = searchPlan(rawTerm)
    abort.current?.abort()

    if (plan.action === 'clear') {
      setResults([])
      setSearching(false)
      setSearched(false)
      setSearchError('')
      return
    }

    const controller = new AbortController()
    abort.current = controller
    setSearching(true)
    setSearchError('')

    fetch(searchPath(serviceFor(forKind), plan.query), { credentials: 'include', signal: controller.signal })
      .then((response) => (response.ok ? apiJson(response) : Promise.reject(response)))
      .then((value: unknown) => {
        setResults(arrayOf(value, isCatalogItem))
        setSearched(true)
      })
      .catch((failure: unknown) => {
        // An abort is this code cancelling itself for a newer query; it is not a
        // failure and must not blank the results the newer one is about to fill.
        if (isAbortError(failure)) return
        setResults([])
        setSearched(true)
        setSearchError('Search failed. Please try again.')
      })
      .finally(() => {
        if (abort.current === controller) setSearching(false)
      })
  }, [])

  useEffect(() => {
    if (!svcReady) return
    const timer = window.setTimeout(() => runSearch(term, kind), SEARCH_DEBOUNCE_MS)
    return () => window.clearTimeout(timer)
  }, [term, kind, svcReady, runSearch])

  // Abort whatever is in flight when the surface goes away, so a late response
  // cannot set state on an unmounted tree.
  useEffect(() => () => abort.current?.abort(), [])

  // ── feed ──────────────────────────────────────────────────────────────────

  useEffect(() => {
    if (!svcReady) return
    let cancelled = false
    setFeedLoading(true)
    loadFeed(service)
      .then((value) => !cancelled && setFeed(value))
      .catch(() => !cancelled && setFeed({ status: 0, source: 'curated', items: [] }))
      .finally(() => !cancelled && setFeedLoading(false))
    return () => {
      cancelled = true
    }
  }, [service, svcReady])

  // ── the rail's contents ───────────────────────────────────────────────────

  const items = useMemo(() => (query ? results : (feed?.items ?? [])), [query, results, feed])
  const loading = unavailable ? false : query ? searching && !searched : feedLoading

  // Each query, and each kind, is its own surface with its own remembered
  // position — they are different lists of different lengths, and one shared
  // memory would restore an index only the other ever had.
  const surface = surfaceId(`discover:${kind}`, query ? [{ id: query }] : [])

  // Restoration runs off the rail CONTENTS rather than off mount, because the
  // list changes under a remembered position routinely here: results arrive,
  // a removed title disappears, the feed refreshes. `restoreFocus` is the
  // cross-language-tested rule for where that lands.
  const focusIds = useMemo(() => items.map((item) => ({ Id: keyOf(kind, item) })), [items, kind])
  useEffect(() => {
    if (loading) return
    const plan = planForSurface(surface, [shelfSnapshot('discover', focusIds)])
    setSelection(plan.itemIndex < 0 ? 0 : plan.itemIndex)
  }, [surface, focusIds, loading])

  const focused = items[selection] ?? null
  const focusKey = focused ? keyOf(kind, focused) : null

  useEffect(() => {
    if (focusKey) rememberSurfaceFocus(surface, 'discover', focusKey, selection)
  }, [surface, focusKey, selection])

  const torrent = focused ? matchTorrent(focused.title, hub.torrents) : null
  const state = focused ? titleState({ item: focused, requested: requests[focusKey!] ?? null, torrent }) : null

  // Sheets belong to the title they were opened for.
  useEffect(() => {
    setSheet(null)
  }, [focusKey])

  // ── rail geometry + prefetch ──────────────────────────────────────────────

  const rail = railMetrics(Math.max(0, viewportWidthPx - layout.gutterPx * 2), layout.size)
  const cursor = railCursor({ total: items.length, selection, slots: rail.slots })
  const prefetchKey = cursor.prefetch.join(',')
  // The catalog's art is remote and proxied, so the analog artwork chain has
  // nothing to resolve — the URLs are already absolute paths and are warmed
  // directly. Backdrops included: the backdrop IS the selection feedback here.
  const warm = useMemo(() => {
    const urls: string[] = []
    const seen = new Set<string>()
    for (const index of cursor.prefetch) {
      const item = items[index]
      if (!item) continue
      for (const url of [posterUrl(item.images), backdropUrl(item.images)]) {
        if (!url || seen.has(url)) continue
        seen.add(url)
        urls.push(url)
      }
    }
    return urls
  }, [items, prefetchKey])
  useArtworkWarm(warm)

  // ── requests ──────────────────────────────────────────────────────────────

  const setRequestState = (key: string, next: RequestState) =>
    setRequests((current) => ({ ...current, [key]: next }))

  /**
   * One tap.
   *
   * A single server call does the add, the live interactive search and the
   * grab-or-remove, and returns what it actually did — so the client flips to
   * that outcome instead of polling and guessing. It can take the better part of
   * a minute while indexers are searched, which is what the 'searching' state is
   * for.
   */
  const request = (item: CatalogItem, forKind: Kind = kind) => {
    const key = keyOf(forKind, item)
    setRequestState(key, 'searching')
    loadMeta(serviceFor(forKind))
      .then((value) => {
        const options = defaultAddOptions(value)
        if (!options) throw new Error('meta')
        return jpost(`/api/servarr/${serviceFor(forKind)}/request`, requestBody(forKind, item, options))
      })
      .then((response) => (response.ok ? apiJson(response) : Promise.reject(response)))
      .then((value: unknown) => setRequestState(key, outcomeToState(outcomeOf(value))))
      .catch(() => setRequestState(key, 'error'))
  }

  const remove = async () => {
    if (!focused?.id) return
    await jdelete(removePath(kind, focused.id))
    // The catalog id is what says "in library", and this client cannot rewrite
    // the lookup it was handed — so drop the row and re-run the search, which is
    // also what surfaces a removal the server refused.
    setSheet(null)
    if (query) runSearch(term, kind)
    else {
      delete feedCache[service]
      setFeed(null)
      setFeedLoading(true)
      loadFeed(service)
        .then(setFeed)
        .catch(() => setFeed({ status: 0, source: 'curated', items: [] }))
        .finally(() => setFeedLoading(false))
    }
  }

  // ── movement ──────────────────────────────────────────────────────────────

  const changeKind = (next: Kind) => {
    if (next === kind) return
    playDetentCue()
    setKind(next)
  }

  const stepRail = (direction: number) => {
    setSelection((current) => {
      const next = stepRailSelection(current, items.length, direction)
      if (next !== current) playDetentCue()
      return next
    })
  }

  // Enter is the primary action for the focused title, exactly as it is on the
  // Movies stage — and a series with seasons opens the chooser rather than
  // silently subscribing to everything it has ever aired.
  const activate = (index: number) => {
    const target = items[index]
    if (!target || unavailable) return
    if (kind === 'series' && hasSeasonList(target)) setSheet('seasons')
    else request(target)
  }

  const onIntent = (intent: StageIntent) => {
    switch (intent) {
      case 'rail-prev':
        return stepRail(-1)
      case 'rail-next':
        return stepRail(1)
      case 'mode-prev':
        return changeKind(stepKind(kind, -1))
      case 'mode-next':
        return changeKind(stepKind(kind, 1))
      case 'activate':
        return activate(selection)
      case 'back':
        return setTerm('')
    }
  }

  // A stepped scroll outside the rail moves the kind slider; the rail swallows
  // its own wheel events, so anything arriving here started elsewhere. A sheet
  // is the exception: it has a real scroll region of its own, and scrolling a
  // list of releases must not quietly flip the catalog underneath it.
  const stageScroll = useRef(newSteppedScrollState())
  const onStageWheel = (event: ReactWheelEvent<HTMLDivElement>) => {
    if ((event.target as HTMLElement | null)?.closest?.('.an-dsheet')) return
    const step = steppedScroll(stageScroll.current, wheelDeltaPx(event), event.timeStamp)
    if (step !== 0) changeKind(stepKind(kind, step))
  }

  // Arrows and Enter have to work before anything has been clicked — a browse
  // surface that needs a focus click first is one a remote cannot drive. Read
  // through a ref so the listener is attached once rather than rebuilt on every
  // step of the rail.
  const intentRef = useRef(onIntent)
  intentRef.current = onIntent
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) return
      const target = event.target as HTMLElement | null
      if (target?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target?.tagName ?? '')) return
      // The rail owns its own keys, and a sheet owns everything while it is open.
      if (target?.closest?.('.an-rail-viewport, .an-dsheet')) return
      const intent = stageKeyFallback(event.key)
      if (!intent) return
      event.preventDefault()
      intentRef.current(intent)
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  // ── render ────────────────────────────────────────────────────────────────

  const railItems: AnalogRailItem[] = items.map((item, index) => {
    const key = keyOf(kind, item)
    const itemState = titleState({
      item,
      requested: requests[key] ?? null,
      torrent: matchTorrent(item.title, hub.torrents),
    })
    return {
      // The index is part of the React key because `keyOf` falls back to the
      // title for a result with no provider id, and the catalog does sometimes
      // return the same title twice — two identical keys in one rail is a
      // broken reconciliation, not a cosmetic warning.
      id: `${key}:${index}`,
      label: item.title,
      // Acquisition state on the poster itself, so a rail of fifty titles says
      // which ones are already yours without focusing any of them — and without
      // a hover, which is what it replaces. A title nobody has acted on has no
      // state to report, so the badge carries its rating instead.
      badge: itemState.badge ?? ratingLabel(item),
      progressPct: itemState.progressPct,
      art: { Id: key, Name: item.title, ImageTags: null },
      artSrc: posterUrl(item.images),
    }
  })

  const feedReason = feed && (feed.status !== 200 || feed.items.length === 0)
    ? discoverEmptyReason(feed.status, service)
    : null

  const copy = railCopy({
    kind,
    query,
    searching,
    searched,
    resultCount: results.length,
    feedLabel: feed ? feedLabel(feed.source) : 'Discover',
    feedReason,
  })

  const away = unavailable ? unavailableCopy(kind, svcState) : null
  // A search that matched nothing, and a feed that could not be reached, are the
  // two places Discover would otherwise be an empty box with a cursor in it.
  const stranded = !loading && !away && items.length === 0
  // A failed search is not an empty one. "No movies matched" against a request
  // that never completed sends people off editing a spelling that was fine.
  const emptyTitle = searchError ? 'Search failed' : copy.emptyTitle
  const emptyHint = searchError ? 'The catalog could not be reached. Try again in a moment.' : copy.emptyHint
  const hasSeasons = focused != null && kind === 'series' && hasSeasonList(focused)

  return (
    <div className="an-discover" onWheel={onStageWheel}>
      <AnalogStage
        backdropUrl={focused ? backdropUrl(focused.images) : null}
        backdropFallbackUrl={focused ? posterUrl(focused.images) : null}
        layout={layout}
        motion={motion}
        side={<DiscoverKindSlider kind={kind} onChange={changeKind} disabled={unavailable} />}
        header={
          <div className="an-stage-head">
            <div className="an-stage-head-row">
              <DiscoverSearch
                term={term}
                kind={kind}
                onTerm={setTerm}
                onSubmit={() => runSearch(term, kind)}
                onClear={() => setTerm('')}
                loading={searching}
                disabled={unavailable}
              />
            </div>

            {stranded ? (
              <SuggestedSearches
                kind={kind}
                onPick={setTerm}
                heading={
                  searchError
                    ? 'Try again, or start with one of these'
                    : query
                      ? `Nothing matched “${query}”. Try one of these`
                      : 'Start with one of these'
                }
              />
            ) : null}

            <DiscoverDetails
              item={focused}
              kind={kind}
              state={state}
              torrent={torrent}
              fallbackTitle={away ? away.title : loading ? 'Searching' : emptyTitle}
              fallbackBody={away ? away.body : loading ? null : emptyHint}
              error={searchError || null}
              disabled={unavailable}
              hasSeasons={hasSeasons}
              onRequest={() => focused && request(focused)}
              onOptions={() => setSheet('options')}
              onSources={() => setSheet('releases')}
              onManual={() => setSheet('manual')}
              onSeasons={() => setSheet('seasons')}
              onRemove={() => setSheet('remove')}
            />
          </div>
        }
        nav={
          <AnalogNav
            active="discover"
            onNavigate={navigate}
            canAcquire={!!user?.isAdmin}
            downloadCount={hub.activeCount}
            failingCount={hub.failingCount}
            compact={layout.size === 'phone'}
          />
        }
        toolboxes={
          <>
            <AnalogProfileTray
              userId={user?.userId}
              name={profile?.displayName || user?.name}
              avatar={profile?.avatar}
              onSettings={() => navigate('/profile')}
              onSignOut={() => void logout()}
            />
            <AnalogPartyWidget />
          </>
        }
      >
        <AnalogRail
          label={away ? 'Discover' : copy.label}
          items={railItems}
          selection={selection}
          onIntent={onIntent}
          onSelect={setSelection}
          onActivate={activate}
          motion={motion}
          posterWidthPx={rail.posterWidthPx}
          gapPx={rail.gapPx}
          slots={rail.slots}
          loading={loading}
          emptyTitle={away ? away.title : emptyTitle}
          emptyHint={away ? away.body : emptyHint}
          disabled={unavailable}
        />
      </AnalogStage>

      {focused && sheet === 'seasons' ? (
        <SeasonSheet
          item={focused}
          motion={motion}
          loadMeta={meta}
          onClose={() => setSheet(null)}
          onWholeSeries={() => request(focused)}
        />
      ) : null}

      {focused && sheet === 'releases' ? (
        <ReleaseSheet
          item={focused}
          motion={motion}
          loadMeta={meta}
          onClose={() => setSheet(null)}
          onGrabbed={() => {
            setRequestState(keyOf(kind, focused), 'grabbed')
            setSheet(null)
          }}
          onManual={() => setSheet('manual')}
        />
      ) : null}

      {focused && sheet === 'options' ? (
        <OptionsSheet
          item={focused}
          kind={kind}
          motion={motion}
          loadMeta={meta}
          onClose={() => setSheet(null)}
          onSettled={(next) => {
            setRequestState(keyOf(kind, focused), next)
            setSheet(null)
          }}
        />
      ) : null}

      {focused && sheet === 'manual' ? (
        <ManualSheet
          item={focused}
          kind={kind}
          motion={motion}
          loadMeta={meta}
          onClose={() => setSheet(null)}
          onSubmitted={() => setRequestState(keyOf(kind, focused), 'grabbed')}
        />
      ) : null}

      {focused && sheet === 'remove' ? (
        <RemoveSheet
          item={focused}
          kind={kind}
          motion={motion}
          onClose={() => setSheet(null)}
          onConfirm={remove}
        />
      ) : null}
    </div>
  )
}

/**
 * The window-level fallback answers to fewer keys than the rail does, for the
 * same reason the Movies stage's does: Space scrolls a page everywhere else in a
 * browser and Backspace is a text edit, so binding either at the window would
 * surprise. Inside the rail, where the user has committed to a listbox, both are
 * the expected controls.
 */
function stageKeyFallback(key: string): StageIntent | null {
  switch (key) {
    case 'ArrowLeft':
      return 'rail-prev'
    case 'ArrowRight':
      return 'rail-next'
    case 'ArrowUp':
      return 'mode-prev'
    case 'ArrowDown':
      return 'mode-next'
    case 'Enter':
      return 'activate'
    case 'Escape':
      return 'back'
    default:
      return null
  }
}
