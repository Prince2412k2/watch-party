import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type FormEvent,
} from 'react'
import { useParty } from '../context/PartyContext.tsx'
import { useAuth } from '../context/AuthContext.tsx'
import { RoomButton } from './RoomControls.tsx'

/** The same opaque right-hand card as native. It overlays, never resizes, video. */
export default function Chat(
  _props: { top?: number; mobileSheet?: boolean } = {}
) {
  const { messages, sendMessage, chatOpen, closeChat, chatFocusToken } =
    useParty()
  const { user } = useAuth()
  const [text, setText] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [mounted, setMounted] = useState(chatOpen)
  const input = useRef<HTMLInputElement>(null)
  const list = useRef<HTMLDivElement>(null)
  const returnFocus = useRef<HTMLElement | null>(null)
  useEffect(() => {
    if (chatOpen) {
      returnFocus.current = document.activeElement as HTMLElement
      setMounted(true)
      return
    }
    returnFocus.current?.focus({ preventScroll: true })
    const timer = setTimeout(() => setMounted(false), 240)
    return () => clearTimeout(timer)
  }, [chatOpen])
  useLayoutEffect(() => {
    if (chatOpen && mounted) input.current?.focus({ preventScroll: true })
  }, [chatOpen, mounted, chatFocusToken])
  useLayoutEffect(() => {
    if (chatOpen && list.current)
      list.current.scrollTop = list.current.scrollHeight
  }, [messages, chatOpen, mounted])
  useEffect(() => {
    if (!chatOpen) return
    const key = (event: KeyboardEvent) => {
      const selection =
        input.current &&
        input.current.selectionStart !== input.current.selectionEnd
      if (
        event.key === 'Escape' ||
        ((event.ctrlKey || event.metaKey) &&
          event.key.toLowerCase() === 'c' &&
          !selection &&
          !window.getSelection()?.toString())
      ) {
        event.preventDefault()
        event.stopImmediatePropagation()
        closeChat()
      }
    }
    window.addEventListener('keydown', key, true)
    return () => window.removeEventListener('keydown', key, true)
  }, [chatOpen, closeChat])
  async function send(event: FormEvent) {
    event.preventDefault()
    if (!text.trim() || busy) return
    setBusy(true)
    setError('')
    const failure = await sendMessage(text.trim())
    if (failure) setError(failure)
    else setText('')
    setBusy(false)
    input.current?.focus({ preventScroll: true })
  }
  if (!mounted) return null
  return (
    <section
      className="native-chat"
      data-open={chatOpen}
      aria-label="Room chat"
      onClick={(event) => event.stopPropagation()}
    >
      <header>
        <h2>Chat</h2>
        <RoomButton label="Close chat" icon="x" onClick={closeChat} />
      </header>
      <div
        className="native-chat-messages"
        ref={list}
        role="log"
        aria-live="polite"
      >
        {messages.length === 0 && (
          <p className="native-chat-empty">No messages yet</p>
        )}
        {messages.map((message, index) => (
          <div
            className="native-chat-message"
            data-own={message.userId === user?.userId}
            key={`${message.timestamp}-${index}`}
          >
            <div className="native-chat-byline">
              <span>
                {message.userId === user?.userId ? 'You' : message.name}
              </span>
              <time>
                {new Date(
                  message.timestamp ?? message.ts ?? 0
                ).toLocaleTimeString([], {
                  hour: '2-digit',
                  minute: '2-digit',
                  hour12: false,
                })}
              </time>
            </div>
            <p>{message.text}</p>
          </div>
        ))}
      </div>
      {error && (
        <p className="native-chat-error" role="alert">
          {error}
        </p>
      )}
      <form
        onSubmit={(event) => {
          void send(event)
        }}
      >
        <input
          ref={input}
          aria-label="Message the room"
          placeholder="Message the room"
          value={text}
          onChange={(event) => setText(event.target.value)}
          maxLength={2000}
          readOnly={busy}
        />
        <button
          aria-label="Send message"
          type="submit"
          disabled={busy || !text.trim()}
        >
          ↑
        </button>
      </form>
    </section>
  )
}
