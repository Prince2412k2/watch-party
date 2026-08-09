import type { AuthUser, ChatMessage, PartySession, PartyUser, SubtitlePreferences, UserProfile } from './types.ts'
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

function isPlayback(value: unknown): boolean {
  if (!isObject(value)) return false
  return (value.selectedAudioIndex === undefined || value.selectedAudioIndex === null || typeof value.selectedAudioIndex === 'number') &&
    (value.selectedSubtitleIndex === undefined || value.selectedSubtitleIndex === null || typeof value.selectedSubtitleIndex === 'number') &&
    (value.mediaSourceId === undefined || value.mediaSourceId === null || typeof value.mediaSourceId === 'string')
}

function isSubtitlePreferences(value: unknown): value is SubtitlePreferences {
  return isObject(value) && Number.isInteger(value.delayMs) && Number.isInteger(value.fontScalePercent) &&
    Number.isInteger(value.verticalOffsetPercent) &&
    (value.verticalOffsetPercent as number) >= 0 && (value.verticalOffsetPercent as number) <= 100 &&
    ['sans', 'serif', 'mono'].includes(String(value.fontFamily)) &&
    typeof value.textColor === 'string' && Number.isInteger(value.backgroundOpacityPercent)
}


export function isPartySession(value: unknown): value is PartySession {
  if (!isObject(value) || typeof value.id !== 'string' || typeof value.hostId !== 'string') return false
  return (value.guests === undefined || (Array.isArray(value.guests) && value.guests.every(isPartyUser))) &&
    (value.waiting === undefined || (Array.isArray(value.waiting) && value.waiting.every(isPartyUser))) &&
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

