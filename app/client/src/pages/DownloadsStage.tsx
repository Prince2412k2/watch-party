import { useEffect, useMemo, useRef, useState, type WheelEvent as ReactWheelEvent } from 'react'
import '../analog/analogKit.css'
import '../analog/analogDownloads.css'
import { useAuth } from '../context/AuthContext.tsx'
import { useParty } from '../context/PartyContext.tsx'
import { useDownloadsHub } from '../context/DownloadsContext.tsx'
import { navigate } from '../router.ts'
import { canDriveBrowse } from '../partyAuthority.ts'
import { apiJson } from '../types/guards.ts'
import { AnalogStage } from '../analog/AnalogStage.tsx'
import { AnalogNav } from '../analog/AnalogNav.tsx'
import { AnalogProfileTray } from '../analog/AnalogProfileTray.tsx'
import { AnalogPartyWidget } from '../analog/AnalogPartyWidget.tsx'
import { AnalogRail, type AnalogRailItem } from '../analog/AnalogRail.tsx'
import { AnalogDownloadArt, AnalogDownloadDetails } from '../analog/AnalogDownloadDetails.tsx'
import { useStageMetrics } from '../analog/useStageMetrics.ts'
import { newSteppedScrollState, steppedScroll } from '../analog/browseCore.ts'
import { wheelDeltaPx } from '../analog/stageCore.ts'
import { playDetentCue } from '../analog/cue.ts'
import { planForSurface, rememberSurfaceFocus, shelfSnapshot, surfaceId } from '../analog/surface.ts'
import { railMetrics, stepRailSelection } from '../analog/movieRail.ts'
import type { StageIntent } from '../analog/movieBrowse.ts'
import type { FailingQueueItem } from '../hooks/useFailingDownloads.ts'
import {
  DOWNLOADS_MODES,
  DOWNLOADS_MODE_LABELS,
  aggregateParts,
  aggregateRates,
  downloadState,
  modeAvailability,
  openRemoval,
  parseCatalog,
  primaryAction,
  queueEntry,
  queueKey,
  stageMessage,
  stepDownloadsMode,
  toggleDeleteFiles,
  torrentEntry,
  type DownloadCatalog,
  type DownloadsMode,
  type RailEntry,
  type RemovalIntent,
  type TorrentLike,
} from '../analog/downloadsStage.ts'

/**
 * Downloads, on the analog stage.
 *
 * The screen this replaces was two stacked sections of cards inside the old web
 * shell — which brought a second bottom nav of its own, so the app showed two
 * different tab systems at once — plus a separate full-screen overlay you had to
 * open before you could see a download's speed, ETA, seeds, peers or size, or
 * reach its controls.
 *
 * Here it is the Movies model with downloads in it:
 *
 * 1. **The list is the detail view.** The focused download's artwork, gauge,
 *    live stats and its pause/resume/remove sit on the stage while you browse.
 *    There is no drill-in and no overlay, so nothing is one click further away
 *    than the thing next to it.
 * 2. **The cursor does not move.** Selection is pinned to the first slot of the
 *    bottom rail and the row translates underneath it, over the same
 *    `railWindow`/`clampRailOffset` the Movies rail runs on.
 * 3. **Two modes on the right rail.** Active is the download client's queue;
 *    Needs attention is the Radarr/Sonarr records that died before they ever
 *    became a torrent — which is why they cannot simply be rows in the first
 *    list, and why the old screen had to stack a second section above the grid.
 * 4. **No poller.** Every live number comes from the one hub in
 *    context/DownloadsContext; hooks/downloadsCore.test.ts fails the build if a
 *    screen mounts its own.
 */

const DEFAULT_MODE: DownloadsMode = 'active'

