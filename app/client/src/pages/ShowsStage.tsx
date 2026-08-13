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
import { AnalogSeasonRail } from '../analog/AnalogSeasonRail.tsx'
import { AnalogDetails } from '../analog/AnalogDetails.tsx'
import { AnalogTrackMenu } from '../analog/AnalogTrackMenu.tsx'
import { AnIcon } from '../analog/icons.tsx'
import { useStageMetrics } from '../analog/useStageMetrics.ts'
import { useArtworkWarm } from '../analog/useArtworkWarm.ts'
import { artworkSrc, backdropSrc, failedArtworkIds, resolveArtwork } from '../analog/artwork.ts'
import { newSteppedScrollState, steppedScroll } from '../analog/browseCore.ts'
import { wheelDeltaPx } from '../analog/stageCore.ts'
import { playDetentCue } from '../analog/cue.ts'
import { planForSurface, rememberSurfaceFocus, shelfSnapshot } from '../analog/surface.ts'
import { prefetchTargets, railCursor, railMetrics, stepRailSelection } from '../analog/movieRail.ts'
import type { StageIntent } from '../analog/movieBrowse.ts'
import { mergeDetail, needsEnrichment } from '../analog/movieDetails.ts'
import {
  activationFor,
  closeSeries,
  openSeries,
  resolveSeasonId,
  rootLevel,
  seasonEpisodes,
  seasonFromStack,
  seasonIndex,
  seasonLabel,
  seriesFromStack,
  showsSurface,
  stepSeason,
  withSeason,
  type SeasonItem,
  type ShowLevel,
} from '../analog/showBrowse.ts'
import { showActions, showContext, type ShowStageItem } from '../analog/showDetails.ts'
import {
  defaultSelection,
  parsePlaybackTracks,
  playbackQuery,
  wireSelection,
  type PlaybackTracks,
  type TrackSelection,
} from '../analog/playbackTracks.ts'

/**
 * Shows, on the analog stage.
 *
 * This is the Movies model with one more axis, and deliberately not a second
 * implementation of it:
 *
 * 1. **The library is the detail view.** The focused series' or episode's copy,
 *    metadata and actions render on the browse stage. There is no drill-in for
 *    an episode and no detail screen behind it — Enter plays.
 * 2. **The cursor does not move.** Selection is pinned to the first slot and the
 *    row translates underneath it, via the shared `railWindow`/`clampRailOffset`
 *    in browseCore.ts. `AnalogRail` is the same component Movies uses.
 * 3. **The season is the vertical axis.** It sits on the right rail with the
 *    geometry the Singles/Collections slider took from the old `.library-seasons`
 *    rail, and answers to the same Up/Down and stepped-scroll intents.
 * 4. **A series drills in.** Enter on a series turns its episodes into the
 *    bottom rail and its seasons into the right one. Back returns to the list,
 *    landing on the exact series it was left from (`restoreFocus`, via
 *    surface.ts).
 *
 * The season rides on the browse stack, so a party follower lands on the season
 * the driver is reading rather than on season 1.
 */

interface LibraryView {
  Id: string
  Name: string
  Type: string
  CollectionType?: string
}

const showItems = (value: unknown): ShowStageItem[] =>
  arrayOf(value, (candidate): candidate is ShowStageItem => isLibraryItemJson(candidate))

const seasonItems = (value: unknown): SeasonItem[] =>
  arrayOf(value, (candidate): candidate is SeasonItem => isLibraryItemJson(candidate))

function parseViews(value: unknown): LibraryView[] {
  if (!isRecord(value)) return []
  return arrayOf(value.views, (candidate): candidate is LibraryView => isLibraryItemJson(candidate))
}

// Jellyfin's CollectionType for a TV library is `tvshows`, but a hand-made
// folder library has none at all and only its name to go on — which is why the
// name is checked too, exactly as the surface this replaces did.
const isShowsView = (view: LibraryView) => {
  const label = (view.CollectionType || view.Name || '').toLowerCase()
  return label.includes('tv') || label.includes('show') || label.includes('series')
}

