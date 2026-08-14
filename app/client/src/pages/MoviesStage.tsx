import { useEffect, useMemo, useRef, useState, type WheelEvent as ReactWheelEvent } from 'react'
import '../analog/analogKit.css'
import { useAuth } from '../context/AuthContext.tsx'
import { useParty } from '../context/PartyContext.tsx'
import { useDownloadsHub } from '../context/DownloadsContext.tsx'
import { navigate } from '../router.ts'
import { apiJson, arrayOf, isLibraryItemJson, isRecord } from '../types/guards.ts'
import { IS_NATIVE } from '../native/env.ts'
import { IPC } from '../native/contract.ts'
import { invoke } from '../native/ipc.ts'
import { AnalogStage } from '../analog/AnalogStage.tsx'
import { AnalogNav } from '../analog/AnalogNav.tsx'
import { AnalogProfileTray } from '../analog/AnalogProfileTray.tsx'
import { AnalogPartyWidget } from '../analog/AnalogPartyWidget.tsx'
import { AnalogRail, type AnalogRailItem } from '../analog/AnalogRail.tsx'
import { AnalogModeSlider } from '../analog/AnalogModeSlider.tsx'
import { AnalogDetails } from '../analog/AnalogDetails.tsx'
import { useLibraryDelete } from '../hooks/useLibraryDelete.ts'
import { AnalogTrackMenu } from '../analog/AnalogTrackMenu.tsx'
import { AnIcon } from '../analog/icons.tsx'
import { useStageMetrics } from '../analog/useStageMetrics.ts'
import { useArtworkWarm } from '../analog/useArtworkWarm.ts'
import { artworkSrc, backdropSrc, failedArtworkIds, resolveArtwork } from '../analog/artwork.ts'
import { newSteppedScrollState, steppedScroll } from '../analog/browseCore.ts'
import { wheelDeltaPx } from '../analog/stageCore.ts'
import { playDetentCue } from '../analog/cue.ts'
import { planForSurface, rememberSurfaceFocus, shelfSnapshot, surfaceId } from '../analog/surface.ts'
import { prefetchTargets, railCursor, railMetrics, stepRailSelection } from '../analog/movieRail.ts'
import {
  activationFor,
  closeCollection,
  collectionFromStack,
  modeFromStack,
  moviesTab,
  openCollection,
  rootLevel,
  stepBrowseMode,
  withMode,
  type BrowseMode,
  type MovieLevel,
  type StageIntent,
} from '../analog/movieBrowse.ts'
import { mergeDetail, needsEnrichment, type StageItem } from '../analog/movieDetails.ts'
import {
  defaultSelection,
  parsePlaybackTracks,
  wireSelection,
  type PlaybackTracks,
  type TrackSelection,
} from '../analog/playbackTracks.ts'

/**
 * Movies, rebuilt to the owner's revised model.
 *
 * Four things separate this from the surface it replaces, and each of them is a
 * different shape rather than a different number:
 *
 * 1. **The library is the detail view.** The focused title's copy, metadata and
 *    actions render on the browse stage; there is no drill-in for a movie and no
 *    detail screen behind it. Enter plays, exactly as it does for an episode on
 *    the Shows screen.
 * 2. **The cursor does not move.** Selection is pinned to the first slot and the
 *    row translates underneath it (analog/movieRail.ts, over the shared
 *    `railWindow`). "Which title is selected" and "how far the row has scrolled"
 *    are one number, which is what makes the prefetch set derivable.
 * 3. **Two modes.** Singles and Collections, on a slider driven by Up/Down and by
 *    a stepped scroll anywhere outside the rail. The mode rides on the browse
 *    stack, so a party follower lands on the one the driver is looking at.
 * 4. **Collections drill in.** Enter on a franchise opens a show-like level: its
 *    parts become the rail, and their details — which the collections route
 *    already returns in full — fill the stage. Back returns to the list.
 */

const DEFAULT_MODE: BrowseMode = 'singles'

