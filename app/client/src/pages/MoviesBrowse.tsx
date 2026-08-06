import { Suspense, lazy, useEffect, useState } from 'react'
import '../analog/analogKit.css'
import { useAuth } from '../context/AuthContext'
import { useParty } from '../context/PartyContext'
import { useDownloadsHub } from '../context/DownloadsContext'
import { navigate } from '../router'
import { apiJson, arrayOf, isLibraryItemJson, isRecord } from '../types/guards'
import { fmtRuntimeFromTicks } from '../lib/format'
import { AnalogStage } from '../analog/AnalogStage'
import { AnalogShelf, type AnalogShelfItem } from '../analog/AnalogShelf'
import { AnalogNav } from '../analog/AnalogNav'
import { AnalogPartyToolbox, AnalogProfileToolbox } from '../analog/AnalogToolbox'
import { useStageMetrics } from '../analog/useStageMetrics'
import { artworkSrc, backdropSrc, resolveArtwork } from '../analog/artwork'
import { planForSurface, rememberSurfaceFocus, shelfSnapshot, surfaceId, type StackLevel } from '../analog/surface'
import type { DetailTrackSelection, LibraryItem } from './Library'

// Only fetched on drill-in, so browsing does not pay for the detail stage's
// chunk (playback-info, the track menu and the episode dock all live there).
const Details = lazy(() => import('./Library').then((module) => ({ default: module.Details })))

/**
 * Movies browse, rebuilt on the analog kit — the first surface converted for
 * issue #66.
 *
 * One stage: the focused title's backdrop fills it, one shelf owns focus, the
 * modes sit on the bottom edge and the two toolboxes take the right-hand
 * corners. Desktop and phone run the SAME model; only the poster size and the
 * nav's density change, because "phones retain the same stage and focus model
 * rather than switching to a conventional vertical feed".
 *
 * Deliberately still shared with the superseded implementation: the detail
 * stage (pages/Library.tsx `Details`) and the drill-in wire contract
 * (`session.browse.stack`, whose first entry is the collection view). #66 says
 * to remove the superseded implementations only after parity is verified, so
 * this surface interoperates with them rather than forking either.
 */

const SHELF_ID = 'movies'
const DETAIL_TYPES = new Set(['Movie', 'Series', 'Episode'])
const isDetailLevel = (type?: string) => typeof type === 'string' && DETAIL_TYPES.has(type)

interface StageItem {
  Id: string
  Name: string
  Type: string
  ProductionYear?: number
  CommunityRating?: number
  OfficialRating?: string
  RunTimeTicks?: number
  Overview?: string
  IndexNumber?: number
  SeriesId?: string
  ImageTags?: { Primary?: string }
  SeriesPrimaryImageTag?: string
  UserData?: { PlayedPercentage?: number }
}

const isStageItem = (value: unknown): value is StageItem => isLibraryItemJson(value)
const stageItems = (value: unknown): StageItem[] => arrayOf(value, isStageItem)

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

