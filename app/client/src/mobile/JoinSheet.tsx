import { useState } from 'react'
import { navigate } from '../router'
import { T, MONO, TYPE, R, EASE } from './theme'
import { Sheet } from './ui/Sheet'
import { Icon, Ic } from './ui/Icon'

// Party codes are 8-char uppercase hex (server: randomUUID().slice(0,8).toUpperCase()).
const CODE_RE = /^[0-9A-F]{8}$/

/**
 * Start-or-join sheet — the tab bar's center Party action opens this. Two verbs:
 *   • Start a new party  → navigate('/party/new')  (lands in the lobby)
 *   • Join by code       → validates 8-hex, navigate('/party/:code')
 * QR join already works by opening the shared link (camera app → /party/:code),
 * so this focuses on manual entry; an in-app scanner can layer on later.
 */
export function JoinSheet({ open, onClose }: any = {}) {
  const [code, setCode] = useState('')
  const clean = code.replace(/[^0-9a-fA-F]/g, '').toUpperCase().slice(0, 8)
  const valid = CODE_RE.test(clean)

  const go = (path) => { onClose?.(); navigate(path) }
  const submit = (e) => { e.preventDefault(); if (valid) go(`/party/${clean}`) }

  return (
    <Sheet open={open} onClose={onClose} title="Watch together">
      <button
        onClick={() => go('/party/new')}
        className="mob-press"
        style={{
          width: '100%', display: 'flex', alignItems: 'center', gap: 14,
          padding: '16px 16px', borderRadius: R.md, border: 'none', cursor: 'pointer',
          background: T.primary, color: T.onLight, textAlign: 'left', marginBottom: 18,
        }}
      >
        <span style={{ width: 42, height: 42, borderRadius: 999, background: 'rgba(10,10,11,.14)', display: 'grid', placeItems: 'center', flex: '0 0 auto' }}>
          <Icon path={Ic.play} size={22} fill={T.onLight} stroke="none" />
        </span>
        <span style={{ minWidth: 0 }}>
          <span style={{ ...TYPE.headline, display: 'block', color: T.onLight }}>Start a new party</span>
          <span style={{ ...TYPE.label, display: 'block', fontWeight: 600, color: 'rgba(10,10,11,.65)' }}>Pick something to watch, invite friends</span>
        </span>
      </button>

      <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '4px 0 16px', color: T.faint }}>
        <span style={{ flex: 1, height: 1, background: T.line }} />
        <span style={{ fontFamily: MONO, fontSize: 11, letterSpacing: '.14em' }}>OR JOIN</span>
        <span style={{ flex: 1, height: 1, background: T.line }} />
      </div>

      <form onSubmit={submit}>
        <label style={{ ...TYPE.meta, color: T.dim, display: 'block', marginBottom: 8 }}>Party code</label>
        <div style={{ display: 'flex', gap: 10 }}>
          <input
            value={clean}
            onChange={(e) => setCode(e.target.value)}
            placeholder="A1B2C3D4"
            inputMode="text"
            autoCapitalize="characters"
            autoCorrect="off"
            spellCheck={false}
            style={{
              flex: 1, minWidth: 0, height: 52, padding: '0 16px', borderRadius: R.md,
              border: `1px solid ${valid ? T.text : T.line2}`,
              background: 'rgba(255,255,255,.05)', color: T.text,
              fontFamily: MONO, fontSize: 20, fontWeight: 600, letterSpacing: '.22em', outline: 'none',
              transition: `border-color .15s ${EASE}`,
            }}
          />
          <button
            type="submit"
            disabled={!valid}
            className="mob-press"
            style={{
              flex: '0 0 auto', height: 52, padding: '0 20px', borderRadius: R.md, border: 'none',
              background: valid ? T.primary : T.surface2,
              color: valid ? T.onLight : T.faint,
              ...TYPE.label, fontWeight: 700, fontSize: 15,
              cursor: valid ? 'pointer' : 'default',
              display: 'flex', alignItems: 'center', gap: 8,
            }}
          >
            <Icon path={Ic.enter} size={19} stroke={valid ? T.onLight : T.faint} />
            Join
          </button>
        </div>
        <p style={{ ...TYPE.label, fontWeight: 500, color: T.faint, marginTop: 12, display: 'flex', alignItems: 'center', gap: 7 }}>
          <Icon path={Ic.qr} size={16} stroke={T.faint} />
          Scan a friend's QR to open their party directly.
        </p>
      </form>
    </Sheet>
  )
}
