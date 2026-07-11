// One row of live download state — queued/active/paused/done/error — with
// pause/resume/cancel controls. Matches the redesign's flat monochrome system
// (app/client/src/lib/ui.jsx): near-white fill for progress, the single muted
// red reserved for the active-dot / error state, nothing else colored.
import { C, SANS, MONO, Icon, Ic } from '../../lib/ui'
import { formatBytes, formatSpeed, progressPct } from './format'

const STATE_LABEL = {
  queued: 'Queued',
  active: 'Downloading',
  paused: 'Paused',
  done: 'Downloaded',
  error: 'Failed',
}

function IconBtn({ onClick, title, children }: any = {}) {
  return (
    <button
      onClick={onClick}
      title={title}
      style={{
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        width: 32, height: 32, borderRadius: 8, cursor: 'pointer',
        background: C.surface2, border: `1px solid ${C.line}`, color: C.dim,
        flexShrink: 0,
      }}
    >
      {children}
    </button>
  )
}

export default function DownloadProgress({ record, onPause, onResume, onCancel }: any = {}) {
  const { title, state, receivedBytes = 0, totalBytes = 0, bytesPerSec = 0, message } = record
  const pct = progressPct(receivedBytes, totalBytes)
  const isError = state === 'error'
  const isActive = state === 'active'
  const isDone = state === 'done'

  return (
    <div
      style={{
        display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px',
        borderRadius: 12, background: C.surface, border: `1px solid ${C.line}`,
      }}
    >
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {isActive && (
            <span
              aria-hidden
              style={{ width: 6, height: 6, borderRadius: '50%', background: C.red, boxShadow: `0 0 6px ${C.red}`, flexShrink: 0 }}
            />
          )}
          <span
            style={{
              fontFamily: SANS, fontSize: 14, fontWeight: 600, color: isError ? C.red : C.text,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            }}
          >
            {title || record.itemId}
          </span>
        </div>

        {isError ? (
          <div style={{ marginTop: 4, fontFamily: SANS, fontSize: 12.5, color: C.red }}>
            {message || 'Download failed'}
          </div>
        ) : (
          <>
            <div style={{ marginTop: 8, height: 4, borderRadius: 999, background: C.surface3, overflow: 'hidden' }}>
              <div
                style={{
                  height: '100%', borderRadius: 999, width: `${isDone ? 100 : pct}%`,
                  background: state === 'paused' ? C.faint : C.accent, transition: 'width .3s ease',
                }}
              />
            </div>
            <div style={{ marginTop: 6, display: 'flex', gap: 10, fontFamily: MONO, fontSize: 11.5, color: C.faint }}>
              <span>{STATE_LABEL[state] || state}</span>
              {!isDone && totalBytes > 0 && (
                <span>{formatBytes(receivedBytes)} / {formatBytes(totalBytes)} · {pct}%</span>
              )}
              {isActive && bytesPerSec > 0 && <span>{formatSpeed(bytesPerSec)}</span>}
            </div>
          </>
        )}
      </div>

      <div style={{ display: 'flex', gap: 6, flexShrink: 0 }}>
        {isActive && (
          <IconBtn title="Pause" onClick={() => onPause(record.id)}>
            <Icon path={Ic.pause} size={15} sw={1.8} />
          </IconBtn>
        )}
        {(state === 'paused' || state === 'queued') && (
          <IconBtn title="Resume" onClick={() => onResume(record.id)}>
            <Icon path={Ic.play} size={15} sw={1.8} fill="currentColor" />
          </IconBtn>
        )}
        {!isDone && (
          <IconBtn title="Cancel" onClick={() => onCancel(record.id)}>
            <Icon path={Ic.x} size={15} sw={1.8} />
          </IconBtn>
        )}
        {isDone && <Icon path={Ic.check} size={18} stroke={C.green} sw={2} />}
      </div>
    </div>
  )
}
