import { glass } from '../glass.jsx'
import { navigate } from '../router.js'
import { useTorrents } from '../hooks/useTorrents.js'
import { useFailingCount } from '../hooks/useFailingDownloads.js'
import { T, MONO, BRAND_GRADIENT, EASE, Z, SANS } from './theme.js'
import { Icon, Ic } from './ui/Icon.jsx'

/**
 * Floating glass tab bar. Not edge-to-edge — a pill that hovers above the
 * home indicator so it reads as an app control. Home / Browse / Downloads
 * navigate via the existing pushState router; the center Party action is
 * elevated (brand-gradient circle) since starting a watch party is the app's
 * primary verb. The Downloads tab carries a live count dot (brand-green active
 * / red failing), mirroring the desktop sidebar badges.
 */
const TABS = [
  { key: 'home',     path: '/library',   icon: Ic.home,     label: 'Home' },
  { key: 'browse',   path: '/discover',  icon: Ic.compass,  label: 'Browse' },
  { key: 'party',    action: 'party',    icon: Ic.plus,     label: 'Party', center: true },
  { key: 'downloads',path: '/downloads', icon: Ic.download, label: 'Downloads' },
]

function isActive(path, tabPath) {
  if (!tabPath) return false
  if (tabPath === '/library') return path === '/library' || path === '/'
  return path === tabPath
}

export function TabBar({ path, onParty }) {
  // Reuse the existing pollers so the Downloads badge matches every surface.
  const { activeCount } = useTorrents(true)
  const failing = useFailingCount(true)

  return (
    <nav
      style={{
        position: 'fixed', left: 12, right: 12, zIndex: Z.tabbar,
        bottom: `calc(var(--sa-b) + 10px)`,
        marginLeft: 'var(--sa-l)', marginRight: 'var(--sa-r)',
      }}
    >
      <div
        style={{
          ...glass('medium', { refract: true }),
          borderRadius: 999,
          display: 'flex', alignItems: 'center', justifyContent: 'space-around',
          padding: '8px 10px',
          overflow: 'visible',
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
                color: active ? T.brand : T.dim,
                transition: `color .18s ${EASE}`,
              }}
            >
              <span style={{ position: 'relative' }}>
                <Icon path={t.icon} size={23} sw={active ? 2.2 : 1.8} />
                {badge}
              </span>
              <span style={{ fontFamily: SANS, fontSize: 10.5, fontWeight: active ? 700 : 600, letterSpacing: '.01em' }}>
                {t.label}
              </span>
            </button>
          )
        })}
      </div>
    </nav>
  )
}

// Elevated center action — brand-gradient circle that pokes above the pill.
function PartyTab({ onClick }) {
  return (
    <button
      onClick={onClick}
      aria-label="Start or join a party"
      className="mob-press"
      style={{
        flex: '0 0 auto',
        width: 56, height: 56, marginTop: -22, marginBottom: -6,
        borderRadius: 999, border: '2px solid rgba(255,255,255,.14)',
        background: BRAND_GRADIENT,
        display: 'grid', placeItems: 'center', cursor: 'pointer',
        color: '#0b0d10',
        boxShadow: '0 10px 26px rgba(62,207,126,.32), 0 4px 12px rgba(0,0,0,.4)',
      }}
    >
      <Icon path={Ic.play} size={24} fill="#0b0d10" stroke="none" />
    </button>
  )
}

// Live count dot on the Downloads tab.
function DownloadDot({ active, failing }) {
  if (!active && !failing) return null
  const color = failing ? T.red : T.brand
  const n = failing || active
  return (
    <span
      style={{
        position: 'absolute', top: -5, right: -9,
        minWidth: 16, height: 16, padding: '0 4px', borderRadius: 999,
        background: color, color: failing ? '#2a0808' : T.brandInk,
        fontFamily: MONO, fontSize: 9.5, fontWeight: 700, lineHeight: '16px',
        display: 'grid', placeItems: 'center',
        boxShadow: '0 0 0 2px rgba(11,13,16,.9)',
      }}
    >
      {n > 9 ? '9+' : n}
    </span>
  )
}
