import { Component, Suspense, lazy, useEffect, useState } from 'react'
import type { ErrorInfo, ReactNode } from 'react'
import { AuthProvider, useAuth } from './context/AuthContext'
import { navigate } from './router'
import { usePhone } from './hooks/useIsMobile'
import { PartyProvider } from './context/PartyContext'
import { DownloadsProvider } from './context/DownloadsContext'

/* Route-level code splitting. Every screen used to be a static import, so the
 * whole app — video pipeline (videojs + hls.js), WebRTC (livekit-client),
 * react-rnd, qrcode, the phone tree and the desktop tree — shipped in one
 * 2.6 MB chunk before the login form could paint. Each entry below becomes its
 * own chunk that is fetched when its route is first visited.
 *
 * `lazy()` is called at module scope so the component identity is stable across
 * renders: once a chunk has loaded, rendering it is synchronous and Suspense
 * never re-suspends. That is what keeps WatchRoute mount-stable through a
 * usePhone() flip on rotation (see the party branch below). */
const Login = lazy(() => import('./pages/Login'))
const PhoneLogin = lazy(() => import('./mobile/screens/Login'))
const Library = lazy(() => import('./pages/Library'))
const FindDownload = lazy(() => import('./pages/FindDownload'))
const Downloads = lazy(() => import('./pages/Downloads'))
const DesktopApp = lazy(() => import('./pages/DesktopApp'))
const Profile = lazy(() => import('./pages/Profile'))
const MobileApp = lazy(() => import('./mobile/MobileApp'))
const WatchRoute = lazy(() => import('./mobile/screens/Watch'))
const WebShell = lazy(() => import('./components/WebShell').then(m => ({ default: m.WebShell })))

/* Splitting routes into chunks introduces one failure mode a single bundle did
 * not have: after a redeploy, an open tab still holds the previous index.html and
 * asks for a chunk hash that no longer exists. Without a boundary that rejection
 * is unhandled and the screen just goes blank. One reload picks up the new
 * index.html; the flag stops a reload loop if the fetch is failing for any other
 * reason (offline, proxy error), which then shows a plain retry instead. */
const RELOADED_KEY = 'watchparty-chunk-reload'

class ChunkBoundary extends Component<{ children?: ReactNode }, { failed: boolean }> {
  state = { failed: false }

  static getDerivedStateFromError() {
    return { failed: true }
  }

  componentDidCatch(error: Error, _info: ErrorInfo) {
    const stale = /dynamically imported module|Importing a module script failed|Loading chunk/i.test(error?.message ?? '')
    if (!stale || sessionStorage.getItem(RELOADED_KEY)) return
    sessionStorage.setItem(RELOADED_KEY, '1')
    window.location.reload()
  }

  render() {
    if (!this.state.failed) return this.props.children
    return (
      <div style={{ display: 'grid', placeItems: 'center', minHeight: '100dvh', padding: 24, textAlign: 'center', font: '500 15px/1.5 system-ui, sans-serif', color: '#f4f4f5', background: '#0a0a0b' }}>
        <div>
          <p style={{ margin: '0 0 16px' }}>This page couldn’t finish loading.</p>
          <button onClick={() => { sessionStorage.removeItem(RELOADED_KEY); window.location.reload() }}
            style={{ padding: '10px 18px', borderRadius: 999, border: '1px solid rgba(255,255,255,.14)', background: '#f4f4f5', color: '#0a0a0b', font: '700 14px system-ui, sans-serif', cursor: 'pointer' }}>
            Reload
          </button>
        </div>
      </div>
    )
  }
}

function useRoute() {
  const [path, setPath] = useState(window.location.pathname)
  useEffect(() => {
    const handler = () => setPath(window.location.pathname)
    window.addEventListener('popstate', handler)
    return () => window.removeEventListener('popstate', handler)
  }, [])
  return path
}

