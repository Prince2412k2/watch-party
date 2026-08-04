import { useEffect, useState, useSyncExternalStore } from 'react'
import type { CSSProperties, ReactNode } from 'react'
import QRCode from 'qrcode'
import { useParty } from '../context/PartyContext'
import type { PartyUser } from '../types'

export const MONO = "'JetBrains Mono', ui-monospace, monospace"

export function initials(name = '') {
  return name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2) || '?'
}

/* ── viewport shape ─────────────────────────────────────────────────────────
   A landscape phone (≈874×402) and a portrait phone (≈402×874) want opposite
   layouts, so width alone can't decide. `short` means "height is the scarce
   axis" — spend the spare width instead of stacking. */
const SHORT = '(max-height: 520px)'
// 640 is the narrowest landscape phone worth spreading three columns across
// (iPhone SE lands at 667). ROOMY additionally allows the QR to sit beside the
// join code rather than under it.
const WIDE = '(min-width: 640px)'
const ROOMY = '(min-width: 820px)'

function useMatch(query: string) {
  return useSyncExternalStore(
    cb => {
      const m = window.matchMedia(query)
      m.addEventListener('change', cb)
      return () => m.removeEventListener('change', cb)
    },
    () => window.matchMedia(query).matches,
    () => false,
  )
}

export type Mode = 'columns3' | 'columns2' | 'stack'

/** Which shape the panel takes. Pulled out of the component so the breakpoint
    table can be asserted without a browser. */
export function panelMode(short: boolean, wide: boolean, phone: boolean): Mode {
  if (short) return wide ? 'columns3' : 'columns2'
  return phone ? 'stack' : 'columns2'
}

/** Every size the panel uses. `dense` = height-starved (short viewport),
    `phone` = coarse pointer, which owns the 44px tap floor independently. */
export function panelMetrics(dense: boolean, phone: boolean) {
  return {
    tap: phone ? 44 : 36,
    pad: dense ? 12 : 18,
    gap: dense ? 8 : 14,
    personRow: phone ? 46 : 38,
    qr: dense ? 74 : 100,
    codeSize: dense ? 19 : 24,
    titleSize: dense ? 14 : 16.5,
    closeSize: dense ? 28 : 30,
    radius: dense ? 16 : 20,
    headerPad: dense ? '7px 10px 7px 14px' : '14px 16px 14px 20px',
    footerPad: dense ? '6px 12px' : '12px 16px',
  }
}

/* ── primitives ─────────────────────────────────────────────────────────────
   Everything below is deliberately small and layout-agnostic: the panel body
   composes them into 1, 2 or 3 columns without any of them knowing which. */

function SectionLabel({ children, tone = 'var(--text3)', size = 11 }: { children: ReactNode; tone?: string; size?: number }) {
  return (
    <div style={{ fontSize: size, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: tone }}>
      {children}
    </div>
  )
}

function Pane({ label, gap, divided, children }: { label: ReactNode; gap: number; divided: boolean; children: ReactNode }) {
  return (
    <section style={{
      display: 'flex', flexDirection: 'column', gap, minHeight: 0, minWidth: 0,
      ...(divided ? { borderTop: '1px solid var(--stroke)', paddingTop: gap } : null),
    }}>
      <SectionLabel>{label}</SectionLabel>
      {children}
    </section>
  )
}

function Avatar({ name, size }: { name: string; size: number }) {
  return (
    <div aria-hidden style={{
      width: size, height: size, borderRadius: '50%', background: 'var(--stroke2)',
      display: 'grid', placeItems: 'center', color: 'var(--text)',
      fontSize: Math.round(size * 0.38), fontWeight: 700, flexShrink: 0,
    }}>{initials(name)}</div>
  )
}

function IconButton({ title, onClick, danger, tap, children }: {
  title: string; onClick: () => void; danger?: boolean; tap: number; children: ReactNode
}) {
  return (
    <button
      type="button" onClick={onClick} title={title} aria-label={title}
      style={{
        width: tap, height: tap, borderRadius: 9, border: 'none', background: 'transparent',
        color: danger ? 'var(--red)' : 'var(--text3)', display: 'grid', placeItems: 'center',
        cursor: 'pointer', flexShrink: 0, padding: 0,
      }}
    >{children}</button>
  )
}

