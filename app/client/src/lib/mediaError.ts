/**
 * Human-readable text for a camera/microphone acquisition failure.
 *
 * getUserMedia rejects with DOMException names, not sentences: raw
 * "Permission denied" or "Requested device not found" in a banner tells the user
 * nothing about what to do next. Kept pure (secure-context passed in) so it is
 * testable without a DOM.
 */
export type MediaKind = 'Camera' | 'Microphone'

export function mediaErrorMessage(
  kind: MediaKind,
  err: unknown,
  { secureContext = true }: { secureContext?: boolean } = {},
): string {
  const device = kind.toLowerCase()
  // getUserMedia only exists in a secure context, so nothing below can succeed
  // over plain http — say that instead of relaying a confusing browser message.
  if (!secureContext) return `${kind} needs a secure (HTTPS) connection — open the site over https.`

  switch (errorName(err)) {
    case 'NotAllowedError':
    case 'SecurityError':
      return `${kind} access was blocked — allow the ${device} in your browser's site settings and try again.`
    case 'NotFoundError':
    case 'OverconstrainedError':
      return `No ${device} found — plug one in or pick a different device.`
    case 'NotReadableError':
    case 'AbortError':
      return `Your ${device} is already in use by another app.`
    default:
      return message(err) ?? `Could not access your ${device}.`
  }
}

function errorName(err: unknown): string | null {
  if (err == null || typeof err !== 'object') return null
  const name = (err as { name?: unknown }).name
  return typeof name === 'string' ? name : null
}

function message(err: unknown): string | null {
  if (err instanceof Error && err.message) return err.message
  if (typeof err === 'string' && err) return err
  return null
}
