import { T, R } from '../theme.js'

/**
 * Shimmer placeholder. Reuses the global `shim` keyframe (styles.css). Give it
 * width/height/radius; defaults to a text-line block. Use while data loads so
 * screens don't pop in.
 */
export function Skeleton({ w = '100%', h = 14, radius = R.sm, style }) {
  return (
    <span
      aria-hidden="true"
      style={{
        display: 'block', width: w, height: h, borderRadius: radius,
        backgroundImage: `linear-gradient(90deg, ${T.surface} 25%, ${T.surface2} 50%, ${T.surface} 75%)`,
        backgroundSize: '200% 100%',
        animation: 'shim 1.3s ease-in-out infinite',
        ...style,
      }}
    />
  )
}

// A 2:3 poster-shaped shimmer (matches <Poster>).
export function PosterSkeleton({ w, ratio = '2 / 3', radius = R.md }) {
  return <Skeleton w={w} h="auto" radius={radius} style={{ aspectRatio: ratio }} />
}

// A horizontal row of poster skeletons for a loading rail.
export function RailSkeleton({ count = 4, w = 118, gap = 14, padX = 16 }) {
  return (
    <div style={{ display: 'flex', gap, padding: `2px ${padX}px`, overflow: 'hidden' }}>
      {Array.from({ length: count }).map((_, i) => <PosterSkeleton key={i} w={w} />)}
    </div>
  )
}
