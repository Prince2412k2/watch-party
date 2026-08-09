import { useEffect, useState, type CSSProperties } from 'react'
import { analogTokens } from '../design/analogTokens.ts'
import { queueTitle, type FailingQueueItem } from '../hooks/useFailingDownloads.ts'
import { AnIcon } from './icons.tsx'
import { posterCssVars } from './AnalogPoster.tsx'
import {
  GAUGE_RING_PX,
  QUEUE_REMOVALS,
  STAGE_POSTER_PX,
  contextParts,
  downloadState,
  downloadStats,
  entryInitials,
  focusedDownload,
  primaryAction,
  progressPct,
  queueDetail,
  torrentTitle,
  type DownloadCatalog,
  type PrimaryKind,
  type RemovalIntent,
  type StageMessage,
  type TorrentLike,
} from './downloadsStage.ts'
import type { MotionProfile, StageLayout } from './stageLayout.ts'

/**
 * The focused download's live detail, on the browse stage itself.
 *
 * This is the surface that replaces BOTH halves of the old Downloads screen: the
 * poster grid, whose cards each carried a ring and a truncated status line, and
 * the separate full-screen overlay you had to open to read the speed, the ETA,
 * the seed and peer counts or reach pause and remove. On the stage there is one
 * focused item and it is already showing all of that, so there is nothing left
 * to drill into — the same relationship the Movies stage has to a title.
 *
 * The gauge deliberately says the number three times over: the arc, the percent
 * inside it, and the status word beneath. Progress drawn as a shape alone is
 * unreadable to anyone who cannot see the shape, and "92%" alone does not
 * distinguish a download that is moving from one that stalled at 92% an hour
 * ago.
 */

/** Glyphs the shared kit does not carry, kept here rather than added to
 *  icons.tsx while other surfaces are being rebuilt against that file. */
const GLYPH = {
  pause: 'M9 5v14M15 5v14',
  ban: 'M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM5 5l14 14',
}

function Glyph({ path, size = 15 }: { path: string; size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d={path} />
    </svg>
  )
}

// ── artwork ─────────────────────────────────────────────────────────────────

export interface AnalogDownloadArtProps {
  /**
   * A Radarr/Sonarr poster URL. A title still downloading is not in Jellyfin
   * yet, so this cannot go through the library image proxy `AnalogPoster` uses.
   */
  posterUrl: string | null
  /** Falls back to fixed-size initials, so nothing moves when art is missing. */
  title: string
  focused: boolean
  motion: MotionProfile
  caption?: string | null
  badge?: string | null
  /** null draws no bar at all; 0 draws an empty one. */
  progressPct?: number | null
  eager?: boolean
}

/**
 * Square, unrounded artwork at every size — the kit's own poster classes, so the
 * frame, the edge light, the cast shadow, the focus lift and the zero radius are
 * the same objects the rest of the stage uses rather than a second description
 * of them.
 */
export function AnalogDownloadArt({
  posterUrl,
  title,
  focused,
  motion,
  caption,
  badge = null,
  progressPct: pct = null,
  eager = false,
}: AnalogDownloadArtProps) {
  const [broken, setBroken] = useState(false)

  // A new poster deserves its own attempt; without this the first 404 on a slot
  // would blank every download that later scrolls through it.
  useEffect(() => setBroken(false), [posterUrl])

  return (
    <span className="an-poster" data-focused={focused} style={posterCssVars(motion)}>
      <span className="an-poster-shade" aria-hidden />
      <span className="an-poster-frame">
        {posterUrl && !broken ? (
          <img
            className="an-poster-art"
            src={posterUrl}
            alt=""
            draggable={false}
            referrerPolicy="no-referrer"
            loading={eager ? 'eager' : 'lazy'}
            decoding="async"
            onError={() => setBroken(true)}
          />
        ) : (
          <span className="an-poster-placeholder" aria-hidden>
            {entryInitials(title)}
          </span>
        )}
        {badge ? <span className="an-poster-badge">{badge}</span> : null}
        {pct != null ? (
          <span className="an-poster-progress" aria-hidden>
            <i style={{ width: `${Math.max(0, Math.min(100, pct))}%` }} />
          </span>
        ) : null}
      </span>
      {caption !== undefined ? <span className="an-poster-caption">{caption}</span> : null}
    </span>
  )
}

// ── the gauge ───────────────────────────────────────────────────────────────

