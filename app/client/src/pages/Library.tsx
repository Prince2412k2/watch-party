import { forwardRef, useEffect, useRef, useState, type CSSProperties, type FormEvent, type KeyboardEvent as ReactKeyboardEvent, type MouseEvent, type ReactNode } from 'react'
import { useAuth } from '../context/AuthContext'
import { useParty } from '../context/PartyContext'
import { useIsMobile } from '../hooks/useIsMobile'
import { useFailingCount } from '../hooks/useFailingDownloads'
import { isActiveState } from '../hooks/useTorrents'
import { navigate } from '../router'
import { mirror } from '../mirror'
import { DownloadPoster, DownloadDetail } from '../components/DownloadDetail'
import { C, SANS, MONO, Ic, Icon, viewIcon, NavRow, GlassBtn } from '../lib/ui'
import { fmtRuntimeFromTicks, fmtSpeed } from '../lib/format'
import { movePosterSelection } from '../components/posterSelection'
import { apiJson, arrayOf, isLibraryItemJson, isRecord, isTorrentJson } from '../types/guards'
import type { PlaybackTrack } from '../types/media'

type ItemType = 'Movie' | 'Series' | 'Episode' | 'Season' | 'CollectionFolder' | 'Folder' | 'UserView' | string
interface LibraryItem {
  Id: string; Name: string; Type: ItemType; CollectionType?: string; SeriesId?: string; SeriesName?: string
  ProductionYear?: number; ParentIndexNumber?: number; IndexNumber?: number
  ChildCount?: number; RecursiveItemCount?: number; CommunityRating?: number; CriticRating?: number
  OfficialRating?: string; Overview?: string; PremiereDate?: string; RunTimeTicks?: number
  Genres?: string[]; People?: Person[]; ProviderIds?: { Imdb?: string; Tmdb?: string }
  UserData?: { PlayedPercentage?: number; Played?: boolean; PlaybackPositionTicks?: number }
  MediaSources?: Array<{ Size?: number; MediaStreams?: Array<{ Type?: string; Height?: number; VideoRange?: string }> }>
}
interface Person { Id: string; Name: string; Type: string; Role?: string }
interface LibraryHome { views: LibraryItem[]; resume: LibraryItem[]; nextUp: LibraryItem[] }
const isLibraryItem = (value: unknown): value is LibraryItem => isLibraryItemJson(value)
const libraryItems = (value: unknown): LibraryItem[] => arrayOf(value, isLibraryItem)
function parseLibraryHome(value: unknown): LibraryHome | null {
  if (!isRecord(value)) return null
  return { views: libraryItems(value.views), resume: libraryItems(value.resume), nextUp: libraryItems(value.nextUp) }
}
interface StackEntry { id?: string; name?: string; type?: ItemType; [key: string]: unknown }
interface Torrent { hash: string; state?: string; progress?: number; displayTitle?: string; name?: string; subtitle?: string; posterUrl?: string; kind?: string; dlspeed?: number }
interface MirrorPoint { scroll: number; x: number; y: number }
type StackUpdater = StackEntry[] | ((stack: StackEntry[]) => StackEntry[])
interface LibraryProps { embedded?: boolean; libraryType?: 'movies' | 'series'; stack?: StackEntry[]; onNavigate?: (stack: StackEntry[]) => void; onPickMedia?: (item: LibraryItem, tracks?: DetailTrackSelection) => void; canDrive?: boolean; headerRight?: ReactNode; banner?: ReactNode; onPointer?: (point: MirrorPoint) => void; mirrorSubscribe?: (listener: (point: MirrorPoint) => void) => () => void; driverName?: string }
interface DetailPlayback {
  mediaSourceId?: string | null
  audioStreams: PlaybackTrack[]
  subtitleStreams: PlaybackTrack[]
  selectedAudioIndex?: number | null
  selectedSubtitleIndex?: number | null
}
interface DetailTrackSelection { audioStreamIndex?: number | null; subtitleStreamIndex?: number | null }
function parseDetailPlayback(value: unknown): DetailPlayback | null {
  if (!isRecord(value)) return null
  const tracks = (raw: unknown): PlaybackTrack[] => Array.isArray(raw)
    ? raw.filter(isRecord).flatMap(track => typeof track.index === 'number' ? [{
      index: track.index,
      displayTitle: typeof track.displayTitle === 'string' ? track.displayTitle : undefined,
      title: typeof track.title === 'string' ? track.title : undefined,
      language: typeof track.language === 'string' ? track.language : undefined,
      codec: typeof track.codec === 'string' ? track.codec : undefined,
      isDefault: track.isDefault === true,
      isForced: track.isForced === true,
      isExternal: track.isExternal === true,
      deliveryUrl: typeof track.deliveryUrl === 'string' ? track.deliveryUrl : null,
    }] : [])
    : []
  return {
    mediaSourceId: typeof value.mediaSourceId === 'string' ? value.mediaSourceId : null,
    audioStreams: tracks(value.audioStreams),
    subtitleStreams: tracks(value.subtitleStreams),
    selectedAudioIndex: typeof value.selectedAudioIndex === 'number' ? value.selectedAudioIndex : null,
    selectedSubtitleIndex: typeof value.selectedSubtitleIndex === 'number' ? value.selectedSubtitleIndex : null,
  }
}

const img = (id: string, type = 'Primary') => `/api/library/image/${id}?type=${type}`

let posterCueContext: AudioContext | null = null
function playPosterMoveCue() {
  try {
    const context = posterCueContext ??= new AudioContext()
    const oscillator = context.createOscillator()
    const gain = context.createGain()
    const now = context.currentTime
    oscillator.type = 'sine'
    oscillator.frequency.setValueAtTime(460, now)
    oscillator.frequency.exponentialRampToValueAtTime(360, now + .045)
    gain.gain.setValueAtTime(.018, now)
    gain.gain.exponentialRampToValueAtTime(.0001, now + .055)
    oscillator.connect(gain).connect(context.destination)
    oscillator.start(now)
    oscillator.stop(now + .06)
  } catch {
    // Audio feedback is optional when Web Audio is unavailable or blocked.
  }
}

function setBalancedPoster(id: string) {
  document.documentElement.style.setProperty('--balanced-poster', `url("${img(id, 'Backdrop')}"), url("${img(id)}")`)
}

/**
 * Poll active-download count from qBittorrent while the page is visible.
 * Returns { active, torrents } — active is the count of actively-downloading
 * torrents (shared isActiveState, so this badge matches the Browse/Downloads
 * badges exactly and excludes seeding/completed/errored items).
 * Servarr-unconfigured / unreachable simply yields active:0 and torrents:[],
 * so every consumer degrades to rendering nothing. Lifecycle: polls ~5s only
 * while the tab is visible, cancels the in-flight request on unmount/hide, and
 * clears the interval. Disabled entirely when `enabled` is false (embedded).
 */
function useDownloads(enabled: boolean) {
  const [torrents, setTorrents] = useState<Torrent[]>([])
  useEffect(() => {
    if (!enabled) { setTorrents([]); return }
    let timer: ReturnType<typeof setInterval> | null = null
    let ctrl: AbortController | null = null
    const poll = () => {
      ctrl?.abort()
      // Capture this run's controller locally so a slower earlier response can't
      // read a newer run's `ctrl` and slip past the aborted-guard to clobber state.
      const c = new AbortController()
      ctrl = c
      // Enriched endpoint = the raw torrent list + a clean displayTitle/subtitle/
      // posterUrl per item (superset of /qbittorrent/torrents), so the
      // "Downloading now" cards can show a title + poster instead of the raw name.
      fetch('/api/servarr/downloads/enriched', { credentials: 'include', signal: c.signal })
        .then(r => r.ok ? apiJson(r) : Promise.reject(r))
        .then(data => { if (!c.signal.aborted) setTorrents(arrayOf(data, isTorrentJson)) })
        .catch(() => { if (!c.signal.aborted) setTorrents([]) })
    }
    const start = () => { if (timer == null) { poll(); timer = setInterval(poll, 5000) } }
    const stop = () => { if (timer != null) { clearInterval(timer); timer = null } ctrl?.abort() }
    const onVis = () => (document.hidden ? stop() : start())
    if (!document.hidden) start()
    document.addEventListener('visibilitychange', onVis)
    return () => { document.removeEventListener('visibilitychange', onVis); stop() }
  }, [enabled])
  const active = torrents.filter(t => isActiveState(t.state)).length
  return { active, torrents }
}
const isFolder = (t?: ItemType) => t === 'Series' || t === 'Season' || t === 'CollectionFolder' || t === 'Folder' || t === 'UserView'
const DETAIL_TYPES = new Set(['Movie', 'Series', 'Episode'])
const isDetail = (t?: ItemType) => typeof t === 'string' && DETAIL_TYPES.has(t)

/**
 * Robust image. Tries `type`, then an optional `fallback` {id,type}, then
 * renders nothing. A 404 is recorded in a session-wide set, so a missing image
 * is NEVER requested again — even if the component remounts repeatedly (which
 * is what caused the runaway 404 storm). Bounded to one request per art URL.
 */
