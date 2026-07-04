import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useAuth } from '../context/AuthContext.jsx'
import { useIsMobile } from '../hooks/useIsMobile.js'
import { useTorrents } from '../hooks/useTorrents.js'
import { useLibraryViews } from '../hooks/useLibraryViews.js'
import { DownloadPoster, DownloadDetail } from '../components/DownloadDetail.jsx'
import { C, SANS, MONO, glassStyle, Ic, Icon, Sidebar, TopBar, Notice, Spinner } from '../lib/ui.jsx'
import { fmtSize, fmtSpeed, stateInfo } from '../lib/format.js'
import { jget } from '../lib/api.js'

/* ── Failing queue items (Radarr/Sonarr) poller ──────────────────────────────
   Visibility-aware ~6s polling of both *arr queues for items stuck in a
   warning/failed state, with a single shared AbortController so an in-flight
   poll is cancelled on the next tick / unmount and never lands stale state. A
   failed poll flags a subtle reconnect and keeps the last good list; remove()
   is optimistic and re-polls to confirm. */
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

export default function Downloads() {
  const { user, logout } = useAuth()
  const mobile = useIsMobile()
  const sidebarW = mobile ? 62 : 236

  const [health, setHealth] = useState(null)
  const [healthLoading, setHealthLoading] = useState(true)

  useEffect(() => {
    setHealthLoading(true)
    jget('/api/servarr/health')
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then(setHealth)
      .catch(() => setHealth({ services: {} }))
      .finally(() => setHealthLoading(false))
  }, [])

  const qbitReady = !!health?.services?.qbittorrent?.configured && !!health?.services?.qbittorrent?.reachable
  const arrReady = (!!health?.services?.radarr?.configured && !!health?.services?.radarr?.reachable)
    || (!!health?.services?.sonarr?.configured && !!health?.services?.sonarr?.reachable)

  const dl = useTorrents(qbitReady)
  const failing = useFailingQueue(arrReady)
  const views = useLibraryViews()

  const initials = user?.name?.split(' ').map((w) => w[0]).join('').toUpperCase().slice(0, 2) || '?'

  return (
    <div style={{ position: 'fixed', inset: 0, background: C.bg, color: C.text, fontFamily: SANS, overflow: 'hidden' }}>
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', background:
        `radial-gradient(120% 90% at 12% -10%, rgba(62,207,126,.06), transparent 55%),
         radial-gradient(120% 90% at 100% 0%, rgba(120,140,220,.07), transparent 55%),
         ${C.bg}` }} />

      <Sidebar mobile={mobile} width={sidebarW} views={views} downloadCount={dl.activeCount} failingCount={(failing.items || []).length} current="downloads" />

      <div style={{
        position: 'absolute', top: mobile ? 8 : 12, right: mobile ? 8 : 12, bottom: mobile ? 8 : 12,
        left: sidebarW + (mobile ? 8 : 12), borderRadius: mobile ? 14 : 20, overflow: 'hidden auto',
      }}>
        <TopBar mobile={mobile} initials={initials} logout={logout} title="Downloads" />

        <div style={{ padding: mobile ? '4px 16px 100px' : '8px 34px 100px', maxWidth: 1100, margin: '0 auto' }}>
          <div style={{ marginBottom: 22, animation: 'up .4s ease both' }}>
            <h1 style={{ fontSize: mobile ? 26 : 32, fontWeight: 800, letterSpacing: '-.02em', margin: 0 }}>Downloads</h1>
            <p style={{ color: C.dim, fontSize: 15, marginTop: 6, maxWidth: 620 }}>
              Everything currently downloading, plus anything that got stuck along the way and needs your attention.
            </p>
          </div>

          <NeedsAttention healthLoading={healthLoading} arrReady={arrReady} failing={failing} />
          <ActiveDownloads mobile={mobile} healthLoading={healthLoading} qbitReady={qbitReady} qbit={health?.services?.qbittorrent} dl={dl} />
        </div>
      </div>
    </div>
  )
}

/* ── "Needs attention" — Radarr/Sonarr queue items stuck in warning/failed.
   This is the actual gap: a bad release can die before it ever becomes a
   torrent, so it never shows up in the section below. Branding purity takes a
   back seat here — the real failure reason is what makes this actionable. ── */
