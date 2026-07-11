// Self-contained "Download for offline" affordance for a single title.
// Native-only (renders nothing under IS_NATIVE === false) so it's safe to drop
// into any title-detail page without a build-time split.
//
// Mount point (Phase 2 integration): the title-detail page's action row,
// next to the existing Play button — e.g.
//   {IS_NATIVE && <DownloadButton itemId={item.Id} title={item.Name} url={streamUrl} />}
// It owns its own state (via useDownloads/useOfflineLibrary) so no wiring
// beyond passing itemId/title/url is required from the host page.
import { useMemo, useState } from 'react'
import { C, SANS, Icon, Ic, Spinner } from '../../lib/ui'
import { IS_NATIVE } from '../env'
import { useDownloads, useOfflineLibrary } from '../useOffline'
import { formatBytes, progressPct } from './format'

export default function DownloadButton({ itemId, title, url, parts }: any = {}) {
  const { downloads, start, pause, resume, cancel } = useDownloads()
  const { items: offlineItems, remove } = useOfflineLibrary()
  const [busy, setBusy] = useState(false)

  const active = useMemo(
    () => downloads.find((d) => d.itemId === itemId && d.state !== 'done'),
    [downloads, itemId]
  )
  const offline = useMemo(() => offlineItems.find((o) => o.itemId === itemId), [offlineItems, itemId])

  if (!IS_NATIVE) return null

  const baseStyle = {
    display: 'inline-flex', alignItems: 'center', gap: 8, height: 38, padding: '0 16px',
    borderRadius: 10, cursor: 'pointer', fontFamily: SANS, fontSize: 13.5, fontWeight: 600,
    background: C.surface, border: `1px solid ${C.line}`, color: C.text,
  }

  if (offline) {
    return (
      <button
        style={{ ...baseStyle, color: C.dim }}
        onClick={() => remove(itemId)}
        title="Remove downloaded file"
      >
        <Icon path={Ic.check} size={15} stroke={C.green} sw={2} />
        Downloaded
        <Icon path={Ic.trash} size={14} sw={1.7} />
      </button>
    )
  }

  if (active) {
    if (active.state === 'error') {
      return (
        <button
          style={{ ...baseStyle, color: C.red, borderColor: 'rgba(224,101,94,.35)' }}
          onClick={() => cancel(active.id).then(() => start({ itemId, url, title, parts }))}
          title={active.message || 'Download failed — retry'}
        >
          <Icon path={Ic.alert} size={15} sw={1.8} />
          Retry
        </button>
      )
    }
    const pct = progressPct(active.receivedBytes, active.totalBytes)
    return (
      <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
        <span
          style={{ ...baseStyle, cursor: 'default', gap: 8 }}
        >
          {active.state === 'active' && (
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: C.red, boxShadow: `0 0 6px ${C.red}` }} />
          )}
          {active.state === 'queued' ? 'Queued' : active.state === 'paused' ? 'Paused' : `${pct}%`}
          {active.totalBytes > 0 && active.state === 'active' && (
            <span style={{ color: C.faint }}>{formatBytes(active.receivedBytes)} / {formatBytes(active.totalBytes)}</span>
          )}
        </span>
        {active.state === 'active' ? (
          <button style={{ ...baseStyle, width: 38, padding: 0 }} title="Pause" onClick={() => pause(active.id)}>
            <Icon path={Ic.pause} size={15} sw={1.8} />
          </button>
        ) : (
          <button style={{ ...baseStyle, width: 38, padding: 0 }} title="Resume" onClick={() => resume(active.id)}>
            <Icon path={Ic.play} size={15} sw={1.8} fill="currentColor" />
          </button>
        )}
        <button style={{ ...baseStyle, width: 38, padding: 0 }} title="Cancel" onClick={() => cancel(active.id)}>
          <Icon path={Ic.x} size={15} sw={1.8} />
        </button>
      </div>
    )
  }

  return (
    <button
      style={baseStyle}
      disabled={busy}
      onClick={async () => {
        setBusy(true)
        try {
          await start({ itemId, url, title, parts })
        } finally {
          setBusy(false)
        }
      }}
      title="Download for offline"
    >
      {busy ? <Spinner size={15} /> : <Icon path={Ic.download} size={15} sw={1.8} />}
      Download
    </button>
  )
}
