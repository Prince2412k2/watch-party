import { forwardRef, useEffect, useRef, useState } from 'react'
import { useAuth } from '../context/AuthContext.jsx'
import { useIsMobile } from '../hooks/useIsMobile.js'
import { useFailingCount } from '../hooks/useFailingDownloads.js'
import { isActiveState } from '../hooks/useTorrents.js'
import { navigate } from '../router.js'
import { DownloadPoster, DownloadDetail } from '../components/DownloadDetail.jsx'
import { C, SANS, MONO, Ic, Icon, viewIcon, NavRow, GlassBtn } from '../lib/ui.jsx'
import { fmtRuntimeFromTicks, fmtSpeed } from '../lib/format.js'

const img = (id, type = 'Primary') => `/api/library/image/${id}?type=${type}`

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
function useDownloads(enabled) {
  const [torrents, setTorrents] = useState([])
  useEffect(() => {
    if (!enabled) { setTorrents([]); return }
    let timer = null
    let ctrl = null
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
        .then(r => r.ok ? r.json() : Promise.reject(r))
        .then(data => { if (!c.signal.aborted) setTorrents(Array.isArray(data) ? data : []) })
        // 503 (unconfigured) / 502 (unreachable) / abort → stay empty, no throw surfaced
        .catch(() => {})
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
const isFolder = (t) => t === 'Series' || t === 'Season' || t === 'CollectionFolder' || t === 'Folder' || t === 'UserView'
const DETAIL_TYPES = new Set(['Movie', 'Series', 'Episode'])
const isDetail = (t) => DETAIL_TYPES.has(t)

/**
 * Robust image. Tries `type`, then an optional `fallback` {id,type}, then
 * renders nothing. A 404 is recorded in a session-wide set, so a missing image
 * is NEVER requested again — even if the component remounts repeatedly (which
 * is what caused the runaway 404 storm). Bounded to one request per art URL.
 */
const failedArt = new Set()
function Img({ id, type = 'Primary', fallback, style, alt = '' }) {
  const [, force] = useState(0)
  const candidates = [{ id, type }, fallback].filter(c => c?.id)
  const cur = candidates.find(c => !failedArt.has(`${c.id}:${c.type}`))
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
  embedded = false, stack: extStack, onNavigate, onPickMedia,
  canDrive = true, headerRight, banner,
  onPointer, mirrorSubscribe, driverName,
} = {}) {
  const { user, logout } = useAuth()
  const mobile = useIsMobile()
  const [home, setHome] = useState(null)
  const [loadingHome, setLoadingHome] = useState(true)
  const [error, setError] = useState('')
  const [internalStack, setInternalStack] = useState([])
  const [gridItems, setGridItems] = useState([])
  const [loadingGrid, setLoadingGrid] = useState(false)
  // Active-download detail overlay (standalone only). Holds the enriched torrent
  // that was clicked; kept fresh from the live poll while open (see render).
  const [dlDetail, setDlDetail] = useState(null)

  // Active downloads (qBittorrent). Standalone only — the embedded lobby stays
  // lean and Servarr-agnostic. Degrades to empty when Servarr isn't configured.
  const { active: dlActive, torrents: dlTorrents } = useDownloads(!embedded)
  const failingCount = useFailingCount(!embedded)

  const stack = embedded ? (extStack ?? []) : internalStack
  const setStack = (updater) => {
    const next = typeof updater === 'function' ? updater(stack) : updater
    if (embedded) onNavigate?.(next); else setInternalStack(next)
  }
  const current = stack[stack.length - 1] || null

  useEffect(() => {
    setLoadingHome(true)
    fetch('/api/library/home', { credentials: 'include' })
      .then(r => r.ok ? r.json() : Promise.reject(r))
      .then(setHome).catch(() => setError('Failed to load your library'))
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
    if (!current || isDetail(current.type)) return
    setLoadingGrid(true)
    fetch(`/api/library/items/${current.id}/children`, { credentials: 'include' })
      .then(r => r.ok ? r.json() : Promise.reject(r))
      .then(setGridItems).catch(() => setGridItems([]))
      .finally(() => setLoadingGrid(false))
  }, [current?.id])

  // ── Screen mirroring ────────────────────────────────────────────────────
  // scrollRef is attached to the scrollable *content pane* (right of the
  // sidebar). Its scroll fraction is what we broadcast / follow.
  const scrollRef = useRef(null)
  const ghostRef = useRef(null)
  const driving = embedded && canDrive && !!onPointer
  const following = embedded && !canDrive && !!mirrorSubscribe

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
    const flush = () => { raf = 0; onPointer({ ...last }) }
    const queue = () => { if (!raf) raf = requestAnimationFrame(flush) }
    const onScroll = () => {
      const sh = el.scrollHeight - el.clientHeight
      last.scroll = sh > 0 ? el.scrollTop / sh : 0
      queue()
    }
    const onMove = (e) => {
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
  }, [driving, onPointer, current?.id])

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
    const onFrame = (p) => { pending = p; if (!raf) raf = requestAnimationFrame(apply) }
    const unsub = mirrorSubscribe(onFrame)
    onFrame(pending) // apply current position on mount / view change
    return () => { unsub(); cancelAnimationFrame(raf) }
  }, [following, mirrorSubscribe, current?.id])

  function open(item) { if (canDrive) setStack(s => [...s, { id: item.Id, name: item.Name, type: item.Type }]) }
  function pick(item) {
    if (!canDrive) return
    if (onPickMedia) onPickMedia(item); else navigate(`/party/new?itemId=${item.Id}`)
  }
  const openDownload = (t) => { if (canDrive) setDlDetail(t) }
  const goHome = () => { if (canDrive) setStack([]) }
  const goBack = () => { if (canDrive) setStack(s => s.slice(0, -1)) }
  const goToDepth = (i) => { if (canDrive) setStack(s => s.slice(0, i + 1)) }
  const openView = (v) => { if (canDrive) setStack([{ id: v.Id, name: v.Name, type: v.Type }]) }

  const initials = user?.name?.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2) || '?'
  const views = home?.views ?? []
  const sidebarW = mobile ? 62 : 236

  return (
    // Outer shell: fixed full-bleed. Holds the flush sidebar and the scrollable
    // content pane. It does NOT scroll itself.
    <div style={{
      position: 'fixed', inset: 0, background: C.bg, color: C.text, fontFamily: SANS,
      overflow: 'hidden',
    }}>
      {following && <GhostCursor ref={ghostRef} name={driverName} />}

      <Sidebar mobile={mobile} width={sidebarW} views={views} activeId={current ? stack[0].id : null}
        onHome={goHome} onView={openView} showDiscover={!embedded} downloadCount={dlActive} failingCount={failingCount} />

      {/* Scrollable content pane — flush to the viewport edge (no inset panel).
          This is the element the mirror engine drives. */}
      <div ref={scrollRef} style={{
        position: 'absolute', top: 0, right: 0, bottom: 0, left: sidebarW,
        overflow: 'hidden auto',
        overflowY: following ? 'hidden' : 'auto',
      }}>
        <TopBar embedded={embedded} mobile={mobile} initials={initials} logout={logout}
          headerRight={headerRight} current={current} onBack={goBack} onHome={goHome} />

        {banner}
        {error && (
          <div style={{ margin: '14px 20px', padding: '12px 16px', borderRadius: 12,
            background: 'rgba(224,101,94,.12)', border: `1px solid rgba(224,101,94,.35)`, color: C.red, fontSize: 14 }}>{error}</div>
        )}

        <div style={{ pointerEvents: canDrive ? 'auto' : 'none' }}>
          {!current && <HomeView home={home} loading={loadingHome} onOpen={open} onOpenView={openView}
            embedded={embedded} downloads={dlTorrents} onOpenDownload={openDownload} />}
          {current && isDetail(current.type) && (
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
const GhostCursor = forwardRef(function GhostCursor({ name }, ref) {
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
function Sidebar({ mobile, width, views, activeId, onHome, onView, showDiscover, downloadCount = 0, failingCount = 0 }) {
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


function TopBar({ embedded, mobile, initials, logout, headerRight, current, onBack, onHome }) {
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
function JoinDialog({ mobile, onClose }) {
  const [code, setCode] = useState('')
  const [err, setErr] = useState('')

  function submit(e) {
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
function HomeView({ home, loading, onOpen, onOpenView, embedded, downloads, onOpenDownload }) {
  const mobileHome = useIsMobile()
  const pad = mobileHome ? '0 16px' : '0 44px'

  // Recently added — fetched independently of /home. Jellyfin-only, so it works
  // regardless of Servarr. /api/library/latest returns a flat array; [] if empty
  // or on any error (endpoint degrades to a clean 502 which we swallow).
  const [latest, setLatest] = useState([])
  useEffect(() => {
    let cancel = false
    fetch('/api/library/latest', { credentials: 'include' })
      .then(r => r.ok ? r.json() : Promise.reject(r))
      .then(d => { if (!cancel) setLatest(Array.isArray(d) ? d : []) })
      .catch(() => {})
    return () => { cancel = true }
  }, [])

  // "Downloading now" — actively-downloading qBittorrent torrents only (shared
  // isActiveState), so finished-but-seeding titles don't linger here at 100%.
  // Servarr-agnostic: [] when unconfigured/unreachable.
  const arriving = (downloads || []).filter(t => isActiveState(t.state))

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
function PosterCard({ item, onClick }) {
  const [h, setH] = useState(false)
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} aria-label={item.Name}
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
function DownloadingCard({ torrent, onOpen }) {
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
        <DownloadPoster posterUrl={torrent.posterUrl} kind={torrent.kind} pct={pct} paused={false} width="100%" radius={14} ringSize={78} />
      </div>
      <div style={{ marginTop: 9, fontSize: 14, fontWeight: 600, color: C.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
      {subtitle && <div style={{ fontFamily: MONO, fontSize: 12, color: C.faint, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{subtitle}</div>}
    </button>
  )
}

/* ── Horizontal rail with header + hover scroll arrows (Sen Player style) ── */
function Rail({ title, count, children }) {
  const trackRef = useRef(null)
  const [hover, setHover] = useState(false)
  const scrollBy = (dir) => {
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
function RailArrow({ dir, show, onClick }) {
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
function StillCard({ item, onClick, progress }) {
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
        {progress && pct > 0 && (
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
function ViewCard({ view, onClick }) {
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
function PosterWall({ children }) {
  const mobile = useIsMobile()
  return <div style={{ display: 'grid', gap: mobile ? 12 : 18, gridTemplateColumns: `repeat(auto-fill, minmax(${mobile ? 118 : 160}px, 1fr))` }}>{children}</div>
}
function WallPoster({ item, onClick }) {
  const badge = item.Type === 'Season' ? `S${item.IndexNumber}` : null
  return <div style={{ width: '100%' }}><PosterCardFluid item={item} onClick={onClick} badge={badge} /></div>
}
// Poster that fills its grid cell width (rail cards are fixed 170px).
function PosterCardFluid({ item, onClick, badge }) {
  const [h, setH] = useState(false)
  const rating = item.CommunityRating
  const isSeries = item.Type === 'Series'
  const epCount = isSeries ? (item.ChildCount ?? item.RecursiveItemCount) : null
  const fullyWatched = item.UserData?.Played
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} aria-label={item.Name}
      style={{ width: '100%', border: 'none', background: 'none', padding: 0, cursor: 'pointer', textAlign: 'left' }}>
      <div style={{ position: 'relative', aspectRatio: '2/3', borderRadius: 14, overflow: 'hidden', background: C.surface,
        boxShadow: h ? '0 18px 40px rgba(0,0,0,.55)' : '0 8px 22px rgba(0,0,0,.4)',
        transform: h ? 'translateY(-3px)' : 'none', transition: 'transform .25s, box-shadow .25s' }}>
        <Img id={item.Id} type="Primary" alt={item.Name}
          style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', transform: h ? 'scale(1.06)' : 'scale(1)', transition: 'transform .4s' }} />
        {epCount > 0 && (
          <div style={{ position: 'absolute', top: 8, right: 8, minWidth: 22, height: 22, padding: '0 6px', borderRadius: 999, display: 'grid', placeItems: 'center', fontFamily: MONO, fontSize: 11.5, fontWeight: 700, background: 'rgba(0,0,0,.65)', color: C.text }}>{epCount}</div>
        )}
        {fullyWatched && !epCount && (
          <div style={{ position: 'absolute', top: 8, right: 8, width: 22, height: 22, borderRadius: '50%', display: 'grid', placeItems: 'center', background: C.green }}>
            <Icon path={Ic.check} size={13} stroke="#06210f" sw={3} />
          </div>
        )}
        {badge && (
          <div style={{ position: 'absolute', top: 8, left: 8, padding: '2px 7px', borderRadius: 8, fontFamily: MONO, fontSize: 10.5, fontWeight: 700, background: 'rgba(0,0,0,.65)', color: '#fff' }}>{badge}</div>
        )}
        {rating != null && (
          <div style={{ position: 'absolute', bottom: 8, right: 8, padding: '2px 8px', borderRadius: 8, fontFamily: MONO, fontSize: 12, fontWeight: 700, color: '#fff', background: 'rgba(0,0,0,.7)' }}>{rating.toFixed(1)}</div>
        )}
      </div>
      <div style={{ marginTop: 9, fontSize: 14, fontWeight: 600, color: C.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{item.Name}</div>
      {item.ProductionYear && <div style={{ fontFamily: MONO, fontSize: 12, color: C.faint, marginTop: 2 }}>{item.ProductionYear}</div>}
    </button>
  )
}

/* ── Detail page (Sen Player detail layout) ─────────────────────────────── */
function CircleAction({ icon, title }) {
  const [h, setH] = useState(false)
  return (
    <button title={title} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} style={{
      width: 54, height: 54, borderRadius: '50%', display: 'grid', placeItems: 'center', cursor: 'pointer',
      border: `1px solid ${C.line}`, background: h ? C.surface2 : C.surface, color: C.text, transition: 'background .15s',
    }}>
      <Icon path={icon} size={22} sw={1.9} />
    </button>
  )
}

function Details({ itemId, onWatch, onOpen, onBack }) {
  const mobile = useIsMobile()
  const [d, setD] = useState(null)
  const [seasons, setSeasons] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    setLoading(true); setSeasons([]); setD(null)
    let cancel = false
    fetch(`/api/library/item/${itemId}`, { credentials: 'include' })
      .then(r => r.ok ? r.json() : null).then(x => { if (!cancel) setD(x) }).catch(() => {}).finally(() => { if (!cancel) setLoading(false) })
    return () => { cancel = true }
  }, [itemId])

  useEffect(() => {
    if (d?.Type !== 'Series') return
    let cancel = false
    fetch(`/api/library/items/${itemId}/children`, { credentials: 'include' })
      .then(r => r.ok ? r.json() : []).then(x => { if (!cancel) setSeasons(x) }).catch(() => {})
    return () => { cancel = true }
  }, [d?.Type, itemId])

  if (loading || !d) return <div style={{ minHeight: '70vh', background: C.surface, animation: 'shim 1.3s linear infinite', backgroundImage: `linear-gradient(100deg, ${C.surface} 30%, ${C.surface2} 50%, ${C.surface} 70%)`, backgroundSize: '200% 100%' }} />

  const backdropId = d.SeriesId || d.Id
  const people = d.People || []
  const cast = people.filter(p => p.Type === 'Actor').slice(0, 16)
  const genres = d.Genres || []
  const isSeries = d.Type === 'Series'

  const ms = d.MediaSources?.[0]
  const streams = ms?.MediaStreams || []
  const video = streams.find(s => s.Type === 'Video')
  const resLabel = video ? (video.Height >= 2160 ? '4K' : video.Height >= 1080 ? '1080P' : video.Height >= 720 ? '720P' : `${video.Height || '?'}P`) : null
  const hdr = video?.VideoRange && video.VideoRange !== 'SDR' ? video.VideoRange : 'SDR'
  const sizeLabel = ms?.Size ? `${Math.round(ms.Size / 1_000_000)}M` : null
  const premiere = d.PremiereDate ? new Date(d.PremiereDate).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : null
  const infoLine = [fmtRuntimeFromTicks(d.RunTimeTicks), premiere, resLabel, video ? hdr : null, sizeLabel].filter(Boolean)

  const resumeTicks = d.UserData?.PlaybackPositionTicks
  const resumeLabel = resumeTicks ? fmtRuntimeFromTicks(resumeTicks) : null

  return (
    <div style={{ paddingBottom: 100 }}>
      {/* Full-bleed backdrop hero — real Jellyfin artwork with only a black-alpha
          legibility scrim, no blur/frost. */}
      <div style={{ position: 'relative', minHeight: 'min(78vh, 640px)', display: 'flex', alignItems: 'flex-end' }}>
        <div style={{ position: 'absolute', inset: 0, overflow: 'hidden' }}>
          <Img id={backdropId} type="Backdrop" fallback={{ id: backdropId, type: 'Primary' }}
            style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top center' }} />
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(0deg, rgba(0,0,0,.92) 4%, rgba(0,0,0,.55) 48%, rgba(0,0,0,.2) 100%)` }} />
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(90deg, rgba(0,0,0,.7) 0%, rgba(0,0,0,.35) 45%, transparent 82%)` }} />
        </div>

        <div style={{ position: 'relative', width: '100%', padding: mobile ? '0 16px 26px' : '0 44px 36px' }}>
          {/* Three circular glass actions */}
          <div style={{ display: 'flex', gap: 14, marginBottom: 20 }}>
            <CircleAction icon={Ic.history} title="Restart / history" />
            <CircleAction icon={Ic.check} title="Mark watched" />
            <CircleAction icon={Ic.heart} title="Favorite" />
          </div>

          {/* Big white Play pill (wired to onWatch exactly as before, movies only) */}
          {!isSeries && (
            <button onClick={() => onWatch({ Id: itemId, Type: d.Type })} style={{
              display: 'inline-flex', alignItems: 'center', gap: 12, padding: '15px 34px', border: 'none', borderRadius: 999,
              background: C.accent, color: C.onAccent, fontFamily: SANS, fontSize: 16, fontWeight: 700, cursor: 'pointer',
              boxShadow: '0 10px 30px rgba(0,0,0,.4)', marginBottom: 22, transition: 'transform .15s' }}
              onMouseEnter={e => e.currentTarget.style.transform = 'scale(1.02)'} onMouseLeave={e => e.currentTarget.style.transform = 'none'}>
              <Icon path={Ic.play} size={19} fill="currentColor" stroke="none" />
              {resumeLabel ? `Play  ${resumeLabel}` : 'Play'}
            </button>
          )}

          {/* Metadata line: ★ rating · critic% · rating badge · genre */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap', marginBottom: 8, fontSize: 15, fontWeight: 600 }}>
            {d.CommunityRating != null && (
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: C.text }}>
                <Icon path={Ic.star} size={16} fill={C.text} stroke="none" />{d.CommunityRating.toFixed(1)}
              </span>
            )}
            {d.CriticRating != null && (
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: C.dim }}>
                <span style={{ fontSize: 15 }}>&#127813;</span>{d.CriticRating}%
              </span>
            )}
            {d.OfficialRating && <span style={{ padding: '1px 8px', borderRadius: 5, border: `1px solid ${C.line2}`, fontSize: 13, fontFamily: MONO }}>{d.OfficialRating}</span>}
            {genres.slice(0, 2).map(g => <span key={g} style={{ color: C.dim }}>{g}</span>)}
          </div>

          {/* Info line: runtime · date · quality */}
          {infoLine.length > 0 && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', marginBottom: 14, fontFamily: MONO, fontSize: 13, color: C.dim }}>
              {infoLine.map((v, i) => <span key={i}>{v}</span>)}
            </div>
          )}

          {/* Overview */}
          {d.Overview && (
            <p style={{ fontSize: 15, lineHeight: 1.6, color: C.dim, maxWidth: 720, margin: 0,
              display: '-webkit-box', WebkitLineClamp: 4, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
              {d.Name ? <b style={{ fontWeight: 700 }}>[{d.Name}]</b> : null} {d.Overview}
            </p>
          )}
        </div>
      </div>

      {/* Body */}
      <div style={{ padding: mobile ? '0 16px' : '0 44px' }}>
        {isSeries && seasons.length > 0 && (
          <SectionHead title="Seasons" count={seasons.length}>
            <PosterWall>{seasons.map(s => <WallPoster key={s.Id} item={s} onClick={() => onOpen(s)} />)}</PosterWall>
          </SectionHead>
        )}

        {cast.length > 0 && (
          <SectionHead title="Cast">
            <div style={{ display: 'flex', gap: 16, overflowX: 'auto', scrollbarWidth: 'none', paddingBottom: 6 }}>
              {cast.map(p => <CastPerson key={p.Id + (p.Role || '')} person={p} />)}
            </div>
          </SectionHead>
        )}

        {/* Link section header (matches Sen Player bottom) */}
        {(d.ProviderIds?.Imdb || d.ProviderIds?.Tmdb) && (
          <SectionHead title="Link">
            <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
              {d.ProviderIds?.Imdb && <a href={`https://www.imdb.com/title/${d.ProviderIds.Imdb}/`} target="_blank" rel="noreferrer" style={linkPill}>IMDb ↗</a>}
              {d.ProviderIds?.Tmdb && <a href={`https://www.themoviedb.org/${isSeries ? 'tv' : 'movie'}/${d.ProviderIds.Tmdb}`} target="_blank" rel="noreferrer" style={linkPill}>TMDb ↗</a>}
            </div>
          </SectionHead>
        )}
      </div>
    </div>
  )
}
const linkPill = { padding: '9px 16px', borderRadius: 999, background: C.surface, border: `1px solid ${C.line}`, color: C.text, fontFamily: MONO, fontSize: 12.5, textDecoration: 'none', display: 'inline-block' }

function SectionHead({ title, count, children }) {
  return (
    <section style={{ marginTop: 34, animation: 'up .4s ease both' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 16 }}>
        <h2 style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-.02em', color: C.text }}>{title}</h2>
        {count != null && <span style={{ fontFamily: MONO, fontSize: 13, color: C.faint }}>{count}</span>}
      </div>
      {children}
    </section>
  )
}

/* ── Cast card (rounded-square avatar, name / role / "Actor") ───────────── */
function CastPerson({ person }) {
  const [ok, setOk] = useState(true)
  return (
    <div style={{ flex: '0 0 120px', width: 120 }}>
      <div style={{ width: 120, height: 120, borderRadius: 18, overflow: 'hidden', marginBottom: 10, background: C.surface2, display: 'grid', placeItems: 'center', border: `1px solid ${C.line}` }}>
        {ok
          ? <img src={img(person.Id, 'Primary')} alt={person.Name} onError={() => setOk(false)} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          : <svg width="46" height="46" viewBox="0 0 24 24" fill="none" stroke={C.faint} strokeWidth="1.6"><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></svg>}
      </div>
      <div style={{ fontSize: 13.5, fontWeight: 700, color: C.text, lineHeight: 1.25, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{person.Name}</div>
      {person.Role && <div style={{ fontSize: 12, color: C.dim, marginTop: 3, lineHeight: 1.25, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{person.Role}</div>}
      <div style={{ fontSize: 11.5, color: C.faint, marginTop: 2 }}>{person.Type}</div>
    </div>
  )
}

/* ── Grid (inside a library / season) ───────────────────────────────────── */
function GridView({ stack, items, loading, onOpen, onCrumb, onHome }) {
  const mobile = useIsMobile()
  const current = stack[stack.length - 1]
  return (
    <div style={{ padding: mobile ? '4px 16px 100px' : '8px 44px 100px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontFamily: MONO, fontSize: 12.5, color: C.dim, marginBottom: 18 }}>
        <span onClick={onHome} style={{ cursor: 'pointer' }}>Home</span>
        {stack.map((s, i) => (
          <span key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ color: C.faint }}>/</span>
            <span onClick={() => onCrumb(i)} style={{ cursor: 'pointer', color: i === stack.length - 1 ? C.text : C.dim }}>{s.name}</span>
          </span>
        ))}
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 22 }}>
        <h1 style={{ fontSize: 30, fontWeight: 800, letterSpacing: '-.02em' }}>{current.name}</h1>
        {!loading && <span style={{ fontFamily: MONO, fontSize: 13, color: C.faint }}>{items.length} titles</span>}
      </div>
      {loading ? (
        <PosterWall>{Array.from({ length: 18 }).map((_, i) => (
          <div key={i} style={{ aspectRatio: '2/3', borderRadius: 14, background: C.surface, animation: 'shim 1.3s linear infinite', backgroundImage: `linear-gradient(100deg, ${C.surface} 30%, ${C.surface2} 50%, ${C.surface} 70%)`, backgroundSize: '200% 100%' }} />
        ))}</PosterWall>
      ) : items.length === 0 ? (
        <p style={{ color: C.dim, fontSize: 15 }}>Nothing here yet.</p>
      ) : (
        <PosterWall>{items.map(it => <WallPoster key={it.Id} item={it} onClick={() => onOpen(it)} />)}</PosterWall>
      )}
    </div>
  )
}
