import { useState } from 'react'
import { useAuth } from '../context/AuthContext.jsx'

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

  return (
    <div style={{
      position: 'fixed', inset: 0, display: 'grid', placeItems: 'center',
      background: 'var(--bg)',
    }}>
      {/* ambient glow */}
      <div style={{
        position: 'absolute', width: 600, height: 600, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(10,132,255,.12) 0%, transparent 70%)',
        top: '50%', left: '50%', transform: 'translate(-50%,-60%)',
        pointerEvents: 'none',
      }} />

      <div style={{
        position: 'relative', width: 400, maxWidth: '90vw',
        padding: '40px 36px', borderRadius: 26,
        background: 'var(--glass)',
        backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
        border: '1px solid var(--stroke)',
        boxShadow: 'var(--shadow-lg), inset 0 1px 0 var(--hi)',
        animation: 'in .35s cubic-bezier(.2,0,.1,1)',
      }}>
        {/* Logo */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 32 }}>
          <div style={{
            width: 36, height: 36, borderRadius: 11,
            background: 'var(--accent)',
            display: 'grid', placeItems: 'center',
            boxShadow: '0 4px 16px var(--accent-glow)',
          }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="#fff"><path d="M8 5v14l11-7z"/></svg>
          </div>
          <span style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.02em' }}>Watchparty</span>
        </div>

        <div style={{ marginBottom: 24 }}>
          <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-0.03em', marginBottom: 4 }}>Sign in</div>
          <div style={{ fontSize: 13.5, color: 'var(--text2)' }}>Use your Jellyfin credentials</div>
        </div>

        <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <input
            type="text"
            placeholder="Username"
            value={username}
            onChange={e => setUsername(e.target.value)}
            disabled={submitting}
            required
            style={{
              width: '100%', padding: '12px 14px', borderRadius: 13,
              border: '1px solid var(--stroke)', background: 'var(--glass2)',
              color: 'var(--text)', fontSize: 14.5, outline: 'none',
              transition: 'border-color .15s',
            }}
            onFocus={e => e.target.style.borderColor = 'var(--accent)'}
            onBlur={e => e.target.style.borderColor = 'var(--stroke)'}
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            disabled={submitting}
            style={{
              width: '100%', padding: '12px 14px', borderRadius: 13,
              border: '1px solid var(--stroke)', background: 'var(--glass2)',
              color: 'var(--text)', fontSize: 14.5, outline: 'none',
              transition: 'border-color .15s',
            }}
            onFocus={e => e.target.style.borderColor = 'var(--accent)'}
            onBlur={e => e.target.style.borderColor = 'var(--stroke)'}
          />

          {error && (
            <div style={{
              padding: '10px 13px', borderRadius: 11,
              background: 'rgba(255,69,58,.12)', border: '1px solid rgba(255,69,58,.25)',
              color: 'var(--red)', fontSize: 13.5,
            }}>{error}</div>
          )}

          <button
            type="submit"
            disabled={submitting}
            style={{
              marginTop: 4, width: '100%', padding: '13px',
              borderRadius: 13, border: 'none',
              background: submitting ? 'rgba(10,132,255,.5)' : 'var(--accent)',
              color: '#fff', fontSize: 15, fontWeight: 600, cursor: submitting ? 'default' : 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
              transition: 'background .15s',
            }}
          >
            {submitting && (
              <div style={{
                width: 16, height: 16, borderRadius: '50%',
                border: '2px solid rgba(255,255,255,.4)', borderTopColor: '#fff',
                animation: 'spin .8s linear infinite',
              }} />
            )}
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