export default function DownloadsStage() {
  const { user, logout, profile } = useAuth()
  const party = useParty()
  const hub = useDownloadsHub()
  const { layout, motion, viewportWidthPx } = useStageMetrics()

  const [mode, setMode] = useState<DownloadsMode>(DEFAULT_MODE)
  const [selection, setSelection] = useState(0)
  /** Non-null while a torrent's removal confirmation is open. */
  const [removal, setRemoval] = useState<RemovalIntent | null>(null)
  /** The queue key whose resolve panel is open. */
  const [resolving, setResolving] = useState<string | null>(null)

  // Outside a party you always drive yourself. Inside one, defer to the tested
  // predicate that mirrors the server's canDrive(): a plain host check drops the
  // collaborative-control case, and a guest who has been handed control should
  // be able to pause a download as well as move the browse cursor.
  const partyBrowsing = party.session != null
  const canDrive = !partyBrowsing || canDriveBrowse(party.session, party.role)

  // ── data ──────────────────────────────────────────────────────────────────

  const torrents = hub.torrents
  const stuck = hub.failing.items
  const availability = modeAvailability(mode, hub.health, hub.healthLoading)

  // "Still arriving" is health not yet answered, or a service that IS ready
  // whose first poll has not landed. A service that is down is not loading —
  // it has an answer, and the answer is a message rather than a skeleton.
  const loading =
    availability === 'loading' ||
    (mode === 'active' && hub.qbitReady && torrents === null) ||
    (mode === 'attention' && hub.arrReady && stuck === null)

  const entries: RailEntry[] = useMemo(
    () => (mode === 'active' ? (torrents ?? []).map(torrentEntry) : (stuck ?? []).map(queueEntry)),
    [mode, torrents, stuck],
  )

  // ── focus ─────────────────────────────────────────────────────────────────

  const surface = surfaceId(`downloads:${mode}`)

  // Restoration runs off the rail CONTENTS rather than off mount, and this rail
  // changes under the cursor constantly: a download finishes and leaves, a stuck
  // grab is removed. `restoreFocus` holds the index when the remembered item is
  // gone, so removing the thing you were looking at lands you on its neighbour
  // instead of back at the start of a fifty-item queue.
  useEffect(() => {
    if (loading) return
    const plan = planForSurface(surface, [
      shelfSnapshot('downloads', entries.map((entry) => ({ Id: entry.key }))),
    ])
    setSelection(plan.itemIndex < 0 ? 0 : plan.itemIndex)
  }, [surface, entries, loading])

  const focused = entries[selection] ?? null

  // The rail entry is a snapshot; the record behind it is re-read from the live
  // poll every render, so the gauge and the stats stay current under the cursor
  // without the stage holding a stale copy of its own.
  const focusedTorrent: TorrentLike | null =
    mode === 'active' && focused ? ((torrents ?? []).find((item) => item.hash === focused.key) ?? null) : null
  const focusedQueue: FailingQueueItem | null =
    mode === 'attention' && focused ? ((stuck ?? []).find((item) => queueKey(item) === focused.key) ?? null) : null

  useEffect(() => {
    if (!focused) return
    rememberSurfaceFocus(surface, 'downloads', focused.key, selection)
  }, [surface, focused?.key, selection])

  // The synopsis, genres, rating and runtime the deleted detail overlay was
  // worth opening for. A download is not in Jellyfin yet, so the *arr record it
  // came from is the only place that copy exists.
  //
  // Once per hash, and behind a short delay: the enriched poll already runs every
  // 2.5s and a lookup fired on every step of the rail would put a request behind
  // each one. The delay is what makes a fast scroll past fifty downloads cost one
  // request rather than fifty.
  const [catalog, setCatalog] = useState<Record<string, DownloadCatalog>>({})
  useEffect(() => {
    const hash = focusedTorrent?.hash
    if (!hash || catalog[hash]) return
    let cancelled = false
    const timer = window.setTimeout(() => {
      fetch(`/api/servarr/downloads/${encodeURIComponent(hash)}/detail`, { credentials: 'include' })
        .then((response) => (response.ok ? apiJson(response) : null))
        .then((value) => {
          const parsed = parseCatalog(value)
          if (cancelled || !parsed) return
          setCatalog((previous) => ({ ...previous, [hash]: parsed }))
        })
        // Radarr and Sonarr are optional deployments and a manual torrent belongs
        // to neither, so a failed lookup is a normal outcome: the stage falls
        // back to what the download client itself reported.
        .catch(() => {})
    }, 140)
    return () => {
      cancelled = true
      window.clearTimeout(timer)
    }
  }, [focusedTorrent?.hash, catalog])

  // A confirmation belongs to the item it was opened on. Carrying it across a
  // step of the rail is how a "Remove" ends up pointed at the wrong download.
  useEffect(() => {
    setRemoval(null)
    setResolving(null)
  }, [focused?.key, mode])

  // ── actions ───────────────────────────────────────────────────────────────

  const runPrimary = () => {
    if (!canDrive || !focusedTorrent) return
    const action = primaryAction(downloadState(focusedTorrent.state), hub.busy.has(focusedTorrent.hash))
    // The button is disabled for this, but Enter reaches the same handler without
    // going through it — so a held key would otherwise fire a second pause on top
    // of one still in flight.
    if (action.disabled) return
    // A failed torrent is resumed to retry it — that is what the download client
    // does with one, and calling it "Resume" is why the old grid looked like it
    // had no answer to a failure at all.
    if (action.kind === 'pause') hub.pause(focusedTorrent)
    else if (action.kind === 'resume' || action.kind === 'retry') hub.resume(focusedTorrent)
  }

  const confirmRemoval = () => {
    if (!removal) return
    hub.remove(removal.hash, removal.deleteFiles)
    setRemoval(null)
  }

  const resolveQueued = (blocklist: boolean) => {
    if (!focusedQueue) return
    hub.failing.remove(focusedQueue, blocklist)
    setResolving(null)
  }

  // ── movement ──────────────────────────────────────────────────────────────

  const changeMode = (next: DownloadsMode) => {
    if (!canDrive || next === mode) return
    playDetentCue()
    setMode(next)
  }

  const stepRail = (direction: number) => {
    setSelection((current) => {
      const next = stepRailSelection(current, entries.length, direction)
      if (next !== current) playDetentCue()
      return next
    })
  }

  // Enter does the primary thing to the focused item, exactly as it plays a
  // focused movie. For a stuck grab that is opening the resolve panel — the two
  // ways out of it are both destructive, so neither may be one keypress away.
  const activate = () => {
    if (!canDrive) return
    if (focusedQueue) {
      setResolving(queueKey(focusedQueue))
      return
    }
    runPrimary()
  }

  const goBack = () => {
    if (removal) setRemoval(null)
    else if (resolving) setResolving(null)
  }

  const onIntent = (intent: StageIntent) => {
    switch (intent) {
      case 'rail-prev':
        return stepRail(-1)
      case 'rail-next':
        return stepRail(1)
      case 'mode-prev':
        return changeMode(stepDownloadsMode(mode, -1))
      case 'mode-next':
        return changeMode(stepDownloadsMode(mode, 1))
      case 'activate':
        return activate()
      case 'back':
        return goBack()
    }
  }

  // A stepped scroll that did NOT land on the rail moves the mode slider; the
  // rail swallows its own wheel events, so anything arriving here is outside it.
  const stageScroll = useRef(newSteppedScrollState())
  const onStageWheel = (event: ReactWheelEvent<HTMLDivElement>) => {
    const step = steppedScroll(stageScroll.current, wheelDeltaPx(event), event.timeStamp)
    if (step !== 0) changeMode(stepDownloadsMode(mode, step))
  }

  // Arrows and Enter must work before anything on the stage has been clicked —
  // a surface that needs a focus click first is one a remote cannot drive. Read
  // through a ref so the listener is attached once rather than being rebuilt on
  // every poll.
  const intentRef = useRef(onIntent)
  intentRef.current = onIntent
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey) return
      const target = event.target as HTMLElement | null
      if (target?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target?.tagName ?? '')) return
      // The rail owns its own keys.
      if (target?.closest?.('.an-rail-viewport')) return
      const intent = stageKeyFallback(event.key)
      if (!intent) return
      // Inside an open confirmation only Escape means anything: stepping the rail
      // from under a dialog would leave it pointed at a different download, and
      // Escape is the one key everyone expects to back out of one.
      if (intent !== 'back' && target?.closest?.('.an-dl-confirm')) return
      event.preventDefault()
      intentRef.current(intent)
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  // ── party ─────────────────────────────────────────────────────────────────

  // The driver publishes the tab it is on, exactly as the shell nav did, so a
  // guest on any client follows onto the same surface.
  useEffect(() => {
    if (!party.session || !canDrive) return
    party.shareView({ tab: 'downloads', screen: 'grid' })
  }, [party.session?.id, canDrive])

  // ── render ────────────────────────────────────────────────────────────────

  const rail = railMetrics(Math.max(0, viewportWidthPx - layout.gutterPx * 2), layout.size)
  const railItems: AnalogRailItem[] = entries.map((entry) => ({
    id: entry.key,
    label: entry.title,
    badge: entry.badge,
    progressPct: entry.progressPct,
  }))
  const artwork = useMemo(() => new Map(entries.map((entry) => [entry.key, entry])), [entries])

  const message = stageMessage(mode, availability, entries.length)
  const counts: Record<DownloadsMode, number> = {
    active: (torrents ?? []).length,
    attention: hub.failingCount,
  }

  const summary =
    mode === 'active'
      ? aggregateParts(aggregateRates(torrents ?? []), hub.activeCount)
      : counts.attention > 0
        ? [`${counts.attention} stuck`]
        : []

  // A failed poll keeps the last good numbers on screen; the hub retries on its
  // own, so this is a note rather than an error. Only meaningful for a service
  // that is supposed to be answering in the first place.
  const reconnecting =
    mode === 'active' ? hub.qbitReady && hub.loadError : hub.arrReady && hub.failing.loadError

  const eyebrow = focused
    ? [DOWNLOADS_MODE_LABELS[mode], `${selection + 1} of ${entries.length}`]
    : [DOWNLOADS_MODE_LABELS[mode]]

  return (
    <div className="an-downloads" onWheel={onStageWheel}>
      <AnalogStage
        backdropUrl={focused?.posterUrl ?? null}
        layout={layout}
        motion={motion}
        inert={!canDrive}
        side={<DownloadsModeSlider mode={mode} counts={counts} onChange={changeMode} disabled={!canDrive} />}
        header={
          <div className="an-stage-head">
            <div className="an-stage-head-row">
              {summary.length > 0 ? (
                <div className="an-dl-summary">
                  {summary.map((part, index) => (
                    <span key={index}>{part}</span>
                  ))}
                </div>
              ) : null}
              {reconnecting ? (
                <span className="an-dl-reconnect" role="status">
                  <i aria-hidden />
                  Reconnecting
                </span>
              ) : null}
            </div>

            <AnalogDownloadDetails
              layout={layout}
              motion={motion}
              eyebrow={eyebrow}
              loading={loading}
              message={message}
              disabled={!canDrive}
              torrent={
                focusedTorrent
                  ? {
                      record: focusedTorrent,
                      catalog: catalog[focusedTorrent.hash] ?? null,
                      busy: hub.busy.has(focusedTorrent.hash),
                      removal,
                      onPrimary: runPrimary,
                      onAskRemove: () => setRemoval(openRemoval(focusedTorrent)),
                      onToggleFiles: () => setRemoval((current) => (current ? toggleDeleteFiles(current) : current)),
                      onCancelRemove: () => setRemoval(null),
                      onConfirmRemove: confirmRemoval,
                    }
                  : null
              }
              queue={
                focusedQueue
                  ? {
                      item: focusedQueue,
                      busy: hub.failing.busy.has(focusedQueue.id),
                      open: resolving === queueKey(focusedQueue),
                      onAsk: () => setResolving(queueKey(focusedQueue)),
                      onCancel: () => setResolving(null),
                      onRemove: resolveQueued,
                    }
                  : null
              }
            />
          </div>
        }
        nav={
          <AnalogNav
            active="downloads"
            onNavigate={navigate}
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
          label={DOWNLOADS_MODE_LABELS[mode]}
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
          // Title only: the stage above is already carrying the explanation, and
          // printing the same two sentences twice on one screen reads as a bug.
          emptyTitle={message?.title ?? 'Nothing here'}
          disabled={!canDrive}
          renderPoster={(item, isFocused) => (
            <AnalogDownloadArt
              posterUrl={artwork.get(item.id)?.posterUrl ?? null}
              title={item.label}
              focused={isFocused}
              motion={motion}
              caption={item.label}
              badge={item.badge}
              progressPct={item.progressPct}
              eager
            />
          )}
        />
      </AnalogStage>
    </div>
  )
}

