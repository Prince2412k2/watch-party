import { useEffect, useRef, type ReactNode } from 'react'
import { AnIcon } from '../icons.tsx'
import { AnalogPoster } from '../AnalogPoster.tsx'
import { posterUrl, type CatalogItem } from './catalog.ts'
import type { MotionProfile } from '../stageLayout.ts'

/**
 * The chrome every one of Discover's four decisions shares.
 *
 * The stage itself has no room for a release list, a profile picker or a file
 * upload, and none of them is a browse step — so each opens over the stage as a
 * sheet rather than pushing a level onto the rail. They are the only surfaces in
 * Discover that do, and they all close the same way: the X, the backdrop, and
 * Escape. Missing any of the three is how a modal traps someone.
 */
export interface DiscoverSheetProps {
  /** Announced as the dialog's name. */
  title: string
  /** Small caps line above the title. */
  eyebrow: string
  /** Under the title: year, counts, whatever identifies the target. */
  subtitle?: string | null
  item: CatalogItem
  motion: MotionProfile
  onClose: () => void
  /** Set while a request is in flight, so a stray Escape cannot orphan it. */
  busy?: boolean
  children: ReactNode
  /** Pinned under the scrolling body — the submit button, usually. */
  footer?: ReactNode
}

export function DiscoverSheet({
  title,
  eyebrow,
  subtitle = null,
  item,
  motion,
  onClose,
  busy = false,
  children,
  footer,
}: DiscoverSheetProps) {
  const panelRef = useRef<HTMLDivElement>(null)

  // Escape closes, and never reaches the stage behind: the rail treats Escape as
  // Back, so letting it through would close the sheet AND clear the search.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.preventDefault()
      event.stopPropagation()
      if (!busy) onClose()
    }
    window.addEventListener('keydown', onKeyDown, true)
    return () => window.removeEventListener('keydown', onKeyDown, true)
  }, [busy, onClose])

  // Focus moves into the sheet on open, so a keyboard user is not left tabbing
  // through the stage underneath looking for the thing that just appeared.
  useEffect(() => {
    panelRef.current?.focus({ preventScroll: true })
  }, [])

  return (
    <div
      className="an-dsheet-scrim"
      onPointerDown={(event) => {
        if (event.target === event.currentTarget && !busy) onClose()
      }}
    >
      <div
        ref={panelRef}
        className="an-dsheet"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        aria-busy={busy || undefined}
        tabIndex={-1}
      >
        <header className="an-dsheet-head">
          <span className="an-dsheet-poster">
            <AnalogPoster
              item={{ Id: `sheet:${title}`, Name: item.title, ImageTags: null }}
              src={posterUrl(item.images)}
              focused={false}
              motion={motion}
              caption={null}
            />
          </span>
          <div className="an-dsheet-headline">
            <span className="an-dsheet-eyebrow">{eyebrow}</span>
            <h2>{title}</h2>
            {subtitle ? <span className="an-dsheet-sub">{subtitle}</span> : null}
          </div>
          <button
            type="button"
            className="an-icon-button"
            aria-label="Close"
            title="Close"
            disabled={busy}
            onClick={onClose}
          >
            <AnIcon name="x" size={15} />
          </button>
        </header>

        <div className="an-dsheet-body">{children}</div>
        {footer ? <div className="an-dsheet-foot">{footer}</div> : null}
      </div>
    </div>
  )
}

/** A labelled form control. Always a real label, never a placeholder standing in for one. */
export function SheetField({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <label className="an-dfield">
      <span className="an-dfield-label">{label}</span>
      {children}
      {hint ? <span className="an-dfield-hint">{hint}</span> : null}
    </label>
  )
}

export type NoticeTone = 'error' | 'warn' | 'ok'

/**
 * A status line. `role="alert"` on the failures only: an "ok" that interrupts a
 * screen reader mid-sentence to confirm what it was just asked to do is noise.
 */
export function SheetNotice({ tone, children }: { tone: NoticeTone; children: ReactNode }) {
  return (
    <p className="an-dnotice" data-tone={tone} role={tone === 'ok' ? 'status' : 'alert'}>
      <AnIcon name={tone === 'ok' ? 'check' : 'alert'} size={14} />
      <span>{children}</span>
    </p>
  )
}
