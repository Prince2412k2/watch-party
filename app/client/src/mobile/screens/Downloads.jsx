import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { glass } from '../../glass.jsx'
import { T, SANS, MONO, R, EASE, TYPE } from '../theme.js'
import { TopBar } from '../ui/TopBar.jsx'
import { Icon, Ic } from '../ui/Icon.jsx'
import { Sheet } from '../ui/Sheet.jsx'
import { useTorrents } from '../../hooks/useTorrents.js'

/**
 * Mobile Downloads (MOBILE-SPEC §3.4). Two live sections over the shared engine:
 *   1. "Needs attention" — Radarr/Sonarr queue records stuck in warning/failed
 *      (a bad grab can die before it ever becomes a torrent, so it never reaches
 *      the section below). Reasons shown inline; destructive choices in a Sheet.
 *   2. "Active" — qBittorrent-backed downloads with poster, state-tinted progress,
 *      live ↓/↑ + ETA, and always-visible pause/resume/remove (no hover reveal).
 *
 * Reuses (verbatim): useTorrents (list, activeCount, pause/resume/remove, busy,
 *   loadError, isPausedState) + /api/servarr/downloads/enriched. The failing
 *   queue detail (reasons + blocklist) is polled locally the same way the desktop
 *   page does — the shared hook (useFailingCount) only exposes a badge count.
 * Endpoints: /api/servarr/health, /downloads/enriched, /{service}/queue[/:id].
 */

// Glyphs the mobile Icon dictionary doesn't carry — kept local (page-scoped) so
// the shared kit stays untouched. `Icon` just renders whatever `path` it's given.
const P = {
  alert: 'M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4m0 4h.01',
  ban: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM5 5l14 14',
}

const jget = (url, signal) => fetch(url, { credentials: 'include', signal })

