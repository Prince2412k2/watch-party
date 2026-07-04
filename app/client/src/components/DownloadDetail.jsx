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
import { useIsMobile } from '../hooks/useIsMobile.js'
import { C, SANS, MONO, glassStyle, Ic, Icon } from '../lib/ui.jsx'
import { fmtSize, fmtSpeed, fmtEta, fmtRuntimeFromMinutes, isPausedState } from '../lib/format.js'
import { jpost } from '../lib/api.js'

const clampPct = (progress) => Math.max(0, Math.min(100, Math.round((progress || 0) * 100)))

/* ── Circular progress ring (SVG donut: track circle + progress arc via
   stroke-dasharray/stroke-dashoffset, NN% centered). ────────────────────────── */
export function DownloadRing({ pct = 0, size = 72, stroke = 6, color = C.green, track = 'rgba(255,255,255,.2)', labelColor = '#fff', labelSize }) {
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

/* ── 2:3 poster tile with the ring centered over a subtle dark scrim. Robust
   DARK placeholder (film/tv icon on the dark surface) when there's no poster or
   it 404s — never a blank white square. A small pulsing "downloading" dot sits
   top-left while active. ─────────────────────────────────────────────────────── */
export function DownloadPoster({ posterUrl, kind, pct = 0, paused = false, width = 170, radius = 14, ringSize }) {
  const [ok, setOk] = useState(true)
  const show = posterUrl && ok
  const rs = ringSize ?? Math.round(Math.min(width, 200) * 0.46)
  const ringColor = paused ? C.dim : C.green
  return (
    <div style={{ position: 'relative', width: width === '100%' ? '100%' : width, aspectRatio: '2/3', borderRadius: radius,
      overflow: 'hidden', background: C.surface, display: 'grid', placeItems: 'center' }}>
      {show
        ? <img src={posterUrl} alt="" onError={() => setOk(false)}
            style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
        : <Icon path={kind === 'movie' ? Ic.film : Ic.tv} size={40} stroke={C.faint} sw={1.4} />}
      {/* Dark scrim under the ring so the % stays legible over any artwork. */}
      <div style={{ position: 'absolute', inset: 0, background:
        'radial-gradient(circle at 50% 50%, rgba(6,8,11,.66) 0%, rgba(6,8,11,.34) 52%, rgba(6,8,11,.12) 100%)' }} />
      <div style={{ position: 'relative' }}><DownloadRing pct={pct} size={rs} color={ringColor} /></div>
      {!paused && (
        <span style={{ position: 'absolute', top: 8, left: 8, display: 'inline-flex', alignItems: 'center', gap: 5,
          padding: '3px 8px', borderRadius: 999, background: 'rgba(6,8,11,.55)', backdropFilter: 'blur(6px)',
          WebkitBackdropFilter: 'blur(6px)', fontFamily: MONO, fontSize: 9.5, fontWeight: 700, letterSpacing: '.05em', color: C.green }}>
          <span style={{ width: 6, height: 6, borderRadius: '50%', background: C.green, boxShadow: `0 0 6px ${C.green}`,
            animation: 'pulse 1.6s ease-in-out infinite' }} />DL
        </span>
      )}
    </div>
  )
}

// Fetch the rich metadata for a download by hash. Falls back silently to the
// torrent's own enriched fields (displayTitle/subtitle/posterUrl/kind) if the
// lookup can't resolve or Radarr/Sonarr are unreachable.
function useDownloadDetail(hash) {
  const [detail, setDetail] = useState(null)
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
export function DownloadDetail({ torrent, onClose }) {
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

  const doAction = (endpoint, body) => {
    setBusy(true)
    jpost(`/api/servarr/qbittorrent/${endpoint}`, { hashes: torrent.hash, ...body })
      .catch(() => {})
      .finally(() => setBusy(false))
  }
  const onPauseResume = () => doAction(paused ? 'resume' : 'pause', {})
  const onDelete = (deleteFiles) => {
    setConfirmDel(false)
    setBusy(true)
    jpost('/api/servarr/qbittorrent/delete', { hashes: torrent.hash, deleteFiles })
      .catch(() => {})
      .finally(() => { setBusy(false); onClose?.() })
  }

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 120, background: C.bg, color: C.text, fontFamily: SANS,
      overflowY: 'auto', animation: 'up .25s ease both' }}>
      {/* Blurred hero from the poster (a downloading title has no wide backdrop). */}
      <div style={{ position: 'relative', minHeight: mobile ? 'auto' : 'min(72vh, 600px)', display: 'flex', alignItems: 'flex-end' }}>
        <div style={{ position: 'absolute', inset: 0, overflow: 'hidden' }}>
          {posterUrl
            ? <img src={posterUrl} alt="" referrerPolicy="no-referrer"
                style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top center', filter: 'blur(26px) brightness(.6)', transform: 'scale(1.15)' }} />
            : <div style={{ width: '100%', height: '100%', background: C.surface }} />}
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(0deg, ${C.bg} 4%, rgba(11,13,16,.55) 48%, rgba(11,13,16,.3) 100%)` }} />
          <div style={{ position: 'absolute', inset: 0, background: `linear-gradient(90deg, rgba(11,13,16,.72) 0%, rgba(11,13,16,.35) 45%, transparent 82%)` }} />
        </div>

        {/* Back / close */}
        <button onClick={onClose} title="Back" style={{ position: 'absolute', top: mobile ? 12 : 18, left: mobile ? 12 : 18, zIndex: 3,
          width: 40, height: 40, borderRadius: 999, display: 'grid', placeItems: 'center', cursor: 'pointer', color: '#fff',
          ...glassStyle, background: C.glass }}>
          <Icon path={Ic.chevL} size={18} sw={2} />
        </button>

        <div style={{ position: 'relative', width: '100%', padding: mobile ? '110px 16px 22px' : '0 40px 40px',
          display: 'flex', gap: mobile ? 16 : 28, alignItems: 'flex-end' }}>
          {/* Poster with the ring overlay (the "progress" in lieu of a play button) */}
          <div style={{ width: mobile ? 128 : 200, flexShrink: 0, boxShadow: '0 20px 50px rgba(0,0,0,.6)', borderRadius: 16, overflow: 'hidden' }}>
            <DownloadPoster posterUrl={posterUrl} kind={kind} pct={pct} paused={paused} width={mobile ? 128 : 200} radius={16} />
          </div>

          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontFamily: MONO, fontSize: 11.5, fontWeight: 700,
              letterSpacing: '.06em', color: paused ? C.dim : C.green, marginBottom: 10 }}>
              <span style={{ width: 7, height: 7, borderRadius: '50%', background: paused ? C.dim : C.green,
                boxShadow: paused ? 'none' : `0 0 6px ${C.green}`, animation: paused ? 'none' : 'pulse 1.6s ease-in-out infinite' }} />
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
                    <Icon path={Ic.star} size={16} fill="#f5c518" stroke="none" />{rating.toFixed(1)}
                  </span>
                )}
                {genres.slice(0, 3).map((g) => <span key={g} style={{ color: C.dim }}>{g}</span>)}
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
              <DownloadRing pct={pct} size={mobile ? 88 : 104} stroke={8} color={paused ? C.dim : C.green} />
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
                  cursor: busy || done ? 'default' : 'pointer', opacity: busy || done ? 0.5 : 1, boxShadow: '0 10px 30px rgba(0,0,0,.4)' }}>
                <Icon path={paused ? Ic.play : Ic.pause} size={17} fill={paused ? 'currentColor' : 'none'} stroke={paused ? 'none' : 'currentColor'} sw={2} />
                {paused ? 'Resume' : 'Pause'}
              </button>
              <button onClick={() => setConfirmDel(true)} disabled={busy} title="Delete"
                style={{ display: 'inline-flex', alignItems: 'center', gap: 10, padding: '13px 24px', borderRadius: 999,
                  border: '1px solid rgba(220,60,60,.4)', background: 'rgba(220,60,60,.14)', color: C.red,
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
          <p style={{ fontSize: 15, lineHeight: 1.65, color: 'rgba(241,243,246,.85)', maxWidth: 760, margin: 0 }}>{overview}</p>
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
   "also delete files" toggle) so the two surfaces read identically. */
function DeleteConfirm({ name, mobile, onClose, onConfirm }) {
  const [deleteFiles, setDeleteFiles] = useState(false)
  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 130, display: 'grid', placeItems: 'center',
      padding: 16, background: 'rgba(6,8,11,.66)', backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)', animation: 'up .2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ width: 'min(440px, 100%)', borderRadius: 20, padding: mobile ? 20 : 26,
        ...glassStyle, background: 'rgba(22,25,30,.92)', boxShadow: '0 30px 80px rgba(0,0,0,.6)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
          <div style={{ width: 42, height: 42, borderRadius: 12, display: 'grid', placeItems: 'center', flexShrink: 0,
            background: 'rgba(220,60,60,.12)', border: '1px solid rgba(220,60,60,.3)' }}>
            <Icon path={Ic.trash} size={20} stroke={C.red} sw={1.8} />
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
          <span style={{ width: 42, height: 24, borderRadius: 999, background: deleteFiles ? C.green : 'rgba(255,255,255,.14)',
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
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, background: 'rgb(200,64,64)' }}>
            <Icon path={Ic.trash} size={16} sw={2} />Remove
          </button>
        </div>
      </div>
    </div>
  )
}
