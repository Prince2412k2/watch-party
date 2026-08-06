import { AnIcon, type AnIconName } from './icons.tsx'

/**
 * The primary modes, along the bottom edge, on every device size.
 *
 * There is no sidebar and no second home: Home is a curated landing mode built
 * from the same components as Movies and Shows, not a parallel implementation.
 * The active mode is marked with a detent rule as well as brighter ink, because
 * selection must never rely on colour alone.
 */

export type AnalogMode = 'home' | 'movies' | 'shows' | 'discover' | 'downloads'

interface ModeSpec {
  id: AnalogMode
  label: string
  href: string
  icon: AnIconName
}

export const ANALOG_MODES: readonly ModeSpec[] = [
  { id: 'home', label: 'Home', href: '/movies', icon: 'home' },
  { id: 'movies', label: 'Movies', href: '/movies', icon: 'film' },
  { id: 'shows', label: 'Shows', href: '/series', icon: 'tv' },
  { id: 'discover', label: 'Discover', href: '/discover', icon: 'compass' },
  { id: 'downloads', label: 'Downloads', href: '/downloads', icon: 'download' },
]

export interface AnalogNavProps {
  active: AnalogMode
  onNavigate: (href: string) => void
  downloadCount?: number
  failingCount?: number
  compact?: boolean
}

export function AnalogNav({ active, onNavigate, downloadCount = 0, failingCount = 0, compact = false }: AnalogNavProps) {
  return (
    <nav className="an-nav" aria-label="Primary">
      {ANALOG_MODES.map((mode) => {
        const isActive = mode.id === active
        const badge = mode.id === 'downloads' ? failingCount || downloadCount : 0
        return (
          <button
            key={mode.id}
            type="button"
            className={isActive ? 'is-active' : ''}
            aria-current={isActive ? 'page' : undefined}
            onClick={() => onNavigate(mode.href)}
          >
            <AnIcon name={mode.icon} size={compact ? 20 : 17} />
            <span>{mode.label}</span>
            {badge > 0 ? (
              <span className={`an-nav-badge${failingCount > 0 ? ' is-alert' : ''}`}>
                {badge > 9 ? '9+' : badge}
              </span>
            ) : null}
          </button>
        )
      })}
    </nav>
  )
}
