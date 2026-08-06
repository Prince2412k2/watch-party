/**
 * `h:mm:ss` past an hour, `m:ss` below it — the same clock the bar's own label
 * and the scrub preview print, so a hover time and the resting time can never
 * be formatted differently.
 */
export function formatClock(seconds: number): string {
  let value = seconds
  if (!Number.isFinite(value) || value < 0) value = 0
  value = Math.floor(value)
  const hours = Math.floor(value / 3600)
  const minutes = Math.floor((value % 3600) / 60)
  const secs = value % 60
  const mm = hours > 0 ? String(minutes).padStart(2, '0') : String(minutes)
  return `${hours > 0 ? `${hours}:` : ''}${mm}:${String(secs).padStart(2, '0')}`
}

/** Spoken form for `aria-valuetext`; "3:07" read as digits is not a time. */
export function spokenClock(seconds: number): string {
  let value = seconds
  if (!Number.isFinite(value) || value < 0) value = 0
  value = Math.floor(value)
  const hours = Math.floor(value / 3600)
  const minutes = Math.floor((value % 3600) / 60)
  const secs = value % 60
  const parts: string[] = []
  if (hours > 0) parts.push(`${hours} hour${hours === 1 ? '' : 's'}`)
  if (minutes > 0) parts.push(`${minutes} minute${minutes === 1 ? '' : 's'}`)
  parts.push(`${secs} second${secs === 1 ? '' : 's'}`)
  return parts.join(' ')
}
