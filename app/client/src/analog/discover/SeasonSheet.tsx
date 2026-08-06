import { useEffect, useState } from 'react'
import { AnIcon } from '../icons.tsx'
import { apiJson } from '../../types/guards.ts'
import { jpost } from '../../lib/api.ts'
import { DiscoverSheet, SheetNotice } from './DiscoverSheet.tsx'
import { defaultAddOptions, type CatalogItem, type CatalogMetadata, type CatalogSeason } from './catalog.ts'
import {
  allSeasonNumbers,
  allSeasonsCovered,
  anySeasonRequesting,
  episodeCountLabel,
  groupSeasons,
  seasonLabel,
  seasonState,
  withSeasonState,
  type SeasonRequestState,
} from './seasons.ts'
import type { MotionProfile } from '../stageLayout.ts'

/**
 * Pick the seasons you actually want.
 *
 * A season request is monitor-and-search rather than grab-now: the server adds
 * the show to Sonarr on first use, flips the chosen seasons to monitored and
 * fires a SeasonSearch, and episodes arrive as they are found. So "Get" here
 * does not promise a file — the copy says as much, because a button that looks
 * like a download and behaves like a subscription is the thing people complain
 * about.
 */
export interface SeasonSheetProps {
  item: CatalogItem
  motion: MotionProfile
  loadMeta: () => Promise<CatalogMetadata>
  onClose: () => void
  /** The whole-series request, for a show whose lookup returned no seasons. */
  onWholeSeries: () => void
}

export function SeasonSheet({ item, motion, loadMeta, onClose, onWholeSeries }: SeasonSheetProps) {
  const groups = groupSeasons(item)
  const [requests, setRequests] = useState<Record<number, SeasonRequestState | undefined>>({})
  const [meta, setMeta] = useState<{ loading: boolean; error: string }>({ loading: true, error: '' })

  useEffect(() => {
    let cancelled = false
    setMeta({ loading: true, error: '' })
    loadMeta()
      .then((value) => {
        if (cancelled) return
        setMeta({
          loading: false,
          error: defaultAddOptions(value) ? '' : 'Download options are unavailable right now.',
        })
      })
      .catch(() => {
        if (!cancelled) setMeta({ loading: false, error: 'Download options are unavailable right now.' })
      })
    return () => {
      cancelled = true
    }
  }, [loadMeta])

  const request = (seasons: number[]) => {
    if (seasons.length === 0) return
    setRequests((current) => withSeasonState(current, seasons, 'requesting'))
    loadMeta()
      .then((value) => {
        const options = defaultAddOptions(value)
        if (!options) throw new Error('meta')
        return jpost('/api/servarr/sonarr/request-season', {
          series: item,
          seasons,
          qualityProfileId: options.qualityProfileId,
          languageProfileId: options.languageProfileId,
          rootFolderPath: options.rootFolderPath,
        })
      })
      .then((response) => (response.ok ? apiJson(response) : Promise.reject(response)))
      .then(() => setRequests((current) => withSeasonState(current, seasons, 'requested')))
      .catch(() => setRequests((current) => withSeasonState(current, seasons, 'error')))
  }

  const busy = anySeasonRequesting(requests)
  const covered = allSeasonsCovered(groups, requests, item)
  const regulars = allSeasonNumbers(groups)

  return (
    <DiscoverSheet
      eyebrow="Seasons"
      title={item.title}
      subtitle={[item.year, item.network].filter(Boolean).join(' · ') || null}
      item={item}
      motion={motion}
      onClose={onClose}
    >
      {meta.loading ? (
        <p className="an-dempty">Loading seasons…</p>
      ) : meta.error ? (
        <SheetNotice tone="error">{meta.error}</SheetNotice>
      ) : groups.regular.length === 0 && groups.specials.length === 0 ? (
        <>
          <p className="an-dempty">This show has no season list, so it can only be requested whole.</p>
          <button
            type="button"
            className="an-action is-primary"
            onClick={() => {
              onWholeSeries()
              onClose()
            }}
          >
            <AnIcon name="download" size={15} />
            <span>Download series</span>
          </button>
        </>
      ) : (
        <>
          {groups.regular.length > 1 ? (
            <div className="an-dseason-all">
              <button
                type="button"
                className={covered ? 'an-action is-static' : 'an-action is-primary'}
                disabled={busy || covered}
                onClick={() => request(regulars)}
              >
                <AnIcon name={covered ? 'check' : 'download'} size={15} />
                <span>All seasons</span>
              </button>
              {/* Specials are excluded on purpose; say so rather than let
                  someone discover it by their absence. */}
              {groups.specials.length > 0 ? <span>Specials are not included.</span> : null}
            </div>
          ) : null}

          <ul className="an-dseasons">
            {groups.regular.map((season) => (
              <SeasonRow
                key={season.seasonNumber}
                season={season}
                state={seasonState(season, requests, item)}
                busy={busy}
                onRequest={() => request([season.seasonNumber])}
              />
            ))}
          </ul>

          {groups.specials.length > 0 ? (
            <>
              <h3 className="an-dsheet-section">Specials</h3>
              <ul className="an-dseasons">
                {groups.specials.map((season) => (
                  <SeasonRow
                    key={season.seasonNumber}
                    season={season}
                    state={seasonState(season, requests, item)}
                    busy={busy}
                    specials
                    onRequest={() => request([season.seasonNumber])}
                  />
                ))}
              </ul>
            </>
          ) : null}

          <p className="an-dhint">
            A requested season is monitored and searched — episodes download on their own as they are
            found, and their progress shows up in Downloads.
          </p>
        </>
      )}
    </DiscoverSheet>
  )
}

/**
 * One season: what it is on the left, what it is doing on the right.
 *
 * A monitored season keeps a re-search next to its pill, because "monitoring"
 * with nothing arriving is the state people actually want to prod.
 */
function SeasonRow({
  season,
  state,
  busy,
  specials = false,
  onRequest,
}: {
  season: CatalogSeason
  state: ReturnType<typeof seasonState>
  busy: boolean
  specials?: boolean
  onRequest: () => void
}) {
  const count = episodeCountLabel(season)

  return (
    <li className="an-dseason" data-specials={specials || undefined}>
      <div className="an-dseason-name">
        <strong>{seasonLabel(season)}</strong>
        <span>{count ?? (specials ? 'Extras & one-offs' : '—')}</span>
      </div>

      <div className="an-dseason-action">
        {state === 'requesting' ? (
          <span className="an-dpill" aria-live="polite">
            <span className="an-dpulse" aria-hidden />
            Requesting…
          </span>
        ) : state === 'requested' ? (
          <span className="an-dpill">
            <AnIcon name="check" size={13} />
            Searching
          </span>
        ) : state === 'monitored' ? (
          <>
            <span className="an-dpill">
              <AnIcon name="check" size={13} />
              Monitoring
            </span>
            <button
              type="button"
              className="an-icon-button"
              disabled={busy}
              aria-label={`Search ${seasonLabel(season)} again`}
              title="Search this season again"
              onClick={onRequest}
            >
              <AnIcon name="search" size={14} />
            </button>
          </>
        ) : state === 'error' ? (
          <button type="button" className="an-action is-small" disabled={busy} onClick={onRequest}>
            <AnIcon name="alert" size={14} />
            <span>Retry</span>
          </button>
        ) : (
          <button type="button" className="an-action is-small is-primary" disabled={busy} onClick={onRequest}>
            <AnIcon name="download" size={14} />
            <span>Get</span>
          </button>
        )}
      </div>
    </li>
  )
}
