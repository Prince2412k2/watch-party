import { useEffect, useRef, useState } from 'react'
import Avatar from '../../src/components/Avatar.tsx'
import { AnIcon } from '../../src/analog/icons.tsx'
import type { Member, Message } from './core.ts'

const reactions = [
  { name: 'Yes · celebrate', url: 'https://media.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif' },
  { name: 'Laugh · happy', url: 'https://media.giphy.com/media/10JhviFuU2gWD6/giphy.gif' },
  { name: 'Wow · surprised', url: 'https://media.giphy.com/media/5VKbvrjxpVJCM/giphy.gif' },
  { name: 'Popcorn · watching', url: 'https://media.giphy.com/media/pUeXcg80cO8I8/giphy.gif' },
]

export default function Chat({ messages, members, ownId, connected, onSend, onError, onClose }: {
  messages: Message[]; members: Member[]; ownId?: string; connected: boolean
  onSend: (content: { text: string; gif?: string; reply?: Message['reply'] }) => Promise<unknown>
  onError: (message: string) => void; onClose: () => void
}) {
  const [draft, setDraft] = useState('')
  const [reply, setReply] = useState<Message['reply']>()
  const [picker, setPicker] = useState<'gif' | 'emoji' | null>(null)
  const [search, setSearch] = useState('')
  const [url, setUrl] = useState('')
  const [sending, setSending] = useState(false)
  const input = useRef<HTMLTextAreaElement>(null)
  const scroll = useRef<HTMLDivElement>(null)
  const atBottom = useRef(true)
  useEffect(() => {
    if (atBottom.current && scroll.current) scroll.current.scrollTop = scroll.current.scrollHeight
  }, [messages])
  async function send(gif?: string) {
    if (sending || !connected || (!draft.trim() && !gif)) return
    if (gif) {
      try { const parsed = new URL(gif); if (parsed.protocol !== 'https:' || parsed.username || parsed.password) throw new Error(); gif = parsed.href }
      catch { onError('Enter a valid HTTPS GIF URL.'); return }
    }
    setSending(true)
    try {
      await onSend({ text: draft.trim(), ...(gif ? { gif } : {}), ...(reply ? { reply } : {}) })
      setDraft(''); setReply(undefined); setPicker(null); setUrl(''); atBottom.current = true
      if (input.current) input.current.style.height = ''
      input.current?.focus()
    } catch (error) { onError(error instanceof Error ? error.message : 'Message could not send.') }
    finally { setSending(false) }
  }
  return <section className="chat-panel" aria-label="Party chat">
    <header className="chat-heading"><img className="chat-heading-icon" src="chat.svg" width="20" height="20" alt="" /><div className="chat-heading-copy"><strong>{connected ? 'Watching together' : 'Reconnecting…'}</strong><span>{members.length} in this party</span></div><div className="chat-people">{members.slice(0, 3).map(member => <Avatar key={member.userId} userId={member.userId} name={member.name} config={member.avatar} circle size={23} />)}</div><button className="icon-button" title="Close chat" aria-label="Close chat" onClick={onClose}><AnIcon name="x" size={16} /></button></header>
    <div className="messages" role="log" aria-label="Messages" aria-live="polite" ref={scroll} onScroll={event => { const node = event.currentTarget; atBottom.current = node.scrollHeight - node.scrollTop - node.clientHeight < 60 }}>
      {!messages.length && <div className="chat-empty"><img src="chat.svg" width="24" height="24" alt="" /><strong>You're here together.</strong><p>Send the first message.</p></div>}
      {messages.map((message, index) => {
        const member = members.find(candidate => candidate.userId === message.userId)
        const own = message.userId === ownId
        return <article className={`message${own ? ' own' : ''}`} key={`${message.timestamp}-${index}`}>
          <Avatar userId={message.userId} name={message.name} config={member?.avatar} size={26} circle />
          <div className="message-content"><header><strong>{own ? 'You' : message.name}</strong><time>{new Date(message.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</time></header>
            {message.reply && <blockquote><strong>{message.reply.name}</strong><span>{message.reply.text}</span></blockquote>}
            {message.gif && /^https:\/\//.test(message.gif) ? <a className="message-gif" href={message.gif} target="_blank" rel="noreferrer"><img src={message.gif} alt="Shared GIF" loading="lazy" referrerPolicy="no-referrer" onError={event => { event.currentTarget.alt = 'GIF unavailable. Open to view.' }} /></a> : <p>{message.text}</p>}
          </div><button className="icon-button reply-button" title={`Reply to ${message.name}`} aria-label={`Reply to ${message.name}`} onClick={() => { setReply({ name: message.name, text: message.gif ? 'GIF' : message.text.slice(0, 240) }); setPicker(null); input.current?.focus() }}><AnIcon name="back" size={15} /></button>
        </article>
      })}
    </div>
    <form className="composer" onSubmit={event => { event.preventDefault(); void send() }}>
      {reply && <div className="reply-strip"><div><strong>Replying to {reply.name}</strong><span>{reply.text}</span></div><button type="button" className="icon-button" aria-label="Cancel reply" onClick={() => setReply(undefined)}><AnIcon name="x" size={14} /></button></div>}
      {picker && <section className="chat-picker" role="dialog" aria-label={picker === 'gif' ? 'GIF picker' : 'Emoji picker'}><header><strong>{picker === 'gif' ? 'Send a GIF' : 'Add an emoji'}</strong><button type="button" className="icon-button" aria-label="Close picker" onClick={() => setPicker(null)}><AnIcon name="x" size={15} /></button></header>
        {picker === 'gif' ? <><label className="sr-only" htmlFor="gif-search">Search reactions</label><input id="gif-search" type="search" placeholder="Search reactions" value={search} onChange={event => setSearch(event.target.value)} /><div className="gif-grid">{reactions.filter(item => item.name.toLowerCase().includes(search.toLowerCase())).map(item => <button type="button" className="gif-choice" key={item.url} disabled={sending || !connected} onClick={() => void send(item.url)} aria-label={`Send ${item.name} GIF`}><img src={item.url} alt={item.name} loading="lazy" referrerPolicy="no-referrer" /><span>{item.name.split(' · ')[0]}</span></button>)}{!reactions.some(item => item.name.toLowerCase().includes(search.toLowerCase())) && <p className="hint">No matching reactions. Paste a GIF link below.</p>}</div><div className="gif-url"><label className="sr-only" htmlFor="gif-url">HTTPS GIF URL</label><input id="gif-url" type="url" placeholder="Paste a GIF link" value={url} onChange={event => setUrl(event.target.value)} /><button type="button" disabled={!url || sending || !connected} onClick={() => void send(url)}>Send</button></div></> : <div className="emoji-grid">{['🙂', '😂', '❤️', '👏', '🍿', '😮', '🙌', '👍', '👀', '🎉', '😢', '🔥'].map(emoji => <button key={emoji} type="button" aria-label={`Insert ${emoji}`} onClick={() => { setDraft(value => `${value}${emoji}`); setPicker(null); input.current?.focus() }}>{emoji}</button>)}</div>}
      </section>}
      <div className="compose-line"><label className="sr-only" htmlFor="chat-draft">Message</label><textarea ref={input} id="chat-draft" rows={1} placeholder="Message your party…" value={draft} maxLength={2000} onChange={event => { setDraft(event.target.value); event.target.style.height = '24px'; event.target.style.height = `${Math.min(96, event.target.scrollHeight)}px` }} onKeyDown={event => { if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) { event.preventDefault(); void send() }; if (event.key === 'Escape') { setPicker(null); setReply(undefined) } }} />
        <div className="compose-tools"><button type="button" className="text-tool" aria-label="Open GIF picker" title="Send a GIF" aria-expanded={picker === 'gif'} onClick={() => setPicker(value => value === 'gif' ? null : 'gif')}><AnIcon name="film" size={16} /></button><button type="button" className="text-tool" aria-label="Open emoji picker" title="Add emoji" aria-expanded={picker === 'emoji'} onClick={() => setPicker(value => value === 'emoji' ? null : 'emoji')}><img src="smile.svg" width="17" height="17" alt="" /></button><button className="send-button" aria-label="Send message" title="Send message" disabled={sending || !draft.trim() || !connected}><AnIcon name="enter" size={17} /></button></div>
      </div>
    </form>
  </section>
}
