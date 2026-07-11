// Shared download UI: a circular progress ring, a 2:3 poster tile with the ring
// overlaid (used on the Library "Downloading now" rail and the Downloads tab),
// and the full-screen download DETAIL overlay. The detail mirrors a library
// item's detail page (blurred hero, poster, title, overview, genres, rating) but
// sources its metadata from Radarr/Sonarr via GET /api/servarr/downloads/:hash/
// detail (a still-downloading title isn't in Jellyfin yet), and — since it can't
// be played — swaps the Play button for the progress ring + live speed/seeds/
// peers/ETA and Pause + Delete controls. Self-contained (own tokens/icons) to
// match the codebase's inline, per-surface style.

import { useEffect, useState } from 'react'
import { useIsMobile } from '../hooks/useIsMobile'
import { C, SANS, MONO, Ic, Icon } from '../lib/ui'
import { fmtSize, fmtSpeed, fmtEta, fmtRuntimeFromMinutes, isPausedState } from '../lib/format'
import { jpost } from '../lib/api'

/* ── Monochrome tokens local to this file. Progress is white on a white-alpha
   track; the only color is a single muted red used strictly for the "active
   transfer" dot and destructive/delete actions — never as decoration. ────── */
const WHITE = '#F4F4F5'
const TRACK = 'rgba(255,255,255,.18)'
const LIVE = '#E0655E'
const DANGER = '#E0655E'
const DANGER_BG = 'rgba(224,101,94,.12)'
const DANGER_BORDER = 'rgba(224,101,94,.35)'
const FLAT = { backgroundColor: '#141416', border: '1px solid rgba(255,255,255,.08)', boxShadow: 'none' }

const clampPct = (progress: number | null | undefined) => Math.max(0, Math.min(100, Math.round((progress || 0) * 100)))
type DownloadRingProps = { pct?: number; size?: number; stroke?: number; color?: string; track?: string; labelColor?: string; labelSize?: number }
type DownloadPosterProps = { posterUrl?: string | null; kind?: string; pct?: number; paused?: boolean; width?: number | string; radius?: number; ringSize?: number }
type Torrent = { hash: string; progress?: number; state?: string; kind?: string; displayTitle?: string; name?: string; subtitle?: string; posterUrl?: string; dlspeed?: number; eta?: number; numSeeds?: number; numLeechs?: number; size?: number }

/* ── Circular progress ring (SVG donut: track circle + progress arc via
   stroke-dasharray/stroke-dashoffset, NN% centered). Neutral white by default —
   no phase color. ────────────────────────────────────────────────────────── */
export function DownloadRing({ pct = 0, size = 72, stroke = 6, color = WHITE, track = TRACK, labelColor = '#fff', labelSize }: DownloadRingProps = {}) {
  const clamped = Math.max(0, Math.min(100, Math.round(pct)))
  const r = (size - stroke) / 2
  const circ = 2 * Math.PI * r
  const offset = circ * (1 - clamped / 100)
  const ls = labelSize ?? Math.max(11, Math.round(size * 0.26))
  const c = size / 2
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ display: 'block' }} role="img" aria-label={`${clamped}% downloaded`}>
      <circle cx={c} cy={c} r={r} fill="none" stroke={track} strokeWidth={stroke} />
      <circle cx={c} cy={c} r={r} fill="none" stroke={color} strokeWidth={stroke}
        strokeLinecap="round" strokeDasharray={circ} strokeDashoffset={offset}
        transform={`rotate(-90 ${c} ${c})`} style={{ transition: 'stroke-dashoffset .5s ease' }} />
      <text x="50%" y="50%" dominantBaseline="central" textAnchor="middle"
        fill={labelColor} fontFamily={MONO} fontSize={ls} fontWeight="700">{clamped}%</text>
    </svg>
  )
}

/* ── 2:3 poster tile with the ring centered over a flat black-alpha scrim (the
   one allowed non-white overlay — a legibility scrim, not decoration). Robust
   DARK placeholder (film/tv icon on the dark surface) when there's no poster or
   it 404s — never a blank white square. A single small "live" red dot sits
   top-left while actively downloading — the only color on the tile. ──────── */
