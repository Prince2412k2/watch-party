import { useEffect, useRef, type FormEvent } from 'react'
import { AnIcon } from '../icons.tsx'
import { KINDS, KIND_LABELS, type Kind } from './catalog.ts'
import { SUGGESTED_SEARCHES } from './query.ts'

/**
 * Movies ⇄ Shows, on the stage's right rail.
 *
 * The same position-on-a-slider the Movies stage uses for Singles/Collections,
 * for the same reason: it is one axis with two detents, driven by Up/Down and by
 * a stepped scroll outside the rail. What it replaces was a segmented control
 * floating above a search box — a second, differently-shaped control for a
 * choice the stage already knows how to express.
 *
 * Still real buttons: a mode switch reachable only by gesture would be an
 * important action hidden behind one.
 */
export function DiscoverKindSlider({
  kind,
  onChange,
  disabled = false,
}: {
  kind: Kind
  onChange: (kind: Kind) => void
  disabled?: boolean
}) {
  return (
    <div className="an-modes" role="tablist" aria-label="Catalog">
      {KINDS.map((candidate) => (
        <button
          key={candidate}
          type="button"
          role="tab"
          className={candidate === kind ? 'is-active' : ''}
          aria-selected={candidate === kind}
          disabled={disabled}
          onClick={() => onChange(candidate)}
        >
          <span>{KIND_LABELS[candidate]}</span>
          {/* Selection is never colour alone: the active position also carries
              the detent rule, which survives a monochrome display. */}
          <i aria-hidden />
        </button>
      ))}
    </div>
  )
}

/**
 * The search field, at the top of the stage head.
 *
 * A form, so Enter submits on every platform and a phone keyboard shows a Search
 * key. The debounce means the submit is usually redundant — but "usually" is not
 * "always" when the network is slow, and a text field that ignores Enter reads as
 * broken.
 *
 * `autoFocus` is deliberately absent: this stage is driven by arrow keys, and
 * stealing the caret on mount would make the rail unreachable without a click.
 */
export interface DiscoverSearchProps {
  term: string
  kind: Kind
  onTerm: (term: string) => void
  onSubmit: () => void
  onClear: () => void
  loading: boolean
  disabled?: boolean
}

export function DiscoverSearch({
  term,
  kind,
  onTerm,
  onSubmit,
  onClear,
  loading,
  disabled = false,
}: DiscoverSearchProps) {
  const inputRef = useRef<HTMLInputElement>(null)

  // "/" focuses the field, the way every search-first surface on the web does.
  // Bound at the window because the stage owns the keyboard: without it the only
  // route to the field is a pointer.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== '/' || event.metaKey || event.ctrlKey || event.altKey) return
      const target = event.target as HTMLElement | null
      if (target?.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target?.tagName ?? '')) return
      // A sheet owns the keyboard while it is open; pulling focus to a field
      // behind it would strand whoever was working in it.
      if (target?.closest?.('.an-dsheet')) return
      event.preventDefault()
      inputRef.current?.focus()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  const submit = (event: FormEvent) => {
    event.preventDefault()
    onSubmit()
  }

  return (
    <form className="an-dsearch" onSubmit={submit} role="search">
      <span className="an-dsearch-glyph" aria-hidden>
        <AnIcon name="search" size={15} />
      </span>
      <input
        ref={inputRef}
        type="search"
        value={term}
        disabled={disabled}
        aria-label={`Search ${kind === 'movie' ? 'movies' : 'series'} by title`}
        placeholder={disabled ? 'Discover is unavailable right now' : `Search ${kind === 'movie' ? 'movies' : 'series'}…`}
        onChange={(event) => onTerm(event.target.value)}
        // The rail's Escape means Back; inside the field it means "abandon what
        // I typed", which has to be handled here or the search survives it.
        onKeyDown={(event) => {
          if (event.key !== 'Escape') return
          event.preventDefault()
          event.stopPropagation()
          if (term) onClear()
          else inputRef.current?.blur()
        }}
      />
      {loading ? <span className="an-dsearch-busy" aria-hidden /> : null}
      {term && !loading ? (
        <button type="button" className="an-dsearch-clear" aria-label="Clear search" onClick={onClear}>
          <AnIcon name="x" size={14} />
        </button>
      ) : null}
    </form>
  )
}

/**
 * Tappable titles that seed the search box.
 *
 * Shown wherever Discover would otherwise be an empty box with a cursor in it —
 * a search that matched nothing, and a feed that could not be reached.
 */
export function SuggestedSearches({
  kind,
  onPick,
  heading,
}: {
  kind: Kind
  onPick: (term: string) => void
  heading: string
}) {
  return (
    <div className="an-dsuggest">
      <span className="an-dsuggest-head">{heading}</span>
      <div className="an-dsuggest-chips">
        {SUGGESTED_SEARCHES[kind].map((title) => (
          <button key={title} type="button" onClick={() => onPick(title)}>
            {title}
          </button>
        ))}
      </div>
    </div>
  )
}