function Router() {
  const { user, loading } = useAuth()

  if (loading) return null
  if (!user) return <UnauthenticatedRouter />

  return (
    <PartyProvider userId={user.userId}>
      <AuthenticatedRouter user={user} />
    </PartyProvider>
  )
}

function UnauthenticatedRouter() {
  const path = useRoute()
  const phone = usePhone()

  useEffect(() => {
    if (path !== '/login') {
      sessionStorage.setItem('returnTo', path + window.location.search)
      navigate('/login')
    }
  }, [path])

  if (path !== '/login') return null
  // The phone-native sign-in screen (52px targets, 16px inputs so iOS doesn't
  // auto-zoom, safe-area padding) was built but never reachable: the only branch
  // that rendered it was MobileApp's '/login' case, and MobileApp is only ever
  // mounted for a signed-IN member. Sign-in is pre-auth, so it belongs here.
  return (
    <Suspense fallback={null}>
      {phone ? <PhoneLogin /> : <Login onSuccess={() => {}} />}
    </Suspense>
  )
}

function AuthenticatedRouter({ user }: { user: NonNullable<ReturnType<typeof useAuth>['user']> }) {
  const path = useRoute()
  const phone = usePhone()
  const { logout, profile } = useAuth()

  useEffect(() => {
    if (path === '/login') {
      const saved = sessionStorage.getItem('returnTo')
      sessionStorage.removeItem('returnTo')
      const returnTo = saved && saved !== '/' && !saved.startsWith('/login') ? saved : '/library'
      navigate(returnTo)
    }
  }, [path])

  useEffect(() => {
    if (path === '/') navigate('/library')
  }, [path])

  if (path === '/' || path === '/login') return null

  // (1) Party routes — ONE shared, mount-stable element for desktop AND phone.
  // Rendered above the device branch so a usePhone() flip on rotation never
  // remounts a live watch session (which would tear down LiveKit + useSyncPlay).
  // Handles /party/new?itemId=xxx and /party/:id. See mobile/screens/Watch.tsx.
  // Deliberately OUTSIDE DownloadsProvider: a watch session has no download UI,
  // and must not be polling qBittorrent/*arr while the player is running.
  if (path.startsWith('/party/')) return <Suspense fallback={null}><WatchRoute path={path} /></Suspense>

  // Installer downloads must remain reachable from any device size.
  if (path === '/desktop-app') return <Suspense fallback={null}><DesktopApp /></Suspense>

  // One profile editor for both device sizes — it is a full-screen page on each,
  // and rendering it above the phone branch keeps a rotation from remounting it
  // (and discarding unsaved edits).
  if (path === '/profile') return <Suspense fallback={null}><Profile /></Suspense>

  // (2) Phone shell — the mobile presentation tree (Home/Browse/Downloads).
  // Coarse-pointer gated, so a narrow desktop window keeps desktop.
  // (3) Desktop — the tab switch, wrapped in the same shell.
  const shell = (active: 'movies' | 'series' | 'discover' | 'downloads', content: ReactNode) => (
    <WebShell
      active={active} userId={user.userId} profileAvatar={profile?.avatar}
      profileName={profile?.displayName || user.name} logout={logout}
    >{content}</WebShell>
  )

  const screen = phone ? <MobileApp path={path} />
    : path === '/library' || path === '/movies' ? shell('movies', <Library libraryType="movies" />)
    : path === '/series' ? shell('series', <Library libraryType="series" />)
    : path === '/discover' ? shell('discover', <FindDownload />)
    : path === '/downloads' ? shell('downloads', <Downloads />)
    : <div>404</div>

  // Every browsing surface shares ONE set of download pollers (see
  // DownloadsContext) rather than each screen mounting its own.
  return (
    <DownloadsProvider>
      <Suspense fallback={null}>{screen}</Suspense>
    </DownloadsProvider>
  )
}

export default function App() {
  return (
    <ChunkBoundary>
      <AuthProvider>
        <Router />
      </AuthProvider>
    </ChunkBoundary>
  )
}
