import { useEffect, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { useParty } from '../context/PartyContext'
import { glass } from '../glass'
import type { ChatMessage } from '../types'

const MONO = "'JetBrains Mono', ui-monospace, monospace"

function fmt(ts: number) {
  return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

// Alert modes: focus (open+focus on msg), on (edge ripple), mute (silent)
const ALERT = {
  focus: { next: 'on', label: 'Alerts: focus', icon: <path d="M12 2v3M12 19v3M2 12h3M19 12h3M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z" /> },
  on: { next: 'mute', label: 'Alerts: on', icon: <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0" /> },
  mute: { next: 'focus', label: 'Alerts: muted', icon: <><path d="m2 2 20 20" /><path d="M18 8a6 6 0 0 0-9.3-5M6 8c0 7-3 9-3 9h13M13.7 21a2 2 0 0 1-3.4 0" /></> },
} as const

export default function Chat({ top = 76, mobileSheet = false }: { top?: number; mobileSheet?: boolean } = {}) {
  const { messages, sendMessage, chatOpen, closeChat, alertMode, setAlertMode, chatFocusToken } = useParty()
  const [text, setText] = useState('')
  const bottomRef = useRef<HTMLDivElement | null>(null)
  const inputRef = useRef<HTMLInputElement | null>(null)

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages, chatOpen])
  // Pull focus into the input whenever asked (hotkey / auto-open on message)
  useEffect(() => { if (chatOpen) inputRef.current?.focus() }, [chatFocusToken, chatOpen])

  useEffect(() => {
    if (!chatOpen) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') closeChat() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [chatOpen, closeChat])

  if (!chatOpen) return null

  function handleSend(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (!text.trim()) return
    sendMessage(text.trim())
    setText('')
  }

  const a = ALERT[alertMode] || ALERT.focus

  // Sheet mode: fill the slide-over container (positioned by ChatSheet in
  // Party.jsx). Desktop mode: the original floating right-side panel.
  const frame: any = mobileSheet
    ? { position: 'absolute', inset: 0, animation: 'none' }
    : { position: 'absolute', top, right: 12, bottom: 84, width: 'min(300px, calc(100vw - 24px))', animation: 'chatIn .28s cubic-bezier(.2,.8,.2,1)' }

  return (
    <div style={{
      ...glass('light'),
      ...frame,
      zIndex: 22, borderRadius: 16, display: 'flex', flexDirection: 'column', overflow: 'hidden', color: 'var(--text)',
    }}>
      {/* Header — minimal: label + alert toggle + close */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '12px 12px 12px 16px', borderBottom: '1px solid var(--stroke)' }}>
        <span style={{ flex: 1, fontFamily: MONO, fontSize: 11, letterSpacing: '.16em', textTransform: 'uppercase', color: 'var(--text2)' }}>Chat</span>
        <button onClick={() => setAlertMode(a.next)} title={a.label} style={hdrBtn(alertMode === 'mute')}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{a.icon}</svg>
        </button>
        <button onClick={closeChat} title="Close (Esc)" style={hdrBtn()}>
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M18 6 6 18M6 6l12 12" /></svg>
        </button>
      </div>

      {/* Messages */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {messages.length === 0 && (
          <div style={{ margin: 'auto', textAlign: 'center', color: 'var(--text3)', fontSize: 13 }}>No messages yet</div>
        )}
        {messages.map((msg: ChatMessage, i: number) => {
          const cont = i > 0 && messages[i - 1].userId === msg.userId
          return (
            <div key={i} style={{ marginTop: cont ? -6 : 0 }}>
              {!cont && (
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 3 }}>
                  <span style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--text)' }}>{msg.name}</span>
                  <span style={{ fontFamily: MONO, fontSize: 10, color: 'var(--text3)' }}>{fmt(msg.timestamp)}</span>
                </div>
              )}
              <div style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--text2)', wordBreak: 'break-word' }}>{msg.text}</div>
            </div>
          )
        })}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <form onSubmit={handleSend} style={{ padding: 12, display: 'flex', gap: 8, alignItems: 'center', borderTop: '1px solid var(--stroke)' }}>
        <input ref={inputRef} value={text} onChange={e => setText(e.target.value)} placeholder="Message…" maxLength={500}
          style={{ flex: 1, padding: '11px 14px', borderRadius: 999, border: '1px solid var(--stroke2)', background: 'var(--glass2)', color: 'var(--text)', fontSize: 14, outline: 'none', transition: 'border-color .15s' }}
          onFocus={e => { e.currentTarget.style.borderColor = 'var(--text3)' }}
          onBlur={e => { e.currentTarget.style.borderColor = 'var(--stroke2)' }} />
        <button type="submit" disabled={!text.trim()} style={{
          width: 40, height: 40, flexShrink: 0, borderRadius: '50%', border: 'none',
          background: text.trim() ? 'var(--accent)' : 'var(--glass2)', color: text.trim() ? 'var(--on-accent)' : 'var(--text3)',
          display: 'grid', placeItems: 'center', cursor: text.trim() ? 'pointer' : 'default', transition: 'background .15s',
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M12 19V5M5 12l7-7 7 7" /></svg>
        </button>
      </form>
    </div>
  )
}

const hdrBtn = (active = false) => ({
  width: 30, height: 30, borderRadius: 9, border: 'none', cursor: 'pointer', display: 'grid', placeItems: 'center',
  background: 'transparent', color: active ? 'var(--text3)' : 'var(--text2)',
})