const failedArt = new Set<string>()
function Img({ id, type = 'Primary', fallback, style, alt = '' }: { id: string; type?: string; fallback?: { id: string; type: string }; style?: CSSProperties; alt?: string }) {
  const [, force] = useState(0)
  const candidates = [{ id, type }, fallback].filter(c => c?.id)
  const cur = candidates.find((c): c is { id: string; type: string } => Boolean(c?.id) && !failedArt.has(`${c!.id}:${c!.type}`))
  if (!cur) return null
  return <img src={img(cur.id, cur.type)} alt={alt} style={style}
    onError={() => { failedArt.add(`${cur.id}:${cur.type}`); force(n => n + 1) }} />
}

/**
 * Standalone (default): manages its own nav, clicking a title starts a party.
 * Embedded (room lobby): `stack` is controlled + synced; `onNavigate` reports
 * drills, `onPickMedia` fires on Watch, `canDrive` gates interaction.
 */
export default function Library({
  embedded = false, libraryType, stack: extStack, onNavigate, onPickMedia,
  canDrive = true, headerRight, banner,
  onPointer, mirrorSubscribe, driverName,
}: LibraryProps = {}) {
  const { user, logout } = useAuth()
  const party = useParty()
  const mobile = useIsMobile()
  const [home, setHome] = useState<LibraryHome | null>(null)
  const [loadingHome, setLoadingHome] = useState(true)
  const [error, setError] = useState('')
  const [internalStack, setInternalStack] = useState<StackEntry[]>([])
  const [gridItems, setGridItems] = useState<LibraryItem[]>([])
  const [loadingGrid, setLoadingGrid] = useState(false)
  const previousLibraryType = useRef(libraryType)
  // Active-download detail overlay (standalone only). Holds the enriched torrent
  // that was clicked; kept fresh from the live poll while open (see render).
  const [dlDetail, setDlDetail] = useState<Torrent | null>(null)

  // Active downloads (qBittorrent). Standalone only — the embedded lobby stays
  // lean and Servarr-agnostic. Degrades to empty when Servarr isn't configured.
  const { active: dlActive, torrents: dlTorrents } = useDownloads(!embedded)
  const failingCount = useFailingCount(!embedded)

  const partyBrowsing = !embedded && party.session != null
  if (partyBrowsing) canDrive = party.role === 'host'
  const stack = embedded ? (extStack ?? []) : partyBrowsing ? (party.session?.browse?.stack ?? []) : internalStack
  const setStack = (updater: StackUpdater) => {
    const next = typeof updater === 'function' ? updater(stack) : updater
    if (embedded) onNavigate?.(next)
    else if (partyBrowsing) party.navigateBrowse(next)
    else setInternalStack(next)
  }
  const current = stack[stack.length - 1] || null

  useEffect(() => {
    setLoadingHome(true)
    fetch('/api/library/home', { credentials: 'include' })
      .then(r => r.ok ? apiJson(r) : Promise.reject(r))
      .then(value => setHome(parseLibraryHome(value))).catch(() => setError('Failed to load your library'))
      .finally(() => setLoadingHome(false))
  }, [])

  // Deep-link: /library?view=<Jellyfin view id> opens that library view directly.
  // Used by the shared nav on Browse/Downloads so a library row there lands here
  // showing the view. Runs once home loads (so we can resolve name/type), then
  // clears the param so a later Home click / refresh doesn't re-trigger it.
  useEffect(() => {
    if (embedded || !home) return
    const viewId = new URLSearchParams(window.location.search).get('view')
    if (!viewId) return
    const v = (home.views || []).find((x) => x.Id === viewId)
    if (v) setInternalStack([{ id: v.Id, name: v.Name, type: v.Type }])
    window.history.replaceState(window.history.state, '', window.location.pathname)
  }, [home, embedded])

  useEffect(() => {
    if (embedded || previousLibraryType.current === libraryType) return
    previousLibraryType.current = libraryType
    setInternalStack([])
  }, [embedded, libraryType])

  useEffect(() => {
    if (embedded || !libraryType || !home || stack.length) return
    const target = home.views.find(view => {
      const type = (view.CollectionType || view.Name || '').toLowerCase()
      return libraryType === 'movies' ? type.includes('movie') : type.includes('tv') || type.includes('show') || type.includes('series')
    })
    if (target) setStack([{ id: target.Id, name: target.Name, type: target.Type }])
  }, [embedded, libraryType, home, stack.length])

  useEffect(() => {
    if (!current || isDetail(current.type)) return
    setLoadingGrid(true)
    fetch(`/api/library/items/${current.id}/children`, { credentials: 'include' })
      .then(r => r.ok ? apiJson(r) : Promise.reject(r))
      .then(value => setGridItems(libraryItems(value))).catch(() => setGridItems([]))
      .finally(() => setLoadingGrid(false))
  }, [current?.id])

  useEffect(() => {
    const first = gridItems.find(item => item.Type === 'Movie' || item.Type === 'Series') ?? gridItems[0]
    if (first) setBalancedPoster(first.Id)
  }, [gridItems])

  // ── Screen mirroring ────────────────────────────────────────────────────
  // scrollRef is attached to the scrollable *content pane* (right of the
  // sidebar). Its scroll fraction is what we broadcast / follow.
  const scrollRef = useRef<HTMLDivElement>(null)
  const ghostRef = useRef<HTMLDivElement>(null)
  const broadcastPointer = onPointer ?? (partyBrowsing ? party.sendPointer : undefined)
  const subscribeToMirror = mirrorSubscribe ?? (partyBrowsing ? mirror.subscribe : undefined)
  const driving = (embedded || partyBrowsing) && canDrive && !!broadcastPointer
  const following = (embedded || partyBrowsing) && !canDrive && !!subscribeToMirror

  // Driver: publish scroll fraction + cursor, coalesced to one send per frame.
  //
  // COORDINATE BASIS: the cursor x/y are fractions of the *content pane's*
  // bounding rect — NOT the raw window. After the redesign the pane is inset by
  // the sidebar (fixed px) plus margins, so a window-relative fraction would
  // land the ghost in the wrong spot (offset by the sidebar), and would differ
  // between host/guest viewports because the sidebar width is fixed, not
  // proportional. The pane is rendered identically on both sides, so a
  // pane-relative fraction maps correctly across ANY viewport size.
  //
  // We use the pane's *viewport* rect (getBoundingClientRect) and do NOT add
  // scrollTop: this is a "screen mirror" — the ghost floats over what the host
  // currently SEES on screen, so the fraction is viewport-relative within the
  // pane, matching the scroll that we mirror separately.
  useEffect(() => {
    if (!driving) return
    const el = scrollRef.current
    if (!el) return
    const last = { scroll: 0, x: 0.5, y: 0.5 }
    let raf = 0
    const flush = () => { raf = 0; broadcastPointer?.({ ...last }) }
    const queue = () => { if (!raf) raf = requestAnimationFrame(flush) }
    const onScroll = () => {
      const sh = el.scrollHeight - el.clientHeight
      last.scroll = sh > 0 ? el.scrollTop / sh : 0
      queue()
    }
    const onMove = (e: globalThis.MouseEvent) => {
      // Convert the window-level mouse position to a fraction of the pane rect.
      // (We listen on window so we still capture moves that start over the
      // sidebar, but the coordinates are always expressed pane-relative.)
      const r = el.getBoundingClientRect()
      if (r.width <= 0 || r.height <= 0) return
      const fx = (e.clientX - r.left) / r.width
      const fy = (e.clientY - r.top) / r.height
      // Clamp to 0..1. When the host's pointer is over the sidebar or otherwise
      // outside the pane, it clamps to the nearest pane edge — the ghost parks
      // at the border rather than flying off-screen or landing on nonsense
      // content. Simple and predictable for a screen mirror.
      last.x = Math.max(0, Math.min(1, fx))
      last.y = Math.max(0, Math.min(1, fy))
      queue()
    }
    el.addEventListener('scroll', onScroll, { passive: true })
    window.addEventListener('mousemove', onMove, { passive: true })
    return () => {
      el.removeEventListener('scroll', onScroll)
      window.removeEventListener('mousemove', onMove)
      cancelAnimationFrame(raf)
    }
  }, [driving, broadcastPointer, current?.id])

  // Follower: apply the host's scroll + cursor imperatively (no re-render).
  // The ghost is positioned using the FOLLOWER's OWN pane rect: paneLeft +
  // x*paneWidth, paneTop + y*paneHeight. Because both sides express the cursor
  // as a fraction of their own (identically-laid-out) pane, the mapping is
  // viewport-independent — a guest on a smaller/larger screen still sees the
  // ghost over the same poster the host is pointing at.
  useEffect(() => {
    if (!following) return
    let raf = 0
    let pending = { scroll: 0, x: 0.5, y: 0.5 }
    const apply = () => {
      raf = 0
      const el = scrollRef.current
      if (el && typeof pending.scroll === 'number') {
        const sh = el.scrollHeight - el.clientHeight
        el.scrollTop = pending.scroll * sh
      }
      const g = ghostRef.current
      if (g && el) {
        const r = el.getBoundingClientRect()
        const x = r.left + pending.x * r.width
        const y = r.top + pending.y * r.height
        g.style.transform = `translate(${x}px, ${y}px)`
      }
    }
    const onFrame = (p: MirrorPoint) => { pending = p; if (!raf) raf = requestAnimationFrame(apply) }
    const unsub = subscribeToMirror!(onFrame)
    onFrame(pending) // apply current position on mount / view change
    return () => { unsub(); cancelAnimationFrame(raf) }
  }, [following, subscribeToMirror, current?.id])

  function open(item: LibraryItem) { if (canDrive) setStack(s => [...s, { id: item.Id, name: item.Name, type: item.Type }]) }
  function pick(item: LibraryItem, tracks?: DetailTrackSelection) {
    if (!canDrive) return
    if (onPickMedia) onPickMedia(item, tracks)
    else if (party.session) {
      party.selectMedia(item.Id, tracks)
      navigate(`/party/${party.session.id}`)
    }
    else {
      const qs = new URLSearchParams({ itemId: item.Id })
      if (Number.isInteger(tracks?.audioStreamIndex)) qs.set('audioStreamIndex', String(tracks!.audioStreamIndex))
      if (Number.isInteger(tracks?.subtitleStreamIndex)) qs.set('subtitleStreamIndex', String(tracks!.subtitleStreamIndex))
      navigate(`/party/new?${qs}`)
    }
  }
  const openDownload = (t: Torrent) => { if (canDrive) setDlDetail(t) }
  const goHome = () => { if (canDrive) setStack([]) }
  const goBack = () => { if (canDrive) setStack(s => s.slice(0, -1)) }
  const goToDepth = (i: number) => { if (canDrive) setStack(s => s.slice(0, i + 1)) }
  const openView = (v: LibraryItem) => { if (canDrive) setStack([{ id: v.Id, name: v.Name, type: v.Type }]) }

  const initials = user?.name?.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2) || '?'
  const views = home?.views ?? []
  const sidebarW = mobile ? 62 : 236

  return (
    // Outer shell: fixed full-bleed. Holds the flush sidebar and the scrollable
    // content pane. It does NOT scroll itself.
    <div style={{
      position: 'absolute', inset: 0, background: 'transparent', color: C.text, fontFamily: SANS,
      overflow: 'hidden',
    }}>
      {following && <GhostCursor ref={ghostRef} name={driverName} />}

      {(embedded || !libraryType) && <Sidebar mobile={mobile} width={sidebarW} views={views} activeId={current ? (stack[0]?.id ?? null) : null}
        onHome={goHome} onView={openView} showDiscover={!embedded} downloadCount={dlActive} failingCount={failingCount} />
      }

      {/* Scrollable content pane — flush to the viewport edge (no inset panel).
          This is the element the mirror engine drives. */}
      <div ref={scrollRef} style={{
        position: 'absolute', top: 0, right: 0, bottom: 0, left: (embedded || !libraryType) ? sidebarW : 0,
        overflow: 'hidden auto',
        overflowY: following ? 'hidden' : 'auto',
      }}>
        {(embedded || !libraryType) && <TopBar embedded={embedded} mobile={mobile} initials={initials} logout={logout}
          headerRight={headerRight} current={current} onBack={goBack} onHome={goHome} />
        }

        {banner}
        {error && (
          <div style={{ margin: '14px 20px', padding: '12px 16px', borderRadius: 12,
            background: 'rgba(224,101,94,.12)', border: `1px solid rgba(224,101,94,.35)`, color: C.red, fontSize: 14 }}>{error}</div>
        )}

        <div style={{ pointerEvents: canDrive ? 'auto' : 'none' }}>
          {!current && <HomeView home={home} loading={loadingHome} onOpen={open} onOpenView={openView}
            embedded={embedded} downloads={dlTorrents} onOpenDownload={openDownload} />}
          {current?.id && isDetail(current.type) && (
            <Details key={current.id} itemId={current.id} onWatch={pick} onOpen={open} onBack={goBack} />
          )}
          {current && !isDetail(current.type) && (
            <GridView stack={stack} items={gridItems} loading={loadingGrid} onOpen={open} onCrumb={goToDepth} onHome={goHome} />
          )}
        </div>
      </div>

      {/* Active-download detail — full-screen overlay. The torrent is re-read from
          the live poll each render so the ring + stats stay current; falls back to
          the click-time snapshot once it leaves the list (completed/removed). */}
      {!embedded && dlDetail && (
        <DownloadDetail
          torrent={dlTorrents.find((t) => t.hash === dlDetail.hash) || dlDetail}
          onClose={() => setDlDetail(null)} />
      )}
    </div>
  )
}