export default function MoviesBrowse() {
  const { user, logout, profile } = useAuth()
  const party = useParty()
  const hub = useDownloadsHub()
  const { layout, motion } = useStageMetrics()

  const [views, setViews] = useState<LibraryView[] | null>(null)
  const [items, setItems] = useState<StageItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [focusedIndex, setFocusedIndex] = useState(0)
  const [profileOpen, setProfileOpen] = useState(false)
  const [partyOpen, setPartyOpen] = useState(false)
  const [internalStack, setInternalStack] = useState<StackLevel[]>([])

  const partyBrowsing = party.session != null
  const canDrive = !partyBrowsing || party.role === 'host'

  // The shared stack wins when the host has published one; otherwise this
  // client's own. A guest whose host has not browsed yet still gets a stage
  // instead of an empty screen, and a driver's local copy is always current.
  const shared = partyBrowsing ? party.session?.browse?.stack : undefined
  const stack: StackLevel[] = shared && shared.length > 0 ? shared : internalStack
  const setStack = (next: StackLevel[]) => {
    setInternalStack(next)
    if (partyBrowsing && canDrive) party.navigateBrowse(next.map((level) => ({ ...level })))
  }

  const current = stack[stack.length - 1] ?? null
  const detailId = current && isDetailLevel(current.type) ? current.id ?? null : null
  // The browse level is the deepest entry that is NOT a title, so drilling into
  // a movie neither refetches nor discards the shelf behind it — which is what
  // makes "Back returns to the exact browsing position" cost nothing.
  const browseLevel = [...stack].reverse().find((level) => !isDetailLevel(level.type)) ?? null
  const browseId = browseLevel?.id ?? null

  useEffect(() => {
    fetch('/api/library/home', { credentials: 'include' })
      .then((response) => (response.ok ? apiJson(response) : Promise.reject(response)))
      .then((value) => setViews(parseViews(value)))
      .catch(() => setError('Failed to load your library'))
  }, [])

  // Resolve the Movies collection once, as the root of the stack — the same
  // shape pages/Library.tsx publishes, so a host on either implementation
  // drives a guest on the other.
  useEffect(() => {
    if (!views || stack.length > 0) return
    const target = views.find(isMoviesView)
    if (target) setStack([{ id: target.Id, name: target.Name, type: target.Type }])
    else if (views.length > 0) setError('No movie library found on this server')
  }, [views, stack.length])

  useEffect(() => {
    if (!browseId) return
    let cancelled = false
    setLoading(true)
    fetch(`/api/library/items/${browseId}/children`, { credentials: 'include' })
      .then((response) => (response.ok ? apiJson(response) : Promise.reject(response)))
      .then((value) => {
        if (!cancelled) setItems(stageItems(value))
      })
      .catch(() => {
        if (!cancelled) setItems([])
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [browseId])

  const surface = surfaceId(SHELF_ID, browseLevel ? [browseLevel] : [])

  // Focus restoration runs off the shelf CONTENTS, not off mount: the shelf can
  // change under a remembered position (a title removed, a library emptied) and
  // restoreFocus is what decides where that lands.
  useEffect(() => {
    if (loading) return
    const plan = planForSurface(surface, [shelfSnapshot(SHELF_ID, items)])
    setFocusedIndex(plan.itemIndex < 0 ? 0 : plan.itemIndex)
  }, [surface, items, loading])

  const focused = items[focusedIndex] ?? null

  useEffect(() => {
    if (!focused) return
    rememberSurfaceFocus(surface, SHELF_ID, focused.Id, focusedIndex)
    // The ambient wash the rest of the app reads (styles.css `.web-ambient`)
    // still keys off this, so leaving it stale would show the wrong title
    // behind the surfaces that have not been converted yet.
    const artwork = resolveArtwork(focused)
    const primary = artworkSrc(artwork)
    document.documentElement.style.setProperty(
      '--balanced-poster',
      [backdropSrc(focused.Id), primary].filter(Boolean).map((url) => `url("${url}")`).join(', '),
    )
  }, [surface, focused, focusedIndex])

  // The host publishes the mode it is on, exactly as the WebShell nav did, so a
  // guest on any client follows. The detail stage publishes its own screen.
  useEffect(() => {
    if (!party.session || party.role !== 'host' || detailId) return
    party.shareView({ tab: 'movies', screen: 'grid' })
  }, [party.session?.id, party.role, detailId])

  const shelfItems: AnalogShelfItem[] = items.map((item) => ({
    id: item.Id,
    label: item.Name,
    badge: item.Type === 'Season' && item.IndexNumber != null ? `S${item.IndexNumber}` : null,
    progressPct: item.UserData?.PlayedPercentage ?? null,
    art: item,
  }))

  const activate = (index: number) => {
    const item = items[index]
    if (!item || !canDrive) return
    setStack([...stack, { id: item.Id, name: item.Name, type: item.Type }])
  }

  const goBack = () => {
    if (!canDrive || stack.length <= 1) return
    setStack(stack.slice(0, -1))
  }

  const watch = (item: LibraryItem, tracks?: DetailTrackSelection) => {
    if (!canDrive) return
    if (party.session) {
      party.selectMedia(item.Id, tracks)
      navigate(`/party/${party.session.id}`)
      return
    }
    const query = new URLSearchParams({ itemId: item.Id })
    if (Number.isInteger(tracks?.audioStreamIndex)) query.set('audioStreamIndex', String(tracks!.audioStreamIndex))
    if (Number.isInteger(tracks?.subtitleStreamIndex)) query.set('subtitleStreamIndex', String(tracks!.subtitleStreamIndex))
    navigate(`/party/new?${query}`)
  }

  const meta = [
    focused?.ProductionYear,
    focused?.OfficialRating,
    focused?.CommunityRating != null ? `★ ${focused.CommunityRating.toFixed(1)}` : null,
    focused?.RunTimeTicks ? fmtRuntimeFromTicks(focused.RunTimeTicks) : null,
  ].filter(Boolean)

  const header = (
    <div className="an-stage-title">
      <div className="an-stage-eyebrow">
        <span>{browseLevel?.name || 'Movies'}</span>
        {meta.map((value, index) => (
          <span key={index}>{value}</span>
        ))}
      </div>
      <h1>{focused?.Name ?? (loading ? 'Loading' : browseLevel?.name ?? 'Movies')}</h1>
      {error ? <p role="alert">{error}</p> : focused?.Overview ? <p>{focused.Overview}</p> : null}
    </div>
  )

  return (
    <>
      <AnalogStage
        backdropUrl={focused ? backdropSrc(focused.Id) : null}
        backdropFallbackUrl={focused ? artworkSrc(resolveArtwork(focused)) : null}
        layout={layout}
        motion={motion}
        inert={!canDrive}
        header={header}
        nav={
          <AnalogNav
            active="movies"
            onNavigate={navigate}
            downloadCount={hub.activeCount}
            failingCount={hub.failingCount}
            compact={layout.size === 'phone'}
          />
        }
        toolboxes={
          <>
            <AnalogProfileToolbox
              open={profileOpen}
              onOpenChange={setProfileOpen}
              userId={user?.userId}
              name={profile?.displayName || user?.name}
              avatar={profile?.avatar}
              onEditProfile={() => {
                setProfileOpen(false)
                navigate('/profile')
              }}
              onSignOut={() => void logout()}
            />
            <AnalogPartyToolbox open={partyOpen} onOpenChange={setPartyOpen} />
          </>
        }
      >
        <AnalogShelf
          label="Movies"
          items={shelfItems}
          focusedIndex={focusedIndex}
          onFocusChange={setFocusedIndex}
          onActivate={activate}
          onBack={stack.length > 1 ? goBack : undefined}
          motion={motion}
          posterWidthPx={layout.posterWidthPx}
          gapPx={layout.gapPx}
          loading={loading}
          skeletonCount={layout.visibleCount + 2}
          emptyTitle="No titles here yet"
          emptyHint="Add something from Discover."
          disabled={!canDrive}
        />
      </AnalogStage>

      {/* The detail stage is still the superseded implementation (see the note
          on `Details`), and its colours come from the `--wp-*` ramp that only
          exists inside `.web-app`. Scoping it here keeps it correct without
          forking a second detail view that would have to be reconciled when the
          rest of #66 lands. */}
      {detailId ? (
        <div className="web-app" data-theme="dark" style={{ zIndex: 60 }}>
          <div className="web-stage">
            <Suspense fallback={null}>
              <Details key={detailId} itemId={detailId} onWatch={watch} onOpen={() => {}} onBack={goBack} />
            </Suspense>
          </div>
        </div>
      ) : null}
    </>
  )
}