const getJson = (url: string) =>
  fetch(url, { credentials: 'include' }).then((response) =>
    response.ok ? apiJson(response) : Promise.reject(response),
  )

export default function ShowsStage() {
  const { user, logout, profile } = useAuth()
  const party = useParty()
  const hub = useDownloadsHub()
  const { layout, motion, viewportWidthPx } = useStageMetrics()

  const [views, setViews] = useState<LibraryView[] | null>(null)
  const [internalStack, setInternalStack] = useState<ShowLevel[]>([])
  const [seriesList, setSeriesList] = useState<ShowStageItem[] | null>(null)
  const [seasonsBySeries, setSeasonsBySeries] = useState<Record<string, SeasonItem[]>>({})
  const [episodesBySeason, setEpisodesBySeason] = useState<Record<string, ShowStageItem[]>>({})
  const [details, setDetails] = useState<Record<string, ShowStageItem>>({})
  const [error, setError] = useState('')
  const [selection, setSelection] = useState(0)

  // Everyone browses their own library. A room shares playback, chat and
  // A/V — never navigation.
  const stack: ShowLevel[] = internalStack

  const setStack = (next: ShowLevel[]) => setInternalStack(next)

  const viewId = stack[0]?.id ?? null
  const seriesLevel = seriesFromStack(stack)
  const seriesId = seriesLevel?.id ?? null

  // ── data ──────────────────────────────────────────────────────────────────

  useEffect(() => {
    getJson('/api/library/home')
      .then((value) => setViews(parseViews(value)))
      .catch(() => setError('Failed to load your library'))
  }, [])

  // Resolve the TV collection once, as the root of the stack — the same shape
  // pages/Library.tsx publishes, so a host on either implementation still drives
  // a guest on the other.
  useEffect(() => {
    if (!views || stack.length > 0) return
    const target = views.find(isShowsView)
    if (target) setStack([rootLevel(target)])
    else if (views.length > 0) setError('No TV library found on this server')
  }, [views, stack.length])

  useEffect(() => {
    if (!viewId || seriesList !== null) return
    let cancelled = false
    getJson(`/api/library/items/${viewId}/children`)
      .then((value) => !cancelled && setSeriesList(showItems(value)))
      .catch(() => !cancelled && setSeriesList([]))
    return () => {
      cancelled = true
    }
  }, [viewId, seriesList])

  // Seasons and episodes are fetched per level and kept. The surface this
  // replaces fetched EVERY season's episodes up front, in a Promise.all — a
  // twelve-season show cost thirteen requests before it could render one. Here
  // the season axis is a slider over data that arrives as it is asked for, and
  // flicking back to a season already seen costs nothing.
  useEffect(() => {
    if (!seriesId || seasonsBySeries[seriesId]) return
    const id = seriesId
    let cancelled = false
    getJson(`/api/library/items/${id}/children`)
      .then((value) => {
        if (!cancelled) setSeasonsBySeries((previous) => ({ ...previous, [id]: seasonItems(value) }))
      })
      .catch(() => {
        if (!cancelled) setSeasonsBySeries((previous) => ({ ...previous, [id]: [] }))
      })
    return () => {
      cancelled = true
    }
  }, [seriesId, seasonsBySeries])

  const seasons = seriesId ? (seasonsBySeries[seriesId] ?? null) : null

  // Derived rather than written back onto the stack when the seasons land: a
  // follower that defaulted into its own stack would publish over its driver,
  // and both clients derive the same answer from the same list anyway.
  const activeSeasonId = resolveSeasonId(seasons ?? [], seasonFromStack(stack))

  useEffect(() => {
    if (!activeSeasonId || episodesBySeason[activeSeasonId]) return
    const id = activeSeasonId
    let cancelled = false
    getJson(`/api/library/items/${id}/children`)
      .then((value) => {
        if (!cancelled) setEpisodesBySeason((previous) => ({ ...previous, [id]: showItems(value) }))
      })
      .catch(() => {
        if (!cancelled) setEpisodesBySeason((previous) => ({ ...previous, [id]: [] }))
      })
    return () => {
      cancelled = true
    }
  }, [activeSeasonId, episodesBySeason])

  // The series' own detail, once, when it is drilled into. It is what the stage
  // falls back to for a backdrop while episodes have none, and it carries the
  // Primary tag the season-artwork chain needs for its middle step.
  useEffect(() => {
    if (!seriesId || details[seriesId]) return
    const id = seriesId
    let cancelled = false
    getJson(`/api/library/item/${id}`)
      .then((value) => {
        if (cancelled || !isLibraryItemJson(value)) return
        setDetails((previous) => ({ ...previous, [id]: value as unknown as ShowStageItem }))
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [seriesId, details])

  const seriesItem = seriesId
    ? (details[seriesId] ?? (seriesList ?? []).find((item) => item.Id === seriesId) ?? null)
    : null

  const list = seriesId ? seasonEpisodes(episodesBySeason, seasons, activeSeasonId) : seriesList
  const items = useMemo(() => list ?? [], [list])
  const loading = list === null

  // ── focus ─────────────────────────────────────────────────────────────────

  const surface = showsSurface(stack, activeSeasonId)

  // Focus restoration runs off the rail CONTENTS, not off mount: the list can
  // change under a remembered position (an episode removed, a season emptied)
  // and restoreFocus is what decides where that lands. It is also what makes
  // Back land on the exact series that was left from.
  useEffect(() => {
    if (loading) return
    const plan = planForSurface(surface, [shelfSnapshot('shows', items)])
    setSelection(plan.itemIndex < 0 ? 0 : plan.itemIndex)
  }, [surface, items, loading])

  const listed = items[selection] ?? null
  // mergeDetail is generic over nothing, so the show-only fields it copies
  // through (SeriesName, ParentIndexNumber) need naming back on the way out.
  const focused = listed ? (mergeDetail(listed, details[listed.Id]) as ShowStageItem) : null

  useEffect(() => {
    if (!focused) return
    rememberSurfaceFocus(surface, 'shows', focused.Id, selection)
    // The ambient wash the unconverted surfaces read (styles.css `.web-ambient`)
    // still keys off this, so leaving it stale shows the wrong title behind them.
    const primary = artworkSrc(resolveArtwork(focused))
    document.documentElement.style.setProperty(
      '--balanced-poster',
      [backdropSrc(focused.Id), primary].filter(Boolean).map((url) => `url("${url}")`).join(', '),
    )
  }, [surface, focused?.Id, selection])

  // Both lists arrive from `/children`, which asks Jellyfin only for
  // MediaSources — no Overview, no Genres. Fetch the rest for the focused item
  // only, once. The delay is what makes a fast scroll through a season cost one
  // request rather than one per episode.
  useEffect(() => {
    if (!listed || !needsEnrichment(listed) || details[listed.Id]) return
    const id = listed.Id
    let cancelled = false
    const timer = window.setTimeout(() => {
      getJson(`/api/library/item/${id}`)
        .then((value) => {
          if (cancelled || !isLibraryItemJson(value)) return
          setDetails((previous) => ({ ...previous, [id]: value as unknown as ShowStageItem }))
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

  // Track choices belong to the episode they were made for. Playback info is
  // fetched only when the menu is opened, because a POST per step of the rail is
  // exactly the cost a fixed cursor over a whole season must not carry.
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

  const watch = (item: ShowStageItem) => {
    const chosen = tracks ? wireSelection(selected) : undefined
    if (party.session) {
      party.selectMedia(item.Id, chosen)
      navigate(`/party/${party.session.id}`)
      return
    }
    navigate(`/party/new?${playbackQuery(item.Id, chosen)}`)
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

  const setSeason = (next: string | null) => {
    if (!seriesId || !next || next === activeSeasonId) return
    playDetentCue()
    setStack(withSeason(stack, next))
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
    setStack(closeSeries(stack))
  }

  const activate = (index: number) => {
    const target = items[index]
    const action = activationFor(target)
    if (action.kind === 'open') setStack(openSeries(stack, action.series))
    else if (action.kind === 'play' && target) watch(target)
  }

  const onIntent = (intent: StageIntent) => {
    switch (intent) {
      case 'rail-prev':
        return stepRail(-1)
      case 'rail-next':
        return stepRail(1)
      // The vertical axis. On Movies it is the Singles/Collections slider; here
      // it is the season, which is why the intent names are shared rather than
      // each surface inventing its own pair for the same two arrow keys.
      case 'mode-prev':
        return setSeason(stepSeason(seasons ?? [], activeSeasonId, -1))
      case 'mode-next':
        return setSeason(stepSeason(seasons ?? [], activeSeasonId, 1))
      case 'activate':
        return activate(selection)
      case 'back':
        return goBack()
    }
  }

  // A stepped scroll that did NOT land on the rail moves the season axis. The
  // rail swallows its own wheel events, so anything arriving here is outside it.
  const stageScroll = useRef(newSteppedScrollState())
  const onStageWheel = (event: ReactWheelEvent<HTMLDivElement>) => {
    const step = steppedScroll(stageScroll.current, wheelDeltaPx(event), event.timeStamp)
    if (step !== 0) setSeason(stepSeason(seasons ?? [], activeSeasonId, step))
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

  // ── party ─────────────────────────────────────────────────────────────────

  const screen = seriesId ? 'detail' : 'grid'

  // The driver publishes the tab it is on, exactly as the WebShell nav did, so a
  // guest on any client follows. `mediaId`/`seasonId` are published as well —
  // the browse stack carries them for an analog follower, but the phone tree and
  // the superseded Library both read the flat fields. Deliberately NOT keyed on
  // the focused item: that would be a socket emit per step of the rail.
  // ── render ────────────────────────────────────────────────────────────────

  const railItems: AnalogRailItem[] = items.map((item) => ({
    id: item.Id,
    label: item.Name,
    badge: item.Type === 'Episode' && item.IndexNumber != null ? `E${item.IndexNumber}` : null,
    progressPct: item.UserData?.PlayedPercentage ?? null,
    art: item,
  }))

  const rootName = stack[0]?.name || 'Shows'
  const seasonList = seasons ?? []
  const activeSeason = seasonList.find((season) => season.Id === activeSeasonId) ?? null
  const railLabel = seriesId
    ? activeSeason
      ? seasonLabel(activeSeason, Math.max(0, seasonIndex(seasonList, activeSeasonId)))
      : (seriesLevel?.name || 'Episodes')
    : rootName

  return (
    <div className="an-shows" onWheel={onStageWheel}>
      <AnalogStage
        backdropUrl={focused ? backdropSrc(focused.Id) : null}
        // An episode still rarely has wide art of its own, so the show's
        // backdrop is painted underneath it. CSS skips an image it cannot load,
        // so the fallback costs no request to discover.
        backdropFallbackUrl={
          seriesItem ? backdropSrc(seriesItem.Id) : focused ? artworkSrc(resolveArtwork(focused)) : null
        }
        layout={layout}
        motion={motion}
        side={
          seriesId && seasonList.length > 0 ? (
            <AnalogSeasonRail
              seasons={seasonList}
              selectedId={activeSeasonId}
              series={seriesItem}
              onSelect={setSeason}
              motion={motion}
            />
          ) : null
        }
        header={
          <div className="an-stage-head">
            <div className="an-stage-head-row">
              {seriesId ? (
                <button type="button" className="an-back" onClick={goBack}>
                  <AnIcon name="back" size={14} />
                  <span>All shows</span>
                </button>
              ) : null}
            </div>

            <AnalogDetails
              item={focused}
              context={showContext(focused, seriesItem?.Name ?? seriesLevel?.name)}
              fallbackTitle={error ? 'Shows' : loading ? 'Loading' : railLabel}
              error={error || null}
              native={IS_NATIVE}
              actions={showActions(focused, IS_NATIVE)}
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
            active="shows"
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
          emptyTitle={
            !seriesId ? 'No shows here yet' : seasonList.length === 0 ? 'No seasons yet' : 'No episodes in this season'
          }
          emptyHint={
            !seriesId
              ? 'Add something from Discover.'
              : 'Sonarr may still be fetching them — check back after the next scan.'
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