/* ── Formatters ───────────────────────────────────────────────────────────── */
function fmtSize(bytes) {
  if (bytes == null || !Number.isFinite(bytes) || bytes <= 0) return '—'
  const u = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0, n = bytes
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
  return `${n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)} ${u[i]}`
}
const fmtSpeed = (bps) => (bps == null || !Number.isFinite(bps) || bps <= 0 ? '0 B/s' : `${fmtSize(bps)}/s`)
function fmtEta(secs) {
  if (secs == null || !Number.isFinite(secs) || secs < 0 || secs >= 8640000) return '∞'
  if (secs === 0) return '—'
  const d = Math.floor(secs / 86400), h = Math.floor((secs % 86400) / 3600)
  const m = Math.floor((secs % 3600) / 60), s = Math.floor(secs % 60)
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m`
  return `${s}s`
}

// Raw download-client state → { label, color, paused }. Matches the desktop
// mapping so a title reads the same on every surface.
function stateInfo(state) {
  switch (state) {
    case 'downloading': case 'forcedDL': case 'metaDL': case 'checkingDL': case 'allocating':
      return { label: 'Downloading', color: T.brand, textColor: T.text, paused: false }
    case 'uploading': case 'forcedUP': case 'checkingUP': case 'stalledUP':
      return { label: 'Finishing up', color: T.faint, textColor: T.dim, paused: false }
    case 'stalledDL':
      return { label: 'Waiting', color: T.faint, textColor: T.dim, paused: false }
    case 'queuedDL': case 'queuedUP': case 'checkingResumeData':
      return { label: 'Queued', color: T.faint, textColor: T.dim, paused: false }
    case 'pausedDL': case 'stoppedDL':
      return { label: 'Paused', color: T.faint, textColor: T.dim, paused: true }
    case 'pausedUP': case 'stoppedUP':
      return { label: 'Completed', color: T.text, textColor: T.text, paused: true }
    case 'error': case 'missingFiles':
      return { label: 'Error', color: T.red, textColor: T.red, paused: true }
    default:
      return { label: state || 'Unknown', color: T.faint, textColor: T.dim, paused: false }
  }
}

/* ── Local failing-queue poller (Radarr/Sonarr) ───────────────────────────────
   Visibility-aware ~6s poll of both *arr queues, one shared AbortController so an
   in-flight request is dropped on the next tick / unmount. A failed poll flags a
   subtle reconnect and keeps the last good list; remove() is optimistic then
   re-polls. Kept in-file (the shared useFailingDownloads hook only exposes the
   badge count) so this screen change stays confined to its own file. */
function useFailingQueue(enabled) {
  const [items, setItems] = useState(null)   // null = never loaded
  const [loadError, setLoadError] = useState(false)
  const [busy, setBusy] = useState(() => new Set())
  const abortRef = useRef(null)

  const poll = useCallback(() => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    return Promise.all([
      jget('/api/servarr/radarr/queue', ctrl.signal).then((r) => (r.ok ? r.json() : Promise.reject(r))).catch(() => null),
      jget('/api/servarr/sonarr/queue', ctrl.signal).then((r) => (r.ok ? r.json() : Promise.reject(r))).catch(() => null),
    ]).then(([a, b]) => {
      if (ctrl.signal.aborted) return
      if (a == null && b == null) { setLoadError(true); return }
      const merged = [...(Array.isArray(a) ? a : []), ...(Array.isArray(b) ? b : [])]
      setItems(merged.filter((q) => q.failing))
      setLoadError(false)
    })
  }, [])

  useEffect(() => {
    if (!enabled) { setItems(null); return }
    let timer = null
    const start = () => { if (timer == null) { poll(); timer = setInterval(poll, 6000) } }
    const stop = () => { if (timer != null) { clearInterval(timer); timer = null } abortRef.current?.abort() }
    const onVis = () => (document.hidden ? stop() : start())
    if (!document.hidden) start()
    document.addEventListener('visibilitychange', onVis)
    return () => { document.removeEventListener('visibilitychange', onVis); stop() }
  }, [enabled, poll])

  const remove = (item, blocklist) => {
    setBusy((prev) => new Set(prev).add(item.id))
    setItems((cur) => cur && cur.filter((q) => q.id !== item.id))
    fetch(`/api/servarr/${item.service}/queue/${item.id}`, {
      method: 'DELETE', credentials: 'include',
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ blocklist: !!blocklist }),
    }).catch(() => {}).finally(() => {
      setBusy((prev) => { const n = new Set(prev); n.delete(item.id); return n })
      poll()
    })
  }

  return { items, loadError, busy, remove }
}

/* ── Screen ───────────────────────────────────────────────────────────────── */
export default function Downloads() {
  const [health, setHealth] = useState(null)
  const [healthLoading, setHealthLoading] = useState(true)

  useEffect(() => {
    let alive = true
    jget('/api/servarr/health')
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then((h) => { if (alive) setHealth(h) })
      .catch(() => { if (alive) setHealth({ services: {} }) })
      .finally(() => { if (alive) setHealthLoading(false) })
    return () => { alive = false }
  }, [])

  const svc = health?.services
  const qbitReady = !!svc?.qbittorrent?.configured && !!svc?.qbittorrent?.reachable
  const arrReady = (!!svc?.radarr?.configured && !!svc?.radarr?.reachable)
    || (!!svc?.sonarr?.configured && !!svc?.sonarr?.reachable)

  const dl = useTorrents(qbitReady)
  const failing = useFailingQueue(arrReady)

  const [confirmDel, setConfirmDel] = useState(null)   // torrent pending delete
  const [resolveItem, setResolveItem] = useState(null) // failing item pending action

  const failCount = (failing.items || []).length

  return (
    <>
      <TopBar title="Downloads" subtitle="What's coming down the pipe" />

      <div style={{
        paddingTop: 14, paddingBottom: 10,
        paddingLeft: 'calc(var(--sa-l) + 16px)', paddingRight: 'calc(var(--sa-r) + 16px)',
        display: 'flex', flexDirection: 'column', gap: 26,
      }}>
        {failCount > 0 || failing.loadError ? (
          <NeedsAttention arrReady={arrReady} failing={failing} onResolve={setResolveItem} />
        ) : null}

        <ActiveSection
          healthLoading={healthLoading}
          qbitReady={qbitReady}
          configured={!!svc?.qbittorrent?.configured}
          dl={dl}
          onDelete={setConfirmDel}
        />
      </div>

      <Sheet open={!!confirmDel} onClose={() => setConfirmDel(null)} title="Remove download?">
        {confirmDel && (
          <DeleteSheet
            t={confirmDel}
            onCancel={() => setConfirmDel(null)}
            onConfirm={(deleteFiles) => { dl.remove(confirmDel.hash, deleteFiles); setConfirmDel(null) }}
          />
        )}
      </Sheet>

      <Sheet open={!!resolveItem} onClose={() => setResolveItem(null)} title="Resolve stuck download">
        {resolveItem && (
          <ResolveSheet
            q={resolveItem}
            onCancel={() => setResolveItem(null)}
            onRemove={(blocklist) => { failing.remove(resolveItem, blocklist); setResolveItem(null) }}
          />
        )}
      </Sheet>
    </>
  )
}

/* ── Section header: colored status dot + eyebrow + count ──────────────────── */
function SectionHeader({ label, count, tone, live }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 12 }}>
      <span style={{
        width: 8, height: 8, borderRadius: '50%', background: tone, flexShrink: 0,
        animation: live ? 'pulse 1.8s ease-in-out infinite' : 'none',
      }} />
      <span style={{ ...TYPE.meta, color: T.dim }}>{label}</span>
      {count != null && (
        <span style={{ fontFamily: MONO, fontSize: 12, fontWeight: 700, color: tone }}>{count}</span>
      )}
    </div>
  )
}

/* ── "Needs attention" — stuck *arr grabs ─────────────────────────────────── */
function NeedsAttention({ arrReady, failing, onResolve }) {
  if (!arrReady) return null
  const items = failing.items || []
  return (
    <section style={{ animation: 'up .4s ease both' }}>
      <SectionHeader label="Needs attention" count={items.length || null} tone={T.red} />
      {failing.loadError && items.length === 0 ? (
        <div style={{ ...reconnectStyle }}>
          <Spinner size={13} /> Reconnecting to your download managers…
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {items.map((q) => (
            <FailingRow key={`${q.service}:${q.id}`} q={q} busy={failing.busy.has(q.id)} onResolve={() => onResolve(q)} />
          ))}
        </div>
      )}
    </section>
  )
}

function FailingRow({ q, busy, onResolve }) {
  const reasons = q.statusMessages.length ? q.statusMessages : (q.errorMessage ? [q.errorMessage] : ['No reason given.'])
  return (
    <div style={{
      background: T.surface, borderRadius: R.md, padding: 14,
      border: '1px solid rgba(255,107,107,.30)',
      opacity: busy ? 0.55 : 1, transition: `opacity .2s ${EASE}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <span style={{
          width: 34, height: 34, borderRadius: 10, flexShrink: 0, display: 'grid', placeItems: 'center',
          background: 'rgba(255,107,107,.12)', border: '1px solid rgba(255,107,107,.3)',
        }}>
          <Icon path={P.alert} size={17} stroke={T.red} sw={1.9} />
        </span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ ...TYPE.headline, color: T.text, wordBreak: 'break-word' }}>{q.title}</div>
          <div style={{ marginTop: 5, display: 'flex', flexDirection: 'column', gap: 3 }}>
            {reasons.map((r, i) => (
              <span key={i} style={{ ...TYPE.body, fontSize: 13, color: T.red }}>{r}</span>
            ))}
          </div>
          <div style={{ marginTop: 7, fontFamily: MONO, fontSize: 11, color: T.faint, letterSpacing: '.03em' }}>
            {[q.indexer, fmtSize(q.size)].filter(Boolean).join('  ·  ') || '—'}
          </div>
        </div>
      </div>
      <button
        onClick={onResolve} disabled={busy} aria-label={`Resolve ${q.title}`} className="mob-press"
        style={{
          marginTop: 12, width: '100%', minHeight: 44, borderRadius: R.sm,
          border: '1px solid rgba(255,107,107,.3)', background: 'rgba(255,107,107,.10)',
          color: T.red, fontFamily: SANS, fontSize: 14.5, fontWeight: 700,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          cursor: busy ? 'default' : 'pointer',
        }}
      >
        <Icon path={Ic.trash} size={16} sw={1.9} /> Resolve
      </button>
    </div>
  )
}

