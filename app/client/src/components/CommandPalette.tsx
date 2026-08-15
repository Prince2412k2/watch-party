import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import '../analog/commandPalette.css'
import { AnIcon } from '../analog/icons.tsx'
import { artworkSrc } from '../analog/artwork.ts'
import {
  moveHighlight,
  opensPalette,
  rankPalette,
  type PaletteItem,
} from '../analog/palette.ts'
import { navigate } from '../router.ts'
import { apiJson, arrayOf, isLibraryItemJson } from '../types/guards.ts'

/**
 * The fuzzy finder, on `/` and Ctrl/Cmd-K.
 *
 * fzf's two panes: the matches down the left, and what the highlight is sitting
 * on shown at size on the right, changing as the highlight moves. Keyboard
 * first, because both of its entry points are keys and a finder you have to
 * reach for the mouse to finish is worse than no finder.
 *
 * The library is fetched once per opening rather than held: it is a single
 * request the server already caches per user, and holding it would mean going
 * stale exactly when someone has just watched something.
 */
export default function CommandPalette() {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [items, setItems] = useState<PaletteItem[]>([])
  const [highlight, setHighlight] = useState(0)
  const inputRef = useRef<HTMLInputElement | null>(null)

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null
      const editing = Boolean(
        target && (target.isContentEditable ||
          ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)),
      )
      if (!opensPalette(event.key, { ctrl: event.ctrlKey, meta: event.metaKey }, editing)) {
        return
      }
      event.preventDefault()
      setOpen(current => !current)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  useEffect(() => {
    if (!open) {
      setQuery('')
      setHighlight(0)
      return
    }
    inputRef.current?.focus()
    let cancelled = false
    fetch('/api/library/items', { credentials: 'include' })
      .then(r => (r.ok ? apiJson(r) : null))
      .then(value => {
        if (cancelled) return
        setItems(arrayOf(value, isLibraryItemJson).map(entry => ({
          id: entry.Id,
          label: entry.Name ?? '',
          trailing: entry.ProductionYear ? String(entry.ProductionYear) : null,
          kind: entry.Type ?? null,
          imageUrl: artworkSrc({
            kind: 'series',
            itemId: entry.Id,
            imageTag: null,
            label: null,
          }),
        })))
      })
      // Offline or signed out: the finder opens empty and says so, rather than
      // refusing to open at all.
      .catch(() => {})
    return () => { cancelled = true }
  }, [open])

  const matches = useMemo(() => rankPalette(items, query), [items, query])
  const current = matches[Math.min(highlight, Math.max(0, matches.length - 1))]

  const activate = useCallback(() => {
    if (!current) return
    setOpen(false)
    navigate(`/party/new?itemId=${encodeURIComponent(current.id)}`)
  }, [current])

  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault()
        setHighlight(h => moveHighlight(h, 1, matches.length))
        break
      case 'ArrowUp':
        event.preventDefault()
        setHighlight(h => moveHighlight(h, -1, matches.length))
        break
      case 'Enter':
        event.preventDefault()
        activate()
        break
      case 'Escape':
        event.preventDefault()
        setOpen(false)
        break
    }
  }

  if (!open) return null

  return (
    <div className="an-palette-scrim" onMouseDown={() => setOpen(false)}>
      <div
        className="an-palette"
        role="dialog"
        aria-label="Find a title"
        onMouseDown={event => event.stopPropagation()}
      >
        <div className="an-palette-search">
          <AnIcon name="search" size={16} />
          <input
            ref={inputRef}
            value={query}
            placeholder="Search your library"
            onChange={event => { setQuery(event.target.value); setHighlight(0) }}
            onKeyDown={onKeyDown}
            aria-label="Search your library"
          />
        </div>

        <div className="an-palette-body">
          <ul className="an-palette-list" role="listbox">
            {matches.length === 0 ? (
              <li className="an-palette-empty">No matches</li>
            ) : matches.map((match, index) => (
              <li key={match.id}>
                <button
                  type="button"
                  role="option"
                  aria-selected={index === highlight}
                  className={index === highlight ? 'is-active' : undefined}
                  onMouseEnter={() => setHighlight(index)}
                  onClick={activate}
                >
                  <span>{match.label}</span>
                  {match.trailing ? <small>{match.trailing}</small> : null}
                </button>
              </li>
            ))}
          </ul>

          {/* The right pane. Reserved whether or not the highlighted row has
              artwork — a pane that appeared and vanished as the highlight moved
              would resize the sheet under the reader's hands. */}
          <div className="an-palette-preview">
            {current?.imageUrl ? (
              <img src={current.imageUrl} alt="" />
            ) : (
              <div className="an-palette-preview-empty" aria-hidden />
            )}
            {current ? (
              <>
                <strong>{current.label}</strong>
                {current.trailing ? <small>{current.trailing}</small> : null}
              </>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  )
}
