// Chat message toasts over the player.
//
// "New messages can appear over the player as compact semi-transparent toasts.
// They disappear without requiring dismissal and must not cover subtitles,
// transport controls, participant faces, or the chat toggle."
//
// The queue behind this — three visible, older ones as a count, four seconds
// each, nothing while the drawer is open — is `playerCore`'s `toastView`; this
// component only paints it. Three properties are structural rather than
// cosmetic and are worth stating:
//
//   · `pointer-events: none` throughout. A toast that can be clicked is a toast
//     that can swallow a click meant for the video, and these dismiss
//     themselves; there is nothing to click.
//   · a polite live region, never focused. "Notifications are announced
//     accessibly without moving keyboard focus."
//   · the surface comes from `toastSurface`, which swaps to opaque under
//     reduced transparency at equivalent contrast.

import type { CSSProperties } from 'react'
import { analogTokens } from '../../design/analogTokens.ts'
import type { ToastView } from '../playerCore.ts'
import { collapsedLabel, toastAnnouncement } from './toastFeed.ts'
import { defaultDisplayPreferences, riseAnimation, toastSurface, type DisplayPreferences } from './presentation.ts'

export interface AnalogToastStackProps {
  view: ToastView
  preferences?: DisplayPreferences
  /**
   * Where the stack sits. The caller owns this because "must not cover
   * subtitles, transport, participant faces or the chat toggle" is a fact about
   * the surrounding screen, not about the toast.
   */
  style?: CSSProperties
  width?: number
}

export default function AnalogToastStack({
  view,
  preferences = defaultDisplayPreferences,
  style,
  width = 260,
}: AnalogToastStackProps) {
  const surface = toastSurface(preferences)
  const hasContent = view.toasts.length > 0 || view.collapsedCount > 0

  return (
    <div
      // The live region is mounted permanently: assistive tech announces
      // additions to an existing region, but a region that appears at the same
      // moment as its content is frequently missed entirely.
      role="status"
      aria-live="polite"
      aria-atomic="false"
      style={{
        position: 'absolute',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'flex-end',
        gap: analogTokens.space.xsPx,
        width,
        maxWidth: '70vw',
        pointerEvents: 'none',
        ...style,
      }}
    >
      {!hasContent ? null : (
        <>
          {view.collapsedCount > 0 && (
            <div style={{
              ...surface,
              borderRadius: analogTokens.radius.pillPx,
              padding: '3px 10px',
              fontSize: 11,
              fontWeight: 600,
              color: 'var(--an-color-ink-dim)',
              animation: riseAnimation(preferences),
            }}>
              {collapsedLabel(view.collapsedCount)}
            </div>
          )}
          {view.toasts.map((toast) => (
            <div
              key={toast.id}
              style={{
                ...surface,
                width: '100%',
                borderRadius: analogTokens.radius.chromePx,
                padding: `${analogTokens.space.smPx}px ${analogTokens.space.mdPx}px`,
                animation: riseAnimation(preferences),
              }}
            >
              <div aria-hidden style={{
                fontSize: 11,
                fontWeight: 700,
                letterSpacing: '.06em',
                textTransform: 'uppercase',
                color: 'var(--an-color-ink-dim)',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
              }}>
                {toast.sender}
              </div>
              <div aria-hidden style={{
                fontSize: 13,
                lineHeight: 1.35,
                color: 'var(--an-color-ink)',
                display: '-webkit-box',
                WebkitLineClamp: 2,
                WebkitBoxOrient: 'vertical',
                overflow: 'hidden',
              }}>
                {toast.preview}
              </div>
              {/* The announcement, once, in the reading order a screen reader
                  wants — the two visual lines above are hidden from it so the
                  sender is not read twice. */}
              <span style={SR_ONLY}>{toastAnnouncement(toast)}</span>
            </div>
          ))}
        </>
      )}
    </div>
  )
}

const SR_ONLY: CSSProperties = {
  position: 'absolute',
  width: 1,
  height: 1,
  margin: -1,
  padding: 0,
  overflow: 'hidden',
  clip: 'rect(0 0 0 0)',
  whiteSpace: 'nowrap',
  border: 0,
}
