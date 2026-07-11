// @ts-nocheck
import { useEffect, useRef, useState } from 'react'
import { useAuth } from '../../context/AuthContext'
import { navigate } from '../../router'
import { useMobileShell } from '../shellContext'
import { useTorrents, isActiveState } from '../../hooks/useTorrents'
import { T, SANS, MONO, R, EASE, TYPE, AVATAR_BG, SP } from '../theme'
import { TopBar, TopBarButton } from '../ui/TopBar'
import { Icon, Ic, viewIcon } from '../ui/Icon'
import { Img } from '../ui/Poster'
import { Rail, RailItem } from '../ui/Rail'
import { Sheet } from '../ui/Sheet'
import { Skeleton, RailSkeleton } from '../ui/Skeleton'

/**
 * Mobile Home — the phone library landing. A vertical stack of swipeable rails
 * built from the SAME data desktop `Library.jsx` uses (verbatim endpoints), plus
 * the live "Downloading now" cards and the create/join-a-party entry points.
 *
 * Reuse: useAuth() (greeting/avatar/logout), useTorrents(true)+isActiveState
 *   (the shared download poller — same shape the TabBar/Downloads use), the shell
 *   `openJoin` (start/join sheet), and navigate('/party/new?itemId=…') to start a
 *   party (exactly like desktop `pick()`).
 * Endpoints: /api/library/home, /api/library/latest,
 *   /api/library/items/:id/children, /api/library/item/:id,
 *   /api/library/image/:id?type=, /api/servarr/downloads/enriched.
 */

const POSTER_W = 128
const STILL_W = 262
const VIEW_W = 262
const DL_W = 290
const LEAF = new Set(['Movie', 'Episode'])

const fmtRuntime = (ticks) => {
  if (!ticks) return null
  const m = Math.round(ticks / 600_000_000)
  const h = Math.floor(m / 60)
  return h > 0 ? `${h}h ${m % 60}m` : `${m}m`
}
const fmtSpeed = (bps) => {
  if (bps == null || !Number.isFinite(bps) || bps <= 0) return '0 B/s'
  const u = ['B', 'KB', 'MB', 'GB']
  let i = 0, n = bps
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
  return `${n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)} ${u[i]}/s`
}

// button reset for tappable cards / rows
const cardBtn: any = {
  border: 'none', background: 'none', padding: 0, margin: 0, cursor: 'pointer',
  textAlign: 'left', color: 'inherit', font: 'inherit', width: '100%', display: 'block',
}

/* Robust artwork tile: an initial-glyph placeholder behind a fallback-chained
   <Img> (shares the session-wide failedArt 404 guard). Overlays render as
   children. Covers the placeholder once the image paints; falls back to the
   glyph if every candidate 404s. */
function Art({ id, type = 'Primary', fallback, alt = '', ratio = '2 / 3', radius = R.md, style, children }: any = {}) {
  return (
    <div style={{
      position: 'relative', aspectRatio: ratio, borderRadius: radius, overflow: 'hidden',
      background: T.surface, border: `1px solid ${T.line}`, ...style,
    }}>
      <span aria-hidden style={{
        position: 'absolute', inset: 0, display: 'grid', placeItems: 'center',
        fontFamily: SANS, fontWeight: 800, fontSize: 24, color: T.faint,
        background: T.surface2,
      }}>{(alt || '?').trim().charAt(0).toUpperCase()}</span>
      <Img id={id} type={type} fallback={fallback} alt={alt}
        style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
      {children}
    </div>
  )
}

/* ── Rail cards ──────────────────────────────────────────────────────────── */