function ProgressRing({
  pct,
  size,
  muted,
  label,
}: {
  pct: number
  size: number
  muted: boolean
  label: string
}) {
  const stroke = analogTokens.hairline.activePx
  const radius = (size - stroke) / 2
  const circumference = 2 * Math.PI * radius
  const centre = size / 2
  const vars = { '--an-k-dl-ring-label-px': `${Math.max(11, Math.round(size * 0.24))}px` } as CSSProperties

  return (
    // The role sits on the ring rather than on the block around it, so the
    // status word beside it stays a node of its own: a progressbar's descendants
    // are not reliably exposed, and that word is the reading that does not
    // depend on seeing a shape.
    <svg
      className="an-dl-ring"
      width={size}
      height={size}
      viewBox={`0 0 ${size} ${size}`}
      data-muted={muted}
      style={vars}
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={pct}
      aria-valuetext={`${pct}% — ${label}`}
    >
      <circle className="an-dl-ring-track" cx={centre} cy={centre} r={radius} strokeWidth={stroke} />
      <circle
        className="an-dl-ring-arc"
        cx={centre}
        cy={centre}
        r={radius}
        strokeWidth={stroke}
        strokeDasharray={circumference}
        strokeDashoffset={circumference * (1 - pct / 100)}
        transform={`rotate(-90 ${centre} ${centre})`}
      />
      <text className="an-dl-ring-label" x="50%" y="50%" dominantBaseline="central" textAnchor="middle">
        {pct}%
      </text>
    </svg>
  )
}

// ── the two kinds of focus ──────────────────────────────────────────────────

export interface TorrentFocus {
  record: TorrentLike
  /** The *arr lookup for this hash, once it has landed. */
  catalog: DownloadCatalog | null
  /** An action is in flight; the hub re-polls to confirm it. */
  busy: boolean
  /** Non-null while the removal confirmation is open. */
  removal: RemovalIntent | null
  onPrimary: () => void
  onAskRemove: () => void
  onToggleFiles: () => void
  onCancelRemove: () => void
  onConfirmRemove: () => void
}

export interface QueueFocus {
  item: FailingQueueItem
  busy: boolean
  open: boolean
  onAsk: () => void
  onCancel: () => void
  onRemove: (blocklist: boolean) => void
}

export interface AnalogDownloadDetailsProps {
  layout: StageLayout
  motion: MotionProfile
  /** Where this item sits: the mode, and its position in the rail. */
  eyebrow: string[]
  loading: boolean
  /** Shown in place of an item — which of the several nothings this is. */
  message: StageMessage | null
  /** Optional: nothing gates these controls now that browsing is never shared. */
  disabled?: boolean
  torrent?: TorrentFocus | null
  queue?: QueueFocus | null
}

