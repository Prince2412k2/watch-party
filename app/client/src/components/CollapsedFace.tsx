import Avatar from './Avatar'
import { useMemberAvatar } from '../hooks/useMemberAvatar'

/**
 * The opaque face of a tile that has been collapsed to a circle. Its own
 * component because looking up whose avatar this is takes a hook, and the grid
 * renders these from inside a map.
 *
 * Opaque, not a wash: the tile underneath is only faded to opacity 0 (to keep
 * its tracks alive), so a translucent fill here would leave the movie showing
 * through the circle.
 */
export default function CollapsedFace({ identity, name }: { identity: string; name?: string }) {
  const avatar = useMemberAvatar(identity)

  return (
    <div style={{
      position: 'absolute', inset: 0, background: 'var(--bg)',
      display: 'grid', placeItems: 'center', pointerEvents: 'none',
      borderRadius: '50%', overflow: 'hidden',
    }}>
      <Avatar userId={identity} name={name} config={avatar} size="100%" circle />
    </div>
  )
}
