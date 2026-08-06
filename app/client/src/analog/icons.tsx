/** The stroke paths the kit's chrome needs. Drawn on a 24-unit grid, stroked
 *  in currentColor so a mode's colour change is the only thing that varies. */
export const AN_ICONS = {
  home: 'M3 10.5 12 3l9 7.5M5.5 9.4V20a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1V9.4',
  film: 'M4 4h16v16H4zM4 8h16M4 16h16M8 4v16M16 4v16',
  tv: 'M3 6h18v12H3zM8 21h8M12 18v3',
  compass: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM16.2 7.8l-2.9 6.5-6.5 2.9 2.9-6.5z',
  download: 'M12 3v12m0 0 4-4m-4 4-4-4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2',
  user: 'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  users: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm13 10v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75',
  plus: 'M12 5v14M5 12h14',
  enter: 'M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M3 12h12m0 0-4-4m4 4-4 4',
  logout: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
  globe: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM2 12h20M12 2a15 15 0 0 1 0 20 15 15 0 0 1 0-20',
  qr: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 14h2v2h-2zM14 18h2v2h-2zM18 18h2v2h-2z',
  copy: 'M8 8h11v11H8zM5 16H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h11a1 1 0 0 1 1 1v1',
  check: 'M20 6 9 17l-5-5',
  x: 'M18 6 6 18M6 6l12 12',
  sound: 'M11 5 6 9H3v6h3l5 4zM16 9a4 4 0 0 1 0 6',
  mute: 'M11 5 6 9H3v6h3l5 4zM16 10l4 4m0-4-4 4',
} as const

export type AnIconName = keyof typeof AN_ICONS

export function AnIcon({ name, size = 18 }: { name: AnIconName; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d={AN_ICONS[name]} />
    </svg>
  )
}
