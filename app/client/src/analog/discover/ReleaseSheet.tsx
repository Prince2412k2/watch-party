import { useCallback, useEffect, useRef, useState } from 'react'
import { AnIcon } from '../icons.tsx'
import { apiJson } from '../../types/guards.ts'
import { jpost } from '../../lib/api.ts'
import { DiscoverSheet, SheetNotice } from './DiscoverSheet.tsx'
import { defaultAddOptions, type CatalogItem, type CatalogMetadata } from './catalog.ts'
import {
  PICKER_CANCEL_DELAYS,
  cancelSettled,
  parseReleaseData,
  releaseCountLabel,
  releaseRow,
  releasesRequest,
  retainedToken,
  shouldCancelPicker,
  type Release,
  type ReleaseData,
} from './releases.ts'
import type { MotionProfile } from '../stageLayout.ts'

/**
 * Every source for a title, with seed counts, and one of them grabbed by hand.
 *
 * The lifecycle is the whole point and it is easy to get wrong, so it is stated
 * once here and enforced by `releases.ts`:
 *   open  → POST /radarr/releases   (adds the title monitored+no-search when it
 *           is not in Radarr yet, then runs the live interactive search)
 *   pick  → POST /radarr/grab       (hand that release over, KEEP the entry)
 *   close → POST /radarr/releases/cancel (remove the entry ONLY when this picker
 *           created it — the server re-checks it is file-less and not queued)
 * Cancel fires on every close path — the X, the backdrop, Escape, and unmount
 * from navigating away mid-search — guarded so it runs at most once and never
 * after a successful grab.
 */
async function cancelWithRetry(movieId: number, cancellationToken: string): Promise<boolean> {
  for (const delay of PICKER_CANCEL_DELAYS) {
    if (delay) await new Promise((resolve) => setTimeout(resolve, delay))
    try {
      const response = await jpost('/api/servarr/radarr/releases/cancel', { movieId, cancellationToken })
      if (cancelSettled(response.status)) return true
    } catch {
      // A network failure is exactly the transient case the backoff exists for.
    }
  }
  return false
}

export interface ReleaseSheetProps {
  item: CatalogItem
  motion: MotionProfile
  loadMeta: () => Promise<CatalogMetadata>
  onClose: () => void
  onGrabbed: () => void
  onManual: () => void
}

