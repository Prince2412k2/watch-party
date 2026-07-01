import { useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext.jsx'
import { navigate } from '../router.js'

export default function Library() {
  const { user, logout } = useAuth()
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [stack, setStack] = useState([])

  const parentId = stack.length > 0 ? stack[stack.length - 1].id : null

  useEffect(() => {
    setLoading(true)
    setError('')
    const url = parentId ? `/api/library/items/${parentId}/children` : '/api/library/items'
    fetch(url, { credentials: 'include' })
      .then(r => r.ok ? r.json() : Promise.reject(r))
      .then(data => setItems(data))
      .catch(() => setError('Failed to load library'))
      .finally(() => setLoading(false))
  }, [parentId])

  function drillInto(item) {
    setStack(s => [...s, { id: item.Id, name: item.Name, type: item.Type }])
  }

  function goBack() {
    setStack(s => s.slice(0, -1))
  }

  function handleSelect(item) {
    if (item.Type === 'Series' || item.Type === 'Season') drillInto(item)
    else navigate(`/party/new?itemId=${item.Id}`)
  }

  const initials = user?.name?.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2) || '?'

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'var(--bg)', overflowY: 'auto' }}>
      {/* Header */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 20,
        padding: '14px 32px',
        display: 'flex', alignItems: 'center', gap: 16,
        background: 'rgba(6,8,15,.8)',
        backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
        borderBottom: '1px solid var(--stroke)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 32, height: 32, borderRadius: 10,
            background: 'var(--accent)', display: 'grid', placeItems: 'center',
            boxShadow: '0 4px 14px var(--accent-glow)',
          }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="#fff"><path d="M8 5v14l11-7z"/></svg>
          </div>
          <span style={{ fontSize: 17, fontWeight: 700, letterSpacing: '-0.02em' }}>Watchparty</span>
        </div>

        {stack.length > 0 && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'var(--text3)', fontSize: 13.5 }}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m9 18 6-6-6-6"/></svg>
            {stack.map((s, i) => (
              <span key={i} style={{ color: i === stack.length - 1 ? 'var(--text)' : 'var(--text3)' }}>{s.name}</span>
            ))}
          </div>
        )}

        <div style={{ flex: 1 }} />

        {/* Avatar / logout */}
        <div
          onClick={logout}
          title="Sign out"
          style={{
            width: 34, height: 34, borderRadius: '50%',
            background: 'linear-gradient(140deg, var(--accent), #0c1322)',
            display: 'grid', placeItems: 'center',
            fontSize: 12, fontWeight: 700, color: '#fff',
            border: '1px solid var(--stroke)', cursor: 'pointer',
          }}
        >{initials}</div>
      </div>

      {/* Content */}
      <div style={{ maxWidth: 1180, margin: '0 auto', padding: '28px 32px 100px' }}>
        {/* Back button */}
        {stack.length > 0 && (
          <button onClick={goBack} style={{
            display: 'flex', alignItems: 'center', gap: 7,
            padding: '8px 14px', borderRadius: 11, marginBottom: 24,
            border: '1px solid var(--stroke)', background: 'var(--glass2)',
            color: 'var(--text)', fontSize: 13.5, fontWeight: 500, cursor: 'pointer',
            backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
          }}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="m15 18-6-6 6-6"/></svg>
            Back
          </button>
        )}

        {/* Title row */}
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 22 }}>
          <h1 style={{ fontSize: 26, fontWeight: 700, letterSpacing: '-0.03em' }}>
            {stack.length > 0 ? stack[stack.length - 1].name : 'Your Library'}
          </h1>
          {!loading && !error && (
            <span style={{ color: 'var(--text3)', fontSize: 13 }}>
              {stack.length === 0 ? 'Pick something to host a party' : `${items.length} items`}
            </span>
          )}
        </div>

        {/* Error */}
        {error && (
          <div style={{
            padding: '12px 16px', borderRadius: 12, marginBottom: 20,
            background: 'rgba(255,69,58,.1)', border: '1px solid rgba(255,69,58,.2)',
            color: 'var(--red)', fontSize: 14,
          }}>{error}</div>
        )}

        {/* Loading skeleton */}
        {loading && (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(168px, 1fr))', gap: '22px 18px' }}>
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} style={{
                aspectRatio: '2/3', borderRadius: 16,
                background: 'linear-gradient(100deg, var(--glass) 30%, var(--glass2) 50%, var(--glass) 70%)',
                backgroundSize: '200% 100%',
                animation: 'shim 1.3s linear infinite',
                border: '1px solid var(--stroke)',
              }} />
            ))}
          </div>
        )}

        {/* Grid */}
        {!loading && !error && (
          <>
            {items.length === 0 && (
              <p style={{ color: 'var(--text3)', fontSize: 14.5 }}>No media found.</p>
            )}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(168px, 1fr))', gap: '22px 18px' }}>
              {items.map(item => (
                <MediaCard key={item.Id} item={item} onSelect={handleSelect} />
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function MediaCard({ item, onSelect }) {
  const isLeaf = item.Type !== 'Series' && item.Type !== 'Season'
  const [hovered, setHovered] = useState(false)

  const tagLabel = item.Type === 'Series' ? 'Series'
    : item.Type === 'Season' ? `S${item.IndexNumber}`
    : item.Type === 'Episode' ? `Ep ${item.IndexNumber}`
    : item.Type

  return (
    <div
      onClick={() => onSelect(item)}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{ cursor: 'pointer' }}
    >
      <div style={{
        position: 'relative', aspectRatio: '2/3', borderRadius: 16,
        overflow: 'hidden',
        border: '1px solid var(--stroke)',
        boxShadow: hovered ? '0 16px 40px rgba(0,0,0,.55)' : 'var(--shadow)',
        transform: hovered ? 'translateY(-5px)' : 'none',
        transition: 'transform .22s cubic-bezier(.2,0,.1,1), box-shadow .22s',
        background: '#0c1322',
      }}>
        <img
          src={`/api/library/image/${item.Id}`}
          alt={item.Name}
          style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }}
          onError={e => { e.target.style.opacity = 0 }}
        />
        <div style={{
          position: 'absolute', inset: 0,
          background: 'linear-gradient(180deg, transparent 45%, rgba(0,0,0,.65))',
        }} />

        {/* Tag */}
        <div style={{
          position: 'absolute', top: 10, left: 10,
          padding: '4px 9px', borderRadius: 7,
          fontSize: 10.5, fontWeight: 700, letterSpacing: '.05em', textTransform: 'uppercase',
          background: 'rgba(255,255,255,.15)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
          color: '#fff', border: '1px solid rgba(255,255,255,.2)',
        }}>{tagLabel}</div>

        {/* Hover CTA */}
        <div style={{
          position: 'absolute', inset: 0, display: 'grid', placeItems: 'center',
          opacity: hovered ? 1 : 0, transition: 'opacity .2s',
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 7,
            padding: '9px 16px', borderRadius: 11,
            background: 'var(--accent)', color: '#fff',
            fontSize: 13, fontWeight: 600,
            boxShadow: '0 6px 22px var(--accent-glow)',
          }}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="#fff"><path d="M8 5v14l11-7z"/></svg>
            {isLeaf ? 'Start party' : 'Open'}
          </div>
        </div>

        {/* Title */}
        <div style={{ position: 'absolute', left: 12, right: 12, bottom: 11 }}>
          <div style={{
            fontSize: 14, fontWeight: 600, lineHeight: 1.2,
            color: '#fff', textShadow: '0 1px 6px rgba(0,0,0,.5)',
          }}>{item.Name}</div>
          {item.ProductionYear && (
            <div style={{ fontSize: 11.5, opacity: .75, marginTop: 2, color: '#fff' }}>{item.ProductionYear}</div>
          )}
        </div>
      </div>
    </div>
  )
}
