import {
  lazy,
  Suspense,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { Rnd } from 'react-rnd'
import { useParty } from '../context/PartyContext.tsx'
import { usePhone } from '../hooks/useIsMobile.ts'
import { AnIcon } from '../analog/icons.tsx'
import { navigate } from '../router.ts'
import { useLiveKit } from '../hooks/useLiveKit.ts'
import {
  PlayerPresentationContext,
  RoomConnectionContext,
} from './PlayerPresentation.tsx'
import RouteLoading from './RouteLoading.tsx'
import RoomFeedback from './RoomFeedback.tsx'
import './playerHost.css'

const WatchRoute = lazy(() => import('../pages/WatchRoute.tsx'))
const SavedWatch = lazy(() => import('../pages/SavedWatch.tsx'))
const isWatch = (path: string) =>
  path.startsWith('/party/') || path.startsWith('/saved/watch/')

/** A route change changes the movie's frame, never the lifetime of its video or room. */
export default function PlayerHost({
  path,
  renderLibrary,
}: {
  path: string
  renderLibrary: (path: string) => ReactNode
}) {
  const phone = usePhone()
  const headerHeight = phone ? 44 : 26
  const party = useParty()
  const connection = useLiveKit({
    partyId: party.session?.id,
    enabled: party.role === 'host' || party.role === 'guest',
  })
  const [retained, setRetained] = useState(isWatch(path) ? path : '')
  const [overlay, setOverlay] = useState<HTMLDivElement | null>(null)
  const [bounds, setBounds] = useState({
    width: innerWidth,
    height: innerHeight,
  })
  const [safe, setSafe] = useState({ top: 0, right: 0, bottom: 0, left: 0 })
  const [frame, setFrame] = useState({ x: innerWidth - 312, y: 12, width: 300 })
  const dragged = useRef(false)
  const boundsRef = useRef<HTMLDivElement>(null)
  const previousPath = useRef(path)
  const browsePath = useRef(path.startsWith('/saved/') ? '/saved' : '/movies')
  if (!isWatch(path) && path !== '/' && path !== '/library')
    browsePath.current = path
  // Adopt the new target before render, avoiding one frame with the old video.
  if (previousPath.current !== path) {
    previousPath.current = path
    if (isWatch(path)) setRetained(path)
  }
  const watchPath = isWatch(path) ? path : retained
  const saved = watchPath.startsWith('/saved/watch/')
  const hasMovie = saved || party.session?.stage === 'watching'
  const floating = !!watchPath && !isWatch(path) && hasMovie
  const showFrame = !!watchPath && (hasMovie || !party.session)
  const hadSession = useRef(false)
  useEffect(() => {
    if (party.session) hadSession.current = true
    else if (hadSession.current && !saved) {
      hadSession.current = false
      setRetained('')
      if (isWatch(window.location.pathname)) navigate(browsePath.current)
    }
  }, [party.session, saved])
  useEffect(() => {
    const element = boundsRef.current
    if (!element) return
    const resize = () => {
      const rect = element.getBoundingClientRect()
      const style = getComputedStyle(element)
      setSafe({
        top: parseFloat(style.paddingTop) || 0,
        right: parseFloat(style.paddingRight) || 0,
        bottom: parseFloat(style.paddingBottom) || 0,
        left: parseFloat(style.paddingLeft) || 0,
      })
      setBounds({ width: rect.width, height: rect.height })
    }
    resize()
    const observer = new ResizeObserver(resize)
    observer.observe(element)
    return () => observer.disconnect()
  }, [])
  const width = Math.min(
    frame.width,
    Math.max(112, bounds.width - safe.left - safe.right - 24),
    Math.max(
      112,
      ((bounds.height - safe.top - safe.bottom - headerHeight - 24) * 16) / 9
    )
  )
  const height = (width * 9) / 16 + headerHeight
  const x = Math.max(
    safe.left + 12,
    Math.min(frame.x, bounds.width - safe.right - width - 12)
  )
  const y = Math.max(
    safe.top + 12,
    Math.min(frame.y, bounds.height - safe.bottom - height - 12)
  )
  const minimize = () => {
    // Party creation replaces /party/new without a popstate event.
    if (isWatch(window.location.pathname)) setRetained(window.location.pathname)
    navigate(browsePath.current)
  }
  const expand = () => navigate(watchPath)
  const close = () => {
    if (party.session?.stage === 'watching') {
      party.backToLobby()
      minimize()
    } else {
      setRetained('')
      navigate(browsePath.current)
    }
  }
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (
        event.key !== 'Escape' ||
        !isWatch(window.location.pathname) ||
        party.chatOpen
      )
        return
      if (
        (event.target as HTMLElement)?.closest(
          'input,textarea,dialog,[role="dialog"],[role="menu"]'
        )
      )
        return
      if (!hasMovie) return
      event.preventDefault()
      minimize()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [hasMovie, party.chatOpen])

  return (
    <RoomConnectionContext.Provider value={connection}>
      <PlayerPresentationContext.Provider
        value={{ floating, overlay, minimize, expand, close }}
      >
        <div
          className="player-library"
          ref={(element) => {
            if (element) element.inert = showFrame && !floating
          }}
        >
          {renderLibrary(browsePath.current)}
        </div>
        <div className="player-host-bounds" ref={boundsRef}>
          <Rnd
            className={`player-host-frame${floating ? ' is-floating' : ''}${showFrame ? '' : ' is-idle'}`}
            size={
              floating ? { width, height } : { width: '100%', height: '100%' }
            }
            position={floating ? { x, y } : { x: 0, y: 0 }}
            disableDragging={!floating}
            dragHandleClassName="player-float-drag"
            cancel="button"
            bounds="parent"
            onDragStart={() => {
              dragged.current = false
            }}
            onDrag={() => {
              dragged.current = true
            }}
            enableResizing={floating ? { bottomRight: true } : false}
            minWidth={112}
            lockAspectRatio={16 / 9}
            lockAspectRatioExtraHeight={headerHeight}
            onDragStop={(_, data) =>
              setFrame((f) => ({
                ...f,
                x:
                  data.x + width / 2 < bounds.width / 2
                    ? 12
                    : bounds.width - width - 12,
                y:
                  data.y + height / 2 < bounds.height / 2
                    ? 12
                    : bounds.height - height - 12,
              }))
            }
            onResizeStop={(_, __, element, ___, position) =>
              setFrame({ ...position, width: element.offsetWidth })
            }
          >
            <div
              className="player-float-header player-float-drag"
              style={{
                display: floating ? 'flex' : 'none',
                height: headerHeight,
              }}
            >
              <button aria-label="Expand movie" onClick={expand}>
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.7"
                >
                  <path d="M14 3h7v7m0-7-8 8M3 14v7h7m-7 0 8-8" />
                </svg>
              </button>
              {(saved ||
                party.role === 'host' ||
                party.session?.collaborativeControl) && (
                <button aria-label="Stop watching" onClick={close}>
                  <AnIcon name="x" size={18} />
                </button>
              )}
            </div>
            <div
              className="player-host-content"
              style={{
                height: floating ? `calc(100% - ${headerHeight}px)` : '100%',
              }}
            >
              <Suspense fallback={<RouteLoading />}>
                {watchPath &&
                  (saved ? (
                    <SavedWatch
                      mediaKey={decodeURIComponent(
                        watchPath.slice('/saved/watch/'.length)
                      )}
                    />
                  ) : (
                    <WatchRoute path={watchPath} />
                  ))}
              </Suspense>
              {floating && (
                <div
                  className="player-float-surface player-float-drag"
                  role="button"
                  tabIndex={0}
                  aria-label="Expand movie picture"
                  onClick={() => {
                    if (!dragged.current) expand()
                  }}
                  onKeyDown={(event) => {
                    if (event.key === 'Enter' || event.key === ' ') {
                      event.preventDefault()
                      expand()
                    }
                  }}
                />
              )}
            </div>
          </Rnd>
        </div>
        <div className="player-room-overlay" ref={setOverlay}>
          {party.session && <RoomFeedback key={party.session.id} />}
        </div>
      </PlayerPresentationContext.Provider>
    </RoomConnectionContext.Provider>
  )
}
