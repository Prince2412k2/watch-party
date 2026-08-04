import { createContext, useContext, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import type { AuthContextValue, AuthUser, UserProfile } from '../types'
import { errorMessage, isAuthUser, isUserProfile } from '../guards'
import { apiJson } from '../types/guards'

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children?: ReactNode } = {}) {
  const [user, setUser] = useState<AuthUser | null>(null)
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/auth/me', { credentials: 'include' })
      .then(async r => {
        if (!r.ok) return null
        const value = await apiJson(r)
        return value
      })
      .then((value: unknown) => setUser(isAuthUser(value) ? value : null))
      .catch(() => setUser(null))
      .finally(() => setLoading(false))
  }, [])

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
    return data
  }

  async function logout() {
    await fetch('/api/auth/logout', { method: 'POST', credentials: 'include' })
    setUser(null)
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