export function AnalogDownloadDetails({
  layout,
  motion,
  eyebrow,
  loading,
  message,
  disabled,
  torrent = null,
  queue = null,
}: AnalogDownloadDetailsProps) {
  const vars = { '--an-k-dl-poster-px': `${STAGE_POSTER_PX[layout.size]}px` } as CSSProperties
  const ringPx = GAUGE_RING_PX[layout.size]

  if (loading) {
    return (
      <div className="an-dl-head" style={vars} aria-busy>
        <div className="an-dl-art">
          <span className="an-poster" data-focused={false} style={posterCssVars(motion)}>
            <span className="an-poster-frame">
              <span className="an-poster-skeleton" aria-hidden />
            </span>
          </span>
        </div>
        <div className="an-detail">
          <div className="an-dl-skeleton" aria-hidden>
            <i />
            <i />
            <i />
          </div>
        </div>
      </div>
    )
  }

  // No focused item: the artwork column goes away entirely rather than standing
  // an empty frame beside copy that is about a missing service, not a title.
  if (!torrent && !queue) {
    return (
      <div className="an-dl-head" style={vars}>
        <div className="an-detail">
          <Eyebrow parts={eyebrow} />
          <h1>{message?.title ?? 'Downloads'}</h1>
          {message?.hint ? <p>{message.hint}</p> : null}
        </div>
      </div>
    )
  }

  if (queue) {
    const { reasons, meta } = queueDetail(queue.item)
    const title = queueTitle(queue.item)
    return (
      <div className="an-dl-head" style={vars}>
        <div className="an-dl-art">
          <AnalogDownloadArt posterUrl={null} title={title} focused motion={motion} caption={undefined} />
          {/* No ring: a grab that died before it reached the download client has
              no progress to report, and an empty one would imply it started. */}
          <span className="an-dl-status" data-tone="danger">
            Stuck
          </span>
        </div>

        <div className="an-detail">
          <Eyebrow parts={eyebrow} />
          <h1>{title}</h1>

          <ul className="an-dl-reasons">
            {reasons.map((reason, index) => (
              <li key={index}>{reason}</li>
            ))}
          </ul>

          {meta.length > 0 ? (
            <div className="an-detail-meta">
              {meta.map((value, index) => (
                <span key={index}>{value}</span>
              ))}
            </div>
          ) : null}

          <div className="an-detail-actions">
            <button
              type="button"
              className="an-action is-danger"
              disabled={disabled || queue.busy}
              aria-expanded={queue.open}
              onClick={queue.onAsk}
            >
              <AnIcon name="trash" size={15} />
              <span>Resolve</span>
            </button>

            {queue.open ? (
              <div className="an-dl-confirm" role="dialog" aria-label="Resolve stuck download">
                <p>
                  <strong>{title}</strong> is stuck in the queue. Dropping it lets your library manager
                  look for the release again.
                </p>
                {QUEUE_REMOVALS.map((choice) => (
                  <button
                    key={String(choice.blocklist)}
                    type="button"
                    className="an-dl-choice"
                    disabled={disabled || queue.busy}
                    onClick={() => queue.onRemove(choice.blocklist)}
                  >
                    <strong>
                      {choice.blocklist ? <Glyph path={GLYPH.ban} size={14} /> : <AnIcon name="trash" size={14} />}
                      {choice.label}
                    </strong>
                    <small>{choice.hint}</small>
                  </button>
                ))}
                <div className="an-dl-confirm-actions">
                  <button type="button" className="an-action" onClick={queue.onCancel}>
                    <span>Cancel</span>
                  </button>
                </div>
              </div>
            ) : null}
          </div>
        </div>
      </div>
    )
  }

  const record = torrent!.record
  const current = downloadState(record.state)
  const pct = progressPct(record.progress)
  const action = primaryAction(current, torrent!.busy)
  const info = focusedDownload(record, torrent!.catalog)
  const context = contextParts(info, torrent!.catalog)
  const removal = torrent!.removal

  return (
    <div className="an-dl-head" style={vars}>
      <div className="an-dl-art">
        <AnalogDownloadArt
          posterUrl={info.posterUrl}
          title={info.title}
          focused
          motion={motion}
          caption={undefined}
        />
        <div className="an-dl-gauge">
          <ProgressRing pct={pct} size={ringPx} muted={current.paused} label={current.label} />
          <span className="an-dl-status" data-tone={current.tone}>
            {current.label}
          </span>
        </div>
      </div>

      <div className="an-detail">
        <Eyebrow parts={eyebrow} />
        <h1>{info.title}</h1>
        {/* The synopsis when the lookup has one, and otherwise the release line —
            which is the only thing a download that no *arr recognises can say
            about itself. */}
        {info.overview ?? info.subtitle ? <p>{info.overview ?? info.subtitle}</p> : null}

        {context.length > 0 ? (
          <div className="an-detail-meta an-dl-context">
            {context.map((value, index) => (
              <span key={index}>{value}</span>
            ))}
          </div>
        ) : null}

        {/* The live numbers stay the brighter of the two lines: they are the
            reason this screen is open, and the catalog copy is context for them. */}
        <div className="an-detail-meta">
          {downloadStats(record, current).map((value, index) => (
            <span key={index}>{value}</span>
          ))}
        </div>

        <div className="an-detail-actions">
          <button
            type="button"
            className="an-action is-primary"
            disabled={disabled || action.disabled}
            onClick={torrent!.onPrimary}
          >
            <PrimaryIcon kind={action.kind} />
            <span>{action.label}</span>
          </button>

          <button
            type="button"
            className="an-action is-danger"
            disabled={disabled || torrent!.busy}
            aria-expanded={removal != null}
            onClick={torrent!.onAskRemove}
          >
            <AnIcon name="trash" size={15} />
            <span>Remove</span>
          </button>

          {removal ? (
            <div className="an-dl-confirm" role="dialog" aria-label="Remove download">
              <p>
                <strong>{removal.title}</strong> will stop downloading and leave the queue.
              </p>

              {/* Off on every open. Erasing what is already on disk is a
                  different decision from cancelling a transfer, and one that
                  cannot be undone — so it is never inherited from last time. */}
              <button
                type="button"
                className="an-dl-toggle"
                role="switch"
                aria-checked={removal.deleteFiles}
                onClick={torrent!.onToggleFiles}
              >
                <span>
                  <strong>Also delete downloaded files</strong>
                  <small>Erase the data already on disk, not just the queue entry.</small>
                </span>
                <i data-on={removal.deleteFiles} aria-hidden />
              </button>

              <div className="an-dl-confirm-actions">
                <button type="button" className="an-action" onClick={torrent!.onCancelRemove}>
                  <span>Keep</span>
                </button>
                {/* The label follows the toggle, so the button always names what
                    it is about to do rather than what it usually does. */}
                <button
                  type="button"
                  className="an-action is-danger"
                  disabled={disabled}
                  onClick={torrent!.onConfirmRemove}
                >
                  <AnIcon name="trash" size={15} />
                  <span>{removal.deleteFiles ? 'Remove & delete' : 'Remove'}</span>
                </button>
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  )
}

function Eyebrow({ parts }: { parts: string[] }) {
  if (parts.length === 0) return null
  return (
    <div className="an-detail-eyebrow">
      {parts.map((part, index) => (
        <span key={index}>{part}</span>
      ))}
    </div>
  )
}

function PrimaryIcon({ kind }: { kind: PrimaryKind }) {
  switch (kind) {
    case 'pause':
      return <Glyph path={GLYPH.pause} />
    case 'resume':
      return <AnIcon name="play" size={15} filled />
    case 'retry':
      return <AnIcon name="update" size={15} />
    case 'none':
      return <AnIcon name="check" size={15} />
  }
}
