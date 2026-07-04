import { useState } from 'react'
import { useAuth } from '../context/AuthContext.jsx'

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
    width: '100%', padding: '14px 16px', borderRadius: 10,
    border: '1px solid rgba(255,255,255,.12)', background: 'rgba(255,255,255,.04)',
    color: '#EDEFF2', fontSize: 15, outline: 'none', transition: 'border-color .15s, background .15s',
  }

  return (
    <div style={{ position: 'fixed', inset: 0, display: 'grid', gridTemplateColumns: '1fr', placeItems: 'center', background: '#08080a', color: '#EDEFF2', overflow: 'hidden' }}>
      {/* cinematic ground: subtle top glow + faint grain via layered gradients */}
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(120% 80% at 50% -10%, rgba(90,96,110,.28), transparent 60%)' }} />
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', opacity: .5,
        background: 'radial-gradient(60% 50% at 80% 110%, rgba(60,66,80,.25), transparent 60%)' }} />

      <div style={{ position: 'relative', width: 380, maxWidth: '90vw', padding: '4px 8px', animation: 'up .5s ease both' }}>
        {/* Wordmark */}
        <div style={{ fontSize: 13, fontWeight: 800, letterSpacing: '.28em', textTransform: 'uppercase', color: 'rgba(255,255,255,.55)', marginBottom: 40 }}>
          Watchparty
        </div>

        <h1 style={{ fontSize: 34, fontWeight: 800, letterSpacing: '-.035em', lineHeight: 1.05, marginBottom: 10 }}>
          Welcome back
        </h1>
        <p style={{ fontSize: 14.5, color: 'rgba(255,255,255,.5)', marginBottom: 34 }}>
          Sign in with your Jellyfin account
        </p>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <label style={{ display: 'block' }}>
            <span style={{ display: 'block', fontFamily: MONO, fontSize: 10.5, letterSpacing: '.14em', textTransform: 'uppercase', color: 'rgba(255,255,255,.4)', marginBottom: 7 }}>Username</span>
            <input type="text" value={username} onChange={e => setUsername(e.target.value)} disabled={submitting} required autoComplete="username" autoFocus
              style={field}
              onFocus={e => { e.target.style.borderColor = 'rgba(255,255,255,.4)'; e.target.style.background = 'rgba(255,255,255,.06)' }}
              onBlur={e => { e.target.style.borderColor = 'rgba(255,255,255,.12)'; e.target.style.background = 'rgba(255,255,255,.04)' }} />
          </label>

          <label style={{ display: 'block' }}>
            <span style={{ display: 'block', fontFamily: MONO, fontSize: 10.5, letterSpacing: '.14em', textTransform: 'uppercase', color: 'rgba(255,255,255,.4)', marginBottom: 7 }}>Password</span>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} disabled={submitting} autoComplete="current-password"
              style={field}
              onFocus={e => { e.target.style.borderColor = 'rgba(255,255,255,.4)'; e.target.style.background = 'rgba(255,255,255,.06)' }}
              onBlur={e => { e.target.style.borderColor = 'rgba(255,255,255,.12)'; e.target.style.background = 'rgba(255,255,255,.04)' }} />
          </label>

          {error && (
            <div role="alert" style={{ padding: '10px 14px', borderRadius: 8, background: 'rgba(220,60,60,.12)', border: '1px solid rgba(220,60,60,.3)', color: 'rgb(240,170,170)', fontSize: 13.5 }}>
              {error}
            </div>
          )}

          <button type="submit" disabled={submitting} style={{
            marginTop: 12, width: '100%', padding: '14px', borderRadius: 10, border: 'none',
            background: '#EDEFF2', color: '#0a0a0c', fontSize: 15, fontWeight: 700, letterSpacing: '.01em',
            cursor: submitting ? 'default' : 'pointer', opacity: submitting ? 0.7 : 1,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, transition: 'opacity .15s, transform .12s',
          }}
            onMouseDown={e => { if (!submitting) e.currentTarget.style.transform = 'scale(.985)' }}
            onMouseUp={e => e.currentTarget.style.transform = 'scale(1)'}
            onMouseLeave={e => e.currentTarget.style.transform = 'scale(1)'}>
            {submitting && <span style={{ width: 15, height: 15, borderRadius: '50%', border: '2px solid rgba(10,10,12,.35)', borderTopColor: '#0a0a0c', animation: 'spin .8s linear infinite' }} />}
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