/* ── Ghost cursor (host's pointer, mirrored to followers) ───────────────── */
const GhostCursor = forwardRef<HTMLDivElement, { name?: string }>(function GhostCursor({ name }, ref) {
  return (
    <div ref={ref} aria-hidden style={{
      position: 'fixed', top: 0, left: 0, zIndex: 200, pointerEvents: 'none',
      willChange: 'transform', transition: 'transform .08s linear',
      display: 'flex', alignItems: 'flex-start', gap: 6,
    }}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="#fff" style={{ filter: 'drop-shadow(0 1px 3px rgba(0,0,0,.7))' }}>
        <path d="M5 3l14 8-6 1.5L9.5 19z" stroke="#0a0a0c" strokeWidth="1" strokeLinejoin="round" />
      </svg>
      {name && (
        <span style={{
          marginTop: 12, padding: '2px 8px', borderRadius: 6, fontSize: 11, fontWeight: 700, whiteSpace: 'nowrap',
          background: C.surface3, color: C.text, boxShadow: '0 2px 8px rgba(0,0,0,.5)',
        }}>{name}</span>
      )}
    </div>
  )
})

/* ── Flush sidebar (edge-to-edge, hairline border, no floating panel) ───── */
function Sidebar({ mobile, width, views, activeId, onHome, onView, showDiscover, downloadCount = 0, failingCount = 0 }: { mobile: boolean; width: number; views: LibraryItem[]; activeId: string | null; onHome: () => void; onView: (view: LibraryItem) => void; showDiscover: boolean; downloadCount?: number; failingCount?: number }) {
  return (
    <aside style={{
      position: 'absolute', top: 0, left: 0, bottom: 0,
      width, zIndex: 20, display: 'flex', flexDirection: 'column',
      padding: mobile ? '12px 8px' : '22px 16px',
      background: C.bg, borderRight: `1px solid ${C.line}`,
    }}>
      {!mobile && (
        <div style={{ display: 'flex', alignItems: 'center', padding: '2px 8px 22px', cursor: 'pointer' }} onClick={onHome}>
          <span style={{ fontSize: 15, fontWeight: 700, letterSpacing: '-.01em' }}>Watchparty</span>
        </div>
      )}

      <nav style={{ display: 'flex', flexDirection: 'column', gap: 3, overflowY: 'auto', scrollbarWidth: 'none', flex: 1 }}>
        <NavRow mobile={mobile} icon={Ic.home} label="Home" active={!activeId} onClick={onHome} />
        {views.map(v => (
          <NavRow key={v.Id} mobile={mobile} icon={viewIcon(v)} label={v.Name} active={activeId === v.Id} onClick={() => onView(v)} />
        ))}
        {showDiscover && (
          <NavRow mobile={mobile} icon={Ic.compass} label="Browse" onClick={() => navigate('/discover')} />
        )}
        {showDiscover && (
          <NavRow mobile={mobile} icon={Ic.download} label="Downloads" badge={downloadCount} alertBadge={failingCount}
            onClick={() => navigate('/downloads')} />
        )}
      </nav>
    </aside>
  )
}


function TopBar({ embedded, mobile, initials, logout, headerRight, current, onBack, onHome }: { embedded: boolean; mobile: boolean; initials: string; logout: () => Promise<void>; headerRight?: ReactNode; current: StackEntry | null; onBack: () => void; onHome: () => void }) {
  const [joinOpen, setJoinOpen] = useState(false)
  return (
    <div style={{
      position: 'sticky', top: 0, zIndex: 15, display: 'flex', alignItems: 'center',
      gap: 12, padding: mobile ? '12px 12px' : '16px 20px',
      background: 'linear-gradient(180deg, rgba(0,0,0,.55), rgba(0,0,0,0))',
    }}>
      {/* Left: back + home when drilled in */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
        {current ? (
          <>
            <GlassBtn onClick={onBack} title="Back"><Icon path={Ic.chevL} size={18} sw={2} /></GlassBtn>
            <GlassBtn onClick={onHome} title="Home"><Icon path={Ic.home} size={17} sw={1.8} /></GlassBtn>
          </>
        ) : (
          <span style={{ fontSize: mobile ? 15 : 17, fontWeight: 800, letterSpacing: '-.01em', paddingLeft: 4 }}>Home</span>
        )}
      </div>

      <div style={{ flex: 1 }} />

      {/* Right: embedded slot OR default standalone actions */}
      {headerRight ?? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0 }}>
          <GlassBtn onClick={() => setJoinOpen(true)} title="Join a party with a code" pill>
            <Icon path={Ic.enter} size={16} sw={2} />
            {!mobile && 'Join'}
          </GlassBtn>
          <GlassBtn onClick={() => navigate('/party/new')} title="Start a watch party" pill>
            <Icon path={Ic.plus} size={16} sw={2.4} />
            {!mobile && 'Start a watch party'}
          </GlassBtn>
          <div title={initials} style={{
            width: 38, height: 38, borderRadius: '50%', display: 'grid', placeItems: 'center',
            fontSize: 12, fontWeight: 700, background: C.surface2, border: `1px solid ${C.line}`, color: C.text, flexShrink: 0,
          }}>{initials}</div>
          <GlassBtn onClick={logout} title="Sign out"><Icon path={Ic.logout} size={17} sw={1.8} /></GlassBtn>
        </div>
      )}

      {joinOpen && <JoinDialog mobile={mobile} onClose={() => setJoinOpen(false)} />}
    </div>
  )
}

