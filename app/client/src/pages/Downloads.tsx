import { useMemo, useState } from 'react'
import type { MouseEvent } from 'react'
import { useIsMobile } from '../hooks/useIsMobile'
import { useDownloadsHub } from '../context/DownloadsContext'
import type { DownloadsHub } from '../context/DownloadsContext'
import { failureReasons, queueTitle } from '../hooks/useFailingDownloads'
import type { FailingQueueItem, FailingQueueState } from '../hooks/useFailingDownloads'
import { DownloadPoster, DownloadDetail } from '../components/DownloadDetail'
import { C, SANS, MONO, Ic, Icon, Spinner } from '../lib/ui'
import { fmtSize, fmtSpeed, stateInfo } from '../lib/format'
import type { ServiceHealth } from '../hooks/downloadsCore'

/* ── Cinematic-minimal, monochrome tokens local to this screen. `ui.jsx`'s
   palette still carries the old liquid-glass colors (out of scope here), so
   status/progress visuals are derived from these flat, neutral values instead
   of the legacy status colors on the shared object — the only color left is
   `DANGER`, used strictly for failed/error/destructive states. ────────────── */
const DANGER = '#E0655E'
const DANGER_BG = 'rgba(224,101,94,.12)'
const DANGER_BORDER = 'rgba(224,101,94,.35)'
const FLAT = { backgroundColor: '#141416', border: '1px solid rgba(255,255,255,.08)', boxShadow: 'none' }

type Torrent = {
  hash: string; name?: string; state?: string; progress?: number; dlspeed?: number; upspeed?: number
  displayTitle?: string; subtitle?: string; posterUrl?: string; kind?: string
}