// 2:3 poster (Recently added, library-grid items). Optional corner badge.
function PosterCard({ item, onOpen, badge }: any = {}) {
  return (
    <RailItem style={{ width: POSTER_W }}>
      <button className="mob-press" style={cardBtn} onClick={() => onOpen(item)} aria-label={item.Name}>
        <Art id={item.Id} type="Primary" fallback={{ id: item.SeriesId || item.Id, type: 'Backdrop' }}
          alt={item.Name} ratio="2 / 3">
          {badge && (
            <span style={{
              position: 'absolute', top: 8, left: 8, ...TYPE.meta, fontSize: 9.5, letterSpacing: '.12em',
              padding: '3px 7px', borderRadius: 999, background: 'rgba(0,0,0,.6)', color: T.dim,
            }}>{badge}</span>
          )}
        </Art>
        <div style={{ ...TYPE.body, fontWeight: 600, color: T.text, marginTop: 8, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{item.Name}</div>
        {item.ProductionYear && <div style={{ fontFamily: MONO, fontSize: 11, color: T.faint, marginTop: 2 }}>{item.ProductionYear}</div>}
      </button>
    </RailItem>
  )
}

// 16:9 still (Continue watching / Next up), with resume progress bar.
function StillCard({ item, onOpen, progress }: any = {}) {
  const pct = item.UserData?.PlayedPercentage
  const label = item.SeriesName ? (item.Name || item.SeriesName) : item.Name
  const sub = item.SeriesName
    ? `${item.SeriesName}${item.ParentIndexNumber != null ? ` · S${item.ParentIndexNumber}·E${item.IndexNumber}` : ''}`
    : (item.ProductionYear ? String(item.ProductionYear) : '')
  return (
    <RailItem style={{ width: STILL_W }}>
      <button className="mob-press" style={cardBtn} onClick={() => onOpen(item)} aria-label={label}>
        <Art id={item.Id} type="Thumb" fallback={{ id: item.SeriesId || item.Id, type: 'Backdrop' }}
          alt={label} ratio="16 / 9">
          {progress && pct > 0 && (
            <span style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 4, background: 'rgba(0,0,0,.5)' }}>
              <span style={{ display: 'block', width: `${pct}%`, height: '100%', background: T.text }} />
            </span>
          )}
        </Art>
        <div style={{ ...TYPE.body, fontWeight: 600, color: T.text, marginTop: 8, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{label}</div>
        {sub && <div style={{ fontFamily: MONO, fontSize: 11, color: T.faint, marginTop: 2, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{sub}</div>}
      </button>
    </RailItem>
  )
}

// 16:9 library view card (label + icon over a dimmed backdrop).
function ViewCard({ view, onOpen }: any = {}) {
  return (
    <RailItem style={{ width: VIEW_W }}>
      <button className="mob-press" style={cardBtn} onClick={() => onOpen(view)} aria-label={view.Name}>
        <Art id={view.Id} type="Primary" alt={view.Name} ratio="16 / 9">
          <span style={{ position: 'absolute', inset: 0, background: 'linear-gradient(90deg, rgba(0,0,0,.74), rgba(0,0,0,.06))' }} />
          <span style={{ position: 'absolute', left: 14, bottom: 12, display: 'flex', alignItems: 'center', gap: 9, ...TYPE.title, fontSize: 18, color: '#fff' }}>
            <Icon path={viewIcon(view)} size={19} sw={2} />{view.Name}
          </span>
        </Art>
      </button>
    </RailItem>
  )
}

// Poster for a download card — external *arr posterUrl, with an icon fallback.
function DlPoster({ src, kind, w }: any = {}) {
  const [ok, setOk] = useState(true)
  return (
    <div style={{
      width: w, aspectRatio: '2 / 3', borderRadius: 10, overflow: 'hidden', flex: '0 0 auto',
      background: T.surface, display: 'grid', placeItems: 'center', position: 'relative',
    }}>
      {src && ok
        ? <img src={src} alt="" onError={() => setOk(false)} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
        : <Icon path={kind === 'movie' ? Ic.film : Ic.tv} size={Math.round(w * 0.34)} stroke={T.faint} sw={1.6} />}
    </div>
  )
}

// "Downloading now" — a live-progress card. Taps through to the Downloads queue.
function DownloadingCard({ torrent }: any = {}) {
  const pct = Math.max(0, Math.min(100, Math.round((torrent.progress || 0) * 100)))
  const title = torrent.displayTitle || torrent.name
  return (
    <RailItem style={{ width: DL_W }}>
      <button className="mob-press" style={cardBtn} onClick={() => navigate('/downloads')} title={torrent.name} aria-label={`${title} — downloading ${pct}%`}>
        <div style={{
          display: 'flex', gap: 12, padding: 12, borderRadius: R.md, border: `1px solid ${T.line}`,
          background: T.surface,
        }}>
          <DlPoster src={torrent.posterUrl} kind={torrent.kind} w={54} />
          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginBottom: 5, ...TYPE.meta, fontSize: 10, color: T.brand }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: T.brand, animation: 'pulse 1.6s ease-in-out infinite' }} />
              DOWNLOADING
            </div>
            <div style={{ ...TYPE.body, fontWeight: 700, color: T.text, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{title}</div>
            {torrent.subtitle && <div style={{ fontFamily: MONO, fontSize: 11, color: T.faint, marginTop: 2, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{torrent.subtitle}</div>}
            <div style={{ marginTop: 'auto', paddingTop: 10 }}>
              <div style={{ height: 6, borderRadius: 999, background: 'rgba(255,255,255,.1)', overflow: 'hidden' }}>
                <div style={{ width: `${pct}%`, height: '100%', borderRadius: 999, background: T.text, transition: 'width .4s' }} />
              </div>
              <div style={{ display: 'flex', gap: 12, marginTop: 8, fontFamily: MONO, fontSize: 11, color: T.faint }}>
                <span style={{ color: T.text, fontWeight: 700 }}>{pct}%</span>
                <span>↓ {fmtSpeed(torrent.dlspeed)}</span>
              </div>
            </div>
          </div>
        </div>
      </button>
    </RailItem>
  )
}

/* ── Detail / drill-in sheet ─────────────────────────────────────────────── */

function MetaChips({ items }: any = {}) {
  const parts = items.filter(Boolean)
  if (!parts.length) return null
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, alignItems: 'center', fontFamily: MONO, fontSize: 12, color: T.dim, marginTop: 12 }}>
      {parts.map((p, i) => <span key={i}>{p}</span>)}
    </div>
  )
}

// Hero for a leaf (Movie/Episode → shows the Watch button) or a Series (info
// only; seasons render below via <ChildrenView>). Fetches full item detail.
function DetailHero({ item, onWatch }: any = {}) {
  const [d, setD] = useState(null)
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    let cancel = false
    setLoading(true); setD(null)
    fetch(`/api/library/item/${item.Id}`, { credentials: 'include' })
      .then(r => r.ok ? r.json() : null)
      .then(x => { if (!cancel) setD(x) })
      .catch(() => {})
      .finally(() => { if (!cancel) setLoading(false) })
    return () => { cancel = true }
  }, [item.Id])

  const data = d || item
  const isLeaf = LEAF.has(item.Type)
  const backdropId = data.SeriesId || data.Id
  const genres = (data.Genres || []).slice(0, 2)
  const resuming = (data.UserData?.PlaybackPositionTicks || 0) > 0
  const epLine = data.Type === 'Episode'
    ? [data.SeriesName, data.ParentIndexNumber != null ? `S${data.ParentIndexNumber} · E${data.IndexNumber}` : null].filter(Boolean).join('   ·   ')
    : null

  return (
    <div>
      <Art id={backdropId} type="Backdrop" fallback={{ id: data.Id, type: 'Primary' }} alt={data.Name} ratio="16 / 9" radius={R.lg}>
        <span style={{ position: 'absolute', inset: 0, background: `linear-gradient(0deg, rgba(0,0,0,.9) 2%, rgba(0,0,0,.15) 62%, transparent)` }} />
      </Art>

      <h2 style={{ ...TYPE.title, fontSize: 22, color: T.text, marginTop: 14 }}>{data.Name}</h2>
      {epLine && <div style={{ fontFamily: MONO, fontSize: 12, color: T.dim, marginTop: 6 }}>{epLine}</div>}

      <MetaChips items={[
        data.Type !== 'Episode' && data.ProductionYear,
        fmtRuntime(data.RunTimeTicks),
        data.CommunityRating != null ? `★ ${data.CommunityRating.toFixed(1)}` : null,
        data.OfficialRating,
        ...genres,
      ]} />

      {isLeaf && (
        <button className="mob-press" onClick={() => onWatch(item.Id)} style={{
          marginTop: 18, width: '100%', height: 54, borderRadius: R.pill, border: 'none', cursor: 'pointer',
          background: T.primary, color: T.onLight, ...TYPE.headline, fontWeight: 800,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        }}>
          <Icon path={Ic.play} size={20} fill={T.onLight} stroke="none" />
          {resuming ? 'Resume together' : 'Watch together'}
        </button>
      )}

      {loading && !d && (
        <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <Skeleton w="82%" h={12} /><Skeleton w="95%" h={12} /><Skeleton w="58%" h={12} />
        </div>
      )}
      {data.Overview && (
        <p style={{ ...TYPE.body, color: 'rgba(241,243,246,.82)', marginTop: 16, display: '-webkit-box', WebkitLineClamp: 5, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{data.Overview}</p>
      )}
    </div>
  )
}

// Tappable episode row (Season contents). Whole row → start a party at it.
function EpisodeRow({ ep, onWatch }: any = {}) {
  const num = ep.IndexNumber != null ? `E${ep.IndexNumber}` : ''
  const rt = fmtRuntime(ep.RunTimeTicks)
  return (
    <button className="mob-press" onClick={() => onWatch(ep.Id)} aria-label={`Watch ${ep.Name}`}
      style={{ ...cardBtn, display: 'flex', gap: 12, alignItems: 'center', padding: 8, borderRadius: R.md, border: `1px solid ${T.line}`, background: 'rgba(255,255,255,.03)' }}>
      <Art id={ep.Id} type="Thumb" fallback={{ id: ep.SeriesId || ep.Id, type: 'Backdrop' }} alt={ep.Name} ratio="16 / 9" radius={10} style={{ width: 120, flex: '0 0 auto' }} />
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ ...TYPE.label, color: T.text, display: 'block', overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>
          {num && <span style={{ color: T.dim, fontFamily: MONO, marginRight: 6 }}>{num}</span>}{ep.Name}
        </span>
        {rt && <span style={{ fontFamily: MONO, fontSize: 11, color: T.faint, display: 'block', marginTop: 4 }}>{rt}</span>}
      </span>
      <span style={{ width: 40, height: 40, flex: '0 0 auto', borderRadius: 999, display: 'grid', placeItems: 'center', background: 'rgba(255,255,255,.06)', color: T.text }}>
        <Icon path={Ic.play} size={16} fill="currentColor" stroke="none" />
      </span>
    </button>
  )
}

// Children of a folder-ish node: seasons/library items → poster grid (tap drills
// in); episodes → a tappable row list (tap starts a party).
function ChildrenView({ parentId, onOpen, onWatch, top = 0 }: any = {}) {
  const [items, setItems] = useState(null)
  useEffect(() => {
    let cancel = false
    setItems(null)
    fetch(`/api/library/items/${parentId}/children`, { credentials: 'include' })
      .then(r => r.ok ? r.json() : [])
      .then(x => { if (!cancel) setItems(Array.isArray(x) ? x : []) })
      .catch(() => { if (!cancel) setItems([]) })
    return () => { cancel = true }
  }, [parentId])

  if (items === null) return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(100px, 1fr))', gap: 12, marginTop: top }}>
      {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} h="auto" radius={R.md} style={{ aspectRatio: '2 / 3' }} />)}
    </div>
  )
  if (!items.length) return <p style={{ ...TYPE.body, color: T.dim, marginTop: 20 }}>Nothing here yet.</p>

  if (items.some(it => it.Type === 'Episode')) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: top }}>
        {items.map(ep => <EpisodeRow key={ep.Id} ep={ep} onWatch={onWatch} />)}
      </div>
    )
  }
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(100px, 1fr))', gap: 12, marginTop: top }}>
      {items.map(it => (
        <button key={it.Id} className="mob-press" style={cardBtn} onClick={() => onOpen(it)} aria-label={it.Name}>
          <Art id={it.Id} type="Primary" fallback={{ id: it.SeriesId || it.Id, type: 'Backdrop' }} alt={it.Name} ratio="2 / 3">
            {it.Type === 'Season' && it.IndexNumber != null && (
              <span style={{ position: 'absolute', top: 6, left: 6, ...TYPE.meta, fontSize: 9.5, padding: '2px 6px', borderRadius: 7, background: 'rgba(0,0,0,.66)', color: '#fff' }}>S{it.IndexNumber}</span>
            )}
          </Art>
          <div style={{ ...TYPE.label, color: T.text, marginTop: 6, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{it.Name}</div>
        </button>
      ))}
    </div>
  )
}

