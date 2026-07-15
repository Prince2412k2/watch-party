import { useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { jget } from '../lib/api'
import { apiJson, arrayOf, isRecord } from '../types/guards'
import { fmtSize } from '../lib/format'

const MONO = "'JetBrains Mono', ui-monospace, monospace"

type Platform = 'macos' | 'windows'
type Build = { platform: Platform; filename: string; size: number; url: string }

const isBuild = (value: unknown): value is Build =>
  isRecord(value) && (value.platform === 'macos' || value.platform === 'windows') &&
  typeof value.filename === 'string' && typeof value.url === 'string'

const PLATFORM_LABEL: Record<Platform, string> = { macos: 'macOS', windows: 'Windows' }

export default function DesktopApp() {
  const { user } = useAuth()
  const [builds, setBuilds] = useState<Build[] | null>(null)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!user) return
    jget('/api/downloads')
      .then(async (r) => {
        if (!r.ok) throw new Error('Could not load the latest builds')
        const data = await apiJson(r)
        setBuilds(isRecord(data) ? arrayOf(data.builds, isBuild) : [])
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Could not load the latest builds'))
  }, [user])

  if (!user) return null // App-level router redirects to /login

  return (
    <div style={{ position: 'fixed', inset: 0, display: 'grid', placeItems: 'center', background: 'var(--bg)', color: 'var(--text)', overflow: 'auto' }}>
      <div style={{ width: 480, maxWidth: '90vw', padding: '48px 36px' }}>
        <div style={{ fontSize: 13, fontWeight: 700, letterSpacing: '-.01em', marginBottom: 36, textAlign: 'center' }}>
          Watchparty
        </div>

        <h1 style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-.02em', lineHeight: 1.15, marginBottom: 8 }}>
          Desktop app
        </h1>
        <p style={{ fontSize: 15, fontWeight: 500, color: 'var(--dim)', marginBottom: 28 }}>
          Download the latest build for your platform
        </p>

        {error && (
          <div role="alert" style={{ padding: '10px 14px', borderRadius: 8, background: 'rgba(224,101,94,.12)', border: '1px solid rgba(224,101,94,.35)', color: 'var(--danger)', fontSize: 13.5, fontWeight: 500, marginBottom: 16 }}>
            {error}
          </div>
        )}

        {!error && builds === null && (
          <div style={{ fontSize: 14, color: 'var(--dim)' }}>Loading…</div>
        )}

        {!error && builds !== null && builds.length === 0 && (
          <div style={{ fontSize: 14, color: 'var(--dim)' }}>No builds are available right now.</div>
        )}

        {!error && builds !== null && builds.length > 0 && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {builds.map((b) => (
              <a key={b.filename} href={b.url} download style={{
                display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16,
                padding: '16px 18px', borderRadius: 12, border: '1px solid var(--line)', background: 'var(--surface)',
                textDecoration: 'none', color: 'var(--text)', transition: 'background .15s',
              }}
                onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--surface2)' }}
                onMouseLeave={(e) => { e.currentTarget.style.background = 'var(--surface)' }}>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontSize: 15, fontWeight: 700 }}>{PLATFORM_LABEL[b.platform]}</div>
                  <div style={{ fontSize: 12.5, color: 'var(--faint)', fontFamily: MONO, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {b.filename} · {fmtSize(b.size)}
                  </div>
                </div>
                <span style={{
                  flexShrink: 0, padding: '9px 18px', borderRadius: 999, border: 'none',
                  background: 'var(--primary)', color: 'var(--onPrimary)', fontSize: 13, fontWeight: 700, letterSpacing: '.01em',
                }}>Download</span>
              </a>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