export function DownloadPoster({ posterUrl, kind, pct = 0, paused = false, width = 170, radius = 14, ringSize }: DownloadPosterProps = {}) {
  const [ok, setOk] = useState(true)
  const show = posterUrl && ok
  const rs = ringSize ?? Math.round(Math.min(typeof width === 'number' ? width : 200, 200) * 0.46)
  return (
    <div style={{ position: 'relative', width: width === '100%' ? '100%' : width, aspectRatio: '2/3', borderRadius: radius,
      overflow: 'hidden', background: C.surface, display: 'grid', placeItems: 'center' }}>
      {show
        ? <img src={posterUrl} alt="" onError={() => setOk(false)}
            style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
        : <Icon path={kind === 'movie' ? Ic.film : Ic.tv} size={40} stroke={C.faint} sw={1.4} />}
      {/* Flat black-alpha scrim under the ring so the % stays legible over any artwork. */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.5)' }} />
      <div style={{ position: 'relative' }}><DownloadRing pct={pct} size={rs} color={paused ? C.dim : WHITE} /></div>
      {!paused && (
        <span style={{ position: 'absolute', top: 8, left: 8, display: 'inline-flex', alignItems: 'center', gap: 5,
          padding: '3px 8px', borderRadius: 999, background: 'rgba(0,0,0,.55)',
          fontFamily: MONO, fontSize: 9.5, fontWeight: 700, letterSpacing: '.05em', color: C.text }}>
          <span style={{ width: 6, height: 6, borderRadius: '50%', background: LIVE,
            animation: 'pulse 1.6s ease-in-out infinite' }} />DL
        </span>
      )}
    </div>
  )
}

// Fetch the rich metadata for a download by hash. Falls back silently to the
// torrent's own enriched fields (displayTitle/subtitle/posterUrl/kind) if the
// lookup can't resolve or Radarr/Sonarr are unreachable.
function useDownloadDetail(hash: string | null | undefined) {
  const [detail, setDetail] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    if (!hash) return
    let cancel = false
    setLoading(true); setDetail(null)
    fetch(`/api/servarr/downloads/${encodeURIComponent(hash)}/detail`, { credentials: 'include' })
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then((d) => { if (!cancel) setDetail(d) })
      .catch(() => {})
      .finally(() => { if (!cancel) setLoading(false) })
    return () => { cancel = true }
  }, [hash])
  return { detail, loading }
}

/* ── Download DETAIL overlay ──────────────────────────────────────────────────
   `torrent` is the live enriched item the page already polls (kept fresh so the
   ring + stats update in place). Actions POST straight to the qBittorrent proxy
   and let the page's poller reconcile; a delete closes the overlay. */