/**
 * Bottom sheet that opens on any poster tap. Manages a small internal drill-in
 * stack so a Series → Season → Episode path lives in one sheet without touching
 * the app router. Leaf items expose "Watch together" → navigate('/party/new?…').
 * The stack is intentionally NOT cleared on close so the panel keeps its content
 * through the slide-out; it re-inits when a new root item opens.
 */
function DetailSheet({ item, onClose }: any = {}) {
  const [stack, setStack] = useState([])
  const rootRef = useRef(null)
  useEffect(() => {
    if (!item) { rootRef.current = null; return }
    if (item.Id !== rootRef.current) { rootRef.current = item.Id; setStack([item]) }
  }, [item])

  const current = stack[stack.length - 1] || null
  const depth = stack.length
  const push = (it) => setStack(s => [...s, { Id: it.Id, Name: it.Name, Type: it.Type, SeriesId: it.SeriesId, SeriesName: it.SeriesName }])
  const pop = () => setStack(s => (s.length > 1 ? s.slice(0, -1) : s))
  const watch = (id) => { onClose(); navigate(`/party/new?itemId=${id}`) }

  const isLeaf = current && LEAF.has(current.Type)
  const isSeries = current && current.Type === 'Series'

  return (
    <Sheet open={!!item} onClose={onClose} maxHeight="92dvh">
      {current && (
        <div key={current.Id} style={{ animation: `tabIn .2s ${EASE} both` }}>
          {depth > 1 && (
            <div style={{
              position: 'sticky', top: 0, zIndex: 3, margin: '0 -16px', padding: '0 16px 12px',
              display: 'flex', alignItems: 'center', gap: 10,
              background: 'linear-gradient(180deg, rgba(0,0,0,.92) 66%, rgba(0,0,0,0))',
            }}>
              <button onClick={pop} aria-label="Back" className="mob-press" style={{
                width: 44, height: 44, flex: '0 0 auto', borderRadius: 999, border: `1px solid ${T.line}`,
                background: 'rgba(255,255,255,.05)', color: T.text, display: 'grid', placeItems: 'center', cursor: 'pointer',
              }}>
                <Icon path={Ic.back} size={20} />
              </button>
              <h2 style={{ ...TYPE.title, fontSize: 18, color: T.text, minWidth: 0, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{current.Name}</h2>
            </div>
          )}

          {isLeaf && <DetailHero item={current} onWatch={watch} />}
          {isSeries && (
            <>
              <DetailHero item={current} onWatch={watch} />
              <div style={{ ...TYPE.meta, color: T.dim, margin: '22px 0 12px' }}>Seasons</div>
              <ChildrenView parentId={current.Id} onOpen={push} onWatch={watch} />
            </>
          )}
          {!isLeaf && !isSeries && <ChildrenView parentId={current.Id} onOpen={push} onWatch={watch} top={4} />}
        </div>
      )}
    </Sheet>
  )
}

/* ── Account sheet (avatar → sign out) ───────────────────────────────────── */
const rowBtn: any = {
  width: '100%', display: 'flex', alignItems: 'center', gap: 12, minHeight: 52, padding: '0 16px',
  borderRadius: R.md, border: `1px solid ${T.line}`, background: 'rgba(255,255,255,.03)', color: T.text,
  ...TYPE.body, fontWeight: 600, cursor: 'pointer', textAlign: 'left',
}
function AccountSheet({ open, onClose, user, initials, logout, onJoin }: any = {}) {
  return (
    <Sheet open={open} onClose={onClose} title="Account">
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '2px 0 18px' }}>
        <span style={{ width: 52, height: 52, borderRadius: 999, display: 'grid', placeItems: 'center', background: AVATAR_BG, border: `1px solid ${T.line2}`, color: T.text, ...TYPE.headline, fontWeight: 800 }}>{initials}</span>
        <div style={{ minWidth: 0 }}>
          <div style={{ ...TYPE.headline, color: T.text, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{user?.name || 'You'}</div>
          <div style={{ ...TYPE.label, fontWeight: 500, color: T.dim, marginTop: 2 }}>Signed in with Jellyfin</div>
        </div>
      </div>
      <button onClick={onJoin} className="mob-press" style={rowBtn}>
        <Icon path={Ic.users} size={20} stroke={T.text} />Start or join a party
        <Icon path={Ic.chevR} size={18} stroke={T.faint} style={{ marginLeft: 'auto' }} />
      </button>
      <button onClick={() => { onClose(); logout() }} className="mob-press" style={{ ...rowBtn, color: T.red, marginTop: 10 }}>
        <Icon path={Ic.logout} size={20} stroke={T.red} />Sign out
      </button>
    </Sheet>
  )
}

/* ── Loading / empty / error ─────────────────────────────────────────────── */
function SectionLoading() {
  return (
    <>
      {[262, 128].map((w, i) => (
        <div key={i} style={{ marginBottom: SP.xl }}>
          <div style={{ padding: '0 16px', marginBottom: SP.md }}><Skeleton w={i ? 150 : 200} h={20} radius={R.sm} /></div>
          <RailSkeleton count={5} w={w} />
        </div>
      ))}
    </>
  )
}
function ErrorNote({ onRetry }: any = {}) {
  return (
    <div style={{
      margin: '14px 16px', padding: '14px 16px', borderRadius: R.md, ...TYPE.body,
      background: 'rgba(255,107,107,.1)', border: '1px solid rgba(255,107,107,.3)', color: T.red,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12,
    }}>
      <span>Couldn't load your library.</span>
      <button onClick={onRetry} className="mob-press" style={{ border: 'none', background: 'rgba(255,255,255,.1)', color: T.text, ...TYPE.label, padding: '8px 14px', borderRadius: 999, cursor: 'pointer' }}>Retry</button>
    </div>
  )
}
function EmptyState({ onStart }: any = {}) {
  return (
    <div style={{ padding: '9vh 24px', display: 'grid', placeItems: 'center', textAlign: 'center' }}>
      <div style={{ maxWidth: 320, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
        <span style={{ width: 60, height: 60, borderRadius: 20, display: 'grid', placeItems: 'center', background: T.surface, border: `1px solid ${T.line}`, color: T.dim }}>
          <Icon path={Ic.film} size={28} />
        </span>
        <h2 style={{ ...TYPE.title, color: T.text }}>Nothing here yet</h2>
        <p style={{ ...TYPE.body, color: T.dim }}>Your library looks empty. Start a watch party or join a friend with a code.</p>
        <button onClick={onStart} className="mob-press" style={{
          marginTop: 6, height: 50, padding: '0 24px', borderRadius: R.pill, border: 'none', cursor: 'pointer',
          background: T.primary, color: T.onLight, ...TYPE.headline, fontWeight: 800,
          display: 'inline-flex', alignItems: 'center', gap: 9,
        }}>
          <Icon path={Ic.play} size={19} fill={T.onLight} stroke="none" />Start a watch party
        </button>
      </div>
    </div>
  )
}

/* ── Screen ──────────────────────────────────────────────────────────────── */
export default function Home() {
  const { user, logout } = useAuth()
  const { openJoin } = useMobileShell()
  const name = (user?.name || 'there').split(' ')[0]
  const initials = (user?.name || '?').split(' ').filter(Boolean).map(w => w[0]).join('').toUpperCase().slice(0, 2) || '?'

  const [home, setHome] = useState(null)
  const [latest, setLatest] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [reload, setReload] = useState(0)
  const [detail, setDetail] = useState(null)
  const [account, setAccount] = useState(false)

  // Shared download poller — same hook/shape the TabBar + Downloads screen use.
  const { list } = useTorrents(true)
  const arriving = list.filter(t => isActiveState(t.state))

  useEffect(() => {
    let cancel = false
    setLoading(true); setError(false)
    fetch('/api/library/home', { credentials: 'include' })
      .then(r => r.ok ? r.json() : Promise.reject(r))
      .then(d => { if (!cancel) setHome(d) })
      .catch(() => { if (!cancel) setError(true) })
      .finally(() => { if (!cancel) setLoading(false) })
    return () => { cancel = true }
  }, [reload])

  useEffect(() => {
    let cancel = false
    fetch('/api/library/latest', { credentials: 'include' })
      .then(r => r.ok ? r.json() : Promise.reject(r))
      .then(d => { if (!cancel) setLatest(Array.isArray(d) ? d : []) })
      .catch(() => {})
    return () => { cancel = true }
  }, [reload])

  const resume = home?.resume ?? []
  const nextUp = home?.nextUp ?? []
  const views = home?.views ?? []
  const nothing = !loading && !error && !resume.length && !latest.length && !nextUp.length && !views.length && !arriving.length

  // gentle staggered rise, contiguous over whichever rails actually render
  let idx = 0
  const rise = () => ({ animation: `up .5s ${EASE} both`, animationDelay: `${(idx++) * 0.05}s` })

  return (
    <>
      <TopBar
        title={`Hey, ${name}`}
        subtitle="What are we watching?"
        right={
          <>
            <TopBarButton label="Start or join a party" onClick={openJoin}><Icon path={Ic.users} size={21} /></TopBarButton>
            <button onClick={() => setAccount(true)} aria-label="Account" className="mob-press" style={{
              width: 44, height: 44, borderRadius: 999, border: `1px solid ${T.line}`, background: T.glassHi,
              color: T.text, ...TYPE.label, fontWeight: 800, cursor: 'pointer', flex: '0 0 auto',
            }}>{initials}</button>
          </>
        }
      />

      <div style={{ paddingTop: 10 }}>
        {loading && !home && <SectionLoading />}
        {error && !home && <ErrorNote onRetry={() => setReload(n => n + 1)} />}
        {nothing && <EmptyState onStart={openJoin} />}

        {resume.length > 0 && (
          <Rail title="Continue watching" count={resume.length} style={rise()}>
            {resume.map(it => <StillCard key={it.Id} item={it} onOpen={setDetail} progress />)}
          </Rail>
        )}
        {latest.length > 0 && (
          <Rail title="Recently added" count={latest.length} style={rise()}>
            {latest.map(it => <PosterCard key={it.Id} item={it} onOpen={setDetail} badge="NEW" />)}
          </Rail>
        )}
        {arriving.length > 0 && (
          <Rail title="Downloading now" count={arriving.length} style={rise()}>
            {arriving.map(t => <DownloadingCard key={t.hash} torrent={t} />)}
          </Rail>
        )}
        {nextUp.length > 0 && (
          <Rail title="Next up" count={nextUp.length} style={rise()}>
            {nextUp.map(it => <StillCard key={it.Id} item={it} onOpen={setDetail} />)}
          </Rail>
        )}
        {views.length > 0 && (
          <Rail title="Libraries" count={views.length} style={rise()}>
            {views.map(v => <ViewCard key={v.Id} view={v} onOpen={setDetail} />)}
          </Rail>
        )}
      </div>

      <DetailSheet item={detail} onClose={() => setDetail(null)} />
      <AccountSheet open={account} onClose={() => setAccount(false)} user={user} initials={initials} logout={logout} onJoin={() => { setAccount(false); openJoin() }} />
    </>
  )
}
