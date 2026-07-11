// @ts-nocheck
import { navigate } from '../router'
import { useTorrents } from '../hooks/useTorrents'
import { useFailingCount } from '../hooks/useFailingDownloads'
import { T, MONO, EASE, Z, SANS } from './theme'
import { Icon, Ic } from './ui/Icon'

/**
 * Flush bottom tab bar. Edge-to-edge with a hairline top border, sitting over
 * the home indicator's safe area. Home / Browse / Downloads navigate via the
 * existing pushState router; the center Party action opens the join sheet.
 * Active state is brighter icon + heavier label only — no pill, no rail, no
 * dot, no color. The Downloads tab keeps its live-count badge (the plan's one
 * permitted status color: red for a failing download, neutral otherwise).
 */
const TABS = [
  { key: 'home',     path: '/library',   icon: Ic.home,     label: 'Home' },
  { key: 'browse',   path: '/discover',  icon: Ic.compass,  label: 'Browse' },
  { key: 'party',    action: 'party',    icon: Ic.plus,     label: 'Party', center: true },
  { key: 'downloads',path: '/downloads', icon: Ic.download, label: 'Downloads' },
]

function isActive(path: string | undefined, tabPath?: string) {
  if (!tabPath) return false
  if (tabPath === '/library') return path === '/library' || path === '/'
  return path === tabPath
}

export function TabBar({ path, onParty }: { path?: string; onParty?: () => void } = {}) {
  // Reuse the existing pollers so the Downloads badge matches every surface.
  const { activeCount } = useTorrents(true)
  const failing = useFailingCount(true)

  return (
    <nav
      style={{
        position: 'fixed', left: 0, right: 0, bottom: 0, zIndex: Z.tabbar,
        background: T.bg,
        borderTop: `1px solid ${T.line}`,
        paddingLeft: 'var(--sa-l)', paddingRight: 'var(--sa-r)',
        paddingBottom: 'var(--sa-b)',
      }}
    >
      <div
        style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-around',
          padding: '8px 6px',
        }}
      >
        {TABS.map((t) => {
          if (t.center) return <PartyTab key={t.key} onClick={onParty} />
          const active = isActive(path, t.path)
          const badge = t.key === 'downloads' ? <DownloadDot active={activeCount} failing={failing} /> : null
          return (
            <button
              key={t.key}
              onClick={() => navigate(t.path)}
              aria-label={t.label}
              aria-current={active ? 'page' : undefined}
              className="mob-press"
              style={{
                position: 'relative',
                flex: 1, minWidth: 44, minHeight: 44,
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
                border: 'none', background: 'transparent', cursor: 'pointer',
                color: active ? T.text : T.dim,
                transition: `color .18s ${EASE}`,
              }}
            >
              <span style={{ position: 'relative' }}>
                <Icon path={t.icon} size={23} sw={active ? 2.0 : 1.7} />
                {badge}
              </span>
              <span style={{ fontFamily: SANS, fontSize: 10.5, fontWeight: active ? 700 : 500, letterSpacing: '.01em' }}>
                {t.label}
              </span>
            </button>
          )
        })}
      </div>
    </nav>
  )
}

// Elevated center action — the app's primary verb, kept flat/neutral like
// every other primary button (near-white fill, dark ink).
function PartyTab({ onClick }: { onClick?: () => void } = {}) {
  return (
    <button
      onClick={onClick}
      aria-label="Start or join a party"
      className="mob-press"
      style={{
        flex: '0 0 auto',
        width: 52, height: 52, marginTop: -18, marginBottom: -2,
        borderRadius: 999, border: `1px solid ${T.line2}`,
        background: T.primary,
        display: 'grid', placeItems: 'center', cursor: 'pointer',
        color: T.onLight,
        boxShadow: '0 8px 20px rgba(0,0,0,.5)',
      }}
    >
      <Icon path={Ic.plus} size={24} stroke={T.onLight} sw={2.2} />
    </button>
  )
}

// Live count dot on the Downloads tab — the plan's one permitted status
// color (red = failing/active transfer). Never used as decoration elsewhere.
function DownloadDot({ active, failing }: { active?: number | false; failing?: number | false } = {}) {
  if (!active && !failing) return null
  const color = failing ? T.red : T.text
  const ink = failing ? T.brandInk : T.onLight
  const n = Number(failing || active || 0)
  return (
    <span
      style={{
        position: 'absolute', top: -5, right: -9,
        minWidth: 16, height: 16, padding: '0 4px', borderRadius: 999,
        background: color, color: ink,
        fontFamily: MONO, fontSize: 9.5, fontWeight: 700, lineHeight: '16px',
        display: 'grid', placeItems: 'center',
        boxShadow: `0 0 0 2px ${T.bg}`,
      }}
    >
      {n > 9 ? '9+' : n}
    </span>
  )
}