export function DownloadDetail({ torrent, onClose }: { torrent?: Torrent | null; onClose?: () => void } = {}) {
  const mobile = useIsMobile()
  const { detail, loading } = useDownloadDetail(torrent?.hash)
  const [busy, setBusy] = useState(false)
  const [confirmDel, setConfirmDel] = useState(false)

  if (!torrent) return null

  const pct = clampPct(torrent.progress)
  const paused = isPausedState(torrent.state)
  const done = pct >= 100

  // Prefer resolved catalog metadata; fall back to the enriched torrent fields.
  const kind = detail?.kind || torrent.kind
  const title = detail?.title || torrent.displayTitle || torrent.name
  const subtitle = detail?.subtitle || torrent.subtitle || null
  const posterUrl = detail?.posterUrl || torrent.posterUrl || null
  const overview = detail?.overview || null
  const genres = detail?.genres || []
  const rating = detail?.rating ?? null
  const runtime = fmtRuntimeFromMinutes(detail?.runtime)
  const infoLine = [detail?.year, runtime, detail?.certification, detail?.network, detail?.status].filter(Boolean)

  const doAction = (endpoint: string, body: unknown) => {
    setBusy(true)
    jpost(`/api/servarr/qbittorrent/${endpoint}`, { hashes: torrent.hash, ...(body as Record<string, unknown>) })
      .catch(() => {})
      .finally(() => setBusy(false))
  }
  const onPauseResume = () => doAction(paused ? 'resume' : 'pause', {})
  const onDelete = (deleteFiles: boolean) => {
    setConfirmDel(false)
    setBusy(true)
    jpost('/api/servarr/qbittorrent/delete', { hashes: torrent.hash, deleteFiles })
      .catch(() => {})
      .finally(() => { setBusy(false); onClose?.() })
  }

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 120, background: C.bg, color: C.text, fontFamily: SANS,
      overflowY: 'auto', animation: 'up .25s ease both' }}>
      {/* Backdrop from the poster, darkened with a flat black-alpha scrim (the one
          allowed gradient — single-hue black, purely for text legibility). */}
      <div style={{ position: 'relative', minHeight: mobile ? 'auto' : 'min(72vh, 600px)', display: 'flex', alignItems: 'flex-end' }}>
        <div style={{ position: 'absolute', inset: 0, overflow: 'hidden' }}>
          {posterUrl
            ? <img src={posterUrl} alt="" referrerPolicy="no-referrer"
                style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top center', filter: 'blur(26px) brightness(.6)', transform: 'scale(1.15)' }} />
            : <div style={{ width: '100%', height: '100%', background: C.surface }} />}
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(0deg, rgba(0,0,0,.92) 4%, rgba(0,0,0,.55) 48%, rgba(0,0,0,.3) 100%)` }} />
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(90deg, rgba(0,0,0,.72) 0%, rgba(0,0,0,.35) 45%, transparent 82%)` }} />
        </div>

        {/* Back / close */}
        <button onClick={onClose} title="Back" style={{ position: 'absolute', top: mobile ? 12 : 18, left: mobile ? 12 : 18, zIndex: 3,
          width: 40, height: 40, borderRadius: 999, display: 'grid', placeItems: 'center', cursor: 'pointer', color: C.text,
          ...FLAT }}>
          <Icon path={Ic.chevL} size={18} sw={2} />
        </button>

        <div style={{ position: 'relative', width: '100%', padding: mobile ? '110px 16px 22px' : '0 40px 40px',
          display: 'flex', gap: mobile ? 16 : 28, alignItems: 'flex-end' }}>
          {/* Poster with the ring overlay (the "progress" in lieu of a play button) */}
          <div style={{ width: mobile ? 128 : 200, flexShrink: 0, boxShadow: '0 16px 44px rgba(0,0,0,.62)', borderRadius: 16, overflow: 'hidden' }}>
            <DownloadPoster posterUrl={posterUrl} kind={kind} pct={pct} paused={paused} width={mobile ? 128 : 200} radius={16} />
          </div>

          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontFamily: MONO, fontSize: 11.5, fontWeight: 700,
              letterSpacing: '.06em', color: C.dim, marginBottom: 10 }}>
              <span style={{ width: 7, height: 7, borderRadius: '50%', background: paused ? C.faint : LIVE,
                animation: paused ? 'none' : 'pulse 1.6s ease-in-out infinite' }} />
              {done ? 'FINISHING UP' : paused ? 'PAUSED' : 'DOWNLOADING'}
            </div>
            <h1 style={{ fontSize: mobile ? 26 : 40, fontWeight: 800, letterSpacing: '-.02em', margin: 0, lineHeight: 1.05,
              display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{title}</h1>
            {subtitle && <div style={{ fontFamily: MONO, fontSize: 13.5, color: C.dim, marginTop: 8 }}>{subtitle}</div>}

            {/* Rating + genres */}
            {(rating != null || genres.length > 0) && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap', marginTop: 14, fontSize: 15, fontWeight: 600 }}>
                {rating != null && (
                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: C.text }}>
                    <Icon path={Ic.star} size={16} fill={C.text} stroke="none" />{rating.toFixed(1)}
                  </span>
                )}
                {genres.slice(0, 3).map((g: string) => <span key={g} style={{ color: C.dim }}>{g}</span>)}
              </div>
            )}

            {/* Info line (year · runtime · rating · network · status) */}
            {infoLine.length > 0 && (
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', marginTop: 10, fontFamily: MONO, fontSize: 13, color: C.dim }}>
                {infoLine.map((v, i) => <span key={i}>{v}</span>)}
              </div>
            )}

            {/* Progress + live stats + controls (no Play — it isn't watchable yet). */}
            <div style={{ display: 'flex', alignItems: 'center', gap: mobile ? 16 : 24, flexWrap: 'wrap', marginTop: 22 }}>
              <DownloadRing pct={pct} size={mobile ? 88 : 104} stroke={8} color={paused ? C.dim : WHITE} />
              <div style={{ minWidth: 180 }}>
                <div style={{ display: 'grid', gridTemplateColumns: 'auto auto', gap: '6px 20px', fontFamily: MONO, fontSize: 13, color: C.dim }}>
                  <span>↓ {fmtSpeed(torrent.dlspeed)}</span>
                  <span>ETA {done ? '—' : fmtEta(torrent.eta)}</span>
                  <span>Seeds {torrent.numSeeds ?? 0}</span>
                  <span>Peers {torrent.numLeechs ?? 0}</span>
                  <span style={{ color: C.faint }}>{fmtSize(torrent.size)}</span>
                </div>
              </div>
            </div>

            {/* Pause / Resume + Delete */}
            <div style={{ display: 'flex', gap: 12, marginTop: 22, flexWrap: 'wrap' }}>
              <button onClick={onPauseResume} disabled={busy || done} title={paused ? 'Resume' : 'Pause'}
                style={{ display: 'inline-flex', alignItems: 'center', gap: 10, padding: '13px 26px', border: 'none', borderRadius: 999,
                  background: C.accent, color: C.onAccent, fontFamily: SANS, fontSize: 15, fontWeight: 700,
                  cursor: busy || done ? 'default' : 'pointer', opacity: busy || done ? 0.5 : 1 }}>
                <Icon path={paused ? Ic.play : Ic.pause} size={17} fill={paused ? 'currentColor' : 'none'} stroke={paused ? 'none' : 'currentColor'} sw={2} />
                {paused ? 'Resume' : 'Pause'}
              </button>
              <button onClick={() => setConfirmDel(true)} disabled={busy} title="Delete"
                style={{ display: 'inline-flex', alignItems: 'center', gap: 10, padding: '13px 24px', borderRadius: 999,
                  border: `1px solid ${DANGER_BORDER}`, background: DANGER_BG, color: DANGER,
                  fontFamily: SANS, fontSize: 15, fontWeight: 700, cursor: busy ? 'default' : 'pointer', opacity: busy ? 0.5 : 1 }}>
                <Icon path={Ic.trash} size={17} sw={2} />Delete
              </button>
            </div>

            {loading && !detail && (
              <div style={{ marginTop: 14, fontFamily: MONO, fontSize: 12, color: C.faint }}>Loading details…</div>
            )}
          </div>
        </div>
      </div>

      {/* Overview */}
      {overview && (
        <div style={{ padding: mobile ? '0 16px 60px' : '0 40px 80px' }}>
          <p style={{ fontSize: 15, lineHeight: 1.65, color: C.dim, maxWidth: 760, margin: 0 }}>{overview}</p>
        </div>
      )}

      {confirmDel && (
        <DeleteConfirm name={torrent.displayTitle || torrent.name} mobile={mobile}
          onClose={() => setConfirmDel(false)} onConfirm={onDelete} />
      )}
    </div>
  )
}