function NeedsAttention({ healthLoading, arrReady, failing }) {
  if (healthLoading || (arrReady && failing.items === null)) {
    return (
      <section style={{ marginBottom: 36 }}>
        <div style={{ padding: '30px 0', display: 'grid', placeItems: 'center' }}><Spinner size={22} /></div>
      </section>
    )
  }
  if (!arrReady) return null
  const items = failing.items || []
  if (items.length === 0 && !failing.loadError) return null

  return (
    <section style={{ marginBottom: 36, animation: 'up .4s ease both' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 14, flexWrap: 'wrap' }}>
        <h2 style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-.02em', margin: 0, color: items.length ? C.red : C.text }}>
          Needs attention
        </h2>
        {items.length > 0 && (
          <span style={{ fontFamily: MONO, fontSize: 12.5, color: C.dim }}>{items.length} stuck</span>
        )}
        {failing.loadError && (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: MONO, fontSize: 12, color: C.amber }}>
            <Spinner size={12} />reconnecting…
          </span>
        )}
      </div>
      {items.length === 0 ? (
        <Notice icon={Ic.check} tone="ok" title="Nothing stuck right now" body="Failed grabs and rejected downloads will show up here with the reason why." />
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {items.map((q) => (
            <FailingRow key={`${q.service}:${q.id}`} q={q} busy={failing.busy.has(q.id)}
              onRemove={(blocklist) => failing.remove(q, blocklist)} />
          ))}
        </div>
      )}
    </section>
  )
}

function FailingRow({ q, busy, onRemove }) {
  const [confirm, setConfirm] = useState(false)
  const reasons = q.statusMessages.length > 0 ? q.statusMessages : (q.errorMessage ? [q.errorMessage] : ['No reason given.'])
  return (
    <div style={{ padding: '15px 18px', borderRadius: 14, ...glassStyle, border: '1px solid rgba(220,60,60,.28)' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12, flexWrap: 'wrap' }}>
        <div style={{ width: 34, height: 34, borderRadius: 10, flexShrink: 0, display: 'grid', placeItems: 'center',
          background: 'rgba(220,60,60,.14)', border: '1px solid rgba(220,60,60,.3)' }}>
          <Icon path={Ic.alert} size={17} stroke={C.red} sw={2} />
        </div>
        <div style={{ flex: 1, minWidth: 180 }}>
          <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>{q.title}</div>
          <div style={{ marginTop: 4, display: 'flex', flexDirection: 'column', gap: 2 }}>
            {reasons.map((r, i) => (
              <span key={i} style={{ fontSize: 12.5, color: C.red }}>{r}</span>
            ))}
          </div>
          <div style={{ marginTop: 6, fontFamily: MONO, fontSize: 11.5, color: C.faint }}>
            {[q.indexer, fmtSize(q.size)].filter(Boolean).join(' · ')}
          </div>
        </div>
        <div style={{ display: 'inline-flex', gap: 6, flexShrink: 0 }}>
          <RowBtn title="Remove" disabled={busy} onClick={() => setConfirm(true)} icon={Ic.trash} />
        </div>
      </div>

      {confirm && (
        <div style={{ marginTop: 12, paddingTop: 12, borderTop: `1px solid ${C.line}`,
          display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
          <span style={{ fontSize: 12.5, color: C.dim, marginRight: 'auto' }}>Remove this download?</span>
          <button onClick={() => setConfirm(false)} style={pillBtnStyle(false)}>Cancel</button>
          <button onClick={() => { onRemove(false); setConfirm(false) }} style={pillBtnStyle(true)}>
            <Icon path={Ic.trash} size={13} sw={2.2} />Remove
          </button>
          <button onClick={() => { onRemove(true); setConfirm(false) }} style={pillBtnStyle(true)} title="Remove and prevent this release from being grabbed again">
            <Icon path={Ic.ban} size={13} sw={2.2} />Remove &amp; block
          </button>
        </div>
      )}
    </div>
  )
}

function pillBtnStyle(danger) {
  return {
    display: 'inline-flex', alignItems: 'center', gap: 6, height: 32, padding: '0 12px', borderRadius: 999,
    border: danger ? '1px solid rgba(220,60,60,.4)' : `1px solid ${C.line2}`, cursor: 'pointer',
    fontFamily: SANS, fontSize: 12.5, fontWeight: 700,
    background: danger ? 'rgba(220,60,60,.14)' : 'rgba(255,255,255,.04)', color: danger ? C.red : C.text,
  }
}

/* ── Active qBittorrent-backed downloads ─────────────────────────────────── */
function ActiveDownloads({ mobile, healthLoading, qbitReady, qbit, dl }) {
  const [confirmDel, setConfirmDel] = useState(null)
  const [detail, setDetail] = useState(null)   // download-detail overlay target
  const list = dl.list
  const agg = useMemo(() => {
    let d = 0, u = 0
    for (const t of list) {
      d += t.dlspeed || 0
      u += t.upspeed || 0
    }
    return { dl: d, up: u, total: list.length }
  }, [list])

  return (
    <section style={{ animation: 'up .4s ease both' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 14, flexWrap: 'wrap' }}>
        <h2 style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-.02em', margin: 0 }}>Active</h2>
        {qbitReady && list.length > 0 && (
          <span style={{ fontFamily: MONO, fontSize: 12.5, color: C.dim }}>
            {dl.activeCount} active · <span style={{ color: C.green }}>↓ {fmtSpeed(agg.dl)}</span>
            <span style={{ color: C.faint }}> · ↑ {fmtSpeed(agg.up)}</span>
          </span>
        )}
        {qbitReady && dl.loadError && (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: MONO, fontSize: 12, color: C.amber }}>
            <Spinner size={12} />reconnecting…
          </span>
        )}
      </div>

      {(healthLoading || (qbitReady && dl.torrents === null)) ? (
        <div style={{ padding: '40px 0', display: 'grid', placeItems: 'center' }}><Spinner size={24} /></div>
      ) : !qbitReady ? (
        <DownloadsUnavailable configured={!!qbit?.configured} />
      ) : list.length === 0 ? (
        <Notice icon={Ic.download} title="No active downloads" body="Titles you download show up here with live progress and controls." />
      ) : (
        <div style={{ display: 'grid', gap: mobile ? 12 : 18,
          gridTemplateColumns: `repeat(auto-fill, minmax(${mobile ? 138 : 160}px, 1fr))` }}>
          {list.map((t) => (
            <TorrentCard key={t.hash} t={t} busy={dl.busy.has(t.hash)}
              onOpen={() => setDetail(t)}
              onPause={() => dl.pause(t)} onResume={() => dl.resume(t)} onDelete={() => setConfirmDel(t)} />
          ))}
        </div>
      )}

      {confirmDel && (
        <DeleteDialog t={confirmDel}
          onClose={() => setConfirmDel(null)}
          onConfirm={(deleteFiles) => { dl.remove(confirmDel.hash, deleteFiles); setConfirmDel(null) }} />
      )}

      {/* Download detail — same overlay as the Library "Downloading now" rail. The
          torrent is re-read from the live poll so the ring + stats stay current. */}
      {detail && (
        <DownloadDetail
          torrent={list.find((t) => t.hash === detail.hash) || detail}
          onClose={() => setDetail(null)} />
      )}
    </section>
  )
}

