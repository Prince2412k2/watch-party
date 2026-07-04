import { useState } from 'react'
import { useAuth } from '../../context/AuthContext.jsx'
import { T, TYPE, R, EASE, BRAND_GRADIENT } from '../theme.js'
import { Icon, Ic } from '../ui/Icon.jsx'

/**
 * Mobile Login (MOBILE-SPEC §3.1). Presentation-only layer over AuthContext —
 * `useAuth().login(username, password)` sets the user, and App.jsx's returnTo
 * effect handles navigation on success (no onSuccess needed). The tab bar is
 * hidden for /login by MobileApp, and the shell paints the ambient ground
 * behind us, so this screen just owns its centered auth hero.
 *
 * Join-by-code lives on Home (behind auth — a party needs user.userId), so the
 * pre-auth Login stays focused on the single sign-in job.
 *
 * Touch/Safari rules honored: inputs are TYPE.input (16px → no iOS auto-zoom),
 * fields/button ≥52px and the eye toggle is a 44px target; safe-area insets pad
 * all four sides; no autoFocus (keeps the keyboard from popping + shifting the
 * centered layout on entry); ≥16px, no hover-only affordances.
 */

// Local single-path glyphs the shared Ic dictionary doesn't carry yet.
const LOCK = 'M6 10V8a6 6 0 1 1 12 0v2 M5 10h14a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1z'
const EYE = 'M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'
const EYE_OFF = 'M9.9 4.24A9.1 9.1 0 0 1 12 4c6.4 0 10 8 10 8a17.6 17.6 0 0 1-2.16 3.19 M6.6 6.6A17.9 17.9 0 0 0 2 12s3.6 7 10 7a9 9 0 0 0 5.4-1.6 M9.9 9.9a3 3 0 0 0 4.2 4.2 M2 2l20 20'
const ALERT = 'M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z M12 9v4 M12 17h.01'

