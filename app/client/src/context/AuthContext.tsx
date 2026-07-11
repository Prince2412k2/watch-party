import { createContext, useContext, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import type { AuthContextValue, AuthUser } from '../types'
import { errorMessage, isAuthUser } from '../guards'
import { apiJson } from '../types/guards'

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children?: ReactNode } = {}) {
  const [user, setUser] = useState<AuthUser | null>(null)
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
    <AuthContext.Provider value={{ user, loading, login, logout }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth must be used within AuthProvider')
  return value
}
