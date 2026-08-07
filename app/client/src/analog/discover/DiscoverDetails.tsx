import { AnIcon } from '../icons.tsx'
import { fmtEta, fmtRuntimeFromMinutes, fmtSpeed } from '../../lib/format.ts'
import { eyebrowParts, metaLine, type CatalogItem, type Kind, type TorrentLike } from './catalog.ts'
import { canChooseSource, primaryActionLabel, stateDetail, type TitleState } from './cardState.ts'

/**
 * The focused catalog title, on the stage itself.
 *
 * Same relationship the Movies stage has to its library: the copy, the metadata
 * and every action are what the stage shows WHILE you browse, and there is no
 * second screen behind it. That is also the fix for the guardrail violation this
 * replaces — the surface it supersedes hid both the overview and the Download
 * button behind `:hover` on the poster, which put the primary action of the
 * entire screen out of reach of touch, keyboard and remote.
 *
 * Everything here is visible at rest.
 */
export interface DiscoverDetailsProps {
  item: CatalogItem | null
  kind: Kind
  state: TitleState | null
  torrent: TorrentLike | null
  /** Headline while the first list is still loading, or when nothing matched. */
  fallbackTitle: string
  /** Sentence under the headline when there is no focused title. */
  fallbackBody?: string | null
  error?: string | null
  disabled?: boolean
  onRequest: () => void
  onOptions: () => void
  onSources: () => void
  onManual: () => void
  onSeasons: () => void
  onRemove: () => void
  /** True while the series has seasons to choose between. */
  hasSeasons: boolean
}

export function DiscoverDetails({
  item,
  kind,
  state,
  torrent,
  fallbackTitle,
  fallbackBody = null,
  error = null,
  disabled = false,
  onRequest,
  onOptions,
  onSources,
  onManual,
  onSeasons,
  onRemove,
  hasSeasons,
}: DiscoverDetailsProps) {
  const eyebrow = item ? eyebrowParts(item, kind) : []
  const meta = item ? metaLine(item, kind, fmtRuntimeFromMinutes(item.runtime)) : []
  const detail = item && state ? stateDetail(state, kind) : null

  return (
    <div className="an-detail">
      {eyebrow.length > 0 ? (
        <div className="an-detail-eyebrow">
          {eyebrow.map((part, index) => (
            <span key={index}>{part}</span>
          ))}
        </div>
      ) : null}

      <h1>{item?.title ?? fallbackTitle}</h1>

      {error ? (
        <p role="alert" className="an-detail-error">
          {error}
        </p>
      ) : item?.overview ? (
        <p>{item.overview}</p>
      ) : !item && fallbackBody ? (
        <p>{fallbackBody}</p>
      ) : null}

      {meta.length > 0 ? (
        <div className="an-detail-meta">
          {meta.map((value, index) => (
            <span key={index}>{value}</span>
          ))}
        </div>
      ) : null}

      {item && state ? (
        <>
          {state.phase === 'downloading' ? (
            <DownloadProgress state={state} torrent={torrent} />
          ) : null}

          {detail ? (
            <p className="an-dstate" data-tone={state.retryable ? 'warn' : 'info'}>
              {state.retryable ? <AnIcon name="alert" size={14} /> : null}
              <span>{detail}</span>
            </p>
          ) : null}

          <div className="an-detail-actions">
            <PrimaryAction
              kind={kind}
              state={state}
              disabled={disabled}
              hasSeasons={hasSeasons}
              onRequest={onRequest}
              onSeasons={onSeasons}
            />

            {/* Every secondary control is a labelled, always-present button.
                None of them is revealed by hover, and none of them is the only
                route to something the primary action cannot do. */}
            {canChooseSource(state) ? (
              <>
                {kind === 'series' && hasSeasons ? (
                  <IconAction
                    icon="tv"
                    label="Download the whole series"
                    disabled={disabled}
                    onClick={onRequest}
                  />
                ) : null}

                {kind === 'movie' ? (
                  <IconAction
                    icon="search"
                    label={state.inLibrary ? 'Choose a release' : 'See all sources'}
                    disabled={disabled}
                    onClick={onSources}
                  />
                ) : null}

                <IconAction
                  icon="settings"
                  label="Download options"
                  disabled={disabled}
                  onClick={onOptions}
                />
                <IconAction
                  icon="plus"
                  label="Add a magnet link or torrent file"
                  disabled={disabled}
                  onClick={onManual}
                />
              </>
            ) : null}

            {state.inLibrary ? (
              <IconAction
                icon="trash"
                label="Remove from library"
                tone="danger"
                disabled={disabled}
                onClick={onRemove}
              />
            ) : null}
          </div>
        </>
      ) : null}
    </div>
  )
}

