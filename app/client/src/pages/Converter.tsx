import { useCallback, useEffect, useRef, useState } from 'react'
import { navigate } from '../router.ts'
import { apiJson, isRecord } from '../types/guards.ts'
import { AnIcon } from '../analog/icons.tsx'
import '../analog/analogKit.css'
import './converter.css'

interface Job {
  id: number; SourcePath: string; TargetPath: string; Status: string; OperationType: string
  Progress: number; FFmpegSpeed: string; SourceSize: number; TargetSize: number
  VideoCodec: string; AudioCodecs: string; ErrorMessage: string; Notes: string
}
interface State {
  jobs: Job[]; counts: Record<string, number>; paused: boolean
  policy: { video: string; audio: string; workers: number; watchSeconds: number; settleSeconds: number; strict: boolean; deleteOriginal: boolean }
}
const activeStates = new Set(['probing', 'remuxing', 'transcoding_audio', 'transcoding_video', 'validating'])
const title = (path: string) => (path.split('/').pop() || path).replace(/\.[^.]+$/, '')
const bytes = (value: number) => value > 0 ? `${(value / 1024 ** 3).toFixed(2)} GiB` : '—'
const statusLabel = (status: string) => ({ probing: 'Inspecting', remuxing: 'Copying streams', transcoding_audio: 'Converting audio', transcoding_video: 'Encoding video', validating: 'Validating', requires_transcode: 'Needs conversion' }[status] || status.replace(/_/g, ' '))

function parseState(value: unknown): State {
  if (!isRecord(value) || !Array.isArray(value.jobs) || !isRecord(value.policy) || !isRecord(value.counts) || typeof value.paused !== 'boolean') throw new Error('Invalid converter response')
  if (!value.jobs.every(j => isRecord(j) && typeof j.id === 'number' && typeof j.SourcePath === 'string' && typeof j.Status === 'string')) throw new Error('Invalid converter jobs')
  return value as unknown as State
}

