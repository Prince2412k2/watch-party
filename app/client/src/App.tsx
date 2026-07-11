import { useEffect, useState } from 'react'
import { AuthProvider, useAuth } from './context/AuthContext'
import { navigate } from './router'
import { GlassDefs } from './glass'
import { usePhone } from './hooks/useIsMobile'
import Login from './pages/Login'
import Library from './pages/Library'
import FindDownload from './pages/FindDownload'
import Downloads from './pages/Downloads'
import MobileApp from './mobile/MobileApp'
import { WatchRoute } from './mobile/screens/Watch'

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
  const path = useRoute()
  const phone = usePhone()

  // Send the root path to the library
  useEffect(() => {
    if (!loading && user && path === '/') navigate('/library')
  }, [user, loading, path])

  // Redirect to login when not authenticated
  useEffect(() => {
    if (!loading && !user && path !== '/login') {
      sessionStorage.setItem('returnTo', path + window.location.search)
      navigate('/login')
    }
  }, [user, loading, path])

  // After login, user state is set — navigate to the saved destination
  useEffect(() => {
    if (!loading && user && path === '/login') {
      const saved = sessionStorage.getItem('returnTo')
      sessionStorage.removeItem('returnTo')
      // Never bounce back to a non-page (root or the login screen itself)
      const returnTo = saved && saved !== '/' && !saved.startsWith('/login') ? saved : '/library'
      navigate(returnTo)
    }
  }, [user, loading, path])

  if (loading) return null
  if (!user && path !== '/login') return null
  if (path === '/') return null

  // (1) Party routes — ONE shared, mount-stable element for desktop AND phone.
  // Rendered above the device branch so a usePhone() flip on rotation never
  // remounts a live watch session (which would tear down LiveKit + useSyncPlay).
  // Handles /party/new?itemId=xxx and /party/:id. See mobile/screens/Watch.jsx.
  if (path.startsWith('/party/')) return <WatchRoute user={user} path={path} />

  // (2) Phone shell — the new mobile presentation tree (Login/Home/Browse/
  // Downloads). Coarse-pointer gated, so a narrow desktop window keeps desktop.
  if (phone) return <MobileApp path={path} />

  // (3) Desktop — existing switch, unchanged.
  if (path === '/login') return <Login onSuccess={() => {
    // onSuccess is a fallback — the useEffect above handles navigation
    // once user state is committed. Both paths are safe to coexist.
  }} />
  if (path === '/library') return <Library />
  if (path === '/discover') return <FindDownload />
  if (path === '/downloads') return <Downloads />

  return <div>404</div>
}

export default function App() {
  return (
    <AuthProvider>
      <GlassDefs />
      <Router />
    </AuthProvider>
  )
}
