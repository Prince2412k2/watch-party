import { isRecord } from '../types/guards'

/* Pure core behind the shared download/queue hub (context/DownloadsContext.tsx).
 * Every surface that shows download state used to parse /api/servarr/health and
 * derive "is this service usable" itself — five near-identical copies that could
 * disagree. These are the single definitions, kept side-effect free so they are
 * directly testable without React. */

export interface ServiceHealth { configured?: boolean; reachable?: boolean }
export type ServiceName = 'qbittorrent' | 'radarr' | 'sonarr'
export interface Health { services?: Partial<Record<ServiceName, ServiceHealth>> }

const SERVICES: ServiceName[] = ['qbittorrent', 'radarr', 'sonarr']

function parseServiceHealth(value: unknown): ServiceHealth | undefined {
  if (!isRecord(value)) return undefined
  return {
    configured: typeof value.configured === 'boolean' ? value.configured : undefined,
    reachable: typeof value.reachable === 'boolean' ? value.reachable : undefined,
  }
}

export function parseHealth(value: unknown): Health {
  if (!isRecord(value) || !isRecord(value.services)) return { services: {} }
  const raw = value.services
  const services: Partial<Record<ServiceName, ServiceHealth>> = {}
  for (const name of SERVICES) services[name] = parseServiceHealth(raw[name])
  return { services }
}

/** Usable = the admin configured it AND we can currently reach it. */
export function serviceReady(health: Health | null, name: ServiceName): boolean {
  const service = health?.services?.[name]
  return !!service?.configured && !!service?.reachable
}

/** Either *arr is enough to render the "needs attention" queue. */
export function arrQueueReady(health: Health | null): boolean {
  return serviceReady(health, 'radarr') || serviceReady(health, 'sonarr')
}
