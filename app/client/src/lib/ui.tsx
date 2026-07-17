// Shared desktop-nav shell for the download surfaces. The palette / type tokens,
// icon-path set, Icon, viewIcon, glass panel style, and the reusable nav chrome
// (Sidebar, NavRow, TopBar, GlassBtn, Notice, Spinner) were copy-pasted and
// drifting across Library.jsx / Downloads.jsx / FindDownload.jsx /
// DownloadDetail.jsx — this is the single reconciled source.
import { useState } from 'react'
import type { CSSProperties, ReactNode } from 'react'
import { navigate } from '../router'
import { glass } from '../glass'

/* ── Cinematic minimal — dark, flat, monochrome ──────────────────────────────
   Content is the interface (Apple TV / Max). Neutral near-black -> near-white
   ramp, ONE color family total: semantic status (danger/live/success), never
   used decoratively. No brand hue, no gradients, no glass. Keys match the old
   object 1:1 so every page inherits this untouched. */
export const C = {
  bg: 'var(--wp-bg, #0a0a0b)',
  surface: 'var(--wp-surface, #141416)',
  surface2: 'var(--wp-surface-2, #1e1e21)',
  surface3: 'var(--wp-surface-3, #2a2a2e)',
  text: 'var(--wp-text, #F4F4F5)',
  dim: 'var(--wp-dim, rgba(244,244,245,.62))',
  faint: 'var(--wp-faint, rgba(244,244,245,.36))',
  line: 'var(--wp-line, rgba(255,255,255,.08))',
  line2: 'var(--wp-line-2, rgba(255,255,255,.14))',
  accent: 'var(--wp-text, #F4F4F5)',
  accentDim: 'var(--wp-dim, #CBCBCE)',
  accentSoft: 'var(--wp-line, rgba(255,255,255,.08))',
  onAccent: 'var(--wp-bg, #0a0a0b)',
  // Semantic status ONLY — never decorative, never "brand", never active-state fill.
  green: '#5AB98A',          // success tick, sparingly
  amber: '#E0655E',          // (legacy key name) — mapped to danger/live red, see `red`/`live`
  red: '#E0655E',
  live: '#E0655E',           // active-download / recording dot
  glass: '#141416',          // flat solid surface (no blur)
  glassHi: '#1e1e21',
}
export const SANS = "'Circular XX', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
export const MONO = "'JetBrains Mono', ui-monospace, monospace"

// Frosted panel style, built on the shared glass() abstraction (heavy = blur 26).
export const glassStyle = glass('heavy')

/* ── Inline stroke icons (Lucide/Heroicons style — NO emoji) — union of every
   path used across the download surfaces. ─────────────────────────────────── */
