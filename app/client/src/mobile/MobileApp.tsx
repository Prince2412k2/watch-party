import { useEffect, useMemo, useState } from 'react'
import type { ReactElement } from 'react'
import { T } from './theme'
import { ShellContext } from './shellContext'
import { TabBar } from './TabBar'
import { JoinSheet } from './JoinSheet'
import Login from './screens/Login'
import Home from './screens/Home'
import Browse from './screens/Browse'
import Downloads from './screens/Downloads'

// Route → shell screen. Party routes never reach MobileApp — App.jsx renders
// them through the shared WatchRoute above the phone branch (mount-stable).
function screenFor(path: string | undefined): { key: string; el: ReactElement; tab: boolean } {
  if (path === '/login') return { key: 'login', el: <Login />, tab: false }
  if (path === '/discover') return { key: 'browse', el: <Browse />, tab: true }
  if (path === '/downloads') return { key: 'downloads', el: <Downloads />, tab: true }
  // '/library' and anything else (incl. '/') land on Home.
  return { key: 'home', el: <Home />, tab: true }
}

/**
 * Phone app shell. Fixed to the dynamic viewport (100dvh) so the collapsing URL
 * bar never shifts layout; a single inner region scrolls with momentum; a
 * flush tab bar sits above the home indicator (hidden on /login). Flat
 * monochrome ground — no ambient glow, no gradient chrome.
 */
export default function MobileApp({ path }: { path?: string } = {}) {
  const [joinOpen, setJoinOpen] = useState(false)
  const { key, el, tab } = screenFor(path)

  const ctx = useMemo(() => ({ openJoin: () => setJoinOpen(true), path }), [path])

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
          style={{ paddingBottom: tab ? `calc(var(--sa-b) + 88px)` : `var(--sa-b)` }}
        >
          <div key={key} className="mobile-screen">
            {el}
          </div>
        </div>

        {tab && <TabBar path={path} onParty={() => setJoinOpen(true)} />}
        <JoinSheet open={joinOpen} onClose={() => setJoinOpen(false)} />
      </div>
    </ShellContext.Provider>
  )
}
