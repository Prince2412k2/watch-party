// Offline library view — native only. Lists in-flight downloads (live
// progress, pause/resume/cancel) above completed offline titles (remove
// action). Self-contained: owns its own data via useDownloads/useOfflineLibrary,
// so Phase 2 integration just needs to mount it on a route (e.g. `/downloads`,
// alongside the existing Sidebar "Downloads" nav row in lib/ui.jsx).
import { C, SANS, Icon, Ic, Notice } from '../../lib/ui'
import { IS_NATIVE } from '../env'
import { useDownloads, useOfflineLibrary } from '../useOffline'
import DownloadProgress from './DownloadProgress'
import { formatBytes } from './format'

export default function OfflineLibrary() {
  const { downloads, pause, resume, cancel } = useDownloads()
  const { items, remove } = useOfflineLibrary()

  if (!IS_NATIVE) return null

  const inFlight = downloads.filter((d) => d.state !== 'done')

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 24, padding: '4px 2px' }}>
      <section>
        <h2 style={{ fontFamily: SANS, fontSize: 15, fontWeight: 700, color: C.text, margin: '0 0 10px' }}>
          Downloading
        </h2>
        {inFlight.length === 0 ? (
          <div style={{ fontFamily: SANS, fontSize: 13.5, color: C.faint }}>Nothing downloading right now.</div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {inFlight.map((record) => (
              <DownloadProgress key={record.id} record={record} onPause={pause} onResume={resume} onCancel={cancel} />
            ))}
          </div>
        )}
      </section>

      <section>
        <h2 style={{ fontFamily: SANS, fontSize: 15, fontWeight: 700, color: C.text, margin: '0 0 10px' }}>
          Available offline
        </h2>
        {items.length === 0 ? (
          <Notice icon={Ic.download} title="Nothing downloaded yet" body="Titles you download for offline appear here." />
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {items.map((item) => (
              <div
                key={item.itemId}
                style={{
                  display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px',
                  borderRadius: 12, background: C.surface, border: `1px solid ${C.line}`,
                }}
              >
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div
                    style={{
                      fontFamily: SANS, fontSize: 14, fontWeight: 600, color: C.text,
                      whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                    }}
                  >
                    {item.title}
                  </div>
                  <div style={{ marginTop: 4, fontFamily: SANS, fontSize: 12, color: C.faint }}>
                    {formatBytes(item.sizeBytes)}
                  </div>
                </div>
                <button
                  onClick={() => remove(item.itemId)}
                  title="Remove from offline library"
                  style={{
                    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                    width: 32, height: 32, borderRadius: 8, cursor: 'pointer',
                    background: C.surface2, border: `1px solid ${C.line}`, color: C.dim, flexShrink: 0,
                  }}
                >
                  <Icon path={Ic.trash} size={15} sw={1.7} />
                </button>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
// @ts-nocheck