export const Ic = {
  home: 'm3 11 9-8 9 8M5 9v11a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9',
  folder: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  film: 'M4 4h16v16H4zM4 8h16M4 16h16M8 4v16M16 4v16',
  tv: 'M2 7h20v11H2zM8 21h8M12 18v3',
  music: 'M9 18V6l10-2v11M9 18a3 3 0 1 1-3-3 3 3 0 0 1 3 3zm10-3a3 3 0 1 1-3-3 3 3 0 0 1 3 3z',
  search: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.3-4.3',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2V21a2 2 0 1 1-4 0v-.1A1.7 1.7 0 0 0 6 19.4l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0-1.2-2.9H2a2 2 0 1 1 0-4h.1A1.7 1.7 0 0 0 3.4 6l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 2.9-1.2V2a2 2 0 1 1 4 0v.1A1.7 1.7 0 0 0 18 3.4l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0 1.2 2.9H22a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  gear: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2V21a2 2 0 1 1-4 0v-.1A1.7 1.7 0 0 0 6 19.4l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0-1.2-2.9H2a2 2 0 1 1 0-4h.1A1.7 1.7 0 0 0 3.4 6l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 2.9-1.2V2a2 2 0 1 1 4 0v.1A1.7 1.7 0 0 0 18 3.4l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0 1.2 2.9H22a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  play: 'M8 5v14l11-7z',
  chevR: 'm9 6 6 6-6 6',
  chevL: 'm15 6-6 6 6 6',
  refresh: 'M3 12a9 9 0 0 1 15-6.7L21 8M21 3v5h-5M21 12a9 9 0 0 1-15 6.7L3 16M3 21v-5h5',
  history: 'M3 3v5h5M3.05 13A9 9 0 1 0 6 5.3L3 8M12 7v5l3 3',
  check: 'M20 6 9 17l-5-5',
  heart: 'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 21l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8z',
  more: 'M5 12h.01M12 12h.01M19 12h.01',
  plus: 'M12 5v14M5 12h14',
  logout: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
  star: 'M12 2 15 9l7 .5-5.3 4.6L18.5 21 12 17l-6.5 4 1.8-6.9L2 9.5 9 9z',
  download: 'M12 3v12m0 0 4-4m-4 4-4-4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2',
  compass: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM16.2 7.8l-2.9 6.5-6.5 2.9 2.9-6.5z',
  enter: 'M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M3 12h12m0 0-4-4m4 4-4 4',
  x: 'M18 6 6 18M6 6l12 12',
  alert: 'M12 9v4m0 4h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z',
  pause: 'M8 5v14M16 5v14',
  trash: 'M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2M6 6l1 14a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1l1-14',
  ban: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM5 5l14 14',
  spark: 'M12 2v4M12 18v4M4.9 4.9l2.8 2.8M16.3 16.3l2.8 2.8M2 12h4M18 12h4M4.9 19.1l2.8-2.8M16.3 7.7l2.8-2.8',
}

export function Icon({ path, size = 20, stroke = 'currentColor', fill = 'none', sw = 1.7, style }: { path: string; size?: number; stroke?: string; fill?: string; sw?: number; style?: CSSProperties }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke={stroke}
      strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" style={style}>
      <path d={path} />
    </svg>
  )
}

// Pick a nav icon from a Jellyfin view's CollectionType/Name.
export function viewIcon(v: { CollectionType?: string }) {
  const t = (v.CollectionType || '').toLowerCase()
  if (t.includes('movie')) return Ic.film
  if (t.includes('tv') || t.includes('show')) return Ic.tv
  if (t.includes('music')) return Ic.music
  return Ic.folder
}

// Flat, quiet icon/pill button — solid surface, hairline border, no glass.
export function GlassBtn({
  onClick, title, children, pill, wide,
}: {
  onClick?: () => void
  title?: string
  children?: ReactNode
  pill?: boolean
  wide?: boolean
} = {}) {
  const [h, setH] = useState(false)
  return (
    <button onClick={onClick} title={title} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 8, justifyContent: 'center',
        height: 38, width: pill ? 'auto' : 38, padding: pill ? '0 16px' : 0,
        borderRadius: 10, cursor: 'pointer', color: h ? C.text : C.dim, fontFamily: SANS, fontSize: 13.5, fontWeight: 600,
        background: h ? C.surface2 : C.surface, border: `1px solid ${C.line}`,
        transition: 'background .15s, color .15s', flexShrink: 0,
      }}>{children}</button>
  )
}

