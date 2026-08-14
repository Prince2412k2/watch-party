import type { ReactNode } from 'react'
import { AnIcon } from './icons.tsx'
import { eyebrowParts, metaLine, stageActions, type StageActions, type StageItem } from './movieDetails.ts'

/**
 * The focused title's details, on the browse stage itself.
 *
 * "Backdrop will not be this dark and will show the movie's details in the
 * library itself." There is no separate detail screen behind this one: the copy,
 * the metadata and the actions are what the stage shows while you browse, and
 * Enter plays — exactly the relationship an episode has to its series screen.
 */
export interface AnalogDetailsProps {
  item: StageItem | null
  /** Where the item sits: the library, or the franchise you drilled into. */
  context?: string | null
  /** Placeholder headline while the first list is still loading. */
  fallbackTitle: string
  error?: string | null
  native: boolean
  /**
   * The action set, when this surface's rule is not the movie one. Shows passes
   * `showActions`: a series opens rather than plays, so it offers neither a
   * track menu nor a download. Omitted, the movie rule applies.
   */
  actions?: StageActions
  disabled?: boolean
  onPlay: () => void
  onDownload: () => void
  onTracks: () => void
  tracksOpen?: boolean
  downloadState?: 'idle' | 'busy' | 'queued' | 'failed'
  /**
   * Removes the title and its files from the SERVER — everyone's copy, not a
   * local tidy-up. Omitted unless all of: the account is a Jellyfin
   * administrator, the item carries the provider id the *arr record is joined
   * on, and that record exists. Absent rather than disabled, because a greyed
   * delete on a hand-copied film invites a question with no answer worth
   * giving.
   */
  onDeleteFromServer?: () => void
  deleting?: boolean
  /** The track menu, mounted next to the button that opens it. */
  children?: ReactNode
}

const DOWNLOAD_LABEL: Record<NonNullable<AnalogDetailsProps['downloadState']>, string> = {
  idle: 'Download for offline',
  busy: 'Starting download',
  queued: 'Downloading',
  failed: 'Download failed — try again',
}

export function AnalogDetails({
  item,
  context = null,
  fallbackTitle,
  error = null,
  native,
  actions: actionsOverride,
  disabled = false,
  onPlay,
  onDownload,
  onTracks,
  onDeleteFromServer,
  deleting = false,
  tracksOpen = false,
  downloadState = 'idle',
  children,
}: AnalogDetailsProps) {
  const actions = actionsOverride ?? stageActions(item, native)
  const eyebrow = item ? eyebrowParts(item, context) : context ? [context] : []
  const meta = item ? metaLine(item) : []

  return (
    <div className="an-detail">
      {eyebrow.length > 0 ? (
        <div className="an-detail-eyebrow">
          {eyebrow.map((part, index) => (
            <span key={index}>{part}</span>
          ))}
        </div>
      ) : null}

      <h1>{item?.Name ?? fallbackTitle}</h1>

      {error ? (
        <p role="alert" className="an-detail-error">
          {error}
        </p>
      ) : item?.Overview ? (
        <p>{item.Overview}</p>
      ) : null}

      {meta.length > 0 ? (
        <div className="an-detail-meta">
          {meta.map((value, index) => (
            <span key={index}>{value}</span>
          ))}
        </div>
      ) : null}

      {item ? (
        <div className="an-detail-actions">
          <button type="button" className="an-action is-primary" disabled={disabled} onClick={onPlay}>
            <AnIcon name={actions.plays ? 'play' : 'enter'} size={15} filled={actions.plays} />
            <span>{actions.label}</span>
          </button>

          {actions.download ? (
            <button
              type="button"
              className="an-action is-icon"
              disabled={disabled || downloadState === 'busy'}
              data-state={downloadState}
              aria-label={DOWNLOAD_LABEL[downloadState]}
              title={DOWNLOAD_LABEL[downloadState]}
              onClick={onDownload}
            >
              <AnIcon name="download" size={16} />
            </button>
          ) : null}

          {actions.tracks ? (
            <button
              type="button"
              className={`an-action is-icon${tracksOpen ? ' is-open' : ''}`}
              disabled={disabled}
              aria-expanded={tracksOpen}
              aria-label="Audio and subtitles"
              title="Audio and subtitles"
              onClick={onTracks}
            >
              <AnIcon name="tracks" size={16} />
            </button>
          ) : null}

          {onDeleteFromServer ? (
            <button
              type="button"
              className="an-action is-icon is-danger"
              disabled={disabled || deleting}
              aria-label="Delete from the server"
              title="Delete from the server"
              onClick={onDeleteFromServer}
            >
              <AnIcon name="trash" size={16} />
            </button>
          ) : null}

          {children}
        </div>
      ) : null}
    </div>
  )
}
