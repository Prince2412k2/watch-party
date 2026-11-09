import type { SyncSchedule } from '../../src/sync/syncCore.ts'

export interface ExternalMedia { provider: 'youtube'; videoId: string | null; url: string; title: string; playbackRate: number }
export interface Member { userId: string; name: string; isAdmin?: boolean }
export interface Session {
  id: string; hostId: string; hostName: string; guests: Member[]; waiting: Member[]
  collaborativeControl: boolean; syncMode: 'hopping' | 'dragging'; externalMedia: ExternalMedia
  schedule: SyncSchedule
  inviteCode: string; controllers: string[]
}
export interface PlayerState {
  type: 'state'; videoId: string | null; title: string; position: number; duration: number
  paused: boolean; rate: number; ready: boolean; seeking: boolean; ad: boolean; buffered: number
  available: boolean; live: boolean
  observedAt?: number
  volume: number
  url: string
}
export interface Message { userId: string; name: string; text: string; timestamp: number }
export interface Connection { server: string; token: string; user: Member; expiresAt: number }
export interface Setup { server: string; name: string; username?: string }
export const TICKS = 10_000_000
export const DEFAULT_SERVER = 'https://watch.sniffkin.tech'

export function timelinePosition(schedule: SyncSchedule, now: number) {
  return Math.max(0, schedule.positionTicks / TICKS + (schedule.phase === 'playing' ? (now - schedule.t0) / 1000 * (schedule.rate ?? 1) : 0))
}

export function playbackPlan({ schedule, player, now, baseRate, force = false, tolerance = .25, gentle = true, hostLead = false }: {
  schedule: SyncSchedule; player: PlayerState; now: number; baseRate: number; force?: boolean
  tolerance?: number; gentle?: boolean; hostLead?: boolean
}): { position?: number; paused: boolean; rate: number; drift: number } | null {
  if (!player.available || player.ad || player.seeking) return null
  const position = timelinePosition(schedule, now)
  const drift = position - player.position
  const paused = schedule.phase !== 'playing'
  // A buffering player must still be allowed to play/read ahead; pausing it at
  // HAVE_CURRENT_DATA can otherwise leave a follow-mode room stuck forever.
  if (!player.ready && !paused) return null
  const seek = force || (paused && Math.abs(drift) > .4) || (!hostLead && Math.abs(drift) > (gentle ? 3 : tolerance))
  const correction = !paused && !hostLead && gentle && Math.abs(drift) > tolerance ? Math.max(-.05, Math.min(.05, drift * .08)) : 0
  const rate = Math.max(.25, Math.min(2, baseRate * (1 + correction)))
  if (!seek && player.paused === paused && Math.abs(rate - player.rate) < .005) return null
  return { ...(seek ? { position } : {}), paused, rate, drift }
}

export function isSession(value: unknown): value is Session {
  if (!value || typeof value !== 'object') return false
  const s = value as Partial<Session>
  return typeof s.id === 'string' && typeof s.hostId === 'string' && Array.isArray(s.guests) && Array.isArray(s.waiting) && Array.isArray(s.controllers) && s.externalMedia?.provider === 'youtube' && typeof s.externalMedia.url === 'string' && (s.externalMedia.videoId === null || /^[A-Za-z0-9_-]{11}$/.test(s.externalMedia.videoId)) && !!s.schedule && Number.isFinite(s.schedule.positionTicks)
}

export function isPlayerState(value: unknown): value is PlayerState {
  if (!value || typeof value !== 'object') return false
  const p = value as Partial<PlayerState>
  return p.type === 'state' && typeof p.url === 'string' && typeof p.title === 'string' && Number.isFinite(p.position) && Number.isFinite(p.rate) && typeof p.paused === 'boolean' && typeof p.ad === 'boolean' && typeof p.available === 'boolean' && (p.videoId === null || typeof p.videoId === 'string')
}

export const canControl = (session: Session, userId?: string) => !!userId && (session.hostId === userId || session.collaborativeControl || session.controllers.includes(userId))
export const formatInvite = (code: string) => code.replace(/(.{4})(?=.)/g, '$1-')

export const bridge = (data: Record<string, unknown>) => window.parent.postMessage({ source: 'watchparty-extension', ...data }, 'https://www.youtube.com')