// Active = brighter + heavier text/icon ONLY. No background fill, no rail, no
// dot, no color — that boxed-pill treatment was explicitly rejected.
export function NavRow({
  mobile, icon, label, active, onClick, badge = 0, alertBadge = 0,
}: {
  mobile?: boolean
  icon: string
  label: string
  active?: boolean
  onClick?: () => void
  badge?: number
  alertBadge?: number
}) {
  const [h, setH] = useState(false)
  const showBadge = badge > 0
  const showAlert = alertBadge > 0
  const title = showAlert ? `${label} — ${alertBadge} need${alertBadge === 1 ? 's' : ''} attention`
    : showBadge ? `${label} — ${badge} downloading` : label
  return (
    <button onClick={onClick} onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)} title={title}
      style={{
        position: 'relative',
        display: 'flex', alignItems: 'center', gap: mobile ? 0 : 12, justifyContent: mobile ? 'center' : 'flex-start',
        padding: mobile ? '11px 0' : '10px 12px', borderRadius: 10, border: 'none', cursor: 'pointer', width: '100%',
        fontFamily: SANS, fontSize: 14.5, fontWeight: active ? 700 : 500, textAlign: 'left',
        color: active ? C.text : (h ? C.text : C.dim),
        background: h && !active ? 'rgba(255,255,255,.04)' : 'transparent',
        transition: 'background .15s, color .15s',
      }}>
      <Icon path={icon} size={mobile ? 21 : 19} sw={active ? 2 : 1.7} />
      {!mobile && <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1 }}>{label}</span>}
      {showAlert && (mobile
        ? <span aria-label={`${alertBadge} need attention`} style={{ position: 'absolute', top: 8, right: 12, width: 9, height: 9,
            borderRadius: '50%', background: C.red, boxShadow: `0 0 6px ${C.red}` }} />
        : <span style={{ flexShrink: 0, minWidth: 20, height: 20, padding: '0 6px', borderRadius: 999, display: 'inline-flex',
            alignItems: 'center', justifyContent: 'center', fontFamily: MONO, fontSize: 11.5, fontWeight: 700,
            background: 'rgba(220,60,60,.18)', color: C.red, border: `1px solid rgba(220,60,60,.4)` }}>{alertBadge}</span>)}
      {!showAlert && showBadge && (mobile
        ? <span aria-label={`${badge} downloading`} style={{ position: 'absolute', top: 8, right: 12, width: 9, height: 9,
            borderRadius: '50%', background: C.green, boxShadow: `0 0 6px ${C.green}`, animation: 'pulse 1.6s ease-in-out infinite' }} />
        : <span style={{ flexShrink: 0, minWidth: 20, height: 20, padding: '0 6px', borderRadius: 999, display: 'inline-flex',
            alignItems: 'center', justifyContent: 'center', gap: 4, fontFamily: MONO, fontSize: 11.5, fontWeight: 700,
            background: 'rgba(62,207,126,.18)', color: C.green, border: `1px solid rgba(62,207,126,.4)` }}>
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: C.green, boxShadow: `0 0 5px ${C.green}`,
              animation: 'pulse 1.6s ease-in-out infinite' }} />{badge}
          </span>)}
    </button>
  )
}

/* ── Floating glass sidebar for the download surfaces — Home → Jellyfin views →
   Browse → Downloads. `current` ('browse' | 'downloads') marks the active row;
   library views come from the shared useLibraryViews hook so a library row
   appears here identically to the Library page. ──────────────────────────────── */
export function Sidebar({
  mobile, width, views = [], downloadCount = 0, failingCount = 0, current,
}: {
  mobile?: boolean
  width?: number | string
  views?: Array<{ Id: string; Name: string; CollectionType?: string }>
  downloadCount?: number
  failingCount?: number
  current?: string
} = {}) {
  return (
    <aside style={{
      position: 'absolute', top: 0, left: 0, bottom: 0,
      width, zIndex: 20, display: 'flex', flexDirection: 'column',
      padding: mobile ? '12px 8px' : '22px 16px',
      background: C.bg, borderRight: `1px solid ${C.line}`,
    }}>
      {!mobile && (
        <div style={{ display: 'flex', alignItems: 'center', padding: '2px 8px 22px', cursor: 'pointer' }}
          onClick={() => navigate('/library')}>
          <span style={{ fontSize: 15, fontWeight: 700, letterSpacing: '-.01em' }}>Watchparty</span>
        </div>
      )}
      <nav style={{ display: 'flex', flexDirection: 'column', gap: 3, overflowY: 'auto', scrollbarWidth: 'none', flex: 1 }}>
        <NavRow mobile={mobile} icon={Ic.home} label="Home" onClick={() => navigate('/library')} />
        {views.map((v) => (
          <NavRow key={v.Id} mobile={mobile} icon={viewIcon(v)} label={v.Name} onClick={() => navigate(`/library?view=${encodeURIComponent(v.Id)}`)} />
        ))}
        <NavRow mobile={mobile} icon={Ic.compass} label="Browse" active={current === 'browse'}
          onClick={current === 'browse' ? () => {} : () => navigate('/discover')} />
        <NavRow mobile={mobile} icon={Ic.download} label="Downloads" active={current === 'downloads'}
          badge={downloadCount} alertBadge={failingCount}
          onClick={current === 'downloads' ? () => {} : () => navigate('/downloads')} />
      </nav>
    </aside>
  )
}

