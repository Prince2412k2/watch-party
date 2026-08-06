import { createContext, useContext, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { jget } from '../lib/api.ts'
import { apiJson } from '../types/guards.ts'
import { useTorrents, isActiveState } from '../hooks/useTorrents.ts'
import type { TorrentRecord } from '../hooks/useTorrents.ts'
import { useFailingQueue } from '../hooks/useFailingDownloads.ts'
import type { FailingQueueItem, FailingQueueState } from '../hooks/useFailingDownloads.ts'
import { arrQueueReady, parseHealth, serviceReady } from '../hooks/downloadsCore.ts'
import type { Health } from '../hooks/downloadsCore.ts'

/**
 * ONE download hub for the whole signed-in app.
 *
 * Every surface that shows download state — the phone tab-bar badge, the phone
 * Home "Downloading now" rail, phone Browse per-card status, both Downloads
 * screens, desktop Library's rail, desktop Discover's cards — used to mount its
 * own `/api/servarr/health` fetch plus its own qBittorrent and *arr queue
 * pollers. On a phone that is unavoidably concurrent: the tab bar is mounted at
 * the same time as whichever screen is showing, so a phone sitting on Downloads
 * ran two enriched-torrent pollers (2×/2.5s) and two *arr queue poll pairs.
 *
 * The hub hoists all three into a single provider mounted once, above the
 * routed tree. Screens read; nobody polls. Readiness is health-gated in one
 * place too — the phone surfaces previously called `useTorrents(true)`
 * unconditionally and hammered the endpoint on deployments with no download
 * client configured at all.
 */
export interface DownloadsHub {
  /** false inside the party surface, where the hub is deliberately not mounted. */
  enabled: boolean
  health: Health | null
  healthLoading: boolean
  qbitReady: boolean
  arrReady: boolean
  /** Live torrents. `torrents` is null until the first poll lands. */
  torrents: TorrentRecord[] | null
  list: TorrentRecord[]
  loadError: boolean
  busy: Set<string>
  activeCount: number
  pause: (torrent: { hash: string }) => void
  resume: (torrent: { hash: string }) => void
  remove: (hash: string, deleteFiles: boolean) => void
  /** Radarr/Sonarr queue records stuck in a warning/failed state. */
  failing: FailingQueueState
  failingCount: number
}

const EMPTY_FAILING: FailingQueueState = {
  items: null, loadError: false, busy: new Set<FailingQueueItem['id']>(), remove: () => {},
}

/* Default = a hub that is present but idle. Library renders `embedded` inside
 * the party lobby, which sits below the provider's mount point on purpose (a
 * watch session must not be polling the download client); reading the idle hub
 * there degrades to "no downloads" instead of throwing. */
const IDLE: DownloadsHub = {
  enabled: false,
  health: null, healthLoading: false, qbitReady: false, arrReady: false,
  torrents: null, list: [], loadError: false, busy: new Set<string>(), activeCount: 0,
  pause: () => {}, resume: () => {}, remove: () => {},
  failing: EMPTY_FAILING, failingCount: 0,
}

const DownloadsContext = createContext<DownloadsHub>(IDLE)

export function DownloadsProvider({ children }: { children?: ReactNode } = {}) {
  const [health, setHealth] = useState<Health | null>(null)
  const [healthLoading, setHealthLoading] = useState(true)

  useEffect(() => {
    let alive = true
    setHealthLoading(true)
    jget('/api/servarr/health')
      .then((r) => (r.ok ? apiJson(r) : Promise.reject(r)))
      .then((value) => { if (alive) setHealth(parseHealth(value)) })
      .catch(() => { if (alive) setHealth({ services: {} }) })
      .finally(() => { if (alive) setHealthLoading(false) })
    return () => { alive = false }
  }, [])

  const qbitReady = serviceReady(health, 'qbittorrent')
  const arrReady = arrQueueReady(health)

  const torrents = useTorrents(qbitReady)
  const failing = useFailingQueue(arrReady)

  const value: DownloadsHub = {
    enabled: true,
    health, healthLoading, qbitReady, arrReady,
    torrents: torrents.torrents, list: torrents.list, loadError: torrents.loadError,
    busy: torrents.busy, activeCount: torrents.activeCount,
    pause: torrents.pause, resume: torrents.resume, remove: torrents.remove,
    failing, failingCount: (failing.items ?? []).length,
  }

  return <DownloadsContext.Provider value={value}>{children}</DownloadsContext.Provider>
}

export function useDownloadsHub(): DownloadsHub {
  return useContext(DownloadsContext)
}

/** Only the torrents that are still working toward a complete file. */
export function activeTorrents(list: TorrentRecord[]): TorrentRecord[] {
  return list.filter((torrent) => isActiveState(torrent.state))
}