const stageItems = (value: unknown): StageItem[] =>
  arrayOf(value, (candidate): candidate is StageItem => isLibraryItemJson(candidate))

interface LibraryView {
  Id: string
  Name: string
  Type: string
  CollectionType?: string
}

function parseViews(value: unknown): LibraryView[] {
  if (!isRecord(value)) return []
  return arrayOf(value.views, (candidate): candidate is LibraryView => isLibraryItemJson(candidate))
}

const isMoviesView = (view: LibraryView) =>
  (view.CollectionType || view.Name || '').toLowerCase().includes('movie')

const getJson = (url: string) =>
  fetch(url, { credentials: 'include' }).then((response) =>
    response.ok ? apiJson(response) : Promise.reject(response),
  )

export default function MoviesStage() {
  const { user, logout, profile } = useAuth()
  const party = useParty()
  const hub = useDownloadsHub()
  const { layout, motion, viewportWidthPx } = useStageMetrics()

  const [views, setViews] = useState<LibraryView[] | null>(null)
  const [internalStack, setInternalStack] = useState<MovieLevel[]>([])
  const [singles, setSingles] = useState<StageItem[] | null>(null)
  const [collections, setCollections] = useState<StageItem[] | null>(null)
  const [parts, setParts] = useState<StageItem[] | null>(null)
  const [details, setDetails] = useState<Record<string, StageItem>>({})
  const [error, setError] = useState('')
  const [selection, setSelection] = useState(0)

  // Everyone browses their own library. A room shares playback, chat and
  // A/V — never navigation.
  const stack: MovieLevel[] = internalStack

  const setStack = (next: MovieLevel[]) => setInternalStack(next)

  const mode = modeFromStack(stack, DEFAULT_MODE)
  const collection = collectionFromStack(stack)
  const viewId = stack[0]?.id ?? null
  const collectionId = collection?.id ?? null

  // ── data ──────────────────────────────────────────────────────────────────

  useEffect(() => {
    getJson('/api/library/home')
      .then((value) => setViews(parseViews(value)))
      .catch(() => setError('Failed to load your library'))
  }, [])

  // Resolve the Movies collection once, as the root of the stack — the same
  // shape pages/Library.tsx publishes, so a host on either implementation still
  // drives a guest on the other.
  useEffect(() => {
    if (!views || stack.length > 0) return
    const target = views.find(isMoviesView)
    if (target) setStack([rootLevel(target, DEFAULT_MODE)])
    else if (views.length > 0) setError('No movie library found on this server')
  }, [views, stack.length])

  // Each list is fetched once and kept. Flicking the mode slider back and forth
  // is a slider, not a reload — and the whole point of the two modes is that
  // both are a step away.
  useEffect(() => {
    if (!viewId || mode !== 'singles' || singles !== null) return
    let cancelled = false
    getJson(`/api/library/items/${viewId}/children`)
      .then((value) => !cancelled && setSingles(stageItems(value)))
      .catch(() => !cancelled && setSingles([]))
    return () => {
      cancelled = true
    }
  }, [viewId, mode, singles])

  useEffect(() => {
    if (!viewId || mode !== 'collections' || collections !== null) return
    let cancelled = false
    getJson(`/api/library/collections?parentId=${encodeURIComponent(viewId)}`)
      .then((value) => !cancelled && setCollections(stageItems(value)))
      .catch(() => !cancelled && setCollections([]))
    return () => {
      cancelled = true
    }
  }, [viewId, mode, collections])

  // A franchise's parts, release-ordered and carrying their full metadata, so a
  // focused part renders on the stage with no second fetch.
  useEffect(() => {
    if (!collectionId) {
      setParts(null)
      return
    }
    let cancelled = false
    setParts(null)
    getJson(`/api/library/collections/${collectionId}/items`)
      .then((value) => !cancelled && setParts(stageItems(value)))
      .catch(() => !cancelled && setParts([]))
    return () => {
      cancelled = true
    }
  }, [collectionId])

  const list = collectionId ? parts : mode === 'collections' ? collections : singles
  const items = useMemo(() => list ?? [], [list])
  const loading = list === null

  // ── focus ─────────────────────────────────────────────────────────────────

  const surface = surfaceId(moviesTab(mode), stack)

  // Focus restoration runs off the rail CONTENTS, not off mount: the list can
  // change under a remembered position (a title removed, a library emptied) and
  // restoreFocus is what decides where that lands.
  useEffect(() => {
    if (loading) return
    const plan = planForSurface(surface, [shelfSnapshot('movies', items)])
    setSelection(plan.itemIndex < 0 ? 0 : plan.itemIndex)
  }, [surface, items, loading])

  const listed = items[selection] ?? null
  const focused = listed ? mergeDetail(listed, details[listed.Id]) : null

  // Admin only, and only when Radarr/Sonarr actually holds the record behind
  // this title — see useLibraryDelete.
  const { canDelete, deleting, remove: removeFromServer } = useLibraryDelete(
    'movie',
    focused,
  )

  useEffect(() => {
    if (!focused) return
    rememberSurfaceFocus(surface, 'movies', focused.Id, selection)
    // The ambient wash the unconverted surfaces read (styles.css `.web-ambient`)
    // still keys off this, so leaving it stale shows the wrong title behind them.
    const primary = artworkSrc(resolveArtwork(focused))
    document.documentElement.style.setProperty(
      '--balanced-poster',
      [backdropSrc(focused.Id), primary].filter(Boolean).map((url) => `url("${url}")`).join(', '),
    )
  }, [surface, focused?.Id, selection])

  // The singles list arrives from /children, which asks Jellyfin only for
  // MediaSources — no Overview, no Genres. Fetch the rest for the focused title
  // only, once, and only when the list it came from did not already carry it: a
  // franchise's parts arrive complete, and asking unconditionally would put a
  // request behind every step of the rail. The delay is what makes a fast scroll
  // through fifty titles cost one request rather than fifty.
  useEffect(() => {
    if (!listed || !needsEnrichment(listed) || details[listed.Id]) return
    const id = listed.Id
    let cancelled = false
    const timer = window.setTimeout(() => {
      getJson(`/api/library/item/${id}`)
        .then((value) => {
          if (cancelled || !isLibraryItemJson(value)) return
          setDetails((previous) => ({ ...previous, [id]: value as unknown as StageItem }))
        })
        .catch(() => {})
    }, 140)
    return () => {
      cancelled = true
      window.clearTimeout(timer)
    }
  }, [listed, details])

  // ── rail geometry + prefetch ──────────────────────────────────────────────

  const rail = railMetrics(Math.max(0, viewportWidthPx - layout.gutterPx * 2), layout.size)
  const cursor = railCursor({ total: items.length, selection, slots: rail.slots })
  const prefetchKey = cursor.prefetch.join(',')
  const warm = useMemo(
    () => prefetchTargets({ items, indices: cursor.prefetch, failedIds: failedArtworkIds() }),
    [items, prefetchKey],
  )
  useArtworkWarm(warm)

  // ── playback selection ────────────────────────────────────────────────────

  const [tracksOpen, setTracksOpen] = useState(false)
  const [tracks, setTracks] = useState<PlaybackTracks | null>(null)
  const [tracksLoading, setTracksLoading] = useState(false)
  const [selected, setSelected] = useState<TrackSelection>({})
  const [downloadState, setDownloadState] = useState<'idle' | 'busy' | 'queued' | 'failed'>('idle')

  // Track choices belong to the title they were made for. Playback info is
  // fetched only when the menu is opened, because a POST per step of the rail is
  // exactly the cost a fixed cursor over a whole library must not carry.
  useEffect(() => {
    setTracksOpen(false)
    setTracks(null)
    setSelected({})
    setDownloadState('idle')
  }, [focused?.Id])

  const loadTracks = async () => {
    if (!focused) return
    setTracksLoading(true)
    try {
      const response = await fetch(`/api/library/playback-info/${focused.Id}`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      })
      const next = parsePlaybackTracks(response.ok ? await apiJson(response) : null)
      setTracks(next)
      if (next) setSelected((current) => (current.audioStreamIndex == null ? defaultSelection(next) : current))
    } catch {
      setTracks(null)
    } finally {
      setTracksLoading(false)
    }
  }

  const toggleTracks = () => {
    if (tracksOpen) {
      setTracksOpen(false)
      return
    }
    setTracksOpen(true)
    if (!tracks) void loadTracks()
  }

  const watch = (item: StageItem) => {
    const chosen = tracks ? wireSelection(selected) : undefined
    if (party.session) {
      party.selectMedia(item.Id, chosen)
      navigate(`/party/${party.session.id}`)
      return
    }
    const query = new URLSearchParams({ itemId: item.Id })
    if (Number.isInteger(chosen?.audioStreamIndex)) query.set('audioStreamIndex', String(chosen!.audioStreamIndex))
    if (Number.isInteger(chosen?.subtitleStreamIndex)) {
      query.set('subtitleStreamIndex', String(chosen!.subtitleStreamIndex))
    }
    navigate(`/party/new?${query}`)
  }

  // Offline download, desktop shell only — a browser tab has nowhere to put the
  // file, which is why every native-only path in this client is gated on
  // IS_NATIVE rather than rendered dead everywhere else.
  const download = async () => {
    if (!focused || !IS_NATIVE) return
    setDownloadState('busy')
    try {
      const value = await getJson(`/api/library/hls-url?itemId=${encodeURIComponent(focused.Id)}&abr=1`)
      const url = isRecord(value) && typeof value.url === 'string' ? value.url : null
      if (!url) throw new Error('no stream url')
      await invoke(IPC.DL_START, { itemId: focused.Id, url, title: focused.Name })
      setDownloadState('queued')
    } catch {
      setDownloadState('failed')
    }
  }

  // ── movement ──────────────────────────────────────────────────────────────

  const setMode = (next: BrowseMode) => {
    if (next === mode || stack.length === 0) return
    playDetentCue()
    setStack(withMode(stack, next))
  }

  const stepRail = (direction: number) => {
    setSelection((current) => {
      const next = stepRailSelection(current, items.length, direction)
      if (next !== current) playDetentCue()
      return next
    })
  }

  const goBack = () => {
    if (stack.length <= 1) return
    setStack(closeCollection(stack))
  }

  const activate = (index: number) => {
    const target = items[index]
    const action = activationFor(target)
    if (action.kind === 'open') setStack(openCollection(stack, action.collection))
    else if (action.kind === 'play' && target) watch(target)
  }

  const onIntent = (intent: StageIntent) => {
    switch (intent) {
      case 'rail-prev':
        return stepRail(-1)
      case 'rail-next':
        return stepRail(1)
      case 'mode-prev':
        return setMode(stepBrowseMode(mode, -1))
      case 'mode-next':
        return setMode(stepBrowseMode(mode, 1))
      case 'activate':
        return activate(selection)
      case 'back':
        return goBack()
    }
  }

  // A stepped scroll that did NOT land on the rail moves the mode slider: "up
  // down and scroll updown (when not in the movie grid) will toggle it". The
  // rail swallows its own wheel events, so anything arriving here is outside it.
  const stageScroll = useRef(newSteppedScrollState())
  const onStageWheel = (event: ReactWheelEvent<HTMLDivElement>) => {
    const step = steppedScroll(stageScroll.current, wheelDeltaPx(event), event.timeStamp)
    if (step !== 0) setMode(stepBrowseMode(mode, step))
  }

  // Arrows and Enter must work before anything on the stage has been clicked — a
  // browse surface that needs a focus click first is one a remote cannot drive.
  // Read through a ref so the listener is attached once instead of being torn
  // down and rebuilt on every step of the rail.
  const intentRef = useRef(onIntent)
  intentRef.current = onIntent
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) return
      const target = event.target as HTMLElement | null
      if (target?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target?.tagName ?? '')) return
      // The rail and the track menu own their own keys; this is the fallback for
      // everywhere else on the stage.
      if (target?.closest?.('.an-rail-viewport, .an-track-menu')) return
      const intent = stageKeyFallback(event.key)
      if (!intent) return
      event.preventDefault()
      intentRef.current(intent)
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  // ── render ────────────────────────────────────────────────────────────────

  const railItems: AnalogRailItem[] = items.map((item) => ({
    id: item.Id,
    label: item.Name,
    badge: item.Type === 'BoxSet' && item.ChildCount ? `${item.ChildCount}` : null,
    progressPct: item.UserData?.PlayedPercentage ?? null,
    art: item,
  }))

  const rootName = stack[0]?.name || 'Movies'
  const railLabel = collection?.name || (mode === 'collections' ? 'Collections' : rootName)
  // Inside a franchise the eyebrow says which part you are on, the way an
  // episode says which season it belongs to — but only once the parts have
  // landed, or it reads "1 of 0" for the length of the fetch.
  const context = collection?.name
    ? items.length > 0
      ? `${collection.name} · ${selection + 1} of ${items.length}`
      : collection.name
    : mode === 'collections'
      ? 'Collection'
      : null

  return (
    <div className="an-movies" onWheel={onStageWheel}>
      <AnalogStage
        backdropUrl={focused ? backdropSrc(focused.Id) : null}
        backdropFallbackUrl={focused ? artworkSrc(resolveArtwork(focused)) : null}
        layout={layout}
        motion={motion}
        side={<AnalogModeSlider mode={mode} onChange={setMode} />}
        header={
          <div className="an-stage-head">
            <div className="an-stage-head-row">
              {collection ? (
                <button type="button" className="an-back" onClick={goBack}>
                  <AnIcon name="back" size={14} />
                  <span>All collections</span>
                </button>
              ) : null}
            </div>

            <AnalogDetails
              item={focused}
              onDeleteFromServer={canDelete ? () => void removeFromServer() : undefined}
              deleting={deleting}
              context={context}
              fallbackTitle={error ? 'Movies' : loading ? 'Loading' : railLabel}
              error={error || null}
              native={IS_NATIVE}
              onPlay={() => activate(selection)}
              onDownload={() => void download()}
              onTracks={toggleTracks}
              tracksOpen={tracksOpen}
              downloadState={downloadState}
            >
              {tracksOpen && focused ? (
                <AnalogTrackMenu
                  itemId={focused.Id}
                  tracks={tracks}
                  loading={tracksLoading}
                  selectedAudio={selected.audioStreamIndex ?? null}
                  selectedSubtitle={selected.subtitleStreamIndex ?? null}
                  onSelectAudio={(index) => setSelected((current) => ({ ...current, audioStreamIndex: index }))}
                  onSelectSubtitle={(index) => setSelected((current) => ({ ...current, subtitleStreamIndex: index }))}
                  onRefresh={loadTracks}
                  onClose={() => setTracksOpen(false)}
                />
              ) : null}
            </AnalogDetails>
          </div>
        }
        nav={
          <AnalogNav
            active="movies"
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
          label={railLabel}
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
          emptyTitle={mode === 'collections' && !collection ? 'No collections yet' : 'No titles here yet'}
          emptyHint={
            mode === 'collections' && !collection
              ? 'Group films into a collection in Jellyfin and it shows up here.'
              : 'Add something from Discover.'
          }
        />
      </AnalogStage>
    </div>
  )
}

/**
 * The window-level fallback answers to fewer keys than the rail does on purpose.
 * Space scrolls a page everywhere else in a browser and Backspace is a text
 * edit, so binding either at the window would surprise; inside the rail, where
 * the user has already committed to a listbox, both are the expected controls.
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