// Join-by-code: complements the QR code (which auto-joins via an embedded
// link) with a plain code-entry fallback for anyone who was just told the
// code out loud. Codes are 8-char hex, matching the server's
// randomUUID().slice(0, 8).toUpperCase() (see server/session.js createSession).
function JoinDialog({ mobile, onClose }: { mobile: boolean; onClose: () => void }) {
  const [code, setCode] = useState('')
  const [err, setErr] = useState('')

  function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const clean = code.trim().toUpperCase()
    if (!clean) return setErr('Enter a party code')
    if (!/^[0-9A-F]{8}$/.test(clean)) return setErr('Codes are 8 characters — letters and numbers')
    navigate(`/party/${clean}`)
  }

  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 100, display: 'grid', placeItems: 'center',
      padding: 16, background: 'rgba(0,0,0,.66)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)', animation: 'up .2s ease both' }}>
      <form onClick={(e) => e.stopPropagation()} onSubmit={submit} style={{ width: 'min(380px, 100%)', borderRadius: 16, padding: mobile ? 20 : 26,
        background: C.surface, border: `1px solid ${C.line}`, boxShadow: '0 24px 60px rgba(0,0,0,.7)' }}>
        <h2 style={{ fontSize: 19, fontWeight: 800, margin: '0 0 6px', fontFamily: SANS }}>Join a party</h2>
        <p style={{ color: C.dim, fontSize: 13.5, lineHeight: 1.5, margin: '0 0 16px', fontFamily: SANS }}>
          Enter the code the host shared with you.
        </p>
        <input autoFocus value={code} onChange={e => { setCode(e.target.value); setErr('') }}
          placeholder="A1B2C3D4" maxLength={8}
          style={{ width: '100%', padding: '13px 16px', borderRadius: 10, border: `1px solid ${C.line2}`,
            background: 'rgba(255,255,255,.04)', color: C.text, fontFamily: MONO, fontSize: 18, letterSpacing: '.14em',
            textAlign: 'center', textTransform: 'uppercase', outline: 'none' }} />
        {err && (
          <div role="alert" style={{ marginTop: 12, padding: '10px 14px', borderRadius: 8, background: 'rgba(224,101,94,.12)', border: `1px solid rgba(224,101,94,.35)`, color: C.red, fontSize: 13.5, fontFamily: SANS }}>{err}</div>
        )}
        <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
          <button type="button" onClick={onClose} style={{ flex: 1, height: 46, borderRadius: 13, border: `1px solid ${C.line2}`,
            cursor: 'pointer', fontFamily: SANS, fontSize: 14.5, fontWeight: 700, color: C.text, background: 'rgba(255,255,255,.04)' }}>Cancel</button>
          <button type="submit" style={{ flex: 1, height: 46, borderRadius: 13, border: 'none',
            cursor: 'pointer', fontFamily: SANS, fontSize: 14.5, fontWeight: 700, color: C.onAccent, background: C.accent }}>Join</button>
        </div>
      </form>
    </div>
  )
}

/* ── HOME ───────────────────────────────────────────────────────────────── */
function HomeView({ home, loading, onOpen, onOpenView, embedded, downloads, onOpenDownload }: { home: LibraryHome | null; loading: boolean; onOpen: (item: LibraryItem) => void; onOpenView: (item: LibraryItem) => void; embedded: boolean; downloads: Torrent[]; onOpenDownload: (torrent: Torrent) => void }) {
  const mobileHome = useIsMobile()
  const pad = mobileHome ? '0 16px' : '0 44px'

  // Recently added — fetched independently of /home. Jellyfin-only, so it works
  // regardless of Servarr. /api/library/latest returns a flat array; [] if empty
  // or on any error (endpoint degrades to a clean 502 which we swallow).
  const [latest, setLatest] = useState<LibraryItem[]>([])
  useEffect(() => {
    let cancel = false
    fetch('/api/library/latest', { credentials: 'include' })
      .then(r => r.ok ? apiJson(r) : Promise.reject(r))
      .then(d => { if (!cancel) setLatest(libraryItems(d)) })
      .catch(() => {})
    return () => { cancel = true }
  }, [])

  // "Downloading now" — actively-downloading qBittorrent torrents only (shared
  // isActiveState), so finished-but-seeding titles don't linger here at 100%.
  // Servarr-agnostic: [] when unconfigured/unreachable.
  const arriving = (downloads || []).filter(t => isActiveState(t.state) && (t.dlspeed ?? 0) > 0)

  if (loading) return (
    <div style={{ padding: '4px 0 100px' }}>
      <div style={{ padding: pad }}><RailSkeleton /></div>
    </div>
  )
  if (!home) return null

  return (
    <div style={{ paddingBottom: 100, padding: `4px 0 100px` }}>
      <div style={{ padding: pad }}>
        {home.resume?.length > 0 && (
          <Rail title="Continue watching" count={home.resume.length}>
            {home.resume.map(it => <StillCard key={it.Id} item={it} onClick={() => onOpen(it)} progress />)}
          </Rail>
        )}
        {latest.length > 0 && (
          <Rail title="Recently added" count={latest.length}>
            {latest.map(it => <PosterCard key={it.Id} item={it} onClick={() => onOpen(it)} />)}
          </Rail>
        )}
        {!embedded && arriving.length > 0 && (
          <Rail title="Downloading now" count={arriving.length}>
            {arriving.map(t => <DownloadingCard key={t.hash} torrent={t} onOpen={() => onOpenDownload(t)} />)}
          </Rail>
        )}
        {home.nextUp?.length > 0 && (
          <Rail title="Next up" count={home.nextUp.length}>
            {home.nextUp.map(it => <StillCard key={it.Id} item={it} onClick={() => onOpen(it)} />)}
          </Rail>
        )}
        {home.views?.length > 0 && (
          <Rail title="Libraries" count={home.views.length}>
            {home.views.map(v => <ViewCard key={v.Id} view={v} onClick={() => onOpenView(v)} />)}
          </Rail>
        )}
      </div>
    </div>
  )
}