function PersonRow({ name, badge, row, actions }: {
  name: string; badge?: string; row: number; actions?: ReactNode
}) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 9, height: row, flexShrink: 0 }}>
      <Avatar name={name} size={Math.min(32, row - 12)} />
      <span style={{
        flex: 1, minWidth: 0, fontSize: 13.5, fontWeight: 600, color: 'var(--text)',
        overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
      }}>{name}</span>
      {badge ? (
        <span style={{
          padding: '2px 6px', borderRadius: 6, background: 'var(--glass2)', color: 'var(--text2)',
          fontSize: 9.5, fontWeight: 700, letterSpacing: '.06em', flexShrink: 0,
        }}>{badge}</span>
      ) : null}
      {actions}
    </div>
  )
}

/** Track stays 40×24 for looks; the hit box grows to `tap` so coarse pointers
    still get a 44px target without a comically large switch. */
function Switch({ checked, onChange, label, tap }: {
  checked: boolean; onChange: () => void; label: string; tap: number
}) {
  return (
    <button
      type="button" role="switch" aria-checked={checked} aria-label={label} title={label}
      onClick={onChange}
      style={{
        width: Math.max(tap, 44), height: tap, border: 'none', background: 'transparent',
        display: 'grid', placeItems: 'center', cursor: 'pointer', flexShrink: 0, padding: 0,
      }}
    >
      <span style={{
        width: 40, height: 24, borderRadius: 12, border: '1px solid var(--stroke2)', padding: 3,
        display: 'flex', alignItems: 'center', justifyContent: checked ? 'flex-end' : 'flex-start',
        background: checked ? 'var(--stroke2)' : 'transparent', transition: 'background .2s',
      }}>
        <span style={{ width: 16, height: 16, borderRadius: '50%', background: 'var(--text)', display: 'block' }} />
      </span>
    </button>
  )
}

/** One-line label + control. `hint` shows inline when there's vertical room and
    falls back to a tooltip when there isn't, so the meaning never disappears. */
function SettingRow({ label, hint, showHint, row, control }: {
  label: string; hint: string; showHint: boolean; row: number; control: ReactNode
}) {
  return (
    <div title={hint} style={{ display: 'flex', alignItems: 'center', gap: 10, minHeight: row }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: 'var(--text)' }}>{label}</div>
        {showHint ? <div style={{ fontSize: 11.5, color: 'var(--text3)', marginTop: 1 }}>{hint}</div> : null}
      </div>
      {control}
    </div>
  )
}

function Segmented({ value, options, onChange, tap }: {
  value: string
  options: { id: string; label: string; hint: string }[]
  onChange: (id: string) => void
  tap: number
}) {
  return (
    <div role="group" aria-label="Sync mode" style={{
      display: 'flex', gap: 4, background: 'var(--glass2)', border: '1px solid var(--stroke)',
      borderRadius: 10, padding: 3,
    }}>
      {options.map(o => {
        const active = value === o.id
        return (
          <button
            key={o.id} type="button" onClick={() => onChange(o.id)}
            title={o.hint} aria-pressed={active}
            style={{
              flex: 1, height: tap - 8, borderRadius: 8, border: 'none', cursor: 'pointer',
              fontSize: 12.5, fontWeight: active ? 700 : 600,
              background: active ? 'var(--accent)' : 'transparent',
              color: active ? 'var(--on-accent)' : 'var(--text2)',
              transition: 'background .15s, color .15s',
            }}
          >{o.label}</button>
        )
      })}
    </div>
  )
}

const SYNC_OPTIONS = [
  { id: 'hopping', label: 'Hopping', hint: 'Host never waits; slow viewers catch up' },
  { id: 'dragging', label: 'Dragging', hint: 'Everyone waits for the slowest viewer' },
]

