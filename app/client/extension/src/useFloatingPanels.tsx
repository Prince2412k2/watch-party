import { useEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { bridge } from './core.ts'

export function useFloatingPanels(active: boolean, render: (id: string) => ReactNode, onVisibility: (id: string, visible: boolean) => void) {
  const owner = useRef(crypto.randomUUID())
  const [views, setViews] = useState<Record<string, HTMLElement>>({})
  const visibility = useRef(onVisibility); visibility.current = onVisibility
  useEffect(() => {
    bridge({ type: 'panels', owner: owner.current, active })
    if (!active) setViews({})
    return () => { bridge({ type: 'panels', owner: owner.current, active: false }) }
  }, [active])
  useEffect(() => {
    const receive = (event: MessageEvent) => {
      const data = event.data
      if (!event.isTrusted || data?.owner !== owner.current) return
      if (event.source === window.parent && event.origin === 'https://www.youtube.com' && data.source === 'watchparty-youtube' && data.type === 'panel-visibility') {
        visibility.current(data.id, data.visible === true)
        return
      }
      if (event.origin !== location.origin || data.source !== 'watchparty-panel-ready' || !['chat', 'av'].includes(data.id)) return
      try {
        const view = event.source as Window
        const url = new URL(view.location.href)
        if (!url.pathname.endsWith('/panel.html') || url.searchParams.get('owner') !== owner.current || url.searchParams.get('id') !== data.id) return
        const root = view.document.getElementById('root')
        if (!root) return
        for (const link of document.querySelectorAll<HTMLLinkElement>('link[rel=stylesheet]')) {
          if (!Array.from(view.document.querySelectorAll<HTMLLinkElement>('link[rel=stylesheet]')).some(existing => existing.href === link.href)) {
            const copy = view.document.createElement('link'); copy.rel = 'stylesheet'; copy.href = link.href; view.document.head.append(copy)
          }
        }
        view.document.title = data.id === 'chat' ? 'Party chat' : 'Camera & mic'
        setViews(previous => previous[data.id] === root ? previous : { ...previous, [data.id]: root })
        view.postMessage({ source: 'watchparty-panel-owner', owner: owner.current }, location.origin)
      } catch { /* A panel may close during navigation. */ }
    }
    window.addEventListener('message', receive)
    return () => window.removeEventListener('message', receive)
  }, [])
  return active ? Object.entries(views).map(([id, root]) => createPortal(render(id), root, id)) : []
}