/**
 * The one action the stage leads with.
 *
 * A series with a season list leads with the chooser rather than a whole-series
 * grab: TV arrives in pieces and "download everything" is rarely what was meant.
 * The whole-series request stays one button away, next to it.
 */
function PrimaryAction({
  kind,
  state,
  disabled,
  hasSeasons,
  onRequest,
  onSeasons,
}: {
  kind: Kind
  state: TitleState
  disabled: boolean
  hasSeasons: boolean
  onRequest: () => void
  onSeasons: () => void
}) {
  // Nothing to press: these two states resolve on their own and a button would
  // only offer to start them again.
  if (state.phase === 'downloading' || state.phase === 'searching') {
    return (
      <span className="an-action is-static" aria-live="polite">
        <span className="an-dpulse" aria-hidden />
        <span>{primaryActionLabel(state)}</span>
      </span>
    )
  }

  if (state.phase === 'monitoring' || (state.phase === 'added' && !(kind === 'series' && hasSeasons))) {
    return (
      <span className="an-action is-static">
        <AnIcon name="check" size={15} />
        <span>{primaryActionLabel(state)}</span>
      </span>
    )
  }

  if (kind === 'series' && hasSeasons) {
    return (
      <button type="button" className="an-action is-primary" disabled={disabled} onClick={onSeasons}>
        <AnIcon name="tv" size={15} />
        <span>Choose seasons</span>
      </button>
    )
  }

  return (
    <button type="button" className="an-action is-primary" disabled={disabled} onClick={onRequest}>
      <AnIcon name={state.retryable ? 'alert' : 'download'} size={15} />
      <span>{state.phase === 'idle' && kind === 'series' ? 'Download series' : primaryActionLabel(state)}</span>
    </button>
  )
}

function IconAction({
  icon,
  label,
  onClick,
  disabled,
  tone,
}: {
  icon: 'search' | 'settings' | 'plus' | 'trash' | 'tv'
  label: string
  onClick: () => void
  disabled: boolean
  tone?: 'danger'
}) {
  return (
    <button
      type="button"
      className="an-action is-icon"
      data-tone={tone}
      disabled={disabled}
      aria-label={label}
      title={label}
      onClick={onClick}
    >
      <AnIcon name={icon} size={16} />
    </button>
  )
}

/**
 * Live progress, with the three numbers that answer "is this actually moving":
 * speed, ETA and seeds. A stalled download at 4% with zero seeds looks exactly
 * like a healthy one without them.
 */
function DownloadProgress({ state, torrent }: { state: TitleState; torrent: TorrentLike | null }) {
  return (
    <div className="an-dprogress">
      <div className="an-dprogress-bar" role="progressbar" aria-valuenow={state.pct ?? undefined} aria-valuemin={0} aria-valuemax={100}>
        <i style={{ width: state.live ? `${state.pct}%` : '15%' }} data-indeterminate={!state.live} />
      </div>
      {state.live && torrent ? (
        <div className="an-detail-meta">
          <span>↓ {fmtSpeed(torrent.dlspeed)}</span>
          <span>ETA {(state.pct ?? 0) >= 100 ? '—' : fmtEta(torrent.eta)}</span>
          <span>{torrent.numSeeds ?? 0} seeds</span>
          <span>{torrent.numLeechs ?? 0} peers</span>
        </div>
      ) : null}
    </div>
  )
}