/* ── Active download card — 2:3 poster with the circular progress ring, title +
   state/subtitle below, and inline pause/resume + delete controls. Clicking the
   poster opens the full download detail. Matches the Library "Downloading now"
   poster+ring treatment for consistency. ─────────────────────────────────────── */
function TorrentCard({ t, busy, onOpen, onPause, onResume, onDelete }) {
  const [h, setH] = useState(false)
  const info = stateInfo(t.state)
  const pct = Math.max(0, Math.min(100, Math.round((t.progress || 0) * 100)))
  const done = pct >= 100
  const title = t.displayTitle || t.name
  const subtitle = t.subtitle || `↓ ${fmtSpeed(t.dlspeed)}`
  return (
    <div onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} style={{ display: 'flex', flexDirection: 'column' }}>
      <button onClick={onOpen} aria-label={title} title={t.name}
        style={{ border: 'none', background: 'none', padding: 0, cursor: 'pointer', textAlign: 'left', borderRadius: 14, overflow: 'hidden',
          boxShadow: h ? '0 18px 40px rgba(0,0,0,.55)' : '0 8px 22px rgba(0,0,0,.4)',
          transform: h ? 'translateY(-3px)' : 'none', transition: 'transform .25s, box-shadow .25s' }}>
        <DownloadPoster posterUrl={t.posterUrl} kind={t.kind} pct={pct} paused={info.paused} width="100%" radius={14} ringSize={78} />
      </button>
      <div style={{ marginTop: 9, display: 'flex', alignItems: 'flex-start', gap: 8 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: C.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={t.name}>{title}</div>
          <div style={{ fontFamily: MONO, fontSize: 11.5, color: info.color, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {info.label}{subtitle ? ` · ${subtitle}` : ''}
          </div>
        </div>
        <div style={{ display: 'inline-flex', gap: 6, flexShrink: 0 }}>
          <RowBtn title={info.paused ? 'Resume' : 'Pause'} disabled={busy || done}
            onClick={info.paused ? onResume : onPause} icon={info.paused ? Ic.play : Ic.pause} />
          <RowBtn title="Remove" disabled={busy} danger onClick={onDelete} icon={Ic.trash} />
        </div>
      </div>
    </div>
  )
}

function RowBtn({ title, icon, onClick, disabled, danger }) {
  const [h, setH] = useState(false)
  return (
    <button onClick={onClick} title={title} disabled={disabled}
      onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 34, height: 34, borderRadius: 10, display: 'grid', placeItems: 'center', flexShrink: 0,
        border: `1px solid ${C.line}`, cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.4 : 1,
        color: danger ? (h ? C.red : C.dim) : (h ? C.text : C.dim),
        background: h ? (danger ? 'rgba(220,60,60,.12)' : 'rgba(255,255,255,.07)') : 'rgba(255,255,255,.03)',
        transition: 'background .15s, color .15s' }}>
      <Icon path={icon} size={16} sw={1.9} />
    </button>
  )
}

function Toggle({ label, hint, on, set }) {
  return (
    <button onClick={() => set(!on)} style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 12,
      padding: '11px 14px', marginBottom: 10, borderRadius: 12, border: `1px solid ${C.line}`, cursor: 'pointer',
      background: 'rgba(255,255,255,.03)', textAlign: 'left' }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>{label}</div>
        {hint && <div style={{ fontSize: 12, color: C.faint, marginTop: 2 }}>{hint}</div>}
      </div>
      <span style={{ width: 42, height: 24, borderRadius: 999, background: on ? C.green : 'rgba(255,255,255,.14)',
        position: 'relative', transition: 'background .18s', flexShrink: 0 }}>
        <span style={{ position: 'absolute', top: 3, left: on ? 21 : 3, width: 18, height: 18, borderRadius: '50%',
          background: '#fff', transition: 'left .18s' }} />
      </span>
    </button>
  )
}