/**
 * Active ⇄ Needs attention, on the right rail.
 *
 * Presented the way the Movies stage presents Singles/Collections — plain text
 * positions each carrying their own detent rule, driven by Up/Down and by a
 * stepped scroll outside the rail, but still real buttons: a mode switch
 * reachable only by gesture would be an important action hidden behind one.
 *
 * The count rides on the position rather than only on the nav badge, because
 * "is anything stuck?" is the question this mode exists to answer and switching
 * to it to find out "no" is the wrong way round.
 */
function DownloadsModeSlider({
  mode,
  counts,
  onChange,
  disabled,
}: {
  mode: DownloadsMode
  counts: Record<DownloadsMode, number>
  onChange: (mode: DownloadsMode) => void
  disabled: boolean
}) {
  return (
    <div className="an-modes" role="tablist" aria-label="Downloads view">
      {DOWNLOADS_MODES.map((candidate) => {
        const count = counts[candidate]
        return (
          <button
            key={candidate}
            type="button"
            role="tab"
            className={candidate === mode ? 'is-active' : ''}
            aria-selected={candidate === mode}
            disabled={disabled}
            onClick={() => onChange(candidate)}
          >
            <span>{DOWNLOADS_MODE_LABELS[candidate]}</span>
            {count > 0 ? <small>{count}</small> : null}
            {/* Selection is never colour alone: the active position also carries
                the longer detent rule and a larger label. */}
            <i aria-hidden />
          </button>
        )
      })}
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
