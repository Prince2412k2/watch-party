import { useState, type FormEvent } from 'react'
import { AnIcon } from '../icons.tsx'
import { apiJson, arrayOf, isRecord } from '../../types/guards.ts'
import { jget, jpost } from '../../lib/api.ts'
import { DiscoverSheet, SheetField, SheetNotice } from './DiscoverSheet.tsx'
import {
  defaultAddOptions,
  isCatalogItem,
  serviceFor,
  type CatalogItem,
  type CatalogMetadata,
  type Kind,
} from './catalog.ts'
import type { MotionProfile } from '../stageLayout.ts'

/** A .torrent is a few KB of metadata; anything larger is not one. */
const MAX_TORRENT_BYTES = 2 * 1024 * 1024

type ManualMode = 'magnet' | 'torrent'

/**
 * Bring your own source.
 *
 * The last resort when the indexers have nothing: paste a magnet or upload a
 * .torrent and hand it to Radarr/Sonarr for validation, so the file still lands
 * in the library with the right name rather than loose in the download client.
 *
 * Submitting needs a target the *arr instance knows about, so a title that is
 * not in the library yet is added first (monitored, no search) — that add is the
 * only side effect this sheet has, and it is the same one the release picker
 * makes for the same reason.
 */
export interface ManualSheetProps {
  item: CatalogItem
  kind: Kind
  motion: MotionProfile
  loadMeta: () => Promise<CatalogMetadata>
  onClose: () => void
  onSubmitted: () => void
}

