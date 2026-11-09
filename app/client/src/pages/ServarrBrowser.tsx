import { useEffect, useMemo, useRef, useState } from 'react'
import { useAuth } from '../context/AuthContext.tsx'
import { jget } from '../lib/api.ts'
import { navigate } from '../router.ts'
import { posterUrl, type CatalogItem, type Service } from '../analog/discover/catalog.ts'
import './servarr.css'

interface LibraryTitle extends CatalogItem {
  id: number
  hasFile?: boolean
  episodeFileCount?: number
  episodeCount?: number
}
type LibraryState = { items: LibraryTitle[]; loading: boolean; error: string }
const initial = (): LibraryState => ({ items: [], loading: true, error: '' })
const available = (item: LibraryTitle, service: Service) => service === 'radarr' ? !!item.hasFile : (item.episodeFileCount ?? 0) > 0
const label = (service: Service) => service === 'sonarr' ? 'Sonarr' : 'Radarr'

function Poster({ item }: { item: LibraryTitle }) {
  const src = posterUrl(item.images)
  const [failed, setFailed] = useState(false)
  return src && !failed
    ? <img src={src} alt="" loading="lazy" onError={() => setFailed(true)} />
    : <span className="sb-poster-fallback" aria-hidden="true">{item.title.slice(0, 1)}</span>
}

