import { createContext, useContext, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import type { AuthContextValue, AuthUser, UserProfile } from '../types.ts'
import { errorMessage, isAuthUser, isUserProfile } from '../guards.ts'
import { initializeOffline, OFFLINE_SUPPORTED, setOwner } from '../offline/client.ts'
import { apiJson } from '../types/guards.ts'

const AuthContext = createContext<AuthContextValue | null>(null)
function rememberOfflineAccount(user: AuthUser | null) {
  try {
    if (user) localStorage.setItem('watchparty-offline-account', JSON.stringify({ userId: user.userId, name: user.name }))
    else localStorage.removeItem('watchparty-offline-account')
  } catch { /* A browser that blocks storage can still sign in and stream. */ }
}

export function AuthProvider({ children }: { children?: ReactNode } = {}) {
  const [user, setUser] = useState<AuthUser | null>(null)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/auth/me', { credentials: 'include' })
      .then(async r => {
        if (!r.ok) { rememberOfflineAccount(null); if (OFFLINE_SUPPORTED) void setOwner(null).catch(() => {}); return null }
        const value = await apiJson(r)
        return value
      })
      .then((value: unknown) => {
        const next = isAuthUser(value) ? value : null
        setUser(next)
        rememberOfflineAccount(next)
      })
      .catch(() => {
        // This remembered identity unlocks only local files. Server APIs still
        // require the real session; never restore privileges from disk.
        try { const cached = JSON.parse(localStorage.getItem('watchparty-offline-account') || 'null'); setUser(isAuthUser(cached) ? {...cached,isAdmin:false,offline:true} : null) }
        catch { setUser(null) }
      })
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => {
    if (!user || !OFFLINE_SUPPORTED) return
    void initializeOffline(user.userId).catch(() => {})
    const timer = setInterval(() => { void initializeOffline(user.userId).catch(() => {}) }, 60 * 60 * 1000)
    return () => clearInterval(timer)
  }, [user?.userId])

  // The signed-in user's own profile follows their identity. Everyone else's
  // arrives on party state; this is only what we need to draw *them* — their
  // own account control, and the profile page's starting point. A failure here
  // is not fatal: no profile is the same as no customisation.
  useEffect(() => {
    if (!user) {
      setProfile(null)
      return
    }
    let active = true
    fetch('/api/profile', { credentials: 'include' })
      .then(async response => (response.ok ? apiJson(response) : null))
      .then(value => {
        if (active) setProfile(isUserProfile(value) ? value : null)
      })
      .catch(() => { if (active) setProfile(null) })
    return () => { active = false }
  }, [user?.userId])

  async function login(username: string, password: string): Promise<AuthUser> {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    })
    const data = await apiJson(res)
    if (!res.ok) throw new Error(errorMessage(data, 'Login failed'))
    if (!isAuthUser(data)) throw new Error('Login returned an invalid user')
    setUser(data)
    rememberOfflineAccount(data)
    return data
  }

  async function logout() {
    try { await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' }) }
    finally {
      setUser(null)
      rememberOfflineAccount(null)
      if (OFFLINE_SUPPORTED) await setOwner(null).catch(() => {})
    }
  }

  return (
    <AuthContext.Provider value={{ user, profile, loading, login, logout, applyProfile: setProfile }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth must be used within AuthProvider')
  return value
}
