import { useEffect, useRef, useState } from 'react'
import { AnalogNav } from '../analog/AnalogNav.tsx'
import { useAuth } from '../context/AuthContext.tsx'
import { navigate } from '../router.ts'
import {
  cacheShell,
  command,
  initializeOffline,
  listMedia,
  ready,
  OFFLINE_SUPPORTED,
  type SavedMedia
} from '../offline/client.ts'
import { backgroundManager, backgroundProgress } from '../offline/background.ts'
import '../analog/analogKit.css'
import './saved.css'
const size = (n: number) =>
  n < 1024 ** 3
    ? `${Math.round(n / 1024 ** 2)} MB`
    : `${(n / 1024 ** 3).toFixed(2)} GB`
const progressBytes = (file: SavedMedia) =>
  Math.min(
    file.size,
    Math.max(
      file.received,
      (file.backgroundBase ?? 0) + (file.backgroundDownloaded ?? 0)
    )
  )
function Glyph({
  kind
}: {
  kind: 'play' | 'more' | 'back' | 'download' | 'info'
}) {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      aria-hidden="true"
    >
      {kind === 'play' ? (
        <path d="m9 5 11 7-11 7Z" fill="currentColor" stroke="none" />
      ) : kind === 'more' ? (
        <>
          <circle cx="5" cy="12" r="1" />
          <circle cx="12" cy="12" r="1" />
          <circle cx="19" cy="12" r="1" />
        </>
      ) : kind === 'back' ? (
        <path d="m14 6-6 6 6 6" />
      ) : kind === 'info' ? (
        <>
          <circle cx="12" cy="12" r="9" />
          <path d="M12 11v6m0-10v1" />
        </>
      ) : (
        <path d="M12 3v12m-5-5 5 5 5-5M5 17v4h14v-4" />
      )}
    </svg>
  )
}
export default function SavedMovies() {
  const { user } = useAuth()
  const [files, setFiles] = useState<SavedMedia[]>([])
  const [tab, setTab] = useState<'download' | 'cache'>('download')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [busy, setBusy] = useState('')
  const [menu, setMenu] = useState<string | null>(null)
  const [details, setDetails] = useState(false)
  const [background, setBackground] = useState(false)
  const [quota, setQuota] = useState(0)
  const warmed = useRef(new Set<string>())
  useEffect(() => {
    if (!user || !OFFLINE_SUPPORTED) return
    let mounted = true
    const refresh = async () => {
      try {
        const registration = await ready()
        const rows = await listMedia(user.userId)
        const files = await backgroundProgress(registration, rows)
        const estimate = await navigator.storage?.estimate?.()
        if (!mounted) return
        setFiles(files)
        setQuota(estimate?.quota ?? 0)
        setBackground(!!backgroundManager(registration))
        for (const file of rows) {
          if (
            !file.artwork &&
            !file.posterAttempted &&
            !warmed.current.has(file.key) &&
            navigator.onLine
          ) {
            warmed.current.add(file.key)
            void command('artwork', file.key).catch(() => {})
          }
        }
      } catch (err) {
        if (mounted)
          setError(
            err instanceof Error ? err.message : 'Could not read saved movies'
          )
      }
    }
    void initializeOffline(user.userId)
      .then(refresh)
      .catch((err) => {
        if (mounted) setError(err.message)
      })
    const timer = setInterval(() => void refresh(), 1000)
    return () => {
      mounted = false
      clearInterval(timer)
    }
  }, [user?.userId])
  useEffect(() => {
    if (!menu) return
    const close = (event: Event) => {
      if (
        !(event.target instanceof Element) ||
        !event.target.closest('[data-saved-menu]')
      )
        setMenu(null)
    }
    const escape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setMenu(null)
    }
    document.addEventListener('pointerdown', close)
    document.addEventListener('keydown', escape)
    return () => {
      document.removeEventListener('pointerdown', close)
      document.removeEventListener('keydown', escape)
    }
  }, [menu])
  const action = async (kind: string, key?: string) => {
    if (busy) return
    setBusy(key || 'all')
    setMenu(null)
    setError('')
    setNotice('')
    try {
      if (kind === 'pin')
        await navigator.storage?.persist?.().catch(() => false)
      const result = await command(kind, key)
      if (result.skipped)
        setNotice('Playing movies were kept. Clear cache after playback ends.')
      if (kind === 'pin' || kind === 'download') await cacheShell()
      if (user) setFiles(await listMedia(user.userId))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Storage action failed')
    } finally {
      setBusy('')
    }
  }
  const play = (file: SavedMedia) =>
    navigate(`/saved/watch/${encodeURIComponent(file.key)}`)
  const total = files.reduce((sum, file) => sum + file.received, 0)
  const rows = files.filter((file) => file.retention === tab)
  return (
    <main className="saved-page">
      <div className="saved-content">
        <header className="saved-heading">
          <div className="saved-heading-start">
            <button
              className="saved-icon"
              aria-label="Library"
              onClick={() => navigate('/movies')}
            >
              <Glyph kind="back" />
            </button>
            <div>
              <h1>Saved</h1>
              <p>{size(total)} on this device</p>
            </div>
          </div>
          <div className="saved-tools">
            <button
              className="saved-icon"
              aria-label="Download information"
              aria-expanded={details}
              onClick={() => setDetails(!details)}
            >
              <Glyph kind="info" />
            </button>
            <div className="saved-menu-anchor" data-saved-menu>
              <button
                className="saved-icon"
                aria-label="Storage options"
                aria-expanded={menu === 'storage'}
                onClick={() => setMenu(menu === 'storage' ? null : 'storage')}
              >
                <Glyph kind="more" />
              </button>
              {menu === 'storage' && (
                <div className="saved-menu">
                  <button
                    disabled={!!busy}
                    onClick={() => {
                      if (
                        window.confirm(
                          'Clear playback cache? Saved downloads will stay.'
                        )
                      )
                        void action('clear')
                    }}
                  >
                    Clear cache
                  </button>
                </div>
              )}
            </div>
          </div>
        </header>
        {details && (
          <aside className="saved-info">
            <p>
              {background
                ? 'Supported downloads can continue after you leave the app.'
                : 'Downloads may pause when the app is closed or your screen locks. They resume when you reopen.'}
            </p>
            <p>Saved movies play offline. Watch parties need a connection.</p>
            {quota > 0 && <p>Browser storage limit: {size(quota)}.</p>}
          </aside>
        )}
        {!OFFLINE_SUPPORTED && (
          <p role="alert">
            Local downloads need HTTPS and browser storage support.
          </p>
        )}
        {error && (
          <p className="saved-message" role="alert">
            {error}
          </p>
        )}
        {notice && (
          <p className="saved-message" role="status">
            {notice}
          </p>
        )}
        <div className="saved-tabs" role="tablist" aria-label="Stored media">
          {(['download', 'cache'] as const).map((value) => (
            <button
              key={value}
              role="tab"
              id={`saved-tab-${value}`}
              aria-selected={tab === value}
              aria-controls="saved-list"
              onClick={() => {
                setTab(value)
                setMenu(null)
              }}
            >
              {value === 'download' ? 'Downloads' : 'Cache'}
              <span>
                {files.filter((file) => file.retention === value).length}
              </span>
            </button>
          ))}
        </div>
        {tab === 'cache' && (
          <p className="saved-cache-note">Cleared after 7 days without use.</p>
        )}
        <ul
          id="saved-list"
          role="tabpanel"
          aria-labelledby={`saved-tab-${tab}`}
          className="saved-list"
        >
          {rows.map((file) => {
            const bytes = progressBytes(file),
              percent = Math.floor((bytes / file.size) * 100)
            const complete = file.state === 'complete',
              downloading = file.state === 'downloading'
            const primary =
              tab === 'cache'
                ? 'Download'
                : complete && !file.subtitleError
                  ? 'Play'
                  : downloading
                    ? 'Pause'
                    : file.state === 'error' || file.subtitleError
                      ? 'Retry'
                      : 'Resume'
            const canPlay = file.received === file.size || navigator.onLine
            return (
              <li className="saved-card" key={file.key}>
                <button
                  className="saved-poster"
                  aria-label={`Play ${file.title}`}
                  disabled={!canPlay}
                  onClick={() => play(file)}
                >
                  {file.artwork ? (
                    <img
                      alt=""
                      src={`/__artwork/${encodeURIComponent(file.key)}`}
                    />
                  ) : (
                    <span aria-hidden="true">{file.title.slice(0, 1)}</span>
                  )}
                  <span className="saved-poster-play">
                    <Glyph kind="play" />
                  </span>
                </button>
                <div className="saved-movie">
                  <h2>{file.series || file.title}</h2>
                  {file.series && (
                    <p className="saved-episode">
                      S{file.season ?? '?'} · E{file.episode ?? '?'} —{' '}
                      {file.title}
                    </p>
                  )}
                  <p className="saved-status">
                    {complete
                      ? `${size(file.size)} · Ready to play`
                      : `${downloading ? `${percent}%` : file.state === 'error' ? 'Interrupted' : 'Paused'} · ${size(bytes)} / ${size(file.size)}`}
                  </p>
                  {!complete && (
                    <div
                      className="saved-progress"
                      role="progressbar"
                      aria-label={`${file.title} download`}
                      aria-valuemin={0}
                      aria-valuemax={100}
                      aria-valuenow={percent}
                    >
                      <span style={{ width: `${percent}%` }} />
                    </div>
                  )}
                  {(file.error || file.subtitleError) && (
                    <p className="saved-file-error" role="alert">
                      {file.error || file.subtitleError}
                    </p>
                  )}
                  <div className="saved-row-actions">
                    <button
                      className="saved-primary"
                      disabled={
                        !!busy ||
                        (primary !== 'Play' &&
                          primary !== 'Pause' &&
                          !navigator.onLine)
                      }
                      onClick={() =>
                        primary === 'Play'
                          ? play(file)
                          : void action(
                              primary === 'Download'
                                ? 'pin'
                                : primary === 'Pause'
                                  ? 'pause'
                                  : 'download',
                              file.key
                            )
                      }
                    >
                      {busy === file.key ? 'Working…' : primary}
                    </button>
                    {!complete && (
                      <button
                        className="saved-icon"
                        aria-label={`Play ${file.title}`}
                        disabled={!canPlay}
                        onClick={() => play(file)}
                      >
                        <Glyph kind="play" />
                      </button>
                    )}
                    <div className="saved-menu-anchor" data-saved-menu>
                      <button
                        className="saved-icon"
                        aria-label={`Options for ${file.title}`}
                        aria-expanded={menu === file.key}
                        onClick={() =>
                          setMenu(menu === file.key ? null : file.key)
                        }
                      >
                        <Glyph kind="more" />
                      </button>
                      {menu === file.key && (
                        <div className="saved-menu">
                          <button
                            disabled={!navigator.onLine || user?.offline}
                            onClick={() =>
                              navigate(
                                `/party/new?${new URLSearchParams({ itemId: file.itemId, audioStreamIndex: String(file.audioIndex ?? -1), mediaSourceId: file.sourceId })}`
                              )
                            }
                          >
                            Watch party
                          </button>
                          {tab === 'download' && !complete && (
                            <button
                              disabled={!!busy}
                              onClick={() => void action('cancel', file.key)}
                            >
                              Cancel download
                            </button>
                          )}
                          <button
                            className="saved-danger"
                            disabled={!!busy}
                            onClick={() => {
                              if (
                                window.confirm(
                                  `Remove ${file.title} from this device?`
                                )
                              )
                                void action('remove', file.key)
                            }}
                          >
                            Remove
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </li>
            )
          })}
        </ul>
        {!rows.length && (
          <div className="saved-empty">
            <Glyph kind="download" />
            <h2>
              {tab === 'download' ? 'No downloads yet' : 'No cached movies'}
            </h2>
            <p>
              {tab === 'download'
                ? 'Save a movie from your library to watch offline.'
                : 'Movies you watch are cached here.'}
            </p>
            {tab === 'download' && (
              <button
                className="saved-primary"
                onClick={() => navigate('/movies')}
              >
                Browse library
              </button>
            )}
          </div>
        )}
      </div>
      <AnalogNav
        active="saved"
        onNavigate={navigate}
        compact
        canAcquire={!!user?.isAdmin}
      />
    </main>
  )
}
