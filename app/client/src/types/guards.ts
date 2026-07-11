/** Runtime guards for values crossing HTTP/storage/native boundaries. */
export type JsonPrimitive = string | number | boolean | null
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue }
export type JsonObject = { [key: string]: JsonValue }

export const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

export const stringValue = (value: unknown): string | undefined =>
  typeof value === 'string' ? value : undefined
export const numberValue = (value: unknown): number | undefined =>
  typeof value === 'number' && Number.isFinite(value) ? value : undefined
export const booleanValue = (value: unknown): boolean | undefined =>
  typeof value === 'boolean' ? value : undefined

export const arrayOf = <T>(value: unknown, guard: (item: unknown) => item is T): T[] =>
  Array.isArray(value) ? value.filter(guard) : []

export async function apiJson(response: Response): Promise<unknown> {
  return response.json() as Promise<unknown>
}

export interface LibraryView { Id: string; Name: string; CollectionType?: string }
export const isLibraryView = (value: unknown): value is LibraryView =>
  isRecord(value) && typeof value.Id === 'string' && typeof value.Name === 'string'

export interface TorrentJson extends Record<string, unknown> { hash: string }
export const isTorrentJson = (value: unknown): value is TorrentJson =>
  isRecord(value) && typeof value.hash === 'string'

export interface QueueJson extends Record<string, unknown> {
  id: string | number
  service: string
  failing?: boolean
}
export const isQueueJson = (value: unknown): value is QueueJson =>
  isRecord(value) && (typeof value.id === 'string' || typeof value.id === 'number')
  && typeof value.service === 'string'

export const isCatalogItem = (value: unknown): value is Record<string, unknown> => isRecord(value)

/** Jellyfin items always carry these three identity fields on client endpoints. */
export interface LibraryItemJson extends Record<string, unknown> { Id: string; Name: string; Type: string }
export const isLibraryItemJson = (value: unknown): value is LibraryItemJson =>
  isRecord(value) && typeof value.Id === 'string' && typeof value.Name === 'string' && typeof value.Type === 'string'

export function objectField(value: unknown, key: string): unknown {
  return isRecord(value) ? value[key] : undefined
}

export function stringField(value: unknown, key: string): string | undefined {
  return stringValue(objectField(value, key))
}
