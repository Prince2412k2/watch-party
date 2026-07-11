// Small formatting helpers shared by the offline/download surfaces.
export function formatBytes(n: number | null | undefined): string {
  if (!n || n <= 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let i = 0
  let v = n
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i += 1
  }
  return `${v >= 100 ? Math.round(v) : v.toFixed(v >= 10 ? 0 : 1)} ${units[i]}`
}

export function formatSpeed(bytesPerSec: number | null | undefined): string {
  if (!bytesPerSec) return ''
  return `${formatBytes(bytesPerSec)}/s`
}

export function progressPct(received: number, total: number): number {
  if (!total) return 0
  return Math.max(0, Math.min(100, Math.round((received / total) * 100)))
}
// @ts-nocheck
