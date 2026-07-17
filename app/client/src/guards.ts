import type { AuthUser, BrowseEntry, ChatMessage, MirrorPoint, PartyBrowse, PartySession, PartyUser } from './types'

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

export function isAuthUser(value: unknown): value is AuthUser {
  return isObject(value) && typeof value.userId === 'string' &&
    (value.name === undefined || typeof value.name === 'string') &&
    (value.username === undefined || typeof value.username === 'string')
}

export function errorMessage(value: unknown, fallback: string): string {
  return isObject(value) && typeof value.error === 'string' ? value.error : fallback
}

export function isPartyUser(value: unknown): value is PartyUser {
  return isObject(value) && typeof value.userId === 'string' && typeof value.name === 'string'
}

export function isBrowseEntry(value: unknown): value is BrowseEntry {
  return isObject(value) && (value.id === undefined || typeof value.id === 'string') &&
    (value.name === undefined || typeof value.name === 'string') &&
    (value.type === undefined || typeof value.type === 'string')
}

export function isPartyBrowse(value: unknown): value is PartyBrowse {
  return isObject(value) && (value.stack === undefined ||
    (Array.isArray(value.stack) && value.stack.every(isBrowseEntry))) &&
    (value.tab === undefined || ['movies', 'series', 'discover', 'downloads'].includes(String(value.tab))) &&
    (value.screen === undefined || value.screen === 'grid' || value.screen === 'detail') &&
    (value.mediaId === undefined || value.mediaId === null || typeof value.mediaId === 'string') &&
    (value.seasonId === undefined || value.seasonId === null || typeof value.seasonId === 'string') &&
    (value.episodeId === undefined || value.episodeId === null || typeof value.episodeId === 'string') &&
    (value.revision === undefined || typeof value.revision === 'number')
}

function isPlayback(value: unknown): boolean {
  if (!isObject(value)) return false
  return (value.selectedAudioIndex === undefined || value.selectedAudioIndex === null || typeof value.selectedAudioIndex === 'number') &&
    (value.selectedSubtitleIndex === undefined || value.selectedSubtitleIndex === null || typeof value.selectedSubtitleIndex === 'number') &&
    (value.mediaSourceId === undefined || value.mediaSourceId === null || typeof value.mediaSourceId === 'string')
}

export function isPartySession(value: unknown): value is PartySession {
  if (!isObject(value) || typeof value.id !== 'string' || typeof value.hostId !== 'string') return false
  return (value.guests === undefined || (Array.isArray(value.guests) && value.guests.every(isPartyUser))) &&
    (value.waiting === undefined || (Array.isArray(value.waiting) && value.waiting.every(isPartyUser))) &&
    (value.browse === undefined || isPartyBrowse(value.browse)) &&
    (value.playback === undefined || value.playback === null || isPlayback(value.playback)) &&
    (value.hostName === undefined || typeof value.hostName === 'string') &&
    (value.stage === undefined || typeof value.stage === 'string') &&
    (value.mediaItemId === undefined || value.mediaItemId === null || typeof value.mediaItemId === 'string')
}

export function isChatMessage(value: unknown): value is ChatMessage {
  if (!isObject(value)) return false
  return (value.id === undefined || typeof value.id === 'string') &&
    (value.userId === undefined || typeof value.userId === 'string') &&
    (value.name === undefined || typeof value.name === 'string') &&
    (value.text === undefined || typeof value.text === 'string') &&
    (value.ts === undefined || typeof value.ts === 'number') &&
    (value.timestamp === undefined || typeof value.timestamp === 'number')
}

export function isMirrorPoint(value: unknown): value is MirrorPoint {
  return isObject(value) && (value.scroll === undefined || typeof value.scroll === 'number') &&
    (value.x === undefined || typeof value.x === 'number') &&
    (value.y === undefined || typeof value.y === 'number')
}
