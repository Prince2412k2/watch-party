import type { AuthUser, BrowseEntry, ChatMessage, MirrorPoint, PartyBrowse, PartyBrowserState, PartySession, PartyUser, SubtitlePreferences, UserProfile } from './types.ts'
import type { AvatarConfig } from './lib/avatar.ts'

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function isStringMap(value: unknown): value is Record<string, string> {
  return isObject(value) && Object.values(value).every(entry => typeof entry === 'string')
}

/** The server validates avatar configurations against the asset set before
    storing them; this only checks the shape we are about to render, so a
    malformed payload can't reach the renderer as a wrong type. */
export function isAvatarConfig(value: unknown): value is AvatarConfig {
  return isObject(value) &&
    (value.selections === undefined || isStringMap(value.selections)) &&
    (value.colors === undefined || isStringMap(value.colors)) &&
    (value.background === undefined || typeof value.background === 'string')
}

function isOptionalAvatar(value: unknown): boolean {
  return value === undefined || value === null || isAvatarConfig(value)
}

export function isUserProfile(value: unknown): value is UserProfile {
  return isObject(value) &&
    (value.displayName === null || typeof value.displayName === 'string') &&
    isOptionalAvatar(value.avatar)
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
  return isObject(value) && typeof value.userId === 'string' && typeof value.name === 'string' &&
    isOptionalAvatar(value.avatar)
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

function isSubtitlePreferences(value: unknown): value is SubtitlePreferences {
  return isObject(value) && Number.isInteger(value.delayMs) && Number.isInteger(value.fontScalePercent) &&
    ['top', 'middle', 'bottom'].includes(String(value.verticalPosition)) &&
    ['sans', 'serif', 'mono'].includes(String(value.fontFamily)) &&
    typeof value.textColor === 'string' && Number.isInteger(value.backgroundOpacityPercent)
}

function isPartyBrowserState(value: unknown): value is PartyBrowserState {
  return isObject(value) &&
    ['starting', 'active', 'error'].includes(String(value.state)) &&
    (value.url === undefined || value.url === null || typeof value.url === 'string') &&
    (value.driverUserId === undefined || value.driverUserId === null || typeof value.driverUserId === 'string') &&
    (value.requests === undefined || (Array.isArray(value.requests) && value.requests.every(isPartyUser))) &&
    (value.error === undefined || value.error === null || typeof value.error === 'string')
}

export function isPartySession(value: unknown): value is PartySession {
  if (!isObject(value) || typeof value.id !== 'string' || typeof value.hostId !== 'string') return false
  return (value.browser === undefined || value.browser === null || isPartyBrowserState(value.browser)) &&
    (value.browserAvailable === undefined || typeof value.browserAvailable === 'boolean') &&
    (value.guests === undefined || (Array.isArray(value.guests) && value.guests.every(isPartyUser))) &&
    (value.waiting === undefined || (Array.isArray(value.waiting) && value.waiting.every(isPartyUser))) &&
    (value.browse === undefined || isPartyBrowse(value.browse)) &&
    (value.playback === undefined || value.playback === null || isPlayback(value.playback)) &&
    (value.subtitlePreferences === undefined || isSubtitlePreferences(value.subtitlePreferences)) &&
    (value.hostName === undefined || typeof value.hostName === 'string') &&
    isOptionalAvatar(value.hostAvatar) &&
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
