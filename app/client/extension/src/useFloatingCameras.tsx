import { useEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { bridge } from './core.ts'

interface Person { id: string; name: string; speaking: boolean }
interface Layout { x: number; y: number; width: number; collapsed: boolean; customized: boolean }

export function useFloatingCameras(people: Person[], defaultWidth: number, render: (id: string) => ReactNode) {
  const owner = useRef(crypto.randomUUID())
  const [layouts, setLayouts] = useState<Record<string, Layout>>({})
  const [views, setViews] = useState<Record<string, HTMLElement>>({})
  const known = useRef(people); known.current = people
  const signature = JSON.stringify(people)
  useEffect(() => { void chrome.storage.local.get<{ cameraLayouts?: Record<string, Layout> }>('cameraLayouts').then(value => setLayouts(value.cameraLayouts ?? {})) }, [])
  useEffect(() => {
    bridge({ type: 'cameras', owner: owner.current, people, layouts, defaultWidth })
    const live = new Set(people.map(person => person.id))
    setViews(previous => Object.fromEntries(Object.entries(previous).filter(([id]) => live.has(id))))
  }, [signature, layouts, defaultWidth])
  useEffect(() => {
    const timer = setTimeout(() => { void chrome.storage.local.set({ cameraLayouts: layouts }) }, 500)
    return () => clearTimeout(timer)
  }, [layouts])
  useEffect(() => {
    const receive = (event: MessageEvent) => {
      const data = event.data
      if (!event.isTrusted) return
      if (data?.owner !== owner.current) return
      if (event.origin === window.location.origin && data.source === 'watchparty-camera-ready' && known.current.some(person => person.id === data.id)) {
        try {
          const view = event.source as Window
          const url = new URL(view.location.href)
          if (!url.pathname.endsWith('/camera.html') || url.searchParams.get('owner') !== owner.current || url.searchParams.get('id') !== data.id) return
          const root = view.document.getElementById('root')
          if (root) {
            setViews(previous => previous[data.id] === root ? previous : { ...previous, [data.id]: root })
            view.postMessage({ source: 'watchparty-camera-owner', owner: owner.current }, window.location.origin)
          }
        } catch { /* The camera frame may have closed during navigation. */ }
      } else if (event.source === window.parent && event.origin === 'https://www.youtube.com' && data.source === 'watchparty-youtube' && data.type === 'camera-layout') {
        const layout = data.layout
        if (typeof data.id === 'string' && layout && [layout.x, layout.y, layout.width].every(Number.isFinite)) setLayouts(previous => ({ ...previous, [data.id]: layout }))
      }
    }
    window.addEventListener('message', receive)
    return () => { window.removeEventListener('message', receive); bridge({ type: 'cameras', owner: owner.current, people: [] }) }
  }, [])
  return Object.entries(views).filter(([id]) => people.some(person => person.id === id)).map(([id, root]) => createPortal(render(id), root, id))
}
