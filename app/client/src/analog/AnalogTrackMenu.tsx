import { useEffect, useRef, useState } from 'react'
import { apiJson, isRecord } from '../types/guards.ts'
import { AnIcon } from './icons.tsx'
import { trackLabel, type PlaybackTrack, type PlaybackTracks } from './playbackTracks.ts'

/**
 * Audio and subtitles for the focused title, opened from the stage's action row.
 *
 * Anchored to the button rather than presented as a sheet: the stage has no
 * scroll region of its own and nothing behind it needs covering. It closes on
 * Escape and on a click outside, and its own key handling stops there — the
 * arrows belong to the rail and the mode slider, and a menu that quietly stole
 * them would strand the user inside it.
 */
export interface AnalogTrackMenuProps {
  itemId: string
  tracks: PlaybackTracks | null
  loading: boolean
  selectedAudio: number | null
  selectedSubtitle: number | null
  onSelectAudio: (index: number | null) => void
  onSelectSubtitle: (index: number | null) => void
  onRefresh: () => Promise<void>
  onClose: () => void
}

export function AnalogTrackMenu({
  itemId,
  tracks,
  loading,
  selectedAudio,
  selectedSubtitle,
  onSelectAudio,
  onSelectSubtitle,
  onRefresh,
  onClose,
}: AnalogTrackMenuProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  // Dismiss on a click anywhere else. `pointerdown`, not `click`: by the time a
  // click completes the file dialog may already own the pointer. The button that
  // opened this is excluded, or its own toggle would immediately reopen what
  // this just closed.
  useEffect(() => {
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as HTMLElement | null
      if (menuRef.current?.contains(target ?? null) || target?.closest?.('.an-action.is-open')) return
      onClose()
    }
    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [onClose])

  const upload = async (file?: File) => {
    if (!file) return
    setBusy(true)
    setError('')
    try {
      const response = await fetch(`/api/library/items/${itemId}/subtitles`, {
        method: 'POST',
        credentials: 'include',
        body: file,
        headers: {
          'Content-Type': file.type || 'application/octet-stream',
          'X-Subtitle-Filename': encodeURIComponent(file.name),
        },
      })
      const data = await apiJson(response).catch(() => ({}))
      if (!response.ok) {
        throw new Error(isRecord(data) && typeof data.error === 'string' ? data.error : 'Subtitle upload failed')
      }
      await onRefresh()
      if (isRecord(data) && typeof data.subtitleStreamIndex === 'number') {
        onSelectSubtitle(data.subtitleStreamIndex)
      }
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Subtitle upload failed')
    } finally {
      setBusy(false)
      if (inputRef.current) inputRef.current.value = ''
    }
  }

  const remove = async (track: PlaybackTrack) => {
    if (!window.confirm(`Delete ${trackLabel(track, 'this subtitle')}?`)) return
    setBusy(true)
    setError('')
    try {
      const response = await fetch(`/api/library/items/${itemId}/subtitles/${track.index}`, {
        method: 'DELETE',
        credentials: 'include',
      })
      const data = await apiJson(response).catch(() => ({}))
      if (!response.ok) {
        throw new Error(isRecord(data) && typeof data.error === 'string' ? data.error : 'Subtitle delete failed')
      }
      if (selectedSubtitle === track.index) onSelectSubtitle(null)
      await onRefresh()
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Subtitle delete failed')
    } finally {
      setBusy(false)
    }
  }

  const row = (label: string, selected: boolean, onClick: () => void, trailing?: PlaybackTrack) => (
    <div className="an-track-row" data-selected={selected}>
      <button type="button" onClick={onClick}>
        <span className="an-track-tick" aria-hidden data-on={selected}>
          <AnIcon name="check" size={13} />
        </span>
        <span>{label}</span>
      </button>
      {trailing ? (
        <button
          type="button"
          className="an-track-remove"
          disabled={busy}
          aria-label={`Delete ${trackLabel(trailing, 'subtitle')}`}
          onClick={() => void remove(trailing)}
        >
          <AnIcon name="trash" size={14} />
        </button>
      ) : null}
    </div>
  )

  return (
    <div
      ref={menuRef}
      className="an-track-menu"
      role="dialog"
      aria-label="Audio and subtitles"
      onClick={(event) => event.stopPropagation()}
      onKeyDown={(event) => {
        if (event.key !== 'Escape') {
          event.stopPropagation()
          return
        }
        event.preventDefault()
        onClose()
      }}
    >
      <div className="an-track-head">
        <strong>Playback tracks</strong>
        <button type="button" aria-label="Close track menu" onClick={onClose}>
          <AnIcon name="x" size={15} />
        </button>
      </div>

      {loading || !tracks ? (
        <p className="an-track-empty">{loading ? 'Reading the file…' : 'No track information for this title.'}</p>
      ) : (
        <>
          {tracks.audioStreams.length > 0 ? (
            <section>
              <small>Audio</small>
              {tracks.audioStreams.map((track, index) =>
                <div key={track.index}>
                  {row(trackLabel(track, `Audio ${index + 1}`), selectedAudio === track.index, () =>
                    onSelectAudio(track.index))}
                </div>,
              )}
            </section>
          ) : null}

          <section>
            <small>Subtitles</small>
            {row('Off', selectedSubtitle == null || selectedSubtitle < 0, () => onSelectSubtitle(null))}
            {tracks.subtitleStreams.map((track, index) =>
              <div key={track.index}>
                {row(
                  trackLabel(track, `Subtitle ${index + 1}`),
                  selectedSubtitle === track.index,
                  () => onSelectSubtitle(track.index),
                  track.isExternal ? track : undefined,
                )}
              </div>,
            )}
            <input
              ref={inputRef}
              type="file"
              accept=".srt,.vtt,text/vtt,application/x-subrip"
              hidden
              onChange={(event) => void upload(event.target.files?.[0])}
            />
            <button
              type="button"
              className="an-track-upload"
              disabled={busy}
              onClick={() => inputRef.current?.click()}
            >
              {busy ? 'Working…' : 'Upload SRT or VTT'}
            </button>
          </section>
        </>
      )}

      {error ? (
        <p role="alert" className="an-track-error">
          {error}
        </p>
      ) : null}
    </div>
  )
}
