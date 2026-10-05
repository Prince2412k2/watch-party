import { useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext.tsx'
import { navigate } from '../router.ts'
import {
  cacheShell,
  command,
  initializeOffline,
  listMedia,
  OFFLINE_SUPPORTED,
  type SavedMedia
} from '../offline/client.ts'
import './saved.css'
const size = (n: number) => `${(n / 1024 ** 3).toFixed(2)} GB`
export default function SavedMovies() {
  const { user } = useAuth()
  const [files, setFiles] = useState<SavedMedia[]>([])
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [busy, setBusy] = useState(false)
  const [usage, setUsage] = useState('')
  useEffect(() => {
    if (!user || !OFFLINE_SUPPORTED) return
    let mounted = true
    const refresh = async () => {
      try {
        const files = await listMedia(user.userId)
        const estimate = await navigator.storage?.estimate?.()
        if (mounted) {
          setFiles(files)
          setUsage(
            estimate?.quota
              ? `${size(estimate.usage || 0)} / ${size(estimate.quota)}`
              : ''
          )
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
      .catch((err) => setError(err.message))
    const timer = setInterval(() => void refresh(), 1000)
    return () => {
      mounted = false
      clearInterval(timer)
    }
  }, [user?.userId])
  const action = async (kind: string, key?: string) => {
    if (busy) return
    setBusy(true)
    setError('')
    setNotice('')
    try {
      if (kind === 'pin')
        await navigator.storage?.persist?.().catch(() => false)
      const result = await command(kind, key)
      if (result.skipped)
        setNotice(
          'Movies playing in another tab were kept. Clear cache again after playback ends.'
        )
      if (kind === 'pin' || kind === 'download') await cacheShell()
      if (user) setFiles(await listMedia(user.userId))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Storage action failed')
    } finally {
      setBusy(false)
    }
  }
  const rows = (retention: 'cache' | 'download') =>
    files
      .filter((f) => f.retention === retention)
      .map((file) => (
        <li key={file.key}>
          <div className="saved-title">
            <strong>
              {file.series
                ? `${file.series} · S${file.season ?? '?'} E${file.episode ?? '?'}`
                : file.title}
            </strong>
            {file.series && <small>{file.title}</small>}
            <small>
              {size(file.received)} / {size(file.size)} ·{' '}
              {file.state === 'complete'
                ? 'Saved'
                : file.state === 'downloading'
                  ? `${Math.floor((file.received / file.size) * 100)}%`
                  : file.state === 'paused'
                    ? 'Paused'
                    : 'Needs attention'}
            </small>
            {file.error && <span role="alert">{file.error}</span>}
            {file.subtitleError && <span>{file.subtitleError}</span>}
            {file.state !== 'complete' && (
              <progress
                max={file.size}
                value={file.received}
                aria-label={`${file.title} download`}
              />
            )}
          </div>
          <div className="saved-actions">
            <button
              disabled={file.state !== 'complete' && !navigator.onLine}
              onClick={() =>
                navigate(`/saved/watch/${encodeURIComponent(file.key)}`)
              }
            >
              Play
            </button>
            <button
              disabled={!navigator.onLine || user?.offline}
              onClick={() =>
                navigate(
                  `/party/new?itemId=${encodeURIComponent(file.itemId)}&audioStreamIndex=${file.audioIndex ?? -1}&mediaSourceId=${file.sourceId}`
                )
              }
            >
              Watch party
            </button>
            {retention === 'cache' && (
              <button
                disabled={busy || !navigator.onLine}
                onClick={() => void action('pin', file.key)}
              >
                Download
              </button>
            )}
            {retention === 'download' && file.state === 'downloading' && (
              <button
                disabled={busy}
                onClick={() => void action('pause', file.key)}
              >
                Pause
              </button>
            )}
            {retention === 'download' &&
              file.state !== 'downloading' &&
              (file.state !== 'complete' || file.subtitleError) && (
                <button
                  disabled={busy || !navigator.onLine}
                  onClick={() => void action('download', file.key)}
                >
                  {file.state === 'error' || file.subtitleError
                    ? 'Retry'
                    : 'Resume'}
                </button>
              )}
            {retention === 'download' && file.state !== 'complete' && (
              <button
                disabled={busy}
                onClick={() => void action('cancel', file.key)}
              >
                Cancel download
              </button>
            )}
            <button
              disabled={busy}
              onClick={() => {
                if (window.confirm(`Remove ${file.title} from this device?`))
                  void action('remove', file.key)
              }}
            >
              Remove
            </button>
          </div>
        </li>
      ))
  return (
    <main className="saved-page">
      <header>
        <button onClick={() => navigate('/movies')}>Library</button>
        <span>{usage}</span>
      </header>
      <div className="saved-heading">
        <h1>Saved on this device</h1>
        <button
          disabled={busy}
          onClick={() => {
            if (
              window.confirm('Clear playback cache? Saved downloads will stay.')
            )
              void action('clear')
          }}
        >
          Clear cache
        </button>
      </div>
      {!OFFLINE_SUPPORTED && (
        <p>Local downloads need HTTPS and browser storage support.</p>
      )}
      <p className="saved-note">
        Keep this app open while downloading. Watch parties need a connection;
        saved movies play locally.
      </p>
      {error && <p role="alert">{error}</p>}
      {notice && <p role="status">{notice}</p>}
      <h2>Downloads</h2>
      <ul>{rows('download')}</ul>
      {!files.some((f) => f.retention === 'download') && (
        <p>No saved downloads.</p>
      )}
      {files.some((f) => f.retention === 'cache') && (
        <>
          <h2>Playback cache</h2>
          <p className="saved-note">Removed after seven days without use.</p>
          <ul>{rows('cache')}</ul>
        </>
      )}
    </main>
  )
}