/** Sync mode. The two words are jargon, so the active mode's meaning is always
    spelled out on a line beneath — never tooltip-only, since a phone can't
    hover. Dense drops the label beside the control to save a line box. */
function SyncControl({ value, onChange, tap, dense }: {
  value: string; onChange: (id: string) => void; tap: number; dense: boolean
}) {
  const meaning = SYNC_OPTIONS.find(o => o.id === value)?.hint ?? ''
  const control = <Segmented value={value} options={SYNC_OPTIONS} onChange={onChange} tap={tap} />
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: dense ? 5 : 6, minWidth: 0 }}>
      {dense ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, minHeight: tap }}>
          <span style={{ fontSize: 13.5, fontWeight: 600, color: 'var(--text)', flexShrink: 0 }}>Sync</span>
          <div style={{ flex: 1, minWidth: 0 }}>{control}</div>
        </div>
      ) : (
        <>
          <span style={{ fontSize: 13.5, fontWeight: 600, color: 'var(--text)' }}>Sync mode</span>
          {control}
        </>
      )}
      <div style={{ fontSize: 11.5, color: 'var(--text3)' }}>{meaning}</div>
    </div>
  )
}

const BUTTON_TONE: Record<'accent' | 'ghost' | 'danger', CSSProperties> = {
  accent: { background: 'var(--accent)', color: 'var(--on-accent)', border: 'none' },
  ghost: { background: 'var(--glass2)', color: 'var(--text)', border: '1px solid var(--stroke2)' },
  danger: { background: 'rgba(224,101,94,.12)', color: 'var(--red)', border: '1px solid rgba(224,101,94,.35)' },
}

function PanelButton({ tone, onClick, height, grow, title, children }: {
  tone: 'accent' | 'ghost' | 'danger'
  onClick: () => void
  height: number
  grow?: boolean
  title?: string
  children: ReactNode
}) {
  return (
    <button
      type="button" onClick={onClick} title={title}
      style={{
        ...BUTTON_TONE[tone], height, padding: '0 14px', borderRadius: 10, cursor: 'pointer',
        fontSize: 13, fontWeight: 700, whiteSpace: 'nowrap',
        ...(grow ? { flex: 1, minWidth: 0 } : null),
      }}
    >{children}</button>
  )
}

// Self-contained QR encoding the join URL — no network calls (the 'qrcode'
// package renders client-side as inline SVG), on a white card so it stays
// scannable against the dark UI.
function JoinQR({ url, size }: { url: string; size: number }) {
  const [svg, setSvg] = useState<string | null>(null)
  useEffect(() => {
    let live = true
    QRCode.toString(url, { type: 'svg', margin: 1, width: size, color: { dark: '#0a0a0c', light: '#ffffff' } })
      .then(s => { if (live) setSvg(s) })
      .catch(() => {})
    return () => { live = false }
  }, [url, size])

  const pad = size < 90 ? 7 : 11
  return (
    <div aria-hidden style={{
      flexShrink: 0, width: size + pad * 2, height: size + pad * 2, borderRadius: 12,
      background: '#fff', display: 'grid', placeItems: 'center',
    }}>
      {svg
        ? <div style={{ width: size, height: size }} dangerouslySetInnerHTML={{ __html: svg }} />
        : <div style={{ width: size, height: size, borderRadius: 6, background: 'rgba(0,0,0,.06)' }} />}
    </div>
  )
}