export function ReleaseSheet({ item, motion, loadMeta, onClose, onGrabbed, onManual }: ReleaseSheetProps) {
  const [meta, setMeta] = useState<{ loading: boolean; error: string }>({ loading: true, error: '' })
  const [data, setData] = useState<ReleaseData | null>(null)
  const [nonce, setNonce] = useState(0)
  const [grabbing, setGrabbing] = useState<string | null>(null)
  const [grabError, setGrabError] = useState('')

  const operationId = useRef(crypto.randomUUID()).current
  const generation = useRef(0)

  // Kept in a ref so an unmount can still cancel exactly once, after the render
  // that knew the ids is gone.
  const life = useRef({
    movieId: null as number | null,
    cancellationToken: null as string | null,
    settled: false,
    cancelling: false,
    cleanupTimer: null as ReturnType<typeof setTimeout> | null,
  })

  const cancelNow = useCallback(() => {
    if (!shouldCancelPicker(life.current)) return
    const { movieId, cancellationToken } = life.current
    life.current.cancelling = true
    void cancelWithRetry(movieId!, cancellationToken!).then((terminal) => {
      life.current.settled = terminal
      life.current.cancelling = false
    })
  }, [])

  // StrictMode mounts, unmounts and remounts every effect in development. A
  // cancel fired straight from the teardown would therefore delete the entry the
  // remount is about to search against, so the teardown only SCHEDULES it and a
  // remount within the window takes it back.
  const scheduleCancel = useCallback(() => {
    if (life.current.cleanupTimer) return
    life.current.cleanupTimer = setTimeout(() => {
      life.current.cleanupTimer = null
      cancelNow()
    }, 100)
  }, [cancelNow])

  useEffect(() => {
    let cancelled = false
    const run = ++generation.current
    setMeta({ loading: true, error: '' })
    setGrabError('')
    ;(async () => {
      const existing = life.current.movieId
      const request = releasesRequest({
        item,
        operationId,
        existingMovieId: existing,
        options: existing == null && item.id == null ? defaultAddOptions(await loadMeta()) : null,
      })
      if (!request) throw new Error('meta')
      const response = await jpost('/api/servarr/radarr/releases', request.body)
      if (!response.ok) throw new Error('releases')
      const parsed = parseReleaseData(await apiJson(response))
      return {
        parsed,
        token: retainedToken(request.kind, life.current.cancellationToken, parsed.cancellationToken),
      }
    })()
      .then(({ parsed, token }) => {
        if (cancelled) {
          // Unmounted mid-search — an entry this picker just created still has
          // to go, and this is the only code path that knows about it.
          if (run === generation.current && token && parsed.movieId != null) {
            void cancelWithRetry(parsed.movieId, token)
          }
          return
        }
        life.current = { ...life.current, movieId: parsed.movieId, cancellationToken: token, settled: false }
        setData(parsed)
        setMeta({ loading: false, error: '' })
      })
      .catch(() => {
        if (!cancelled) setMeta({ loading: false, error: 'Couldn’t load sources right now. Please try again.' })
      })
    return () => {
      cancelled = true
    }
  }, [item, nonce, operationId, loadMeta])

  // Unmount is a close too — navigating away mid-browse must not leave the entry.
  useEffect(() => {
    if (life.current.cleanupTimer) {
      clearTimeout(life.current.cleanupTimer)
      life.current.cleanupTimer = null
    }
    return scheduleCancel
  }, [scheduleCancel])

  const close = () => {
    cancelNow()
    onClose()
  }

  const grab = (release: Release) => {
    if (grabbing) return
    setGrabbing(release.guid)
    setGrabError('')
    jpost('/api/servarr/radarr/grab', {
      movieId: data?.movieId,
      guid: release.guid,
      indexerId: release.indexerId,
      cancellationToken: life.current.cancellationToken,
    })
      .then((response) => (response.ok ? apiJson(response) : Promise.reject(response)))
      .then(() => {
        // Settled, so the unmount that follows does not remove the entry the
        // grab just attached a download to.
        life.current.settled = true
        onGrabbed()
      })
      .catch(() => {
        setGrabbing(null)
        setGrabError('Couldn’t start that download. Try another source.')
      })
  }

  // Each raw release is kept beside its presentation row: the row is what the
  // list renders, the release is what the grab has to send.
  const rows = (data?.releases ?? []).map((release) => ({ release, row: releaseRow(release) }))

  return (
    <DiscoverSheet
      eyebrow="Choose a release"
      title={item.title}
      subtitle={[item.year, meta.loading ? null : releaseCountLabel(rows.length)].filter(Boolean).join(' · ') || null}
      item={item}
      motion={motion}
      onClose={close}
      busy={grabbing != null}
    >
      {meta.loading ? (
        <p className="an-dempty">
          <span className="an-dpulse" aria-hidden /> Searching every source for the healthiest release. This can
          take up to a minute.
        </p>
      ) : meta.error ? (
        <>
          <SheetNotice tone="error">{meta.error}</SheetNotice>
          <Recovery onRetry={() => setNonce((value) => value + 1)} onManual={onManual} />
        </>
      ) : data?.searchFailed ? (
        <>
          <SheetNotice tone="warn">Couldn’t reach the sources just now. Please try again.</SheetNotice>
          <Recovery onRetry={() => setNonce((value) => value + 1)} onManual={onManual} />
        </>
      ) : rows.length === 0 ? (
        <>
          <SheetNotice tone="warn">No sources found for this title right now.</SheetNotice>
          <Recovery onRetry={() => setNonce((value) => value + 1)} onManual={onManual} />
        </>
      ) : (
        <>
          {grabError ? <SheetNotice tone="error">{grabError}</SheetNotice> : null}
          <ul className="an-dreleases">
            {rows.map(({ release, row }) => (
              <li key={row.guid} className="an-drelease" data-rejected={row.rejected || undefined}>
                <div className="an-drelease-body">
                  <span className="an-drelease-title" title={row.title}>
                    {row.title}
                  </span>
                  <div className="an-drelease-meta">
                    {row.quality ? <span className="an-dchip">{row.quality}</span> : null}
                    {/* Seeds lead, and carry a dot whose tone is a shape as well
                        as a colour — zero seeds means it will never finish. */}
                    <span className="an-dseeds" data-tone={row.seedTone}>
                      <i aria-hidden />
                      {row.seedLabel}
                    </span>
                    <span>{row.peerLabel}</span>
                    <span>{row.sizeLabel}</span>
                    {row.indexer ? <span className="an-drelease-indexer">{row.indexer}</span> : null}
                  </div>
                  {row.reason ? (
                    <span className="an-drelease-reason" title={row.reasons.join(' · ')}>
                      <AnIcon name="alert" size={13} />
                      {row.reason}
                    </span>
                  ) : null}
                </div>

                {row.grabbable ? (
                  <button
                    type="button"
                    className="an-action is-small is-primary"
                    disabled={grabbing != null}
                    onClick={() => grab(release)}
                  >
                    <AnIcon name="download" size={14} />
                    <span>{grabbing === row.guid ? 'Starting…' : 'Get'}</span>
                  </button>
                ) : null}
              </li>
            ))}
          </ul>
          <p className="an-dhint">Greyed rows were skipped by the auto-picker for the reason shown.</p>
        </>
      )}
    </DiscoverSheet>
  )
}

/**
 * The two ways out of a picker that found nothing: search again, or bring your
 * own source. Neither is a dead end, which is the point.
 */
function Recovery({ onRetry, onManual }: { onRetry: () => void; onManual: () => void }) {
  return (
    <div className="an-drecovery">
      <button type="button" className="an-action is-primary" onClick={onRetry}>
        <AnIcon name="update" size={15} />
        <span>Try again</span>
      </button>
      <button type="button" className="an-action" onClick={onManual}>
        <AnIcon name="plus" size={15} />
        <span>Add a source</span>
      </button>
    </div>
  )
}