/* Delete confirm — mirrors Downloads.jsx's DeleteDialog (with the same
   "also delete files" toggle) so the two surfaces read identically: a flat
   solid surface, no blur, sitting on a plain black-alpha scrim. */
function DeleteConfirm({ name, mobile, onClose, onConfirm }: any = {}) {
  const [deleteFiles, setDeleteFiles] = useState(false)
  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 130, display: 'grid', placeItems: 'center',
      padding: 16, background: 'rgba(0,0,0,.6)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)', animation: 'up .2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ width: 'min(440px, 100%)', borderRadius: 16, padding: mobile ? 20 : 26,
        ...FLAT, boxShadow: '0 24px 60px rgba(0,0,0,.7)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
          <div style={{ width: 42, height: 42, borderRadius: 12, display: 'grid', placeItems: 'center', flexShrink: 0,
            background: DANGER_BG, border: `1px solid ${DANGER_BORDER}` }}>
            <Icon path={Ic.trash} size={20} stroke={DANGER} sw={1.8} />
          </div>
          <h2 style={{ fontSize: 19, fontWeight: 800, margin: 0 }}>Remove download?</h2>
        </div>
        <p style={{ color: C.dim, fontSize: 14, lineHeight: 1.55, margin: '0 0 16px', wordBreak: 'break-word' }}>
          <span style={{ color: C.text, fontWeight: 600 }}>{name}</span> will stop downloading and be removed.
        </p>
        <button onClick={() => setDeleteFiles((v) => !v)} style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 12,
          padding: '11px 14px', marginBottom: 10, borderRadius: 12, border: `1px solid ${C.line}`, cursor: 'pointer',
          background: 'rgba(255,255,255,.03)', textAlign: 'left' }}>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>Also delete downloaded files</div>
            <div style={{ fontSize: 12, color: C.faint, marginTop: 2 }}>Erase the data on disk, not just the download</div>
          </div>
          <span style={{ width: 42, height: 24, borderRadius: 999, background: deleteFiles ? 'rgba(255,255,255,.55)' : 'rgba(255,255,255,.14)',
            position: 'relative', transition: 'background .18s', flexShrink: 0 }}>
            <span style={{ position: 'absolute', top: 3, left: deleteFiles ? 21 : 3, width: 18, height: 18, borderRadius: '50%',
              background: '#fff', transition: 'left .18s' }} />
          </span>
        </button>
        <div style={{ display: 'flex', gap: 10, marginTop: 8 }}>
          <button onClick={onClose} style={{ flex: 1, height: 46, borderRadius: 13, border: `1px solid ${C.line2}`,
            cursor: 'pointer', fontFamily: SANS, fontSize: 14.5, fontWeight: 700, color: C.text, background: 'rgba(255,255,255,.04)' }}>Cancel</button>
          <button onClick={() => onConfirm(deleteFiles)} style={{ flex: 1, height: 46, borderRadius: 13, border: 'none',
            cursor: 'pointer', fontFamily: SANS, fontSize: 14.5, fontWeight: 700, color: '#fff',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, background: DANGER }}>
            <Icon path={Ic.trash} size={16} sw={2} />Remove
          </button>
        </div>
      </div>
    </div>
  )
}