function ShareBlock({ code, url, side, qr, codeSize, tap }: {
  code: string; url: string; side: boolean; qr: number; codeSize: number; tap: number
}) {
  const [label, setLabel] = useState('Copy link')
  function copy() {
    navigator.clipboard.writeText(url)
    setLabel('Copied!')
    setTimeout(() => setLabel('Copy link'), 2000)
  }
  // The code is the thing people read aloud, so it leads in both arrangements:
  // beside the QR when there's width, above it when there isn't.
  const codeBlock = (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0, alignSelf: 'stretch', flex: side ? 1 : undefined }}>
      <span style={{
        fontFamily: MONO, fontSize: codeSize, fontWeight: 600, letterSpacing: '.1em',
        color: 'var(--text)', userSelect: 'all', lineHeight: 1.1,
      }}>{code}</span>
      <PanelButton tone="accent" height={tap} onClick={copy} title="Copy the invite link">{label}</PanelButton>
    </div>
  )
  const qrBlock = <JoinQR url={url} size={qr} />

  return (
    <div style={{
      display: 'flex', gap: side ? 12 : 10, minWidth: 0,
      flexDirection: side ? 'row' : 'column', alignItems: 'center',
    }}>
      {side ? <>{qrBlock}{codeBlock}</> : <>{codeBlock}{qrBlock}</>}
    </div>
  )
}

function EndPartyConfirm({ onCancel, onConfirm }: { onCancel: () => void; onConfirm: () => void }) {
  return (
    <>
      <div onClick={onCancel} style={{ position: 'absolute', inset: 0, zIndex: 52, background: 'rgba(0,0,0,.72)' }} />
      <div role="dialog" aria-modal="true" aria-label="End party for everyone?" style={{
        position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', zIndex: 53,
        width: 360, maxWidth: 'calc(100vw - 28px)', borderRadius: 14, padding: 20,
        background: 'var(--bg)', border: '1px solid var(--stroke)', color: 'var(--text)',
      }}>
        <div style={{ fontSize: 16.5, fontWeight: 700, letterSpacing: '-.01em', marginBottom: 8 }}>End party for everyone?</div>
        <p style={{ fontSize: 13, color: 'var(--text2)', lineHeight: 1.5, margin: '0 0 18px' }}>
          Everyone in the party will be disconnected immediately and returned to the lobby. This can&apos;t be undone.
        </p>
        <div style={{ display: 'flex', gap: 10 }}>
          <PanelButton tone="ghost" height={44} grow onClick={onCancel}>Cancel</PanelButton>
          <button type="button" onClick={onConfirm} style={{
            flex: 1, height: 44, borderRadius: 10, border: 'none', background: 'var(--red)',
            color: 'var(--text)', fontSize: 13.5, fontWeight: 700, cursor: 'pointer',
          }}>End party</button>
        </div>
      </div>
    </>
  )
}

/* ── the panel ──────────────────────────────────────────────────────────────
   Rebuilt as three independent panes (People / Controls / Share) plus an action
   footer. The panes are laid out side by side when height is the scarce axis
   (landscape phone, short desktop window), two-up on a roomy desktop, and
   stacked on a portrait phone. Only the participant list — the one unbounded
   list here — ever scrolls. */
