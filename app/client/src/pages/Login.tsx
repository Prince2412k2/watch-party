import { useState } from 'react'
import { useAuth } from '../context/AuthContext'

const MONO = "'JetBrains Mono', ui-monospace, monospace"

export default function Login({ onSuccess }) {
  const { login } = useAuth()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  async function handleSubmit(e) {
    e.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      await login(username, password)
      onSuccess?.()
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  const field = {
    width: '100%', padding: '13px 16px', borderRadius: 10, boxSizing: 'border-box',
    border: '1px solid var(--line2)', background: 'var(--bg)',
    color: 'var(--text)', fontSize: 15, outline: 'none', transition: 'border-color .15s',
  }

  return (
    <div style={{ position: 'fixed', inset: 0, display: 'grid', placeItems: 'center', background: 'var(--bg)', color: 'var(--text)', overflow: 'hidden' }}>
      <div style={{ width: 380, maxWidth: '90vw', padding: '48px 36px', borderRadius: 16, background: 'var(--surface)', border: '1px solid var(--line)' }}>
        <div style={{ fontSize: 13, fontWeight: 700, letterSpacing: '-.01em', color: 'var(--text)', marginBottom: 44, textAlign: 'center' }}>
          Watchparty
        </div>

        <h1 style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-.02em', lineHeight: 1.15, marginBottom: 8 }}>
          Welcome back
        </h1>
        <p style={{ fontSize: 15, fontWeight: 500, color: 'var(--dim)', marginBottom: 28 }}>
          Sign in with your Jellyfin account
        </p>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <label style={{ display: 'block' }}>
            <span style={{ display: 'block', fontFamily: MONO, fontSize: 11.5, letterSpacing: '.14em', textTransform: 'uppercase', fontWeight: 700, color: 'var(--faint)', marginBottom: 8 }}>Username</span>
            <input type="text" value={username} onChange={e => setUsername(e.target.value)} disabled={submitting} required autoComplete="username" autoFocus
              style={field}
              onFocus={e => { e.target.style.borderColor = 'var(--text)' }}
              onBlur={e => { e.target.style.borderColor = 'var(--line2)' }} />
          </label>

          <label style={{ display: 'block' }}>
            <span style={{ display: 'block', fontFamily: MONO, fontSize: 11.5, letterSpacing: '.14em', textTransform: 'uppercase', fontWeight: 700, color: 'var(--faint)', marginBottom: 8 }}>Password</span>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} disabled={submitting} autoComplete="current-password"
              style={field}
              onFocus={e => { e.target.style.borderColor = 'var(--text)' }}
              onBlur={e => { e.target.style.borderColor = 'var(--line2)' }} />
          </label>

          {error && (
            <div role="alert" style={{ padding: '10px 14px', borderRadius: 8, background: 'rgba(224,101,94,.12)', border: '1px solid rgba(224,101,94,.35)', color: 'var(--danger)', fontSize: 13.5, fontWeight: 500 }}>
              {error}
            </div>
          )}

          <button type="submit" disabled={submitting} style={{
            marginTop: 8, width: '100%', padding: '14px', borderRadius: 999, border: 'none',
            background: 'var(--primary)', color: 'var(--onPrimary)', fontSize: 13.5, fontWeight: 700, letterSpacing: '.01em',
            cursor: submitting ? 'default' : 'pointer', opacity: submitting ? 0.7 : 1,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, transition: 'opacity .15s, transform .15s cubic-bezier(.2,.8,.2,1)',
          }}
            onMouseEnter={e => { if (!submitting) e.currentTarget.style.transform = 'scale(1.02)' }}
            onMouseLeave={e => { e.currentTarget.style.transform = 'scale(1)' }}>
            {submitting && <span style={{ width: 14, height: 14, borderRadius: '50%', border: '2px solid rgba(10,10,11,.35)', borderTopColor: 'var(--onPrimary)', animation: 'spin .8s linear infinite' }} />}
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
