// Optional rich content stays compatible with older text-only clients.
export function chatContent(payload = {}) {
  const text = typeof payload?.text === 'string' ? payload.text.trim().slice(0, 2000) : ''
  let gif
  if (payload?.gif) {
    try {
      const url = new URL(payload.gif)
      if (url.protocol !== 'https:' || url.username || url.password || url.href.length > 2000) return null
      gif = url.href
    } catch { return null }
  }
  if (!text && !gif) return null
  const reply = payload?.reply && typeof payload.reply.name === 'string' && typeof payload.reply.text === 'string'
    ? { name: payload.reply.name.slice(0, 80), text: payload.reply.text.slice(0, 240) } : undefined
  return { text: text || 'GIF', ...(gif ? { gif } : {}), ...(reply ? { reply } : {}) }
}