function DeleteDialog({ t, onClose, onConfirm }) {
  const mobile = useIsMobile()
  const [deleteFiles, setDeleteFiles] = useState(false)
  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 100, display: 'grid', placeItems: 'center',
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
          <span style={{ color: C.text, fontWeight: 600 }}>{t.name}</span> will stop downloading and be removed.
        </p>
        <Toggle label="Also delete downloaded files" hint="Erase the data on disk, not just the download" on={deleteFiles} set={setDeleteFiles} />
        <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
          <button onClick={onClose} style={{ flex: 1, height: 46, borderRadius: 13, border: `1px solid ${C.line2}`,
            cursor: 'pointer', fontFamily: SANS, fontSize: 14.5, fontWeight: 700, color: C.text, background: 'rgba(255,255,255,.04)' }}>
            Cancel
          </button>
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

function DownloadsUnavailable({ configured }) {
  return (
    <div style={{ marginTop: 8, padding: '40px 26px', borderRadius: 18, ...glassStyle,
      display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', animation: 'up .4s ease both' }}>
      <div style={{ width: 60, height: 60, borderRadius: 16, display: 'grid', placeItems: 'center', marginBottom: 16,
        background: 'rgba(62,207,126,.1)', border: '1px solid rgba(62,207,126,.3)' }}>
        <Icon path={Ic.download} size={28} stroke={C.green} sw={1.7} />
      </div>
      <h2 style={{ fontSize: 20, fontWeight: 800, margin: 0 }}>
        {configured ? 'Downloads are temporarily unavailable' : 'Downloads aren’t set up yet'}
      </h2>
      <p style={{ color: C.dim, fontSize: 14.5, lineHeight: 1.6, maxWidth: 440, marginTop: 10 }}>
        {configured
          ? 'We can’t reach downloads right now. Live progress and controls will return on their own.'
          : 'Once downloads are configured, anything you add shows live progress, speeds, and controls here.'}
      </p>
    </div>
  )
}