/* ── Poster card (2:3) fixed-width for the "Recently added" rail ──────────── */
function PosterCard({ item, onClick }: { item: LibraryItem; onClick: () => void }) {
  const [h, setH] = useState(false)
  return (
    <button onClick={onClick} onFocus={() => setBalancedPoster(item.Id)} onMouseEnter={() => { setH(true); setBalancedPoster(item.Id) }} onMouseLeave={() => setH(false)} aria-label={item.Name}
      style={{ flex: '0 0 auto', width: 170, border: 'none', background: 'none', padding: 0, cursor: 'pointer', textAlign: 'left', scrollSnapAlign: 'start' }}>
      <div style={{ position: 'relative', aspectRatio: '2/3', borderRadius: 14, overflow: 'hidden', background: C.surface,
        boxShadow: h ? '0 18px 40px rgba(0,0,0,.55)' : '0 8px 22px rgba(0,0,0,.4)',
        transform: h ? 'translateY(-3px)' : 'none', transition: 'transform .25s, box-shadow .25s' }}>
        <Img id={item.Id} type="Primary" fallback={{ id: item.SeriesId || item.Id, type: 'Backdrop' }} alt={item.Name}
          style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', transform: h ? 'scale(1.06)' : 'scale(1)', transition: 'transform .4s' }} />
        <div style={{ position: 'absolute', top: 8, left: 8, padding: '2px 8px', borderRadius: 999, fontFamily: MONO, fontSize: 10.5, fontWeight: 700,
          background: 'rgba(0,0,0,.6)', color: C.dim, letterSpacing: '.06em' }}>NEW</div>
      </div>
      <div style={{ marginTop: 9, fontSize: 14, fontWeight: 600, color: C.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{item.Name}</div>
      {item.ProductionYear && <div style={{ fontFamily: MONO, fontSize: 12, color: C.faint, marginTop: 2 }}>{item.ProductionYear}</div>}
    </button>
  )
}


/* ── "Downloading now" card — a normal 2:3 poster tile (same rail sizing as
   PosterCard) with the circular progress ring centered over a dark scrim, and a
   clean title + subtitle below. Enriched with the *arr-sourced poster/title
   (dark film/tv placeholder when none yet). Clicking opens the download detail. ── */
function DownloadingCard({ torrent, onOpen }: { torrent: Torrent; onOpen: () => void }) {
  const [h, setH] = useState(false)
  const pct = Math.max(0, Math.min(100, Math.round((torrent.progress || 0) * 100)))
  const title = torrent.displayTitle || torrent.name
  const subtitle = torrent.subtitle || `↓ ${fmtSpeed(torrent.dlspeed)}`
  return (
    <button onClick={onOpen} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} title={torrent.name}
      style={{ flex: '0 0 auto', width: 170, border: 'none', background: 'none', padding: 0, cursor: 'pointer', textAlign: 'left', scrollSnapAlign: 'start' }}>
      <div style={{ position: 'relative', borderRadius: 14, overflow: 'hidden',
        boxShadow: h ? '0 18px 40px rgba(0,0,0,.55)' : '0 8px 22px rgba(0,0,0,.4)',
        transform: h ? 'translateY(-3px)' : 'none', transition: 'transform .25s, box-shadow .25s' }}>
        <DownloadPoster posterUrl={torrent.posterUrl} kind={torrent.kind} pct={pct} paused={(torrent.dlspeed ?? 0) <= 0} width="100%" radius={14} ringSize={78} />
      </div>
      <div style={{ marginTop: 9, fontSize: 14, fontWeight: 600, color: C.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
      {subtitle && <div style={{ fontFamily: MONO, fontSize: 12, color: C.faint, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{subtitle}</div>}
    </button>
  )
}

/* ── Horizontal rail with header + hover scroll arrows (Sen Player style) ── */
function Rail({ title, count, children }: { title: string; count?: number; children: ReactNode }) {
  const trackRef = useRef<HTMLDivElement>(null)
  const [hover, setHover] = useState(false)
  const scrollBy = (dir: number) => {
    const el = trackRef.current
    if (el) el.scrollBy({ left: dir * Math.round(el.clientWidth * 0.8), behavior: 'smooth' })
  }
  return (
    <section style={{ marginBottom: 40, animation: 'up .4s ease both' }}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 14 }}>
        <h2 style={{ fontSize: 21, fontWeight: 800, letterSpacing: '-.02em', color: C.text }}>{title}</h2>
        {count != null && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 4, fontFamily: MONO, fontSize: 13, color: C.dim }}>
            {count}<Icon path={Ic.chevR} size={15} sw={2} />
          </div>
        )}
      </div>
      <div style={{ position: 'relative' }}>
        <div ref={trackRef} style={{ display: 'flex', gap: 16, overflowX: 'auto', scrollbarWidth: 'none', paddingBottom: 6, scrollSnapType: 'x proximity' }}>
          {children}
        </div>
        <RailArrow dir={-1} show={hover} onClick={() => scrollBy(-1)} />
        <RailArrow dir={1} show={hover} onClick={() => scrollBy(1)} />
      </div>
    </section>
  )
}
function RailArrow({ dir, show, onClick }: { dir: number; show: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} aria-label={dir < 0 ? 'Scroll left' : 'Scroll right'} style={{
      position: 'absolute', top: 'calc(50% - 34px)', [dir < 0 ? 'left' : 'right']: 6, transform: 'translateY(-50%)',
      width: 44, height: 44, borderRadius: '50%', display: 'grid', placeItems: 'center', cursor: 'pointer',
      background: 'rgba(0,0,0,.6)', border: `1px solid ${C.line}`, color: '#fff',
      opacity: show ? 1 : 0, pointerEvents: show ? 'auto' : 'none', transition: 'opacity .2s', zIndex: 5,
    }}>
      <Icon path={dir < 0 ? Ic.chevL : Ic.chevR} size={22} sw={2.2} />
    </button>
  )
}
function RailSkeleton() {
  return (
    <div style={{ display: 'flex', gap: 16 }}>
      {Array.from({ length: 6 }).map((_, i) => (
        <div key={i} style={{ flex: '0 0 170px', aspectRatio: '2/3', borderRadius: 14, background: C.surface,
          animation: 'shim 1.3s linear infinite', backgroundImage: `linear-gradient(100deg, ${C.surface} 30%, ${C.surface2} 50%, ${C.surface} 70%)`, backgroundSize: '200% 100%' }} />
      ))}
    </div>
  )
}

/* ── Still card (16:9) for continue watching / next up ──────────────────── */
function StillCard({ item, onClick, progress }: { item: LibraryItem; onClick: () => void; progress?: boolean }) {
  const [h, setH] = useState(false)
  const pct = item.UserData?.PlayedPercentage
  const label = item.SeriesName ? (item.Name || item.SeriesName) : item.Name
  const sub = item.SeriesName
    ? `${item.SeriesName}${item.ParentIndexNumber ? ` · S${item.ParentIndexNumber}·E${item.IndexNumber}` : ''}`
    : (item.ProductionYear || '')
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ flex: '0 0 auto', width: 300, border: 'none', background: 'none', padding: 0, cursor: 'pointer', textAlign: 'left', scrollSnapAlign: 'start' }}>
      <div style={{ position: 'relative', aspectRatio: '16/9', borderRadius: 14, overflow: 'hidden', background: C.surface,
        boxShadow: h ? '0 18px 40px rgba(0,0,0,.55)' : '0 8px 22px rgba(0,0,0,.4)',
        transform: h ? 'translateY(-3px)' : 'none', transition: 'transform .25s, box-shadow .25s' }}>
        <Img id={item.Id} type="Thumb" fallback={{ id: item.SeriesId || item.Id, type: 'Backdrop' }} alt={label}
          style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', transform: h ? 'scale(1.05)' : 'scale(1)', transition: 'transform .4s' }} />
        {progress && (pct ?? 0) > 0 && (
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 4, background: 'rgba(255,255,255,.15)' }}>
            <div style={{ width: `${pct}%`, height: '100%', background: C.text }} />
          </div>
        )}
      </div>
      <div style={{ marginTop: 9, fontSize: 14, fontWeight: 600, color: C.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{label}</div>
      {sub && <div style={{ fontFamily: MONO, fontSize: 11.5, color: C.faint, marginTop: 3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{sub}</div>}
    </button>
  )
}

/* ── Library card (16:9 with label overlay) ─────────────────────────────── */
function ViewCard({ view, onClick }: { view: LibraryItem; onClick: () => void }) {
  const [h, setH] = useState(false)
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ flex: '0 0 auto', width: 300, border: 'none', background: 'none', padding: 0, cursor: 'pointer', scrollSnapAlign: 'start' }}>
      <div style={{ position: 'relative', aspectRatio: '16/9', borderRadius: 14, overflow: 'hidden', background: C.surface,
        boxShadow: h ? '0 18px 40px rgba(0,0,0,.55)' : '0 8px 22px rgba(0,0,0,.4)',
        transform: h ? 'translateY(-3px)' : 'none', transition: 'transform .25s, box-shadow .25s' }}>
        <Img id={view.Id} type="Primary"
          style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', filter: h ? 'brightness(1)' : 'brightness(.74)', transition: 'filter .25s' }} />
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(90deg, rgba(0,0,0,.72), rgba(0,0,0,.1))' }} />
        <div style={{ position: 'absolute', left: 16, bottom: 13, display: 'flex', alignItems: 'center', gap: 9, fontSize: 20, fontWeight: 800, color: '#fff' }}>
          <Icon path={viewIcon(view)} size={20} sw={2} />{view.Name}
        </div>
      </div>
    </button>
  )
}

