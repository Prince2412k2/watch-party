export interface TrickplayManifest {
  itemId: string
  mediaSourceId: string
  width: number
  height: number
  tileWidth: number
  tileHeight: number
  thumbnailCount: number
  intervalMs: number
  sheetCount: number
  sheetUrlTemplate: string
}

export interface TrickplayFrame {
  sheetIndex: number
  x: number
  y: number
  columns: number
  rows: number
}

export function parseTrickplayManifest(value: unknown): TrickplayManifest | null {
  if (!value || typeof value !== 'object') return null
  const manifest = value as Record<string, unknown>
  const strings = ['itemId', 'mediaSourceId', 'sheetUrlTemplate'] as const
  const numbers = ['width', 'height', 'tileWidth', 'tileHeight', 'thumbnailCount', 'intervalMs', 'sheetCount'] as const
  if (strings.some(key => typeof manifest[key] !== 'string' || manifest[key].length === 0)) return null
  if (numbers.some(key => typeof manifest[key] !== 'number' || !Number.isFinite(manifest[key]) || manifest[key] <= 0)) return null
  if (!(manifest.sheetUrlTemplate as string).includes('{sheetIndex}')) return null
  return manifest as unknown as TrickplayManifest
}

export function trickplayFrame(manifest: TrickplayManifest, timeSeconds: number): TrickplayFrame | null {
  const columns = manifest.tileWidth
  const rows = manifest.tileHeight
  const framesPerSheet = columns * rows
  if (columns < 1 || rows < 1 || framesPerSheet < 1 || manifest.thumbnailCount < 1 || manifest.intervalMs <= 0 || manifest.sheetCount < 1) return null

  const requested = Number.isFinite(timeSeconds) ? Math.floor(Math.max(0, timeSeconds) * 1000 / manifest.intervalMs) : 0
  const available = Math.min(manifest.thumbnailCount, framesPerSheet * manifest.sheetCount)
  const frameIndex = Math.min(requested, available - 1)
  const sheetIndex = Math.floor(frameIndex / framesPerSheet)
  const frameInSheet = frameIndex % framesPerSheet
  return {
    sheetIndex,
    x: (frameInSheet % columns) * manifest.width,
    y: Math.floor(frameInSheet / columns) * manifest.height,
    columns,
    rows,
  }
}

export function trickplaySheetUrl(manifest: TrickplayManifest, sheetIndex: number): string {
  return manifest.sheetUrlTemplate.replace('{sheetIndex}', String(sheetIndex))
}