export function ManualSheet({ item, kind, motion, loadMeta, onClose, onSubmitted }: ManualSheetProps) {
  const service = serviceFor(kind)
  const [mode, setMode] = useState<ManualMode>('magnet')
  const [title, setTitle] = useState(() =>
    kind === 'movie' ? [item.title, item.year].filter(Boolean).join('.') : item.title,
  )
  const [magnet, setMagnet] = useState('')
  const [torrent, setTorrent] = useState<File | null>(null)
  const [seasonNumber, setSeasonNumber] = useState('')
  const [episodeNumber, setEpisodeNumber] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [status, setStatus] = useState<{ tone: 'error' | 'ok'; message: string } | null>(null)

  /**
   * The *arr id to attach the source to.
   *
   * Three steps, because each can be the one that works: the lookup's own id, an
   * add that returns one, and — when the add races another client or the title
   * was already there under a different lookup — a library scan for the same
   * provider id.
   */
  const resolveTargetId = async (): Promise<number> => {
    if (item.id != null && item.id > 0) return item.id

    const options = defaultAddOptions(await loadMeta())
    if (!options) throw new Error('Download options are unavailable.')

    const body =
      kind === 'movie'
        ? {
            movie: item,
            qualityProfileId: options.qualityProfileId,
            rootFolderPath: options.rootFolderPath,
            monitor: true,
            searchNow: false,
          }
        : {
            series: item,
            qualityProfileId: options.qualityProfileId,
            rootFolderPath: options.rootFolderPath,
            languageProfileId: options.languageProfileId,
            monitor: true,
            searchNow: false,
          }

    const added = await jpost(`/api/servarr/${service}/add`, body)
    if (added.ok) {
      const value = await apiJson(added)
      if (isRecord(value) && typeof value.id === 'number') return value.id
    }

    const library = await jget(`/api/servarr/${service}/${kind === 'movie' ? 'movies' : 'series'}`)
    if (!library.ok) throw new Error('Could not prepare this title in the library.')
    const existing = arrayOf(await apiJson(library), isCatalogItem).find((candidate) =>
      kind === 'movie' ? candidate.tmdbId === item.tmdbId : candidate.tvdbId === item.tvdbId,
    )
    if (existing?.id == null) throw new Error('Could not prepare this title in the library.')
    return existing.id
  }

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (submitting || !title.trim() || (mode === 'magnet' ? !magnet.trim() : !torrent)) return
    setSubmitting(true)
    setStatus(null)
    try {
      const targetId = await resolveTargetId()
      // Season/episode are optional coordinates: without them Sonarr treats the
      // source as a full-series pack, which is wrong for a single episode.
      const coordinates =
        kind === 'series'
          ? {
              ...(seasonNumber === '' ? {} : { seasonNumber: Number(seasonNumber) }),
              ...(episodeNumber === '' ? {} : { episodeNumber: Number(episodeNumber) }),
            }
          : {}

      let response: Response
      if (mode === 'magnet') {
        response = await jpost('/api/servarr/manual/magnet', {
          service,
          targetId,
          title: title.trim(),
          magnet: magnet.trim(),
          ...coordinates,
        })
      } else {
        const query = new URLSearchParams({ service, targetId: String(targetId), title: title.trim() })
        for (const [key, value] of Object.entries(coordinates)) query.set(key, String(value))
        response = await fetch(`/api/servarr/manual/torrent?${query}`, {
          method: 'POST',
          credentials: 'include',
          headers: { 'Content-Type': 'application/x-bittorrent' },
          body: torrent,
        })
      }

      if (!response.ok) {
        const failure = await apiJson(response).catch(() => null)
        throw new Error(
          isRecord(failure) && typeof failure.error === 'string' ? failure.error : 'Could not submit this source.',
        )
      }
      setStatus({ tone: 'ok', message: 'Source submitted for validation.' })
      onSubmitted()
    } catch (failure) {
      setStatus({
        tone: 'error',
        message: failure instanceof Error ? failure.message : 'Could not submit this source.',
      })
    } finally {
      setSubmitting(false)
    }
  }

  const done = status?.tone === 'ok'
  const canSubmit = !!title.trim() && (mode === 'magnet' ? !!magnet.trim() : !!torrent) && !submitting && !done

  return (
    <DiscoverSheet
      eyebrow="Manual source"
      title={item.title}
      subtitle={item.year != null ? String(item.year) : null}
      item={item}
      motion={motion}
      onClose={onClose}
      busy={submitting}
      footer={
        <button
          type="submit"
          form="an-manual-form"
          className="an-action is-primary is-wide"
          disabled={!canSubmit}
        >
          <AnIcon name={done ? 'check' : 'plus'} size={15} />
          <span>{submitting ? 'Submitting…' : done ? 'Submitted' : 'Submit source'}</span>
        </button>
      }
    >
      <form id="an-manual-form" onSubmit={submit}>
        <div className="an-dmodes" role="radiogroup" aria-label="Source type">
          {(['magnet', 'torrent'] as const).map((value) => (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={mode === value}
              className={mode === value ? 'is-active' : ''}
              onClick={() => {
                setMode(value)
                setStatus(null)
              }}
            >
              {value === 'magnet' ? 'Magnet link' : '.torrent file'}
            </button>
          ))}
        </div>

        <SheetField
          label="Release title"
          hint="Name it the way a release is named, so the library files it correctly."
        >
          <input
            className="an-dinput is-mono"
            value={title}
            maxLength={500}
            required
            placeholder={kind === 'movie' ? 'Movie.Title.2026.1080p.WEB-DL' : 'Series.Title.S01E01.1080p.WEB-DL'}
            onChange={(event) => setTitle(event.target.value)}
          />
        </SheetField>

        {kind === 'series' ? (
          <div className="an-dgrid">
            <SheetField label="Season (optional)">
              <input
                className="an-dinput is-mono"
                type="number"
                min={0}
                step={1}
                value={seasonNumber}
                onChange={(event) => {
                  setSeasonNumber(event.target.value)
                  // An episode without a season is not a coordinate.
                  if (event.target.value === '') setEpisodeNumber('')
                }}
              />
            </SheetField>
            <SheetField label="Episode (optional)">
              <input
                className="an-dinput is-mono"
                type="number"
                min={1}
                step={1}
                disabled={seasonNumber === ''}
                value={episodeNumber}
                onChange={(event) => setEpisodeNumber(event.target.value)}
              />
            </SheetField>
          </div>
        ) : null}

        {mode === 'magnet' ? (
          <SheetField label="Magnet URI">
            <textarea
              className="an-dinput is-mono"
              rows={4}
              required
              value={magnet}
              placeholder="magnet:?xt=urn:btih:…"
              onChange={(event) => setMagnet(event.target.value)}
            />
          </SheetField>
        ) : (
          <SheetField label="Torrent file" hint="2 MiB or smaller.">
            <input
              className="an-dinput"
              type="file"
              accept=".torrent,application/x-bittorrent"
              required
              onChange={(event) => {
                const file = event.target.files?.[0] ?? null
                if (file && file.size > MAX_TORRENT_BYTES) {
                  setTorrent(null)
                  setStatus({ tone: 'error', message: 'Torrent files must be 2 MiB or smaller.' })
                  event.target.value = ''
                  return
                }
                setTorrent(file)
                setStatus(null)
              }}
            />
          </SheetField>
        )}

        {status ? <SheetNotice tone={status.tone}>{status.message}</SheetNotice> : null}
      </form>
    </DiscoverSheet>
  )
}