/* ── Active downloads ─────────────────────────────────────────────────────── */
function ActiveSection({ healthLoading, qbitReady, configured, dl, onDelete }) {
  const list = dl.list
  const agg = useMemo(() => {
    let down = 0, up = 0, active = 0
    for (const t of list) {
      down += t.dlspeed || 0
      up += t.upspeed || 0
      if (!stateInfo(t.state).paused) active++
    }
    return { down, up, active }
  }, [list])

  // Rolling trace of total download throughput — one sample per successful poll.
  const [spark, setSpark] = useState([])
  useEffect(() => {
    if (dl.torrents == null) { setSpark([]); return }
    setSpark((prev) => [...prev, agg.down].slice(-40))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dl.torrents])

  const loading = healthLoading || (qbitReady && dl.torrents === null)

  return (
    <section style={{ animation: 'up .4s ease both' }}>
      <SectionHeader label="Active" count={list.length || null} tone={T.brand} live={agg.active > 0} />

      {loading ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {[0, 1, 2].map((i) => <RowSkeleton key={i} />)}
        </div>
      ) : !qbitReady ? (
        <EmptyState
          icon={Ic.download}
          title={configured ? 'Downloads are offline right now' : 'Downloads aren’t set up yet'}
          body={configured
            ? 'We can’t reach your download manager. Live progress and controls come back on their own.'
            : 'Once a download manager is connected, anything you grab shows live progress and controls here.'}
        />
      ) : list.length === 0 ? (
        <EmptyState
          icon={Ic.download}
          title="Nothing downloading"
          body="Find something in Browse and it’ll land here with live progress, speed, and controls."
        />
      ) : (
        <>
          <SummaryCard agg={agg} spark={spark} reconnecting={dl.loadError} />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 12 }}>
            {list.map((t) => (
              <TorrentRow
                key={t.hash} t={t} busy={dl.busy.has(t.hash)}
                onPause={() => dl.pause(t)} onResume={() => dl.resume(t)} onDelete={() => onDelete(t)}
              />
            ))}
          </div>
        </>
      )}
    </section>
  )
}

