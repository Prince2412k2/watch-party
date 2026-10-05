import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { AnalogPoster } from '../analog/AnalogPoster.tsx'
import { AnIcon } from '../analog/icons.tsx'
import type { AnalogRailItem } from '../analog/AnalogRail.tsx'
import type { MotionProfile } from '../analog/stageLayout.ts'
import './phoneCatalog.css'

interface Props {
  title: string; label: string; items: readonly AnalogRailItem[]; selection: number
  onSelect: (index: number) => void; loading: boolean; error?: string
  back?: () => void; backLabel?: string; filters?: ReactNode
  details: ReactNode; nav: ReactNode; toolboxes: ReactNode; motion: MotionProfile
}

// Keep the native visual language, with an actual touch-scrolling library.
// A poster opens its details, never accidentally starts a movie after a swipe.
export function PhoneCatalog({ title, label, items, selection, onSelect, loading, error, back, backLabel, filters, details, nav, toolboxes, motion }: Props) {
  const [query, setQuery] = useState('')
  const [limit, setLimit] = useState(48)
  const [detailOpen, setDetailOpen] = useState(false)
  const dialogRef = useRef<HTMLDialogElement>(null)
  const closeRef = useRef<HTMLButtonElement>(null)
  const cardRef = useRef<HTMLButtonElement | null>(null)
  const scrollRef = useRef<HTMLDivElement>(null)
  const previousLabel = useRef(label)

  useEffect(() => {
    setQuery(''); setLimit(48); setDetailOpen(false)
    if (previousLabel.current !== label) scrollRef.current?.scrollTo(0, 0)
    previousLabel.current = label
  }, [label])
  useEffect(() => setLimit(48), [query])
  useEffect(() => {
    const dialog = dialogRef.current
    if (detailOpen && dialog && !dialog.open) { dialog.showModal(); closeRef.current?.focus() }
    if (!detailOpen && dialog?.open) { dialog.close(); cardRef.current?.focus({ preventScroll: true }) }
  }, [detailOpen])

  const filtered = useMemo(() => items.map((item, index) => ({ item, index })).filter(({ item }) => item.label.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())), [items, query])
  return (
    <div className="phone-catalog">
      <div className="phone-catalog-scroll" ref={scrollRef}>
        <header className="phone-catalog-header">
          {back && <button className="phone-back" onClick={back}><AnIcon name="back" size={18} /><span>{backLabel || 'Back'}</span></button>}
          <h1>{title}</h1>
          {filters && <div className="phone-catalog-filters">{filters}</div>}
          <label className="phone-search"><AnIcon name="search" size={18} /><input type="search" aria-label={`Search ${title}`} placeholder={`Search ${title.toLocaleLowerCase()}`} value={query} onChange={e => setQuery(e.target.value)} /></label>
        </header>
        <div className="phone-catalog-heading"><h2>{label}</h2><span>{loading && !error ? 'Loading…' : `${filtered.length} ${filtered.length === 1 ? 'title' : 'titles'}`}</span></div>
        {error && <div className="phone-catalog-error"><p role="alert">{error}</p><button className="phone-load-more" onClick={() => window.location.reload()}>Reload library</button></div>}
        <section className="phone-poster-grid" aria-label={label} aria-busy={loading}>
          {loading && !error ? Array.from({ length: 9 }, (_, index) => <div key={index} aria-hidden><AnalogPoster item={null} focused={false} motion={motion} caption="" /></div>) : filtered.slice(0, limit).map(({ item, index }) => (
            <button key={item.id} className="phone-poster-button" type="button" aria-label={`Details for ${item.label}`} onClick={event => { cardRef.current = event.currentTarget; onSelect(index); setDetailOpen(true) }}>
              <AnalogPoster item={item.art ?? null} src={item.artSrc} focused={false} motion={motion} caption={item.label} badge={item.badge} progressPct={item.progressPct} />
            </button>
          ))}
        </section>
        {!loading && !filtered.length && <p className="phone-catalog-empty">{query ? 'No titles match your search.' : 'No titles here yet.'}</p>}
        {filtered.length > limit && <button className="phone-load-more" onClick={() => setLimit(value => value + 48)}>Show more · {filtered.length - limit} remaining</button>}
      </div>
      <div className="phone-catalog-nav">{nav}</div>
      {toolboxes}
      <dialog className="phone-title-dialog" ref={dialogRef} aria-label={items[selection]?.label || 'Title details'} onCancel={() => setDetailOpen(false)} onClose={() => setDetailOpen(false)}>
        <div className="phone-title-top"><button ref={closeRef} className="phone-back" onClick={() => setDetailOpen(false)}><AnIcon name="back" size={18} />Library</button></div>
        <div className="phone-title-art"><AnalogPoster item={items[selection]?.art ?? null} focused={false} motion={motion} /></div>
        <div className="phone-title-copy" onClickCapture={event => {
          if ((event.target as HTMLElement).closest('button.is-primary')) setDetailOpen(false)
        }}>{details}</div>
      </dialog>
    </div>
  )
}