export default function Downloads() {
  const mobile = useIsMobile()

  // Health, the live torrent list, and the *arr failing queue all come from the
  // shared hub (context/DownloadsContext) — this page used to run its own copy of
  // each, including a verbatim duplicate of the phone screen's queue poller.
  const dl = useDownloadsHub()
  const { health, healthLoading, qbitReady, arrReady, failing } = dl
  return (
    <div style={{ position: 'absolute', inset: 0, background: C.bg, color: C.text, fontFamily: SANS, overflow: 'hidden' }}>
      <div style={{
        position: 'absolute', inset: 0, overflow: 'hidden auto',
      }}>
        <div style={{ padding: mobile ? '72px 16px 100px' : '64px 42px 100px clamp(40px, 5vw, 72px)', maxWidth: 1600, margin: '0 auto' }}>
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
function NeedsAttention({ healthLoading, arrReady, failing }: {
  healthLoading: boolean; arrReady: boolean; failing: FailingQueueState
}) {
  if (healthLoading || (arrReady && failing.items === null)) return null
  if (!arrReady) return null
  const items = failing.items || []
  if (items.length === 0 && !failing.loadError) return null

  return (
    <section style={{ marginBottom: 36, animation: 'up .4s ease both' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 14, flexWrap: 'wrap' }}>
        <h2 style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-.02em', margin: 0, color: items.length ? DANGER : C.text }}>
          Needs attention
        </h2>
        {items.length > 0 && (
          <span style={{ fontFamily: MONO, fontSize: 12.5, color: C.dim }}>{items.length} stuck</span>
        )}
        {failing.loadError && (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: MONO, fontSize: 12, color: C.faint }}>
            <Spinner size={12} />reconnecting…
          </span>
        )}
      </div>
      {items.length === 0 ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: C.faint, fontSize: 13 }}><Icon path={Ic.check} size={15} />Queue unavailable</div>
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

function FailingRow({ q, busy, onRemove }: { q: FailingQueueItem; busy: boolean; onRemove: (blocklist: boolean) => void }) {
  const [confirm, setConfirm] = useState(false)
  const reasons = failureReasons(q)
  return (
    <div style={{ padding: '15px 18px', borderRadius: 14, ...FLAT, border: `1px solid ${DANGER_BORDER}` }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12, flexWrap: 'wrap' }}>
        <div style={{ width: 34, height: 34, borderRadius: 10, flexShrink: 0, display: 'grid', placeItems: 'center',
          background: DANGER_BG, border: `1px solid ${DANGER_BORDER}` }}>
          <Icon path={Ic.alert} size={17} stroke={DANGER} sw={2} />
        </div>
        <div style={{ flex: 1, minWidth: 180 }}>
          <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>{queueTitle(q)}</div>
          <div style={{ marginTop: 4, display: 'flex', flexDirection: 'column', gap: 2 }}>
            {reasons.map((r: string, i: number) => (
              <span key={i} style={{ fontSize: 12.5, color: DANGER }}>{r}</span>
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

function pillBtnStyle(danger: boolean) {
  return {
    display: 'inline-flex', alignItems: 'center', gap: 6, height: 32, padding: '0 12px', borderRadius: 999,
    border: danger ? `1px solid ${DANGER_BORDER}` : `1px solid ${C.line2}`, cursor: 'pointer',
    fontFamily: SANS, fontSize: 12.5, fontWeight: 700,
    background: danger ? DANGER_BG : 'rgba(255,255,255,.04)', color: danger ? DANGER : C.text,
  }
}

/* ── Active qBittorrent-backed downloads ─────────────────────────────────── */
function ActiveDownloads({ mobile, healthLoading, qbitReady, qbit, dl }: {
  mobile: boolean; healthLoading: boolean; qbitReady: boolean; qbit?: ServiceHealth; dl: DownloadsHub
}) {
  const [confirmDel, setConfirmDel] = useState<Torrent | null>(null)
  const [detail, setDetail] = useState<Torrent | null>(null)   // download-detail overlay target
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
      {(list.length > 0 || dl.loadError) && <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 14, flexWrap: 'wrap' }}>
        <h2 style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-.02em', margin: 0 }}>Active</h2>
        {qbitReady && list.length > 0 && (
          <span style={{ fontFamily: MONO, fontSize: 12.5, color: C.dim }}>
            {dl.activeCount} active · ↓ {fmtSpeed(agg.dl)}
            <span style={{ color: C.faint }}> · ↑ {fmtSpeed(agg.up)}</span>
          </span>
        )}
        {qbitReady && dl.loadError && (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: MONO, fontSize: 12, color: C.faint }}>
            <Spinner size={12} />reconnecting…
          </span>
        )}
      </div>}

      {(healthLoading || (qbitReady && dl.torrents === null)) ? (
        <div style={{ padding: '40px 0', display: 'grid', placeItems: 'center' }}><Spinner size={24} /></div>
      ) : !qbitReady ? (
        <DownloadsUnavailable configured={!!qbit?.configured} />
      ) : list.length === 0 ? (
        <div style={{ minHeight: '55vh', display: 'grid', placeItems: 'center', color: C.faint }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 10, fontSize: 13 }}><Icon path={Ic.download} size={18} />No downloads</span>
        </div>
      ) : (
        <div style={{ display: 'grid', gap: mobile ? 12 : 18,
          gridTemplateColumns: `repeat(auto-fill, minmax(${mobile ? 138 : 160}px, 1fr))` }}>
          {list.map((t: Torrent) => (
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
          torrent={list.find((t: Torrent) => t.hash === detail.hash) || detail}
          onClose={() => setDetail(null)} />
      )}
    </section>
  )
}

/* Neutral status read for a torrent row: only the error state gets a semantic
   color, everything else — downloading, finishing up, queued, paused — is
   plain dim/faint text. Progress never carries a phase color. */
function statusColor(info: ReturnType<typeof stateInfo>) {
  if (info.label === 'Error') return DANGER
  return info.paused ? C.faint : C.dim
}

/* ── Active download card — 2:3 poster with the circular progress ring, title +
   state/subtitle below, and inline pause/resume + delete controls. Clicking the
   poster opens the full download detail. Matches the Library "Downloading now"
   poster+ring treatment for consistency. ─────────────────────────────────────── */
function TorrentCard({ t, busy, onOpen, onPause, onResume, onDelete }: {
  t: Torrent; busy: boolean; onOpen: () => void; onPause: () => void; onResume: () => void; onDelete: () => void
}) {
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
          boxShadow: h ? '0 16px 44px rgba(0,0,0,.62)' : 'none',
          transform: h ? 'translateY(-4px)' : 'none', transition: 'transform .2s cubic-bezier(.2,.8,.2,1), box-shadow .2s cubic-bezier(.2,.8,.2,1)' }}>
        <DownloadPoster posterUrl={t.posterUrl} kind={t.kind} pct={pct} paused={info.paused} width="100%" radius={14} ringSize={78} />
      </button>
      <div style={{ marginTop: 9, display: 'flex', alignItems: 'flex-start', gap: 8 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: C.text, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={t.name}>{title}</div>
          <div style={{ fontFamily: MONO, fontSize: 11.5, color: statusColor(info), marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
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

function RowBtn({ title, icon, onClick, disabled, danger = false }: {
  title: string; icon: string; onClick: () => void; disabled?: boolean; danger?: boolean
}) {
  const [h, setH] = useState(false)
  return (
    <button onClick={onClick} title={title} disabled={disabled}
      onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{ width: 34, height: 34, borderRadius: 10, display: 'grid', placeItems: 'center', flexShrink: 0,
        border: `1px solid ${C.line}`, cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.4 : 1,
        color: danger ? (h ? DANGER : C.dim) : (h ? C.text : C.dim),
        background: h ? (danger ? DANGER_BG : 'rgba(255,255,255,.07)') : 'rgba(255,255,255,.03)',
        transition: 'background .15s, color .15s' }}>
      <Icon path={icon} size={16} sw={1.9} />
    </button>
  )
}

function Toggle({ label, hint, on, set }: { label: string; hint?: string; on: boolean; set: (value: boolean) => void }) {
  return (
    <button onClick={() => set(!on)} style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 12,
      padding: '11px 14px', marginBottom: 10, borderRadius: 12, border: `1px solid ${C.line}`, cursor: 'pointer',
      background: 'rgba(255,255,255,.03)', textAlign: 'left' }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>{label}</div>
        {hint && <div style={{ fontSize: 12, color: C.faint, marginTop: 2 }}>{hint}</div>}
      </div>
      <span style={{ width: 42, height: 24, borderRadius: 999, background: on ? 'rgba(255,255,255,.55)' : 'rgba(255,255,255,.14)',
        position: 'relative', transition: 'background .18s', flexShrink: 0 }}>
        <span style={{ position: 'absolute', top: 3, left: on ? 21 : 3, width: 18, height: 18, borderRadius: '50%',
          background: '#fff', transition: 'left .18s' }} />
      </span>
    </button>
  )
}

function DeleteDialog({ t, onClose, onConfirm }: { t: Torrent; onClose: () => void; onConfirm: (deleteFiles: boolean) => void }) {
  const mobile = useIsMobile()
  const [deleteFiles, setDeleteFiles] = useState(false)
  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 100, display: 'grid', placeItems: 'center',
      padding: 16, background: 'rgba(0,0,0,.6)', backdropFilter: 'blur(2px)', WebkitBackdropFilter: 'blur(2px)', animation: 'up .2s ease both' }}>
      <div onClick={(e: MouseEvent<HTMLDivElement>) => e.stopPropagation()} style={{ width: 'min(440px, 100%)', borderRadius: 16, padding: mobile ? 20 : 26,
        ...FLAT, boxShadow: '0 24px 60px rgba(0,0,0,.7)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
          <div style={{ width: 42, height: 42, borderRadius: 12, display: 'grid', placeItems: 'center', flexShrink: 0,
            background: DANGER_BG, border: `1px solid ${DANGER_BORDER}` }}>
            <Icon path={Ic.trash} size={20} stroke={DANGER} sw={1.8} />
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
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, background: DANGER }}>
            <Icon path={Ic.trash} size={16} sw={2} />Remove
          </button>
        </div>
      </div>
    </div>
  )
}

function DownloadsUnavailable({ configured }: { configured: boolean }) {
  return (
    <div style={{ minHeight: '55vh', display: 'grid', placeItems: 'center', color: C.faint }}>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 10, fontSize: 13 }}>
        <Icon path={Ic.download} size={18} />{configured ? 'Downloads unavailable' : 'Downloads not configured'}
      </span>
    </div>
  )
}