/* ── Poster wall grid (inside a library / season) ───────────────────────── */
function PosterWall({ items, onOpen, children }: { items?: LibraryItem[]; onOpen?: (item: LibraryItem) => void; children?: ReactNode }) {
  const mobile = useIsMobile()
  const railRef = useRef<HTMLDivElement>(null)
  const focusAfterMove = useRef(false)
  const wheelLocked = useRef(false)
  const wheelTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [selected, setSelected] = useState(0)
  const [edges, setEdges] = useState({ left: false, right: false })
  const count = items?.length ?? 0

  const updateEdges = () => {
    const rail = railRef.current
    if (!rail) return
    setEdges({
      left: rail.scrollLeft > 2,
      right: rail.scrollLeft + rail.clientWidth < rail.scrollWidth - 2,
    })
  }

  useEffect(() => {
    setSelected(index => Math.min(index, Math.max(0, count - 1)))
  }, [count])

  useEffect(() => {
    if (mobile || count === 0) return
    const poster = railRef.current?.querySelector<HTMLButtonElement>(`[data-poster-index="${selected}"]`)
    poster?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' })
    if (focusAfterMove.current) {
      focusAfterMove.current = false
      poster?.focus({ preventScroll: true })
    }
  }, [selected, mobile, count])

  useEffect(() => {
    const rail = railRef.current
    if (!rail) return
    const frame = requestAnimationFrame(updateEdges)
    const observer = new ResizeObserver(updateEdges)
    observer.observe(rail)
    rail.addEventListener('scroll', updateEdges, { passive: true })
    return () => {
      cancelAnimationFrame(frame)
      observer.disconnect()
      rail.removeEventListener('scroll', updateEdges)
    }
  }, [count])

  useEffect(() => () => {
    if (wheelTimer.current) clearTimeout(wheelTimer.current)
  }, [])

  useEffect(() => {
    const rail = railRef.current
    if (!rail || mobile || !items) return
    const handleWheel = (event: WheelEvent) => {
      const delta = Math.abs(event.deltaX) >= Math.abs(event.deltaY) ? event.deltaX : event.deltaY
      if (!delta) return
      event.preventDefault()
      if (wheelLocked.current) return
      wheelLocked.current = true
      setSelected(index => {
        const next = movePosterSelection(index, count, delta < 0 ? -1 : 1)
        if (next !== index) playPosterMoveCue()
        return next
      })
      if (wheelTimer.current) clearTimeout(wheelTimer.current)
      wheelTimer.current = setTimeout(() => { wheelLocked.current = false }, 140)
    }
    rail.addEventListener('wheel', handleWheel, { passive: false })
    return () => rail.removeEventListener('wheel', handleWheel)
  }, [mobile, count, items])

  const move = (direction: number, focus = false) => {
    if (mobile || !items) {
      railRef.current?.scrollBy({ left: direction * (railRef.current.clientWidth * .72), behavior: 'smooth' })
      return
    }
    setSelected(index => {
      const next = movePosterSelection(index, count, direction)
      if (next !== index) {
        focusAfterMove.current = focus
        playPosterMoveCue()
      }
      return next
    })
  }
  const onKeyDown = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return
    event.preventDefault()
    move(event.key === 'ArrowLeft' ? -1 : 1, true)
  }
  return (
    <div className={`library-poster-rail${edges.left ? ' has-left-overflow' : ''}${edges.right ? ' has-right-overflow' : ''}`}>
      <div className="library-row-controls">
        <button onClick={() => move(-1)} disabled={!!items && !mobile && selected === 0} aria-label="Previous title">‹</button>
        <button onClick={() => move(1)} disabled={!!items && !mobile && selected === count - 1} aria-label="Next title">›</button>
      </div>
      <div ref={railRef} className="library-poster-wall" role={items ? 'listbox' : undefined} aria-label={items ? 'Titles' : undefined} aria-orientation={items ? 'horizontal' : undefined}
        onKeyDown={onKeyDown}
        style={{ display: 'grid', gap: mobile ? 12 : 18, gridTemplateColumns: `repeat(auto-fill, minmax(${mobile ? 118 : 150}px, 1fr))` }}>
        {items ? items.map((item, index) => (
          <WallPoster key={item.Id} item={item} onClick={() => onOpen?.(item)} selected={index === selected}
            tabIndex={mobile || index === selected ? 0 : -1} index={index} onSelect={() => setSelected(index)} />
        )) : children}
      </div>
    </div>
  )
}
function WallPoster({ item, onClick, selected, tabIndex, index, onSelect }: { item: LibraryItem; onClick: () => void; selected: boolean; tabIndex: number; index: number; onSelect: () => void }) {
  const badge = item.Type === 'Season' ? `S${item.IndexNumber}` : null
  return <div className={selected ? 'is-selected' : ''} style={{ width: '100%' }}><PosterCardFluid item={item} onClick={onClick} badge={badge}
    selected={selected} tabIndex={tabIndex} index={index} onSelect={onSelect} /></div>
}
// Poster that fills its grid cell width (rail cards are fixed 170px).
function PosterCardFluid({ item, onClick, badge, selected, tabIndex, index, onSelect }: { item: LibraryItem; onClick: () => void; badge?: string | null; selected: boolean; tabIndex: number; index: number; onSelect: () => void }) {
  const rating = item.CommunityRating
  const filledStars = rating == null ? 0 : Math.round(rating / 2)
  const isSeries = item.Type === 'Series'
  const epCount = isSeries ? (item.ChildCount ?? item.RecursiveItemCount) : null
  const fullyWatched = item.UserData?.Played
  return (
    <button className="library-poster-card" onClick={onClick} onFocus={() => { onSelect(); setBalancedPoster(item.Id) }} onMouseEnter={() => setBalancedPoster(item.Id)}
      role="option" aria-selected={selected} tabIndex={tabIndex} data-poster-index={index} aria-label={item.Name}>
      <div className="library-poster-art">
        <Img id={item.Id} type="Primary" alt={item.Name}
          style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
        {(epCount ?? 0) > 0 && (
          <div style={{ position: 'absolute', top: 8, right: 8, minWidth: 22, height: 22, padding: '0 6px', borderRadius: 999, display: 'grid', placeItems: 'center', fontFamily: MONO, fontSize: 11.5, fontWeight: 700, background: 'rgba(0,0,0,.65)', color: '#fff' }}>{epCount}</div>
        )}
        {fullyWatched && !epCount && (
          <div style={{ position: 'absolute', top: 8, right: 8, width: 22, height: 22, borderRadius: '50%', display: 'grid', placeItems: 'center', background: C.green }}>
            <Icon path={Ic.check} size={13} stroke="#06210f" sw={3} />
          </div>
        )}
        {badge && (
          <div style={{ position: 'absolute', top: 8, left: 8, padding: '2px 7px', borderRadius: 6, fontFamily: MONO, fontSize: 10.5, fontWeight: 700, background: 'rgba(0,0,0,.65)', color: '#fff' }}>{badge}</div>
        )}
      </div>
      <div className="library-poster-meta" aria-hidden>
        <span className="library-poster-title">{item.Name}</span>
        <span className="library-poster-stars">{Array.from({ length: 5 }, (_, index) => <span key={index} className={index >= filledStars ? 'is-empty' : ''}>★</span>)}</span>
      </div>
    </button>
  )
}