export default function Login() {
  const { login } = useAuth()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [showPw, setShowPw] = useState(false)
  const [focus, setFocus] = useState('')   // '' | 'u' | 'p'
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const canSubmit = !!username.trim() && !busy

  async function submit(e) {
    e.preventDefault()
    if (!username.trim()) return
    setError(''); setBusy(true)
    try { await login(username.trim(), password) }
    catch (err) { setError(err.message || 'Login failed') }
    finally { setBusy(false) }
  }

  const caption = (on) => ({
    ...TYPE.meta, color: on ? T.brand : T.dim, display: 'block',
    marginBottom: 8, transition: `color .16s ${EASE}`,
  })
  const fieldStyle = (on, pad) => ({
    width: '100%', height: 54, padding: `0 ${pad}px 0 46px`, borderRadius: R.md,
    border: `1px solid ${on ? T.brand : T.line2}`,
    background: on ? 'rgba(62,207,126,.06)' : 'rgba(255,255,255,.05)',
    color: T.text, ...TYPE.input, outline: 'none',
    boxShadow: on ? '0 0 0 3px rgba(62,207,126,.14)' : 'none',
    transition: `border-color .16s ${EASE}, box-shadow .16s ${EASE}, background .16s ${EASE}`,
  })
  const lead = { position: 'absolute', left: 14, top: 0, bottom: 0, display: 'grid', placeItems: 'center', pointerEvents: 'none' }

  return (
    <div style={{
      minHeight: '100dvh', display: 'flex', flexDirection: 'column', justifyContent: 'center',
      padding: `calc(var(--sa-t) + 32px) calc(var(--sa-r) + 22px) calc(var(--sa-b) + 28px) calc(var(--sa-l) + 22px)`,
      position: 'relative', overflow: 'hidden',
    }}>
      {/* login-only brand halo behind the mark (shell paints the base ambient) */}
      <div aria-hidden style={{
        position: 'absolute', top: '-4%', left: '50%', transform: 'translateX(-50%)',
        width: 340, height: 340, borderRadius: '50%', background: BRAND_GRADIENT,
        filter: 'blur(96px)', opacity: 0.2, pointerEvents: 'none',
      }} />

      <div style={{
        position: 'relative', width: '100%', maxWidth: 400, margin: '0 auto',
        display: 'flex', flexDirection: 'column', alignItems: 'center', animation: 'up .5s ease both',
      }}>
        {/* app-tile mark — same play-on-gradient language as the Party CTA */}
        <div style={{
          width: 76, height: 76, borderRadius: 22, background: BRAND_GRADIENT,
          display: 'grid', placeItems: 'center', marginBottom: 22,
          boxShadow: '0 18px 44px rgba(62,207,126,.28), inset 0 1px 0 rgba(255,255,255,.45)',
        }}>
          <Icon path={Ic.play} size={34} fill="#0b0d10" stroke="none" />
        </div>

        <div style={{ ...TYPE.meta, letterSpacing: '.3em', color: T.dim, marginBottom: 16 }}>Watchparty</div>
        <h1 style={{ ...TYPE.display, color: T.text, textAlign: 'center', marginBottom: 8 }}>Welcome back</h1>
        <p style={{ ...TYPE.body, color: T.dim, textAlign: 'center', marginBottom: 28, maxWidth: 300 }}>
          Sign in with your Jellyfin account to start the party
        </p>

        <form onSubmit={submit} style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 14 }}>
          <label style={{ display: 'block' }}>
            <span style={caption(focus === 'u')}>Username</span>
            <div style={{ position: 'relative' }}>
              <span style={lead}><Icon path={Ic.user} size={19} stroke={focus === 'u' ? T.brand : T.faint} /></span>
              <input
                type="text" value={username} onChange={(e) => setUsername(e.target.value)}
                onFocus={() => setFocus('u')} onBlur={() => setFocus('')}
                disabled={busy} required
                name="username" autoComplete="username" autoCapitalize="none"
                autoCorrect="off" spellCheck={false} enterKeyHint="next" placeholder="jellyfin username"
                style={fieldStyle(focus === 'u', 16)}
              />
            </div>
          </label>

          <label style={{ display: 'block' }}>
            <span style={caption(focus === 'p')}>Password</span>
            <div style={{ position: 'relative' }}>
              <span style={lead}><Icon path={LOCK} size={19} stroke={focus === 'p' ? T.brand : T.faint} /></span>
              <input
                type={showPw ? 'text' : 'password'} value={password} onChange={(e) => setPassword(e.target.value)}
                onFocus={() => setFocus('p')} onBlur={() => setFocus('')}
                disabled={busy}
                name="password" autoComplete="current-password" enterKeyHint="go" placeholder="••••••••"
                style={fieldStyle(focus === 'p', 50)}
              />
              <button
                type="button" onClick={() => setShowPw((v) => !v)}
                aria-label={showPw ? 'Hide password' : 'Show password'} tabIndex={-1} className="mob-press"
                style={{
                  position: 'absolute', right: 6, top: 0, bottom: 0, width: 44,
                  border: 'none', background: 'transparent', display: 'grid', placeItems: 'center',
                  cursor: 'pointer', color: T.dim,
                }}
              >
                <Icon path={showPw ? EYE_OFF : EYE} size={20} stroke={T.dim} />
              </button>
            </div>
          </label>

          {error && (
            <div role="alert" style={{
              display: 'flex', alignItems: 'center', gap: 9, padding: '11px 14px', borderRadius: R.sm,
              ...TYPE.body, background: 'rgba(255,107,107,.12)', border: '1px solid rgba(255,107,107,.32)', color: T.red,
            }}>
              <Icon path={ALERT} size={17} stroke={T.red} sw={1.8} style={{ flex: '0 0 auto' }} />
              <span style={{ minWidth: 0 }}>{error}</span>
            </div>
          )}

          <button type="submit" disabled={!canSubmit} className="mob-press" style={{
            marginTop: 6, width: '100%', height: 54, borderRadius: R.md, border: 'none',
            background: T.primary, color: T.onLight, ...TYPE.headline, fontWeight: 700, letterSpacing: '.01em',
            cursor: canSubmit ? 'pointer' : 'default', opacity: canSubmit ? 1 : 0.55,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9,
            transition: `opacity .16s ${EASE}`,
          }}>
            {busy && <span style={{ width: 16, height: 16, borderRadius: '50%', border: '2px solid rgba(10,11,13,.3)', borderTopColor: T.onLight, animation: 'spin .8s linear infinite' }} />}
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>

        <p style={{
          ...TYPE.label, fontWeight: 500, color: T.faint, textAlign: 'center', marginTop: 20,
          display: 'flex', gap: 7, justifyContent: 'center', alignItems: 'center',
        }}>
          <Icon path={LOCK} size={14} stroke={T.faint} />
          Sent securely to your Jellyfin server
        </p>
      </div>
    </div>
  )
}
