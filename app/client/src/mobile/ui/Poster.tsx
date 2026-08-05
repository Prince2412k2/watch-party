import { useState } from 'react'
import type { CSSProperties } from 'react'

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