/* ── Cinematic movie / series / episode detail ──────────────────────────── */
function Details({ itemId, onWatch, onOpen: _onOpen, onBack }: { itemId: string; onWatch: (item: LibraryItem, tracks?: DetailTrackSelection) => void; onOpen: (item: LibraryItem) => void; onBack: () => void }) {
  const mobile = useIsMobile()
  const party = useParty()
  const [activeId, setActiveId] = useState(itemId)
  const [d, setD] = useState<LibraryItem | null>(null)
  const [series, setSeries] = useState<LibraryItem | null>(null)
  const [seasonRows, setSeasonRows] = useState<Array<{ season: LibraryItem; episodes: LibraryItem[] }>>([])
  const [loadingSeasons, setLoadingSeasons] = useState(false)
  const [playback, setPlayback] = useState<DetailPlayback | null>(null)
  const [selectedAudio, setSelectedAudio] = useState<number | null>(null)
  const [selectedSubtitle, setSelectedSubtitle] = useState<number | null>(null)
  const [trackMenuOpen, setTrackMenuOpen] = useState(false)
  const tracksInitialized = useRef(false)
  const [loading, setLoading] = useState(true)

  useEffect(() => { setActiveId(itemId); setSeries(null); setSeasonRows([]) }, [itemId])

  useEffect(() => {
    if (!party.session) return
    if (party.role === 'host') {
      party.shareView({ screen: 'detail', mediaId: itemId, episodeId: activeId === itemId ? null : activeId })
      return
    }
    const sharedEpisode = party.session.browse?.episodeId
    if (party.role === 'guest' && sharedEpisode && sharedEpisode !== activeId) setActiveId(sharedEpisode)
  }, [party.session?.id, party.session?.browse?.episodeId, party.role, itemId, activeId])

  useEffect(() => {
    setLoading(true); setD(null); setTrackMenuOpen(false); tracksInitialized.current = false
    let cancel = false
    fetch(`/api/library/item/${activeId}`, { credentials: 'include' })
      .then(r => r.ok ? apiJson(r) : null).then(x => {
        if (cancel) return
        const detail = isLibraryItem(x) ? x : null
        setD(detail)
        if (activeId === itemId && detail?.Type === 'Series') setSeries(detail)
      }).catch(() => {}).finally(() => { if (!cancel) setLoading(false) })
    return () => { cancel = true }
  }, [activeId, itemId])

  useEffect(() => {
    if (!series) return
    let cancel = false
    setLoadingSeasons(true)
    fetch(`/api/library/items/${itemId}/children`, { credentials: 'include' })
      .then(r => r.ok ? apiJson(r) : [])
      .then(value => Promise.all(libraryItems(value).map(async season => {
        const response = await fetch(`/api/library/items/${season.Id}/children`, { credentials: 'include' })
        return { season, episodes: response.ok ? libraryItems(await apiJson(response)) : [] }
      })))
      .then(rows => { if (!cancel) setSeasonRows(rows) })
      .catch(() => { if (!cancel) setSeasonRows([]) })
      .finally(() => { if (!cancel) setLoadingSeasons(false) })
    return () => { cancel = true }
  }, [series?.Id, itemId])

  const refreshPlayback = () => fetch(`/api/library/playback-info/${activeId}`, {
    method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: '{}',
  }).then(r => r.ok ? apiJson(r) : null).then(value => {
    const next = parseDetailPlayback(value)
    setPlayback(next)
    if (next && !tracksInitialized.current) {
      tracksInitialized.current = true
      setSelectedAudio(next.audioStreams.find(track => track.isDefault)?.index ?? next.audioStreams[0]?.index ?? null)
      setSelectedSubtitle(next.subtitleStreams.find(track => track.isDefault || track.isForced)?.index ?? null)
    }
  })

  useEffect(() => {
    if (!d || d.Type === 'Series') { setPlayback(null); return }
    let cancelled = false
    refreshPlayback().catch(() => { if (!cancelled) setPlayback(null) })
    return () => { cancelled = true }
  }, [d?.Id]) // eslint-disable-line react-hooks/exhaustive-deps

  if (loading || !d) return <div style={{ minHeight: '70vh', background: C.surface, animation: 'shim 1.3s linear infinite', backgroundImage: `linear-gradient(100deg, ${C.surface} 30%, ${C.surface2} 50%, ${C.surface} 70%)`, backgroundSize: '200% 100%' }} />

  const detailSeries = series ?? (d.Type === 'Series' ? d : null)
  const hero = detailSeries ?? d
  const backdropId = hero.Id
  const people = hero.People || []
  const cast = people.filter(p => p.Type === 'Actor').slice(0, 10)
  const genres = hero.Genres || []
  const isSeries = detailSeries != null
  const isEpisode = d.Type === 'Episode'
  const activeSeason = seasonRows.find(row => row.episodes.some(episode => episode.Id === activeId)) ?? seasonRows[0]
  const firstEpisode = seasonRows[0]?.episodes[0]
  const playItem = d.Type === 'Series' ? firstEpisode : d

  const ms = d.MediaSources?.[0]
  const streams = ms?.MediaStreams || []
  const video = streams.find(s => s.Type === 'Video')
  const resLabel = video ? ((video.Height ?? 0) >= 2160 ? '4K' : (video.Height ?? 0) >= 1080 ? '1080P' : (video.Height ?? 0) >= 720 ? '720P' : `${video.Height || '?'}P`) : null
  const hdr = video?.VideoRange && video.VideoRange !== 'SDR' ? video.VideoRange : 'SDR'
  const sizeLabel = ms?.Size ? `${Math.round(ms.Size / 1_000_000)}M` : null
  const premiere = d.PremiereDate ? new Date(d.PremiereDate).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : null
  const infoLine = [fmtRuntimeFromTicks(d.RunTimeTicks), premiere, resLabel, video ? hdr : null, sizeLabel].filter(Boolean)

  const resumeTicks = d.UserData?.PlaybackPositionTicks
  const resumeLabel = resumeTicks ? fmtRuntimeFromTicks(resumeTicks) : null
  const selection = { audioStreamIndex: selectedAudio, subtitleStreamIndex: selectedSubtitle ?? -1 }

  return (
    <div className={`library-detail${isSeries ? ' is-series' : ' is-movie'}`}>
      <article className="library-detail-stage">
        <div className="library-detail-backdrop">
          <Img id={backdropId} type="Backdrop" fallback={{ id: backdropId, type: 'Primary' }} alt=""
            style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'center 28%' }} />
        </div>
        <div className="library-detail-wash" />

        <button onClick={onBack} className="library-detail-back" aria-label="Back">
          <Icon path={Ic.chevL} size={20} sw={2} />
        </button>

        <div className="library-detail-content">
          <div className="library-detail-copy">
            {genres.length > 0 ? <div className="library-detail-genres">{genres.slice(0, 3).join('  /  ')}</div> : null}
            <h1>{hero.Name}</h1>
            {isEpisode ? <div className="library-detail-episode-label">{d.SeriesName || detailSeries?.Name} · S{d.ParentIndexNumber ?? 0} E{d.IndexNumber ?? 0} · {d.Name}</div> : null}
            {hero.Overview ? <p>{hero.Overview}</p> : null}
            <div className="library-detail-meta">
              {hero.CommunityRating != null ? <span>★ {hero.CommunityRating.toFixed(1)}</span> : null}
              {hero.OfficialRating ? <span>{hero.OfficialRating}</span> : null}
              {infoLine.slice(0, 3).map((value, index) => <span key={index}>{value}</span>)}
            </div>
            {playItem ? <div className="library-detail-actions">
              <button className="library-detail-play" onClick={() => onWatch(playItem, playItem.Id === d.Id ? selection : undefined)}>
                <Icon path={Ic.play} size={17} fill="currentColor" stroke="none" />
                <span>{resumeLabel && playItem.Id === d.Id ? `Resume ${resumeLabel}` : isSeries && !isEpisode ? 'Play first episode' : 'Watch now'}</span>
              </button>
              {d.Type !== 'Series' ? <button className={`library-detail-track${trackMenuOpen ? ' is-open' : ''}`} onClick={() => setTrackMenuOpen(open => !open)} aria-label="Audio and subtitles" title="Audio and subtitles"><Icon path={Ic.music} size={18} sw={1.8} /></button> : null}
              {trackMenuOpen && playback ? <DetailTrackMenu itemId={activeId} playback={playback} selectedAudio={selectedAudio} selectedSubtitle={selectedSubtitle} onSelectAudio={setSelectedAudio} onSelectSubtitle={setSelectedSubtitle} onRefresh={refreshPlayback} onClose={() => setTrackMenuOpen(false)} /> : null}
            </div> : null}
          </div>

          {!isSeries ? <div className="library-detail-poster">
            <Img id={d.Id} type="Primary" fallback={{ id: d.Id, type: 'Backdrop' }} alt={d.Name}
              style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div> : (
            <nav className="library-seasons" aria-label="Seasons">
              {seasonRows.map((row, index) => {
                const selected = row.season.Id === activeSeason?.season.Id
                return <button key={row.season.Id} className={selected ? 'is-active' : ''} onClick={() => row.episodes[0] && setActiveId(row.episodes[0].Id)}>
                  <span>{row.season.Name || `Season ${index + 1}`}</span><i />
                </button>
              })}
            </nav>
          )}

          {!isSeries && cast.length > 0 ? <div className="library-detail-cast">
            {cast.slice(0, mobile ? 4 : 6).map(person => <StagePerson key={person.Id + (person.Role || '')} person={person} />)}
          </div> : null}
        </div>

        {isSeries ? <div className="library-episodes-dock">
          {loadingSeasons ? <div className="library-episodes-loading" /> : activeSeason ? <EpisodeRow season={activeSeason.season} episodes={activeSeason.episodes} activeId={activeId} onSelect={episode => setActiveId(episode.Id)} /> : null}
        </div> : null}
      </article>
    </div>
  )
}

