import type { IconControl } from './cornerWidgets.ts'

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
  globeOff: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM2 12h20M4.9 4.9l14.2 14.2',
  qr: 'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 14h2v2h-2zM14 18h2v2h-2zM18 18h2v2h-2z',
  copy: 'M8 8h11v11H8zM5 16H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h11a1 1 0 0 1 1 1v1',
  link: 'M10.5 13.5a4 4 0 0 0 5.7 0l2.8-2.8a4 4 0 0 0-5.7-5.7l-1.4 1.4M13.5 10.5a4 4 0 0 0-5.7 0l-2.8 2.8a4 4 0 0 0 5.7 5.7l1.4-1.4',
  check: 'M20 6 9 17l-5-5',
  x: 'M18 6 6 18M6 6l12 12',
  // A refresh arc that reads as "fetch the newer one" rather than "reload".
  update: 'M20.5 12a8.5 8.5 0 1 1-2.5-6M20.5 3v5h-5',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2v.1a2 2 0 1 1-4 0v-.2a1.7 1.7 0 0 0-2.9-1.1l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.7 1.7 0 0 0 3.4 14H3a2 2 0 1 1 0-4h.2a1.7 1.7 0 0 0 1.1-2.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.7 1.7 0 0 0 10 3.4V3a2 2 0 1 1 4 0v.2a1.7 1.7 0 0 0 2.9 1.1l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0 1.2 2.9h.1a2 2 0 1 1 0 4h-.2a1.7 1.7 0 0 0-1.4 1z',
  star: 'M12 3.5 14.6 9l6 .9-4.3 4.2 1 6-5.3-2.8-5.3 2.8 1-6L3.4 9.9l6-.9z',
  power: 'M12 3v9M18.4 6.6a9 9 0 1 1-12.8 0',
  lock: 'M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4',
  unlock: 'M5 11h14v10H5zM8 11V7a4 4 0 0 1 7.5-2',
  sound: 'M11 5 6 9H3v6h3l5 4zM16 9a4 4 0 0 1 0 6',
  mute: 'M11 5 6 9H3v6h3l5 4zM16 10l4 4m0-4-4 4',
  play: 'M7 4.5v15l12.5-7.5z',
  tracks: 'M9 18V5l11-2v13M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0zm11-2a3 3 0 1 1-6 0 3 3 0 0 1 6 0z',
  trash: 'M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13',
  back: 'm15 6-6 6 6 6',
} as const

export type AnIconName = keyof typeof AN_ICONS

export function AnIcon({ name, size = 18, filled = false }: { name: AnIconName; size?: number; filled?: boolean }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={filled ? 'currentColor' : 'none'}
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

/**
 * The button the corner widgets are built from: one glyph, no text.
 *
 * The name and the tooltip both come from `control.label`, because with nothing
 * written on the button that string is the only thing telling anyone — pointer,
 * keyboard or screen reader — what it does. Host-only controls carry a data
 * attribute the stylesheet turns into a dashed edge and an accent mark, so the
 * distinction is not left to the label alone.
 */
export function AnIconButton({
  control,
  onPress,
  size = 16,
}: {
  control: IconControl
  onPress: () => void
  size?: number
}) {
  return (
    <button
      type="button"
      className="an-icon-button"
      onClick={onPress}
      disabled={control.disabled}
      aria-label={control.label}
      title={control.label}
      aria-pressed={control.pressed}
      data-host-only={control.hostOnly ? 'true' : undefined}
      data-tone={control.tone}
    >
      <AnIcon name={control.icon} size={size} />
    </button>
  )
}