// Live throughput header — the glance-first summary. Aggregate ↓/↑ + a subtle
// SVG sparkline of download speed over the last ~40 polls.
function SummaryCard({ agg, spark, reconnecting }) {
  return (
    <div style={{
      ...glass('medium', { refract: true }), borderRadius: R.lg,
      padding: 16, display: 'flex', alignItems: 'center', gap: 14,
    }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <span style={{ fontFamily: MONO, fontSize: 26, fontWeight: 700, color: T.text, lineHeight: 1 }}>
            {agg.active}
          </span>
          <span style={{ ...TYPE.meta, color: T.dim }}>downloading</span>
        </div>
        <div style={{ display: 'flex', gap: 16, marginTop: 10, fontFamily: MONO, fontSize: 12.5, fontWeight: 700 }}>
          <span style={{ color: T.text }}>↓ {fmtSpeed(agg.down)}</span>
          <span style={{ color: T.faint }}>↑ {fmtSpeed(agg.up)}</span>
        </div>
        {reconnecting && (
          <div style={{ marginTop: 8, display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: MONO, fontSize: 11, color: T.dim }}>
            <Spinner size={11} /> reconnecting…
          </div>
        )}
      </div>
      <Sparkline data={spark} color={T.text} />
    </div>
  )
}

function Sparkline({ data, w = 108, h = 40, color }) {
  if (!data || data.length < 2) return null
  const max = Math.max(...data, 1)
  const n = data.length
  const pts = data.map((v, i) => [(i / (n - 1)) * w, h - (v / max) * (h - 5) - 3])
  const line = pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`).join(' ')
  const [lx, ly] = pts[pts.length - 1]
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{ flexShrink: 0, overflow: 'visible' }} aria-hidden="true">
      <defs>
        <linearGradient id="dlSpark" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={color} stopOpacity="0.26" />
          <stop offset="1" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={`${line} L${w} ${h} L0 ${h} Z`} fill="url(#dlSpark)" />
      <path d={line} fill="none" stroke={color} strokeWidth="1.7" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={lx} cy={ly} r="2.6" fill={color} />
    </svg>
  )
}

// Poster for an active download. The source is an *arr-provided URL (public
// TMDb/TVDB art or the /api/servarr/image proxy), NOT Jellyfin art — so it uses
// a plain <img> with its own fallback rather than the library <Poster>.
function DlPoster({ src, kind }) {
  const [ok, setOk] = useState(true)
  return (
    <div style={{
      width: 44, aspectRatio: '2 / 3', borderRadius: 9, overflow: 'hidden', flexShrink: 0,
      background: T.surface2,
      border: `1px solid ${T.line}`, display: 'grid', placeItems: 'center', position: 'relative',
    }}>
      {src && ok
        ? <img src={src} alt="" loading="lazy" onError={() => setOk(false)}
            style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
        : <Icon path={kind === 'movie' ? Ic.film : Ic.tv} size={16} stroke={T.faint} sw={1.6} />}
    </div>
  )
}

function TorrentRow({ t, busy, onPause, onResume, onDelete }) {
  const info = stateInfo(t.state)
  const pct = Math.max(0, Math.min(100, Math.round((t.progress || 0) * 100)))
  const done = pct >= 100
  const active = !info.paused && !done
  const title = t.displayTitle || t.name
  const barFill = info.paused ? T.faint
    : info.label === 'Error' ? T.red
    : T.text

  return (
    <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: R.md, padding: 14 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <DlPoster src={t.posterUrl} kind={t.kind} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            ...TYPE.headline, color: T.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }} title={t.name}>{title}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 3, minWidth: 0 }}>
            <span style={{
              width: 6, height: 6, borderRadius: '50%', background: info.color, flexShrink: 0,
              animation: active && info.label === 'Downloading' ? 'pulse 1.6s ease-in-out infinite' : 'none',
            }} />
            <span style={{ fontFamily: SANS, fontSize: 12.5, fontWeight: 700, color: info.textColor, flexShrink: 0 }}>{info.label}</span>
            {t.subtitle && (
              <span style={{
                fontFamily: MONO, fontSize: 11, color: T.faint, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              }}>· {t.subtitle}</span>
            )}
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8, flexShrink: 0 }}>
          <RowBtn
            label={info.paused ? 'Resume' : 'Pause'} disabled={busy}
            icon={info.paused ? Ic.play : Ic.pause} fill={info.paused}
            onClick={info.paused ? onResume : onPause}
          />
          <RowBtn label="Remove" disabled={busy} icon={Ic.trash} danger onClick={onDelete} />
        </div>
      </div>

      <div
        role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}
        style={{ height: 7, borderRadius: 999, background: 'rgba(255,255,255,.07)', overflow: 'hidden', marginTop: 12 }}
      >
        <div style={{
          width: `${pct}%`, height: '100%', borderRadius: 999, background: barFill,
          transition: `width .45s ${EASE}`,
        }} />
      </div>

      <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '4px 14px', marginTop: 10, fontFamily: MONO, fontSize: 12 }}>
        <span style={{ color: T.text, fontWeight: 700 }}>{pct}%</span>
        <span style={{ color: T.dim }}>↓ {fmtSpeed(t.dlspeed)}</span>
        <span style={{ color: T.dim }}>ETA {done ? '—' : fmtEta(t.eta)}</span>
        <span style={{ marginLeft: 'auto', color: T.faint }}>
          {t.numSeeds ?? 0}S · {t.numLeechs ?? 0}P · {fmtSize(t.size)}
        </span>
      </div>
    </div>
  )
}

// 44×44 always-visible row action (touch has no hover — feedback via :active).
function RowBtn({ label, icon, onClick, disabled, danger, fill }) {
  return (
    <button
      onClick={onClick} disabled={disabled} aria-label={label} title={label} className="mob-press"
      style={{
        width: 44, height: 44, borderRadius: 12, display: 'grid', placeItems: 'center', flexShrink: 0,
        border: `1px solid ${danger ? 'rgba(255,107,107,.28)' : T.line}`,
        background: danger ? 'rgba(255,107,107,.10)' : T.surface2,
        color: danger ? T.red : T.text,
        cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.4 : 1,
      }}
    >
      <Icon path={icon} size={18} sw={1.9} fill={fill && !danger ? 'currentColor' : 'none'} stroke={fill && !danger ? 'none' : 'currentColor'} />
    </button>
  )
}

/* ── Sheets ───────────────────────────────────────────────────────────────── */
function DeleteSheet({ t, onCancel, onConfirm }) {
  const [deleteFiles, setDeleteFiles] = useState(false)
  return (
    <div style={{ padding: '4px 4px 8px', display: 'flex', flexDirection: 'column', gap: 16 }}>
      <p style={{ ...TYPE.body, color: T.dim, margin: 0 }}>
        <span style={{ color: T.text, fontWeight: 700 }}>{t.displayTitle || t.name}</span> will stop downloading and leave the queue.
      </p>
      <SwitchRow
        label="Also delete downloaded files"
        hint="Erase the data on disk, not just the queue entry"
        on={deleteFiles} onToggle={() => setDeleteFiles((v) => !v)}
      />
      <div style={{ display: 'flex', gap: 10 }}>
        <SheetBtn onClick={onCancel}>Keep</SheetBtn>
        <SheetBtn danger onClick={() => onConfirm(deleteFiles)}>
          <Icon path={Ic.trash} size={17} sw={1.9} /> Remove
        </SheetBtn>
      </div>
    </div>
  )
}

function ResolveSheet({ q, onCancel, onRemove }) {
  const reasons = q.statusMessages.length ? q.statusMessages : (q.errorMessage ? [q.errorMessage] : ['No reason given.'])
  return (
    <div style={{ padding: '4px 4px 8px', display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div>
        <div style={{ ...TYPE.headline, color: T.text, wordBreak: 'break-word' }}>{q.title}</div>
        <div style={{ marginTop: 6, display: 'flex', flexDirection: 'column', gap: 3 }}>
          {reasons.map((r, i) => <span key={i} style={{ ...TYPE.body, fontSize: 13, color: T.red }}>{r}</span>)}
        </div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <SheetBtn danger block onClick={() => onRemove(false)}>
          <Icon path={Ic.trash} size={17} sw={1.9} /> Remove from queue
        </SheetBtn>
        <SheetBtn danger block onClick={() => onRemove(true)}>
          <Icon path={P.ban} size={17} sw={1.9} /> Remove &amp; block this release
        </SheetBtn>
        <SheetBtn block onClick={onCancel}>Cancel</SheetBtn>
      </div>
      <p style={{ ...TYPE.body, fontSize: 12.5, color: T.faint, margin: 0 }}>
        Blocking stops this exact release from being grabbed again, so your download manager can look for a better one.
      </p>
    </div>
  )
}

function SwitchRow({ label, hint, on, onToggle }) {
  return (
    <button
      onClick={onToggle} role="switch" aria-checked={on} aria-label={label} className="mob-press"
      style={{
        width: '100%', minHeight: 56, display: 'flex', alignItems: 'center', gap: 12, textAlign: 'left',
        padding: '12px 14px', borderRadius: R.sm, border: `1px solid ${T.line}`,
        background: 'rgba(255,255,255,.03)', cursor: 'pointer',
      }}
    >
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', ...TYPE.body, fontWeight: 700, color: T.text }}>{label}</span>
        {hint && <span style={{ display: 'block', fontSize: 12.5, color: T.faint, marginTop: 2 }}>{hint}</span>}
      </span>
      <span style={{
        width: 46, height: 28, borderRadius: 999, flexShrink: 0, position: 'relative',
        background: on ? 'rgba(255,255,255,.34)' : 'rgba(255,255,255,.16)', transition: `background .18s ${EASE}`,
      }}>
        <span style={{
          position: 'absolute', top: 3, left: on ? 21 : 3, width: 22, height: 22, borderRadius: '50%',
          background: '#fff', transition: `left .18s ${EASE}`,
        }} />
      </span>
    </button>
  )
}

function SheetBtn({ children, onClick, danger, block }) {
  return (
    <button
      onClick={onClick} className="mob-press"
      style={{
        flex: block ? undefined : 1, width: block ? '100%' : undefined,
        minHeight: 50, borderRadius: R.md,
        border: danger ? '1px solid rgba(255,107,107,.35)' : `1px solid ${T.line2}`,
        background: danger ? 'rgba(255,107,107,.12)' : 'rgba(255,255,255,.05)',
        color: danger ? T.red : T.text,
        fontFamily: SANS, fontSize: 15.5, fontWeight: 700, cursor: 'pointer',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      }}
    >
      {children}
    </button>
  )
}

/* ── Shared bits ──────────────────────────────────────────────────────────── */
function EmptyState({ icon, title, body }) {
  return (
    <div style={{
      ...glass('light'), borderRadius: R.lg, padding: '38px 24px', textAlign: 'center',
      display: 'flex', flexDirection: 'column', alignItems: 'center',
    }}>
      <span style={{
        width: 58, height: 58, borderRadius: 18, display: 'grid', placeItems: 'center', marginBottom: 16,
        background: T.surface, border: `1px solid ${T.line}`, color: T.dim,
      }}>
        <Icon path={icon} size={27} sw={1.7} />
      </span>
      <h2 style={{ ...TYPE.title, color: T.text, margin: 0, textWrap: 'balance' }}>{title}</h2>
      {body && <p style={{ ...TYPE.body, color: T.dim, maxWidth: 320, marginTop: 8 }}>{body}</p>}
    </div>
  )
}

function RowSkeleton() {
  return (
    <div style={{ background: T.surface, border: `1px solid ${T.line}`, borderRadius: R.md, padding: 14 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <Shim w={44} h={66} radius={9} />
        <div style={{ flex: 1 }}>
          <Shim w="62%" h={15} />
          <Shim w="38%" h={11} style={{ marginTop: 8 }} />
        </div>
      </div>
      <Shim w="100%" h={7} radius={999} style={{ marginTop: 14 }} />
    </div>
  )
}

function Shim({ w, h, radius = R.sm, style }) {
  return (
    <span aria-hidden="true" style={{
      display: 'block', width: w, height: h, borderRadius: radius,
      backgroundImage: `linear-gradient(90deg, ${T.surface} 25%, ${T.surface2} 50%, ${T.surface} 75%)`,
      backgroundSize: '200% 100%', animation: 'shim 1.3s ease-in-out infinite', ...style,
    }} />
  )
}

function Spinner({ size = 16 }) {
  return (
    <span style={{
      display: 'inline-block', width: size, height: size, borderRadius: '50%',
      border: '2px solid rgba(255,255,255,.2)', borderTopColor: T.text, animation: 'spin .7s linear infinite',
    }} />
  )
}

const reconnectStyle = {
  display: 'inline-flex', alignItems: 'center', gap: 8,
  padding: '14px 16px', borderRadius: R.md, border: `1px solid ${T.line}`, background: T.surface,
  fontFamily: MONO, fontSize: 12.5, color: T.dim,
}
