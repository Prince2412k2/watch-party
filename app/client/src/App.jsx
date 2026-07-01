import { useEffect, useState } from 'react'
import { AuthProvider, useAuth } from './context/AuthContext.jsx'
import { PartyProvider } from './context/PartyContext.jsx'
import { navigate } from './router.js'
import Login from './pages/Login.jsx'
import Library from './pages/Library.jsx'
import Party from './pages/Party.jsx'

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

  if (path === '/login') return <Login onSuccess={() => {
    // onSuccess is a fallback — the useEffect above handles navigation
    // once user state is committed. Both paths are safe to coexist.
  }} />
  if (path === '/library') return <Library />

  // /party/new?itemId=xxx  or  /party/:id
  if (path.startsWith('/party/')) {
    const segment = path.slice('/party/'.length)
    const qs = new URLSearchParams(window.location.search)
    if (segment === 'new') {
      return (
        <PartyProvider userId={user.userId}>
          <Party isNew itemId={qs.get('itemId')} />
        </PartyProvider>
      )
    }
    return (
      <PartyProvider userId={user.userId}>
        <Party partyId={segment} />
      </PartyProvider>
    )
  }

  return <div>404</div>
}

export default function App() {
  return (
    <AuthProvider>
      <Router />
    </AuthProvider>
  )
}
