import { T, R } from '../theme'
import type { CSSProperties } from 'react'

/**
 * Neutral loading placeholder — a flat `surface` block that breathes with the
 * global `pulse` keyframe (styles.css). Give it width/height/radius; defaults
 * to a text-line block. Use while data loads so screens don't pop in.
 */
export function Skeleton({ w = '100%', h = 14, radius = R.sm, style }: { w?: string | number; h?: string | number; radius?: number; style?: CSSProperties } = {}) {
  return (
    <span
      aria-hidden="true"
      style={{
        display: 'block', width: w, height: h, borderRadius: radius,
        background: T.surface2,
        animation: 'pulse 1.3s ease-in-out infinite',
        ...style,
      }}
    />
  )
}

// A 2:3 poster-shaped shimmer (matches <Poster>).
export function PosterSkeleton({ w, ratio = '2 / 3', radius = R.md }: { w?: string | number; ratio?: string; radius?: number } = {}) {
  return <Skeleton w={w} h="auto" radius={radius} style={{ aspectRatio: ratio }} />
}

// A horizontal row of poster skeletons for a loading rail.
export function RailSkeleton({ count = 4, w = 118, gap = 14, padX = 16 }: { count?: number; w?: string | number; gap?: number; padX?: number } = {}) {
  return (
    <div style={{ display: 'flex', gap, padding: `2px ${padX}px`, overflow: 'hidden' }}>
      {Array.from({ length: count }).map((_, i) => <PosterSkeleton key={i} w={w} />)}
    </div>
  )
}
