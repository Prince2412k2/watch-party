import { useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { AuthProvider, useAuth } from './context/AuthContext'
import { navigate } from './router'
import { usePhone } from './hooks/useIsMobile'
import Login from './pages/Login'
import Library from './pages/Library'
import FindDownload from './pages/FindDownload'
import Downloads from './pages/Downloads'
import DesktopApp from './pages/DesktopApp'
import MobileApp from './mobile/MobileApp'
import { WatchRoute } from './mobile/screens/Watch'
import { PartyProvider } from './context/PartyContext'
import { WebShell } from './components/WebShell'

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

  useEffect(() => {
    if (path !== '/login') {
      sessionStorage.setItem('returnTo', path + window.location.search)
      navigate('/login')
    }
  }, [path])

  if (path !== '/login') return null
  return <Login onSuccess={() => {}} />
}

function AuthenticatedRouter({ user }: { user: NonNullable<ReturnType<typeof useAuth>['user']> }) {
  const path = useRoute()
  const phone = usePhone()
  const { logout } = useAuth()

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
  // Handles /party/new?itemId=xxx and /party/:id. See mobile/screens/Watch.jsx.
  if (path.startsWith('/party/')) return <WatchRoute path={path} />

  // (2) Phone shell — the new mobile presentation tree (Login/Home/Browse/
  // Downloads). Coarse-pointer gated, so a narrow desktop window keeps desktop.
  if (phone) return <MobileApp path={path} />

  // (3) Desktop — existing switch, unchanged.
  const initials = user.name?.split(' ').map(part => part[0]).join('').toUpperCase().slice(0, 2) || '?'
  const shell = (active: 'movies' | 'series' | 'discover' | 'downloads', content: ReactNode) => (
    <WebShell active={active} initials={initials} profileName={user.name} logout={logout}>{content}</WebShell>
  )

  if (path === '/library' || path === '/movies') return shell('movies', <Library libraryType="movies" />)
  if (path === '/series') return shell('series', <Library libraryType="series" />)
  if (path === '/discover') return shell('discover', <FindDownload />)
  if (path === '/downloads') return shell('downloads', <Downloads />)
  if (path === '/desktop-app') return <DesktopApp />

  return <div>404</div>
}

export default function App() {
  return (
    <AuthProvider>
      <Router />
    </AuthProvider>
  )
}
