import { useEffect, useRef, useState } from 'react'
import { useParty } from '../context/PartyContext.jsx'
import { glass } from '../glass.jsx'

const MONO = "'JetBrains Mono', ui-monospace, monospace"

function fmt(ts) {
  return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}
const COLORS = ['#7dd3fc', '#fca5a5', '#86efac', '#c4b5fd', '#fda4af', '#fcd34d']
function colorFor(name = '') {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffffffff
  return COLORS[Math.abs(h) % COLORS.length]
}

// Alert modes: focus (open+focus on msg), on (edge ripple), mute (silent)
const ALERT = {
  focus: { next: 'on', label: 'Alerts: focus', icon: <path d="M12 2v3M12 19v3M2 12h3M19 12h3M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z" /> },
  on: { next: 'mute', label: 'Alerts: on', icon: <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0" /> },
  mute: { next: 'focus', label: 'Alerts: muted', icon: <><path d="m2 2 20 20" /><path d="M18 8a6 6 0 0 0-9.3-5M6 8c0 7-3 9-3 9h13M13.7 21a2 2 0 0 1-3.4 0" /></> },
}

export default function Chat({ top = 76, mobileSheet = false }) {
  const { messages, sendMessage, chatOpen, closeChat, alertMode, setAlertMode, chatFocusToken } = useParty()
  const [text, setText] = useState('')
  const bottomRef = useRef(null)
  const inputRef = useRef(null)

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages, chatOpen])
  // Pull focus into the input whenever asked (hotkey / auto-open on message)
  useEffect(() => { if (chatOpen) inputRef.current?.focus() }, [chatFocusToken, chatOpen])

  useEffect(() => {
    if (!chatOpen) return
    const onKey = (e) => { if (e.key === 'Escape') closeChat() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [chatOpen, closeChat])

  if (!chatOpen) return null

  function handleSend(e) {
    e.preventDefault()
    if (!text.trim()) return
    sendMessage(text.trim())
    setText('')
  }

  const a = ALERT[alertMode] || ALERT.focus

  // Sheet mode: fill the slide-over container (positioned by ChatSheet in
  // Party.jsx). Desktop mode: the original floating right-side panel.
  const frame = mobileSheet
    ? { position: 'absolute', inset: 0, animation: 'none' }
    : { position: 'absolute', top, right: 12, bottom: 84, width: 'min(300px, calc(100vw - 24px))', animation: 'chatIn .28s cubic-bezier(.2,.8,.2,1)' }

  return (
    <div style={{
      ...glass('heavy', { refract: true }),
      ...frame,
      zIndex: 22, borderRadius: 18, display: 'flex', flexDirection: 'column', overflow: 'hidden', color: '#fff',
    }}>
      {/* Header — minimal: label + alert toggle + close */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '12px 12px 12px 16px', borderBottom: '1px solid rgba(255,255,255,.08)' }}>
        <span style={{ flex: 1, fontFamily: MONO, fontSize: 11, letterSpacing: '.16em', textTransform: 'uppercase', color: 'rgba(255,255,255,.5)' }}>Chat</span>
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
          <div style={{ margin: 'auto', textAlign: 'center', color: 'rgba(255,255,255,.32)', fontSize: 13 }}>No messages yet</div>
        )}
        {messages.map((msg, i) => {
          const cont = i > 0 && messages[i - 1].userId === msg.userId
          return (
            <div key={i} style={{ marginTop: cont ? -6 : 0 }}>
              {!cont && (
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 3 }}>
                  <span style={{ fontSize: 12.5, fontWeight: 700, color: colorFor(msg.name) }}>{msg.name}</span>
                  <span style={{ fontFamily: MONO, fontSize: 10, color: 'rgba(255,255,255,.3)' }}>{fmt(msg.timestamp)}</span>
                </div>
              )}
              <div style={{ fontSize: 14, lineHeight: 1.5, color: 'rgba(255,255,255,.92)', wordBreak: 'break-word' }}>{msg.text}</div>
            </div>
          )
        })}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <form onSubmit={handleSend} style={{ padding: 12, display: 'flex', gap: 8, alignItems: 'center', borderTop: '1px solid rgba(255,255,255,.08)' }}>
        <input ref={inputRef} value={text} onChange={e => setText(e.target.value)} placeholder="Message…" maxLength={500}
          style={{ flex: 1, padding: '11px 14px', borderRadius: 999, border: '1px solid rgba(255,255,255,.12)', background: 'rgba(255,255,255,.05)', color: '#fff', fontSize: 14, outline: 'none', transition: 'border-color .15s' }}
          onFocus={e => e.target.style.borderColor = 'rgba(255,255,255,.36)'}
          onBlur={e => e.target.style.borderColor = 'rgba(255,255,255,.12)'} />
        <button type="submit" disabled={!text.trim()} style={{
          width: 40, height: 40, flexShrink: 0, borderRadius: '50%', border: 'none',
          background: text.trim() ? '#EDEFF2' : 'rgba(255,255,255,.06)', color: text.trim() ? '#0a0a0c' : 'rgba(255,255,255,.3)',
          display: 'grid', placeItems: 'center', cursor: text.trim() ? 'pointer' : 'default', transition: 'background .15s',
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M12 19V5M5 12l7-7 7 7" /></svg>
        </button>
      </form>
    </div>
  )
}

const hdrBtn = (active) => ({
  width: 30, height: 30, borderRadius: 9, border: 'none', cursor: 'pointer', display: 'grid', placeItems: 'center',
  background: 'transparent', color: active ? 'rgba(255,255,255,.35)' : 'rgba(255,255,255,.7)',
})