/* ── Top bar for the download surfaces. `title` names the page; when `detail` is
   truthy the back button pops the detail view (onBack) instead of leaving. ──── */
export function TopBar({
  mobile, initials, logout, title, detail, onBack,
}: {
  mobile?: boolean
  initials?: string
  logout?: () => void
  title?: string
  detail?: boolean
  onBack?: () => void
} = {}) {
  return (
    <div style={{
      position: 'sticky', top: 0, zIndex: 15, display: 'flex', alignItems: 'center', gap: 12,
      padding: mobile ? '12px 12px' : '16px 20px',
      background: 'linear-gradient(180deg, rgba(10,10,11,.85) 20%, rgba(10,10,11,0))',
    }}>
      <GlassBtn onClick={detail ? onBack : () => navigate('/library')} title={detail ? 'Back' : 'Back to library'}>
        <Icon path={Ic.chevL} size={18} sw={2} />
      </GlassBtn>
      <span style={{ fontSize: mobile ? 18 : 20, fontWeight: 700, letterSpacing: '-.02em' }}>{title}</span>
      <div style={{ flex: 1 }} />
      <div title={initials} style={{ width: 38, height: 38, borderRadius: '50%', display: 'grid', placeItems: 'center',
        fontSize: 12, fontWeight: 700, background: C.surface2, border: `1px solid ${C.line}`, color: C.text, flexShrink: 0 }}>{initials}</div>
      <GlassBtn onClick={logout} title="Sign out"><Icon path={Ic.logout} size={17} sw={1.8} /></GlassBtn>
    </div>
  )
}

export function Notice({
  icon, title, body, tone, compact,
}: {
  icon: string
  title?: string
  body?: string
  tone?: 'error' | 'ok' | 'warn' | string
  compact?: boolean
}) {
  const color = tone === 'error' ? C.red : tone === 'ok' ? C.green : tone === 'warn' ? C.red : C.dim
  const bg = tone === 'error' ? 'rgba(224,101,94,.1)' : tone === 'ok' ? 'rgba(90,185,138,.1)' : tone === 'warn' ? 'rgba(224,101,94,.1)' : 'transparent'
  const border = tone === 'error' ? 'rgba(224,101,94,.3)' : tone === 'ok' ? 'rgba(90,185,138,.3)' : tone === 'warn' ? 'rgba(224,101,94,.3)' : C.line
  if (compact) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginTop: 12, padding: '10px 14px', borderRadius: 10,
        background: bg, border: `1px solid ${border}`, color, fontSize: 13.5, fontWeight: 600 }}>
        <Icon path={icon} size={17} sw={2} />{title}
      </div>
    )
  }
  return (
    <div style={{ marginTop: 8, padding: '46px 28px', borderRadius: 16, background: C.surface, border: `1px solid ${C.line}`, animation: 'up .4s ease both',
      display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
      <div style={{ width: 56, height: 56, borderRadius: 16, display: 'grid', placeItems: 'center', marginBottom: 16,
        background: bg === 'transparent' ? 'rgba(255,255,255,.04)' : bg, border: `1px solid ${border}` }}>
        <Icon path={icon} size={26} stroke={color} sw={1.7} />
      </div>
      <h2 style={{ fontSize: 20, fontWeight: 800, margin: 0, color: tone === 'error' ? C.red : C.text }}>{title}</h2>
      {body && <p style={{ color: C.dim, fontSize: 14.5, lineHeight: 1.6, maxWidth: 420, marginTop: 8 }}>{body}</p>}
    </div>
  )
}

export function Spinner({ size = 20, dark = false }: { size?: number; dark?: boolean } = {}) {
  return (
    <span style={{ display: 'inline-block', width: size, height: size, borderRadius: '50%',
      border: `2px solid ${dark ? 'rgba(10,11,13,.25)' : 'rgba(255,255,255,.2)'}`,
      borderTopColor: dark ? C.onAccent : C.text, animation: 'spin .7s linear infinite' }} />
  )
}
