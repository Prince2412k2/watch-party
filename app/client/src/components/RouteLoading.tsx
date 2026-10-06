import { AnalogNav, type AnalogMode } from '../analog/AnalogNav.tsx'
import { useAuth } from '../context/AuthContext.tsx'
import { navigate } from '../router.ts'
import '../analog/analogKit.css'
import '../mobile/phoneCatalog.css'

/** Navigation stays available while a first-visit route chunk is loading. */
export default function RouteLoading() {
  const { user } = useAuth()
  const modes: Record<string, [AnalogMode, string]> = {
    '/movies': ['movies', 'Movies'],
    '/series': ['shows', 'Shows'],
    '/discover': ['discover', 'Discover'],
    '/downloads': ['downloads', 'Downloads'],
    '/saved': ['saved', 'Saved']
  }
  const mode = modes[location.pathname]
  return (
    <div className="route-loading" aria-busy="true">
      <p role="status">Loading{mode ? ` ${mode[1].toLowerCase()}` : ''}…</p>
      {mode && (
        <>
          <div className="route-loading-posters" aria-hidden>
            {Array.from({ length: 6 }, (_, i) => (
              <span key={i} />
            ))}
          </div>
          <div className="phone-catalog-nav">
            <AnalogNav
              active={mode[0]}
              onNavigate={navigate}
              compact
              canAcquire={user?.isAdmin}
            />
          </div>
        </>
      )}
    </div>
  )
}