export default function ServarrBrowser() {
  const { user } = useAuth()
  const [service, setService] = useState<Service>(() => new URLSearchParams(window.location.search).get('service') === 'radarr' ? 'radarr' : 'sonarr')
  const [libraries, setLibraries] = useState<Record<Service, LibraryState>>({ sonarr: initial(), radarr: initial() })
  const [revision, setRevision] = useState(0)
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('all')
  const [sort, setSort] = useState('title')
  const [selected, setSelected] = useState<LibraryTitle | null>(null)
  const dialog = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    const controller = new AbortController()
    for (const name of ['sonarr', 'radarr'] as const) {
      setLibraries(previous => ({ ...previous, [name]: { ...previous[name], loading: true, error: '' } }))
      void (async () => {
        try {
          const response = await jget(`/api/servarr/${name}/${name === 'sonarr' ? 'series' : 'movies'}`, controller.signal)
          if (!response.ok) throw new Error(response.status === 503
            ? `${label(name)} is not configured. Set its server URL and API key to connect your library.`
            : response.status === 401 ? 'Your session has expired. Please sign in again.'
            : `Could not reach ${label(name)}. Check that the service is running, then retry.`)
          const data: unknown = await response.json()
          if (!Array.isArray(data)) throw new Error(`${label(name)} returned an unexpected response.`)
          const items = data.filter((item): item is LibraryTitle => !!item && typeof item === 'object' && typeof item.id === 'number' && typeof item.title === 'string')
          if (!controller.signal.aborted) setLibraries(previous => ({ ...previous, [name]: { items, loading: false, error: '' } }))
        } catch (error) {
          if (!controller.signal.aborted) setLibraries(previous => ({ ...previous, [name]: { items: [], loading: false, error: error instanceof Error ? error.message : `Could not load ${label(name)}.` } }))
        }
      })()
    }
    return () => controller.abort()
  }, [revision])

  useEffect(() => {
    if (selected) dialog.current?.showModal()
    else dialog.current?.close()
  }, [selected])

  const library = libraries[service]
  const titles = useMemo(() => library.items.filter(item => {
    const matchesQuery = item.title.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())
    return matchesQuery && (filter === 'all' || (filter === 'available' ? available(item, service) : filter === 'missing' ? !available(item, service) : item.monitored))
  }).sort((a, b) => sort === 'year' ? (b.year ?? 0) - (a.year ?? 0) || a.title.localeCompare(b.title) : a.title.localeCompare(b.title)), [library.items, service, query, filter, sort])
  const availableCount = library.items.filter(item => available(item, service)).length

  const discoverHref = `/discover?type=${service === 'sonarr' ? 'series' : 'movie'}`

  function switchService(next: Service) {
    setService(next)
    setQuery('')
    setFilter('all')
    window.history.replaceState({}, '', `/servarr?service=${next}`)
  }

  return (
    <div className="sb-page">
      <header className="sb-header">
        <a className="sb-brand" href="/movies" onClick={event => { event.preventDefault(); navigate('/movies') }}><span className="sb-brand-mark">W</span> Watch Party</a>
        <nav aria-label="Media navigation"><a href="/movies">Watch</a><a href="/servarr" aria-current="page">Sonarr & Radarr</a><a href="/downloads">Downloads</a></nav>
      </header>
      <main className="sb-main">
        <div className="sb-heading">
          <div><p className="sb-eyebrow">YOUR MEDIA, TOGETHER</p><h1>The library room.</h1><p>Browse your shows in Sonarr and movies in Radarr.</p></div>
          <button className="sb-button" onClick={() => setRevision(value => value + 1)} disabled={library.loading}>{library.loading ? 'Refreshing…' : 'Refresh libraries'}</button>
        </div>
        <div className="sb-services" role="group" aria-label="Choose media service">
          {(['sonarr', 'radarr'] as const).map(name => <button key={name} aria-pressed={service === name} className={`sb-service ${service === name ? 'is-active' : ''}`} onClick={() => switchService(name)}>
            <span className="sb-service-initial" aria-hidden="true">{name === 'sonarr' ? 'S' : 'R'}</span>
            <span><strong>{label(name)}</strong><span>{name === 'sonarr' ? 'TV shows' : 'Movies'}</span></span>
            <span className="sb-service-count">{libraries[name].loading ? '…' : libraries[name].error ? 'Offline' : libraries[name].items.length}</span>
          </button>)}
        </div>
        <section aria-labelledby="sb-library-title">
          <div className="sb-library-heading"><h2 id="sb-library-title">{service === 'sonarr' ? 'Your shows' : 'Your movies'}</h2><span>{!library.loading && !library.error ? `${library.items.length} titles · ${availableCount} available` : label(service)}</span></div>
          <div className="sb-toolbar">
            <div className="sb-search"><label htmlFor="sb-search">Search your library</label><input id="sb-search" type="search" placeholder={service === 'sonarr' ? 'Find a show…' : 'Find a movie…'} value={query} onChange={event => setQuery(event.target.value)} /></div>
            <div><label htmlFor="sb-filter">Show</label><select id="sb-filter" value={filter} onChange={event => setFilter(event.target.value)}><option value="all">All titles</option><option value="available">Available</option><option value="missing">Missing</option><option value="monitored">Monitored</option></select></div>
            <div><label htmlFor="sb-sort">Sort by</label><select id="sb-sort" value={sort} onChange={event => setSort(event.target.value)}><option value="title">Title A–Z</option><option value="year">Newest year</option></select></div>
          </div>
          {library.loading ? <div className="sb-grid" aria-label="Loading library" aria-busy="true">{Array.from({ length: 12 }, (_, index) => <div className="sb-skeleton" key={index} />)}</div>
            : library.error ? <div className="sb-empty" role="alert"><h3>{label(service)} is unavailable</h3><p>{library.error}</p><button className="sb-button" onClick={() => setRevision(value => value + 1)}>Try again</button></div>
            : titles.length === 0 ? <div className="sb-empty"><h3>{library.items.length ? 'No matching titles' : 'Your next favorite belongs here.'}</h3><p>{library.items.length ? 'Try a different search or filter.' : `Titles you add to ${label(service)} will appear here.`}</p>{library.items.length ? <button className="sb-button" onClick={() => { setQuery(''); setFilter('all') }}>Clear filters</button> : user?.isAdmin ? <a className="sb-button" href={discoverHref}>Discover titles</a> : null}</div>
            : <><p className="sb-result-count" aria-live="polite">{titles.length} {titles.length === 1 ? 'title' : 'titles'}</p><div className="sb-grid">{titles.map(item => <button className="sb-card" key={`${service}-${item.id}`} onClick={() => setSelected(item)} aria-label={`View ${item.title}`}><span className="sb-poster"><Poster item={item} /><span className={`sb-status ${available(item, service) ? 'is-available' : ''}`}>{available(item, service) ? 'Available' : 'Missing'}</span></span><strong>{item.title}</strong><span className="sb-card-meta">{item.year || 'Year unknown'}<span>{service === 'sonarr' && item.seasonCount != null ? `${item.seasonCount} seasons` : item.monitored ? 'Monitored' : 'Unmonitored'}</span></span></button>)}</div></>}
        </section>
        <footer className="sb-footer">Connected through Watch Party <span>Sonarr / TV · Radarr / Movies</span></footer>
      </main>
      <dialog ref={dialog} className="sb-dialog" onCancel={() => setSelected(null)} onClose={() => setSelected(null)} onClick={event => { if (event.target === event.currentTarget) setSelected(null) }} aria-labelledby="sb-detail-title">
        {selected && <div className="sb-detail"><button className="sb-close sb-button" onClick={() => setSelected(null)} autoFocus>Close</button><div className="sb-detail-poster"><Poster item={selected} /></div><div className="sb-detail-copy"><p className="sb-eyebrow">{label(service)} · {selected.year || 'Year unknown'}</p><h2 id="sb-detail-title">{selected.title}</h2><p className="sb-detail-status">{available(selected, service) ? 'Available in your library' : 'No files available'} · {selected.monitored ? 'Monitored' : 'Unmonitored'}</p><p>{selected.overview || 'No synopsis is available for this title.'}</p>{selected.genres?.length ? <p className="sb-genres">{selected.genres.join(' / ')}</p> : null}{service === 'sonarr' && <p>{selected.episodeFileCount ?? 0} of {selected.episodeCount ?? 0} aired episodes downloaded · {selected.seasonCount ?? 0} seasons</p>}{selected.runtime ? <p>{selected.runtime} min{service === 'sonarr' ? ' per episode' : ''}</p> : null}{user?.isAdmin && <a className="sb-button" href={`${discoverHref}&q=${encodeURIComponent(selected.title)}`}>Find in Discover</a>}</div></div>}
      </dialog>
    </div>
  )
}
