import { useMemo } from 'react'
import type { CSSProperties } from 'react'
import { Avatar as HumationAvatar } from '@humation/react'
import { assets, effectiveConfig, DEFAULT_BACKGROUND } from '../lib/avatar.ts'
import type { AvatarConfig } from '../lib/avatar.ts'

/**
 * Somebody's face, wherever we need one. Draws entirely from the asset package
 * that ships in the bundle — no request, so it still renders on a degraded
 * connection or offline.
 *
 * `userId` is the seed and is required: an avatar without one would be a
 * different person on every render. `config` is what that person saved, if
 * anything; absent, they get their derived default.
 */
export default function Avatar({ userId, name, config, size = 40, circle = false, style }: {
  userId: string
  name?: string
  config?: AvatarConfig | null
  size?: number | string
  circle?: boolean
  style?: CSSProperties
}) {
  const resolved = useMemo(() => effectiveConfig(userId, config), [userId, config])

  return (
    <HumationAvatar
      assets={assets}
      selections={resolved.selections}
      colors={resolved.colors}
      background={resolved.background ?? DEFAULT_BACKGROUND}
      size={size}
      // The avatar is how you tell who this is, so it is labelled with who it
      // is rather than left decorative.
      title={name}
      style={{ display: 'block', flexShrink: 0, borderRadius: circle ? '50%' : undefined, ...style }}
    />
  )
}
