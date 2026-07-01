import { useEffect, useRef, useState } from 'react'
import { useParty } from '../context/PartyContext.jsx'

function fmt(ts) {
  return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

const COLORS = ['#0A84FF','#FF9F0A','#30D158','#BF5AF2','#FF6482','#64D2FF']
function colorFor(name) {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffffffff
  return COLORS[Math.abs(h) % COLORS.length]
}

export default function Chat() {
  const { messages, sendMessage, chatOpen, toggleChat } = useParty()
  const [text, setText] = useState('')
  const bottomRef = useRef(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  function handleSend(e) {
    e.preventDefault()
    if (!text.trim()) return
    sendMessage(text.trim())
    setText('')
  }

  if (!chatOpen) return null

  return (
    <div style={{
      position: 'absolute', top: 76, right: 18, bottom: 108, width: 310,
      zIndex: 15, borderRadius: 22,
      display: 'flex', flexDirection: 'column',
      background: 'var(--glass)',
      backdropFilter: 'var(--blur)', WebkitBackdropFilter: 'var(--blur)',
      border: '1px solid var(--stroke)',
      boxShadow: 'var(--shadow), inset 0 1px 0 var(--hi)',
      overflow: 'hidden',
      animation: 'up .25s cubic-bezier(.2,0,.1,1)',
    }}>
      {/* Header */}
      <div style={{
        padding: '14px 16px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        borderBottom: '1px solid var(--stroke)',
        flexShrink: 0,
      }}>
        <span style={{ fontSize: 14.5, fontWeight: 700, letterSpacing: '-0.01em' }}>Chat</span>
        <button onClick={toggleChat} style={{
          width: 26, height: 26, borderRadius: 8, border: 'none',
          background: 'var(--glass2)', color: 'var(--text2)',
          display: 'grid', placeItems: 'center', cursor: 'pointer',
        }}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M18 6 6 18M6 6l12 12"/></svg>
        </button>
      </div>

      {/* Messages */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        {messages.length === 0 && (
          <div style={{ color: 'var(--text3)', fontSize: 13, textAlign: 'center', marginTop: 20 }}>
            No messages yet
          </div>
        )}
        {messages.map((msg, i) => (
          <div key={i}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 7, marginBottom: 3 }}>
              <span style={{ fontSize: 12, fontWeight: 700, color: colorFor(msg.name) }}>{msg.name}</span>
              <span style={{ fontSize: 10.5, color: 'var(--text3)' }}>{fmt(msg.timestamp)}</span>
            </div>
            <div style={{
              fontSize: 13.5, lineHeight: 1.45, color: 'var(--text)',
              padding: '8px 11px', borderRadius: '4px 12px 12px 12px',
              background: 'var(--glass2)', border: '1px solid var(--stroke)',
              display: 'inline-block', maxWidth: '100%', wordBreak: 'break-word',
            }}>{msg.text}</div>
          </div>
        ))}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <form onSubmit={handleSend} style={{
        padding: '12px 13px',
        borderTop: '1px solid var(--stroke)',
        display: 'flex', gap: 8, alignItems: 'center',
        flexShrink: 0,
      }}>
        <input
          value={text}
          onChange={e => setText(e.target.value)}
          placeholder="Message…"
          maxLength={500}
          style={{
            flex: 1, padding: '10px 13px', borderRadius: 13,
            border: '1px solid var(--stroke)', background: 'var(--glass2)',
            color: 'var(--text)', fontSize: 13.5, outline: 'none',
            transition: 'border-color .15s',
          }}
          onFocus={e => e.target.style.borderColor = 'var(--accent)'}
          onBlur={e => e.target.style.borderColor = 'var(--stroke)'}
        />
        <button type="submit" style={{
          width: 38, height: 38, flexShrink: 0,
          borderRadius: 11, border: 'none',
          background: text.trim() ? 'var(--accent)' : 'var(--glass2)',
          color: text.trim() ? '#fff' : 'var(--text3)',
          display: 'grid', placeItems: 'center', cursor: 'pointer',
          transition: 'background .15s, color .15s',
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M22 2 11 13M22 2l-7 20-4-9-9-4 20-7z"/></svg>
        </button>
      </form>
    </div>
  )
}
