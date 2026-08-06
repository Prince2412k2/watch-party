import { Suspense, lazy, useEffect, useMemo, useState } from 'react'
import type { ReactElement } from 'react'
import { T } from './theme.ts'
import { ShellContext } from './shellContext.ts'
import { TabBar } from './TabBar.tsx'
import { JoinSheet } from './JoinSheet.tsx'
import { useParty } from '../context/PartyContext.tsx'
import { canDriveBrowse, isBrowseFollower } from '../partyAuthority.ts'
import { tabForMobilePath } from './sharedBrowse.ts'

/* Screens are split per route (they are the bulk of the phone bundle: Browse and
 * Downloads alone are ~1.8k lines of presentation). Only the screen a member
 * actually opens is fetched. */
const Home = lazy(() => import('./screens/Home'))
const Browse = lazy(() => import('./screens/Browse'))
const Downloads = lazy(() => import('./screens/Downloads'))

// Route → shell screen. MobileApp is only mounted for a signed-in member on a
// tabbed route: '/login' is pre-auth (App.tsx renders the phone sign-in screen
// itself) and party routes go through the shared WatchRoute above the phone
// branch, so neither reaches here.
function screenFor(path: string | undefined): { key: string; el: ReactElement } {
  if (path === '/discover') return { key: 'browse', el: <Browse /> }
  if (path === '/downloads') return { key: 'downloads', el: <Downloads /> }
  // '/library', '/movies', '/series' and anything else (incl. '/') land on Home,
  // which is the phone stand-in for both desktop library tabs — a guest pushed to
  // '/series' by the host's shared browse state arrives here.
  return { key: 'home', el: <Home /> }
}

/**
 * Phone app shell. Fixed to the dynamic viewport (100dvh) so the collapsing URL
 * bar never shifts layout; a single inner region scrolls with momentum; a
 * flush tab bar sits above the home indicator. Flat monochrome ground — no
 * ambient glow, no gradient chrome.
 */
export default function MobileApp({ path }: { path?: string } = {}) {
  const [joinOpen, setJoinOpen] = useState(false)
  const { key, el } = screenFor(path)
  const { session, role, shareView } = useParty()

  const driving = canDriveBrowse(session, role)
  const following = isBrowseFollower(session, role)

  const ctx = useMemo(() => ({ openJoin: () => setJoinOpen(true), path, following }), [path, following])

  // Publish the tab this phone is showing, exactly as the desktop WebShell does
  // for its own nav — so a phone host drives desktop guests and vice versa. Only
  // fires when the route (or the party) actually changes.
  useEffect(() => {
    if (!driving) return
    const next = tabForMobilePath(path)
    if (next) shareView({ tab: next, screen: 'grid' })
  }, [session?.id, driving, path])

  // `--app-vh` hardens `.mobile-shell`'s `100dvh` against iOS cases where the
  // CSS unit under-reports the real visible height (standalone/home-screen
  // mode, or a residual gap left after the keyboard dismisses) — see
  // styles.css's `.mobile-shell` comment. `visualViewport` is preferred over
  // `innerHeight` since it tracks the actually-visible area, which is exactly
  // what's unreliable here.
  useEffect(() => {
    const set = () => {
      const h = window.visualViewport?.height ?? window.innerHeight
      document.documentElement.style.setProperty('--app-vh', `${h}px`)
    }
    set()
    window.visualViewport?.addEventListener('resize', set)
    window.addEventListener('resize', set)
    window.addEventListener('orientationchange', set)
    return () => {
      window.visualViewport?.removeEventListener('resize', set)
      window.removeEventListener('resize', set)
      window.removeEventListener('orientationchange', set)
    }
  }, [])

  return (
    <ShellContext.Provider value={ctx}>
      <div className="mobile-shell" style={{ color: T.text }}>
        {/* flat ground */}
        <div aria-hidden style={{ position: 'absolute', inset: 0, background: T.bg, pointerEvents: 'none' }} />

        {/* the ONLY scroller */}
        <div
          className="mobile-scroll"
          style={{ paddingBottom: `calc(var(--sa-b) + 88px)` }}
        >
          {/* A follower's screen mirrors the driver, so it is inert — same rule
              the desktop shell applies to `.web-main` for guests. The tab bar
              below stays live so a guest can still leave the mirrored view. */}
          <div
            key={key}
            className="mobile-screen"
            aria-label={following ? 'Shared host view' : undefined}
            style={following ? { pointerEvents: 'none' } : undefined}
          >
            <Suspense fallback={null}>{el}</Suspense>
          </div>
        </div>

        <TabBar path={path} onParty={() => setJoinOpen(true)} />
        <JoinSheet open={joinOpen} onClose={() => setJoinOpen(false)} />
      </div>
    </ShellContext.Provider>
  )
}