function StagePerson({ person }: { person: Person }) {
  const [imageAvailable, setImageAvailable] = useState(true)
  return (
    <div style={{ flex: '0 0 92px', minWidth: 0 }}>
      <div style={{ height: 116, overflow: 'hidden', background: 'rgba(255,255,255,.08)', outline: '1px solid rgba(255,255,255,.1)' }}>
        {imageAvailable ? <img src={img(person.Id, 'Primary')} alt={person.Name} onError={() => setImageAvailable(false)} style={{ width: '100%', height: '100%', objectFit: 'cover', filter: 'saturate(.82)' }} /> : <span style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center', color: C.dim, fontSize: 11, fontWeight: 700 }}>{person.Name.split(' ').map(part => part[0]).join('').slice(0, 2)}</span>}
      </div>
      <div style={{ marginTop: 7, color: '#fff', fontSize: 11.5, fontWeight: 650, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{person.Name}</div>
      {person.Role ? <div style={{ marginTop: 2, color: 'rgba(255,255,255,.52)', fontSize: 10.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{person.Role}</div> : null}
    </div>
  )
}

function EpisodeRow({ season, episodes, activeId, onSelect }: { season: LibraryItem; episodes: LibraryItem[]; activeId: string; onSelect: (episode: LibraryItem) => void }) {
  const mobile = useIsMobile()
  return (
    <section style={{ marginTop: 36 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 15 }}>
        <h2 style={{ margin: 0, fontSize: mobile ? 19 : 22, fontWeight: 800, letterSpacing: '-.025em' }}>{season.Name}</h2>
        <span style={{ color: C.faint, fontFamily: MONO, fontSize: 12 }}>{episodes.length} episodes</span>
      </div>
      {episodes.length > 0 ? <div style={{ display: 'flex', gap: mobile ? 12 : 16, overflowX: 'auto', padding: '0 0 10px', scrollbarWidth: 'none', scrollSnapType: 'x proximity' }}>
        {episodes.map(episode => <EpisodeCard key={episode.Id} episode={episode} selected={episode.Id === activeId} onClick={() => onSelect(episode)} />)}
      </div> : <p style={{ color: C.faint, fontSize: 13 }}>No episodes available.</p>}
    </section>
  )
}

function EpisodeCard({ episode, selected, onClick }: { episode: LibraryItem; selected: boolean; onClick: () => void }) {
  const mobile = useIsMobile()
  return (
    <button onClick={onClick} aria-current={selected ? 'true' : undefined} style={{ flex: `0 0 ${mobile ? 250 : 310}px`, width: mobile ? 250 : 310, padding: 0, border: 0, background: 'transparent', color: C.text, cursor: 'pointer', textAlign: 'left', scrollSnapAlign: 'start' }}>
      <div style={{ position: 'relative', aspectRatio: '16/9', overflow: 'hidden', borderRadius: 12, background: C.surface, border: `2px solid ${selected ? '#fff' : 'transparent'}`, boxShadow: selected ? '0 0 0 1px rgba(255,255,255,.2), 0 16px 38px rgba(0,0,0,.45)' : '0 10px 26px rgba(0,0,0,.32)' }}>
        <Img id={episode.Id} type="Thumb" fallback={{ id: episode.Id, type: 'Primary' }} alt={episode.Name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(0deg, rgba(0,0,0,.58), transparent 52%)' }} />
        <span style={{ position: 'absolute', left: 11, bottom: 9, padding: '3px 7px', borderRadius: 5, background: 'rgba(0,0,0,.68)', color: '#fff', fontFamily: MONO, fontSize: 11 }}>E{episode.IndexNumber ?? '?'}</span>
        {(episode.UserData?.PlayedPercentage ?? 0) > 0 && <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 3, background: 'rgba(255,255,255,.2)' }}><div style={{ width: `${episode.UserData?.PlayedPercentage}%`, height: '100%', background: '#fff' }} /></div>}
      </div>
      <div style={{ marginTop: 9, display: 'flex', gap: 8, alignItems: 'baseline' }}>
        <span style={{ color: C.faint, fontFamily: MONO, fontSize: 11.5 }}>{episode.IndexNumber ?? '–'}</span>
        <strong style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontSize: 14, fontWeight: 700 }}>{episode.Name}</strong>
      </div>
      {episode.Overview && <p style={{ margin: '5px 0 0 22px', color: C.faint, fontSize: 12.5, lineHeight: 1.4, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{episode.Overview}</p>}
    </button>
  )
}

function trackLabel(track: PlaybackTrack, fallback: string) {
  const base = track.displayTitle || track.title || track.language || fallback
  return `${base}${track.isDefault ? ' · Default' : ''}${track.isForced ? ' · Forced' : ''}`
}

function DetailTrackMenu({ itemId, playback, selectedAudio, selectedSubtitle, onSelectAudio, onSelectSubtitle, onRefresh, onClose }: {
  itemId: string; playback: DetailPlayback; selectedAudio: number | null; selectedSubtitle: number | null
  onSelectAudio: (index: number | null) => void; onSelectSubtitle: (index: number | null) => void
  onRefresh: () => Promise<void>; onClose: () => void
}) {
  const inputRef = useRef<HTMLInputElement | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const upload = async (file?: File) => {
    if (!file) return
    setBusy(true); setError('')
    try {
      const response = await fetch(`/api/library/items/${itemId}/subtitles`, {
        method: 'POST', credentials: 'include', body: file,
        headers: { 'Content-Type': file.type || 'application/octet-stream', 'X-Subtitle-Filename': encodeURIComponent(file.name) },
      })
      const data = await apiJson(response).catch(() => ({}))
      if (!response.ok) throw new Error(isRecord(data) && typeof data.error === 'string' ? data.error : 'Subtitle upload failed')
      await onRefresh()
      if (isRecord(data) && typeof data.subtitleStreamIndex === 'number') onSelectSubtitle(data.subtitleStreamIndex)
    } catch (err) { setError(err instanceof Error ? err.message : 'Subtitle upload failed') }
    finally { setBusy(false); if (inputRef.current) inputRef.current.value = '' }
  }

  const remove = async (track: PlaybackTrack) => {
    if (!window.confirm(`Delete ${trackLabel(track, 'this subtitle')}?`)) return
    setBusy(true); setError('')
    try {
      const response = await fetch(`/api/library/items/${itemId}/subtitles/${track.index}`, { method: 'DELETE', credentials: 'include' })
      const data = await apiJson(response).catch(() => ({}))
      if (!response.ok) throw new Error(isRecord(data) && typeof data.error === 'string' ? data.error : 'Subtitle delete failed')
      if (selectedSubtitle === track.index) onSelectSubtitle(null)
      await onRefresh()
    } catch (err) { setError(err instanceof Error ? err.message : 'Subtitle delete failed') }
    finally { setBusy(false) }
  }

  const row = (label: string, selected: boolean, onClick: () => void, action?: ReactNode) => (
    <div style={{ display: 'flex', alignItems: 'center', minHeight: 44, borderRadius: 9, background: selected ? 'rgba(255,255,255,.08)' : 'transparent' }}>
      <button onClick={onClick} style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 9, padding: '9px 10px', border: 0, background: 'transparent', color: selected ? '#fff' : 'rgba(255,255,255,.72)', cursor: 'pointer', textAlign: 'left', fontFamily: SANS, fontSize: 13 }}>
        <span style={{ width: 15, opacity: selected ? 1 : 0 }}><Icon path={Ic.check} size={14} sw={2.4} /></span>
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{label}</span>
      </button>
      {action}
    </div>
  )

  return (
    <div onClick={e => e.stopPropagation()} style={{ position: 'absolute', zIndex: 20, top: 58, left: 0, width: 'min(430px, calc(100vw - 38px))', maxHeight: 'min(62vh, 520px)', overflow: 'hidden auto', padding: 12, borderRadius: 18, background: 'rgba(24,22,21,.94)', border: '1px solid rgba(255,255,255,.18)', boxShadow: '0 24px 70px rgba(0,0,0,.55)', backdropFilter: 'blur(22px)' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '2px 5px 9px' }}>
        <strong style={{ fontSize: 13.5 }}>Playback tracks</strong>
        <button onClick={onClose} aria-label="Close track menu" style={{ border: 0, background: 'transparent', color: C.dim, cursor: 'pointer', padding: 4 }}><Icon path={Ic.x} size={17} /></button>
      </div>
      {playback.audioStreams.length > 0 && <div style={{ marginBottom: 12 }}>
        <div style={{ padding: '5px 10px', fontFamily: MONO, fontSize: 10.5, color: C.faint, letterSpacing: '.1em', textTransform: 'uppercase' }}>Audio</div>
        {playback.audioStreams.map((track, i) => <div key={track.index}>{row(trackLabel(track, `Audio ${i + 1}`), selectedAudio === track.index, () => onSelectAudio(track.index))}</div>)}
      </div>}
      <div>
        <div style={{ padding: '5px 10px', fontFamily: MONO, fontSize: 10.5, color: C.faint, letterSpacing: '.1em', textTransform: 'uppercase' }}>Subtitles</div>
        {row('Off', selectedSubtitle == null || selectedSubtitle < 0, () => onSelectSubtitle(null))}
        {playback.subtitleStreams.map((track, i) => <div key={track.index}>{row(trackLabel(track, `Subtitle ${i + 1}`), selectedSubtitle === track.index, () => onSelectSubtitle(track.index), track.isExternal ? <button disabled={busy} onClick={() => remove(track)} title="Delete subtitle" style={{ border: 0, background: 'transparent', color: C.faint, cursor: busy ? 'wait' : 'pointer', padding: '9px 10px' }}><Icon path={Ic.trash} size={15} /></button> : null)}</div>)}
        <input ref={inputRef} type="file" accept=".srt,.vtt,text/vtt,application/x-subrip" hidden onChange={e => upload(e.target.files?.[0])} />
        <button disabled={busy} onClick={() => inputRef.current?.click()} style={{ width: '100%', marginTop: 8, padding: '10px 12px', borderRadius: 10, border: '1px solid rgba(255,255,255,.14)', background: 'rgba(255,255,255,.06)', color: '#fff', cursor: busy ? 'wait' : 'pointer', fontFamily: SANS, fontSize: 13, fontWeight: 650 }}>{busy ? 'Working…' : 'Upload SRT or VTT'}</button>
        {error && <div role="alert" style={{ marginTop: 8, padding: '0 4px', color: C.red, fontSize: 12 }}>{error}</div>}
      </div>
    </div>
  )
}
/* ── Grid (inside a library / season) ───────────────────────────────────── */
function GridView({ stack, items, loading, onOpen }: { stack: StackEntry[]; items: LibraryItem[]; loading: boolean; onOpen: (item: LibraryItem) => void; onCrumb: (index: number) => void; onHome: () => void }) {
  const current = stack[stack.length - 1]
  const genreRows = Array.from(new Set(items.flatMap(item => item.Genres ?? [])))
    .map(name => ({ name, items: items.filter(item => item.Genres?.includes(name)) }))
    .filter(row => row.items.length > 1 && row.items.length < items.length)

  return (
    <div className="library-catalog">
      <section className="library-results">
        <section className="library-media-row">
          <div className="library-title-row"><h1>{current?.name}</h1></div>
          {loading ? (
            <PosterWall>{Array.from({ length: 8 }).map((_, index) => <div key={index} className="library-poster-skeleton" />)}</PosterWall>
          ) : items.length === 0 ? (
            <div className="library-empty"><strong>No titles here yet</strong><span>Add something from Discover.</span></div>
          ) : (
            <PosterWall items={items} onOpen={onOpen} />
          )}
        </section>
        {!loading && genreRows.map(row => (
          <section className="library-media-row" key={row.name}>
            <div className="library-title-row"><h2>{row.name}</h2></div>
            <PosterWall items={row.items} onOpen={onOpen} />
          </section>
        ))}
      </section>
    </div>
  )
}