export default function Converter() {
  const [state, setState] = useState<State | null>(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState('')
  const [tab, setTab] = useState<'queue' | 'history'>('queue')
  const alive = useRef(true)
  const refresh = useCallback(async () => {
    const response = await fetch('/api/converter/state', { credentials: 'include' })
    const value = await apiJson(response)
    if (!response.ok) throw new Error(isRecord(value) && typeof value.error === 'string' ? value.error : 'Could not load converter')
    const next = parseState(value)
    if (alive.current) { setState(next); setError('') }
  }, [])
  useEffect(() => {
    alive.current = true
    let timer: ReturnType<typeof setTimeout>
    const poll = async () => {
      try { await refresh() } catch (err) { if (alive.current) setError(err instanceof Error ? err.message : 'Could not load converter') }
      if (alive.current) timer = setTimeout(poll, 2500)
    }
    void poll()
    return () => { alive.current = false; clearTimeout(timer) }
  }, [refresh])

  const action = async (path: string) => {
    if (busy) return
    setBusy(path)
    try {
      const response = await fetch(`/api/converter/${path}`, { method: 'POST', credentials: 'include' })
      const value = await apiJson(response)
      if (!response.ok) throw new Error(isRecord(value) && typeof value.error === 'string' ? value.error : 'Action failed')
      await refresh()
    } catch (err) { setError(err instanceof Error ? err.message : 'Action failed') }
    finally { setBusy('') }
  }
  const active = state?.jobs.filter(j => activeStates.has(j.Status)) ?? []
  const waiting = state?.jobs.filter(j => j.Status === 'queued') ?? []
  const history = state?.jobs.filter(j => j.Status !== 'queued' && !activeStates.has(j.Status)) ?? []
  const jobAction = (job: Job, kind: string) => void action(`jobs/${job.id}/${kind}`)

  return (
    <main className="converter-page">
      <header className="converter-header">
        <button className="converter-back" onClick={() => navigate('/movies')}><AnIcon name="back" size={18} /> Library</button>

      </header>
      <section className="converter-intro">
        <div><h1>Converter</h1><p>MP4 · H.264 / AAC</p></div>
        <div className="converter-toolbar">
          <button disabled={!!busy || !state} onClick={() => void action(state?.paused ? 'resume' : 'pause')}>{state?.paused ? 'Resume' : 'Pause'}</button>
          <button disabled={!!busy} onClick={() => void action('scan')}>{busy === 'scan' ? 'Scanning…' : 'Scan library'}</button>
        </div>
      </section>
      {error && <div className="converter-error" role="alert">{error}<button disabled={!!busy} onClick={() => void refresh().catch(err => setError(err.message))}>Retry</button></div>}
      {!state && !error && <p aria-busy="true">Loading…</p>}
      {state && <>
        <div className="converter-section-head"><h2>Running <span>{active.length} / {state.policy.workers}</span></h2><span>{state.paused ? 'Paused' : ''}</span></div>
        <section className="converter-running" aria-label="Running conversions">
          {!active.length && <p className="converter-empty">{state.paused ? 'Paused' : 'Idle'}</p>}
          {active.map(job => <article className="converter-job" key={job.id}>
            <div className="converter-job-heading"><div><strong title={job.SourcePath}>{title(job.SourcePath)}</strong><small>{statusLabel(job.Status)} · {job.VideoCodec || 'Reading codecs'}{job.AudioCodecs && ` / ${job.AudioCodecs}`}</small></div><button disabled={!!busy} onClick={() => jobAction(job, 'cancel')}>Cancel</button></div>
            <progress max={100} value={job.Progress || 0} aria-label={`${title(job.SourcePath)} conversion`} />
            <div className="converter-job-meta"><span>{(job.Progress || 0).toFixed(1)}%</span><span>{job.FFmpegSpeed || '—'}</span><span>{bytes(job.SourceSize)} → {bytes(job.TargetSize)}</span></div>
          </article>)}
        </section>
        <nav className="converter-tabs" aria-label="Converter lists">
          <button aria-current={tab === 'queue' ? 'page' : undefined} onClick={() => setTab('queue')}>Queue <span>{state.counts.queued || 0}</span></button>
          <button aria-current={tab === 'history' ? 'page' : undefined} onClick={() => setTab('history')}>History</button>
        </nav>
        <ol className="converter-list">
          {(tab === 'queue' ? waiting : history).map((job, index) => <li key={job.id}>
            <span className="converter-position">{tab === 'queue' ? String(index + 1).padStart(2, '0') : <AnIcon name={job.Status === 'completed' ? 'check' : 'film'} size={18} />}</span>
            <div className="converter-file"><strong title={job.SourcePath}>{title(job.SourcePath)}</strong>{tab === 'history' && <span data-failed={job.Status === 'failed'}>{statusLabel(job.Status)}</span>}{tab === 'history' && (job.ErrorMessage || job.Notes) && <details><summary>Details</summary><p>{job.ErrorMessage || job.Notes}</p></details>}</div>
            <div className="converter-row-actions">
              {tab === 'queue' ? <>
                <button disabled={!!busy || index === 0} onClick={() => jobAction(job, 'next')}>Next</button>
                <button disabled={!!busy || index === 0} aria-label={`Move ${title(job.SourcePath)} up`} onClick={() => jobAction(job, 'up')}>↑</button>
                <button disabled={!!busy || index === waiting.length - 1} aria-label={`Move ${title(job.SourcePath)} down`} onClick={() => jobAction(job, 'down')}>↓</button>
                <button disabled={!!busy} onClick={() => jobAction(job, 'cancel')}>Cancel</button>
              </> : job.Status !== 'completed' && <button disabled={!!busy || job.Notes === 'conflict'} onClick={() => jobAction(job, 'retry')}>Retry</button>}
            </div>
          </li>)}
        </ol>
        {!(tab === 'queue' ? waiting : history).length && <p className="converter-empty">{tab === 'queue' ? 'Queue empty' : 'No history'}</p>}

      </>}
    </main>
  )
}
