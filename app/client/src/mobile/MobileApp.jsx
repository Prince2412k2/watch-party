import { useMemo, useState } from 'react'
import { T, AMBIENT } from './theme.js'
import { ShellContext } from './shellContext.js'
import { TabBar } from './TabBar.jsx'
import { JoinSheet } from './JoinSheet.jsx'
import Login from './screens/Login.jsx'
import Home from './screens/Home.jsx'
import Browse from './screens/Browse.jsx'
import Downloads from './screens/Downloads.jsx'

// Route → shell screen. Party routes never reach MobileApp — App.jsx renders
// them through the shared WatchRoute above the phone branch (mount-stable).
function screenFor(path) {
  if (path === '/login') return { key: 'login', el: <Login />, tab: false }
  if (path === '/discover') return { key: 'browse', el: <Browse />, tab: true }
  if (path === '/downloads') return { key: 'downloads', el: <Downloads />, tab: true }
  // '/library' and anything else (incl. '/') land on Home.
  return { key: 'home', el: <Home />, tab: true }
}

/**
 * Phone app shell. Fixed to the dynamic viewport (100dvh) so the collapsing URL
 * bar never shifts layout; a single inner region scrolls with momentum; a
 * floating glass tab bar sits above the home indicator (hidden on /login). The
 * ambient backdrop and <GlassDefs/> (mounted at app root) give every screen the
 * same Midnight-Glass ground.
 */
export default function MobileApp({ path }) {
  const [joinOpen, setJoinOpen] = useState(false)
  const { key, el, tab } = screenFor(path)

  const ctx = useMemo(() => ({ openJoin: () => setJoinOpen(true), path }), [path])

  return (
    <ShellContext.Provider value={ctx}>
      <div className="mobile-shell" style={{ color: T.text }}>
        {/* ambient ground — dual radial glows over the page bg */}
        <div aria-hidden style={{ position: 'absolute', inset: 0, background: T.bg, pointerEvents: 'none' }} />
        <div aria-hidden style={{ position: 'absolute', inset: 0, background: AMBIENT, pointerEvents: 'none' }} />

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
