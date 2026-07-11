// ── Shared stroke icons ───────────────────────────────────────────────────
// Lifted from the desktop pages (Lucide/Heroicons-style single-path strokes,
// NO emoji) so the mobile tree draws from one dictionary. Adds the phone-shell
// glyphs (close, back, qr, dot, …) the desktop set didn't need.

export const Ic = {
  home: 'm3 11 9-8 9 8M5 9v11a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9',
  folder: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  film: 'M4 4h16v16H4zM4 8h16M4 16h16M8 4v16M16 4v16',
  tv: 'M2 7h20v11H2zM8 21h8M12 18v3',
  music: 'M9 18V6l10-2v11M9 18a3 3 0 1 1-3-3 3 3 0 0 1 3 3zm10-3a3 3 0 1 1-3-3 3 3 0 0 1 3 3z',
  search: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.3-4.3',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2V21a2 2 0 1 1-4 0v-.1A1.7 1.7 0 0 0 6 19.4l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0-1.2-2.9H2a2 2 0 1 1 0-4h.1A1.7 1.7 0 0 0 3.4 6l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 2.9-1.2V2a2 2 0 1 1 4 0v.1A1.7 1.7 0 0 0 18 3.4l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0 1.2 2.9H22a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  play: 'M8 5v14l11-7z',
  chevR: 'm9 6 6 6-6 6',
  chevL: 'm15 6-6 6 6 6',
  chevD: 'm6 9 6 6 6-6',
  refresh: 'M3 12a9 9 0 0 1 15-6.7L21 8M21 3v5h-5M21 12a9 9 0 0 1-15 6.7L3 16M3 21v-5h5',
  history: 'M3 3v5h5M3.05 13A9 9 0 1 0 6 5.3L3 8M12 7v5l3 3',
  check: 'M20 6 9 17l-5-5',
  heart: 'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 21l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8z',
  more: 'M5 12h.01M12 12h.01M19 12h.01',
  plus: 'M12 5v14M5 12h14',
  logout: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
  star: 'M12 2 15 9l7 .5-5.3 4.6L18.5 21 12 17l-6.5 4 1.8-6.9L2 9.5 9 9z',
  download: 'M12 3v12m0 0 4-4m-4 4-4-4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2',
  compass: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM16.2 7.8l-2.9 6.5-6.5 2.9 2.9-6.5z',
  enter: 'M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M3 12h12m0 0-4-4m4 4-4 4',
  // ── phone-shell additions ──
  close: 'M18 6 6 18M6 6l12 12',
  back: 'M19 12H5m0 0 7 7m-7-7 7-7',
  user: 'M20 21a8 8 0 1 0-16 0M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  pause: 'M8 5v14M16 5v14',
  trash: 'M4 7h16M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2m2 0v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V7',
  qr: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 14h2v2h-2zM14 18h2v2h-2zM18 18h2v2h-2z',
  users: 'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
  bolt: 'M13 2 3 14h9l-1 8 10-12h-9z',
  dot: 'M12 12h.01',
}

/**
 * Single-path stroke icon. `path` is an entry from `Ic`.
 * `fill` lets a glyph render solid (e.g. the play triangle).
 */
export function Icon({ path, size = 22, stroke = 'currentColor', fill = 'none', sw = 1.7, style }: any = {}) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke={stroke}
      strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" style={style} aria-hidden="true">
      <path d={path} />
    </svg>
  )
}

// Pick a nav glyph from a Jellyfin view's CollectionType.
export function viewIcon(v) {
  const t = (v?.CollectionType || '').toLowerCase()
  if (t.includes('movie')) return Ic.film
  if (t.includes('tv') || t.includes('show')) return Ic.tv
  if (t.includes('music')) return Ic.music
  return Ic.folder
}