export default function PartyPanel({
  phone, watching, top, onClose,
  layoutMode, onToggleLayout, hideSelf, onToggleHideSelf,
}: {
  phone: boolean
  watching: boolean
  top: number
  onClose: () => void
  layoutMode?: 'float' | 'dock'
  onToggleLayout?: () => void
  hideSelf?: boolean
  onToggleHideSelf?: () => void
}) {
  const { session, role, kickUser, transferHost, setCollaborative, setSyncMode, backToLobby, endParty } = useParty()
  const short = useMatch(SHORT)
  const wide = useMatch(WIDE)
  const roomy = useMatch(ROOMY)
  const [confirmEnd, setConfirmEnd] = useState(false)

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  if (!session) return null

  const isHost = role === 'host'
  const guests = session.guests ?? []
  const participantCount = 1 + guests.length
  const joinUrl = `${window.location.origin}/party/${session.id}`
  const syncMode = session.syncMode ?? 'hopping'

  const mode = panelMode(short, wide, phone)
  const dense = short
  const { tap, pad, gap, personRow, qr, codeSize, titleSize, closeSize, radius, headerPad, footerPad } =
    panelMetrics(dense, phone)
  const centred = phone || short

  // Explicit cap rather than flex-shrink: the panel's own height is auto, so a
  // shrink-to-fit list would need a definite parent height to resolve against.
  const listMax = dense
    ? 'min(320px, calc(100dvh - var(--sa-t) - var(--sa-b) - 180px))'
    : 'min(300px, calc(100dvh - 340px))'

  const people = (
    <Pane key="people" label={`In the party · ${participantCount}`} gap={dense ? 2 : 4} divided={false}>
      <div style={{
        display: 'flex', flexDirection: 'column', minHeight: 0, maxHeight: listMax,
        overflowY: 'auto', overscrollBehavior: 'contain', WebkitOverflowScrolling: 'touch',
      }}>
        <PersonRow name={session.hostName || 'Host'} badge="HOST" row={personRow} />
        {guests.map((g: PartyUser) => (
          <PersonRow
            key={g.userId} name={g.name} row={personRow}
            actions={isHost ? (
              <>
                <IconButton title={`Make ${g.name} host`} tap={tap} onClick={() => transferHost(g.userId)}>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="m3 11 2-7 4 4 3-5 3 5 4-4 2 7z" /><path d="M3 11h18v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /></svg>
                </IconButton>
                <IconButton title={`Remove ${g.name}`} tap={tap} danger onClick={() => kickUser(g.userId)}>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9"><path d="M16 17l5-5-5-5M21 12H9M13 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h8" /></svg>
                </IconButton>
              </>
            ) : undefined}
          />
        ))}
      </div>
    </Pane>
  )

  const showCollab = isHost
  const showSync = isHost && watching
  const showHideSelf = watching && !!onToggleHideSelf
  const showLayout = watching && !!onToggleLayout && !phone
  const hasControls = showCollab || showSync || showHideSelf || showLayout

  const controls = hasControls ? (
    <Pane key="controls" label="Controls" gap={gap} divided={mode === 'stack'}>
      {showCollab ? (
        <SettingRow
          label="Collaborative control"
          hint="Let guests browse, play, pause & seek"
          showHint={!dense} row={tap}
          control={
            <Switch
              checked={!!session.collaborativeControl} tap={tap}
              label="Collaborative control"
              onChange={() => setCollaborative(!session.collaborativeControl)}
            />
          }
        />
      ) : null}
      {showSync ? <SyncControl value={syncMode} onChange={setSyncMode} tap={tap} dense={dense} /> : null}
      {showHideSelf || showLayout ? (
        <div style={{
          display: 'flex', flexDirection: 'column', gap: dense ? 4 : 8,
          borderTop: hasControls && (showCollab || showSync) ? '1px solid var(--stroke)' : undefined,
          paddingTop: showCollab || showSync ? gap : 0,
        }}>
          {showHideSelf ? (
            <SettingRow
              label="Hide my camera"
              hint="Others still see you — this only drops your own tile"
              showHint={!dense} row={tap}
              control={<Switch checked={!!hideSelf} tap={tap} label="Hide my camera" onChange={onToggleHideSelf!} />}
            />
          ) : null}
          {showLayout ? (
            <SettingRow
              label="Camera layout"
              hint={layoutMode === 'dock' ? 'Docked in a column beside the video' : 'Floating over the video, drag anywhere'}
              showHint={!dense} row={tap}
              control={
                <PanelButton
                  tone="ghost" height={tap} onClick={onToggleLayout!}
                  title={layoutMode === 'dock' ? 'Float the cameras over the video' : 'Dock the cameras beside the video'}
                >{layoutMode === 'dock' ? 'Float' : 'Dock'}</PanelButton>
              }
            />
          ) : null}
        </div>
      ) : null}
    </Pane>
  ) : null

  const share = (
    <Pane key="share" label="Invite" gap={gap} divided={mode === 'stack'}>
      <ShareBlock
        code={session.id} url={joinUrl} tap={tap}
        side={mode === 'stack' || (mode === 'columns3' && roomy)} qr={qr} codeSize={codeSize}
      />
    </Pane>
  )

  const panes = [people, controls, share].filter(Boolean) as ReactNode[]
  const groups: ReactNode[][] =
    mode === 'stack' ? [panes]
      : mode === 'columns3' ? panes.map(p => [p])
        : panes.length === 3 ? [[panes[0], panes[1]], [panes[2]]]
          : panes.map(p => [p])

  const showFooter = isHost
  const template = groups.length === 3
    ? 'minmax(0,1.05fr) minmax(0,1fr) minmax(0,1fr)'
    : `repeat(${groups.length}, minmax(0,1fr))`

  const width = mode === 'columns3'
    ? 'min(860px, calc(100vw - var(--sa-l) - var(--sa-r) - 20px))'
    : mode === 'stack'
      ? 'min(420px, calc(100vw - 24px))'
      : 'min(560px, calc(100vw - var(--sa-l) - var(--sa-r) - 20px))'

  return (
    <>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, zIndex: 50, background: 'rgba(0,0,0,.72)' }} />
      <div
        role="dialog" aria-modal="true" aria-label="Watch party"
        style={{
          position: 'absolute', zIndex: 51,
          top: centred ? '50%' : top + 64,
          left: centred ? '50%' : 'auto',
          right: centred ? 'auto' : 18,
          transform: centred ? 'translate(-50%,-50%)' : 'none',
          width, display: 'flex', flexDirection: 'column',
          maxHeight: dense
            ? 'calc(100dvh - var(--sa-t) - var(--sa-b) - 16px)'
            : 'min(680px, calc(100dvh - 100px))',
          background: 'var(--bg)', border: '1px solid var(--stroke)', borderRadius: radius,
          color: 'var(--text)', boxShadow: '0 24px 70px rgba(0,0,0,.55)', overflow: 'hidden',
        }}
      >
        <header style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10,
          padding: headerPad, borderBottom: '1px solid var(--stroke)', flexShrink: 0,
        }}>
          <span style={{ fontSize: titleSize, fontWeight: 700, letterSpacing: '-.02em' }}>Watch party</span>
          <button
            type="button" onClick={onClose} title="Close" aria-label="Close"
            style={{
              width: closeSize, height: closeSize, borderRadius: 8, border: 'none',
              background: 'transparent', color: 'var(--text2)', display: 'grid', placeItems: 'center', cursor: 'pointer',
            }}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M18 6 6 18M6 6l12 12" /></svg>
          </button>
        </header>

        <div style={{
          flex: 1, minHeight: 0, padding: pad,
          overflowY: 'auto', overscrollBehavior: 'contain',
          display: 'grid', gridTemplateColumns: template, gap: pad, alignItems: 'stretch',
        }}>
          {groups.map((group, i) => (
            <div key={i} style={{
              display: 'flex', flexDirection: 'column', gap: mode === 'stack' ? gap + 4 : gap,
              minWidth: 0, minHeight: 0,
              ...(i > 0 && mode !== 'stack'
                ? { borderLeft: '1px solid var(--stroke)', paddingLeft: pad }
                : null),
            }}>
              {group}
            </div>
          ))}
        </div>

        {showFooter ? (
          <footer style={{
            display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0, flexWrap: 'wrap',
            padding: footerPad, borderTop: '1px solid var(--stroke)',
          }}>
            {watching ? (
              <PanelButton tone="ghost" height={tap} onClick={() => { backToLobby(); onClose() }} title="Go back and pick something else">
                ← Pick something else
              </PanelButton>
            ) : null}
            {/* Deliberately no shared-browser control here either: this panel is
                reached from the movie screen. It lives in the popcorn widget. */}
            <div style={{ flex: 1, minWidth: 0 }} />
            <PanelButton tone="danger" height={tap} onClick={() => setConfirmEnd(true)} title="End the party for everyone">
              {dense ? 'End party' : 'End party for everyone'}
            </PanelButton>
          </footer>
        ) : null}
      </div>

      {/* Instant and permanent, unlike leaving/closing the tab (which still goes
          through the grace-period host-disconnect path) — so it keeps its own
          explicit confirmation step. */}
      {confirmEnd ? (
        <EndPartyConfirm
          onCancel={() => setConfirmEnd(false)}
          onConfirm={() => { setConfirmEnd(false); onClose(); void endParty() }}
        />
      ) : null}
    </>
  )
}
