import { useState } from 'react'
import type { CSSProperties, ReactNode } from 'react'
import { T, R } from '../theme'

// Same-origin Jellyfin art. type ∈ Primary | Thumb | Backdrop.
export const imageUrl = (id: string | number, type = 'Primary') => `/api/library/image/${id}?type=${type}`

/**
 * Session-wide 404 guard (ported from Library's `failedArt`). A missing image is
 * recorded here and NEVER re-requested — even across remounts — which is what
 * prevents the runaway 404 storm when scrolling a wall of posters. Bounded to
 * one request per art URL. Exported so any mobile surface shares one set.
 */
export const failedArt = new Set<string>()

/**
 * Robust <img>. Tries `type`, then optional `fallback` {id,type}, then renders
 * a neutral placeholder. Any failure is memoised in `failedArt`.
 */
type ArtRef = { id: string | number; type?: string }
export function Img({ id, type = 'Primary', fallback, style, alt = '', className }: { id?: string | number; type?: string; fallback?: ArtRef; style?: CSSProperties; alt?: string; className?: string } = {}) {
  const [, force] = useState(0)
  const candidates: ArtRef[] = [{ id, type }, fallback].filter((candidate): candidate is ArtRef => candidate?.id != null)
  const cur = candidates.find((candidate) => !failedArt.has(`${candidate.id}:${candidate.type ?? 'Primary'}`))
  if (!cur) return null
  return (
    <img
      src={imageUrl(cur.id, cur.type ?? 'Primary')}
      alt={alt}
      className={className}
      style={{ objectFit: 'cover', maxWidth: '100%', ...style }}
      loading="lazy"
      onError={() => { failedArt.add(`${cur.id}:${cur.type}`); force((n) => n + 1) }}
    />
  )
}

/**
 * 2:3 poster tile with rounded corners, art 404-guard, and a graceful fallback
 * (initial glyph on a surface). Press-scales on tap. Pass `w` to size it; the
 * height follows the 2:3 ratio. `ratio` can override (e.g. '16 / 9' for stills).
 */
export function Poster({ id, type = 'Primary', fallback, title = '', w, ratio = '2 / 3', radius = R.md, onClick, style, children }: { id?: string | number; type?: string; fallback?: ArtRef; title?: string; w?: number | string; ratio?: string; radius?: number; onClick?: () => void; style?: CSSProperties; children?: ReactNode } = {}) {
  const [broken, setBroken] = useState(false)
  const key = id ? `${id}:${type}` : null
  const show = id && !broken && !(key && failedArt.has(key))
  return (
    <div
      onClick={onClick}
      className="mob-press"
      style={{
        position: 'relative',
        width: w, aspectRatio: ratio,
        borderRadius: radius, overflow: 'hidden',
        background: T.surface, border: `1px solid ${T.line}`,
        cursor: onClick ? 'pointer' : 'default',
        flex: '0 0 auto',
        ...style,
      }}
    >
      {show ? (
        <img
          src={imageUrl(id, type)}
          alt={title}
          loading="lazy"
          style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
          onError={() => { if (key) failedArt.add(key); setBroken(true) }}
        />
      ) : (
        <div style={{
          width: '100%', height: '100%', display: 'grid', placeItems: 'center',
          color: T.faint, fontFamily: "'Circular XX', sans-serif", fontWeight: 700, fontSize: 26,
          background: T.surface,
        }}>
          {(title || '?').trim().charAt(0).toUpperCase()}
        </div>
      )}
      {children}
    </div>
  )
}
