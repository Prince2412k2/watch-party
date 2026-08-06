// The upper-right profile control.
//
// "Profile is a compact control in the upper-right corner. Activating it
// expands an inline toolbox rather than opening a separate dashboard."
//
// So: a 34px disc with a face on it and no name beside it, which slides a tray
// of icon buttons out to its left. Everything it used to say in words (who you
// are, the build number, a three-way theme switch, a labelled row per action) is
// either gone or carried by the accessible name of a button, which is what
// "icon only" costs.
//
// The tray is DOM-ordered AFTER the trigger and laid out with row-reverse, so
// it appears to the left while Tab still walks trigger -> update -> sound ->
// settings -> sign out. Reversing the DOM instead would look identical and put
// the whole tray before the control that opens it.

import { useEffect, useReducer, useRef, useState } from 'react'
import Avatar from '../components/Avatar.tsx'
import type { AvatarConfig } from '../lib/avatar.ts'
import { AnIcon, AnIconButton } from './icons.tsx'
import { cueEnabled, setCueEnabled } from './cue.ts'
import {
  closedWidget,
  entryModules,
  isAppModule,
  isSettledUpdate,
  profileTrayControls,
  updateOutcome,
  widgetNext,
  type UpdateStatus,
} from './cornerWidgets.ts'

const TRAY_ID = 'an-profile-tray'

/** The build's own module scripts, as this document loaded them. */
function loadedModules(): string[] {
  return Array.from(document.querySelectorAll<HTMLScriptElement>('script[type="module"][src]'))
    .map((script) => script.getAttribute('src') ?? '')
    .filter(isAppModule)
}

export interface AnalogProfileTrayProps {
  userId?: string
  name?: string
  avatar?: AvatarConfig | null
  onSettings: () => void
  onSignOut: () => void
}

export function AnalogProfileTray({ userId, name, avatar, onSettings, onSignOut }: AnalogProfileTrayProps) {
  const [tray, dispatch] = useReducer(widgetNext, closedWidget)
  const [status, setStatus] = useState<UpdateStatus>('idle')
  // The shelf's detent cue has no other switch in the client, and the reference
  // asks for one — see profileTrayControls.
  const [sound, setSound] = useState(cueEnabled)
  const rootRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    if (!tray.open) return
    const onPointerDown = (event: PointerEvent) => {
      dispatch({ type: rootRef.current?.contains(event.target as Node) ? 'pointerInside' : 'pointerOutside' })
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') dispatch({ type: 'escape' })
    }
    document.addEventListener('pointerdown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [tray.open])

  // Escape from inside the tray must not drop focus onto the document body —
  // the machine says when focus is owed back, and this pays it.
  useEffect(() => {
    if (!tray.open && tray.returnFocus) triggerRef.current?.focus()
  }, [tray])

  // A finished answer is about the moment it was given, so it does not survive
  // into the next time the tray is opened. An *available* update does.
  useEffect(() => {
    if (!tray.open && isSettledUpdate(status)) setStatus('idle')
  }, [tray.open, status])

  async function checkForUpdates() {
    // Once a newer build is known to exist, the button becomes the way to take
    // it: reloading is what actually swaps the running bundle.
    if (status === 'available') {
      window.location.reload()
      return
    }
    setStatus('checking')
    try {
      const response = await fetch('/index.html', { cache: 'no-store', credentials: 'same-origin' })
      if (!response.ok) throw new Error(`index.html responded ${response.status}`)
      setStatus(updateOutcome(loadedModules(), entryModules(await response.text())))
    } catch {
      setStatus('failed')
    }
  }

  function run(id: string) {
    // Sticky: both of these answer on the button that was pressed, so closing
    // over the answer would look like nothing happened.
    if (id === 'update') {
      dispatch({ type: 'action', sticky: true })
      void checkForUpdates()
      return
    }
    if (id === 'sound') {
      dispatch({ type: 'action', sticky: true })
      setCueEnabled(!sound)
      setSound(!sound)
      return
    }
    dispatch({ type: 'action' })
    if (id === 'settings') onSettings()
    if (id === 'signOut') onSignOut()
  }

  return (
    <div className="an-corner" data-corner="top-right" ref={rootRef}>
      <button
        ref={triggerRef}
        type="button"
        className="an-corner-trigger"
        aria-label={name ? `Profile — ${name}` : 'Profile'}
        aria-expanded={tray.open}
        aria-controls={TRAY_ID}
        aria-busy={status === 'checking'}
        onClick={() => dispatch({ type: 'toggle' })}
      >
        {userId ? (
          <Avatar userId={userId} name={name} config={avatar} size={30} circle />
        ) : (
          <AnIcon name="user" size={16} />
        )}
      </button>

      {tray.open ? (
        <div className="an-tray" id={TRAY_ID} role="group" aria-label="Profile actions">
          {profileTrayControls(status, sound).map((control) => (
            <AnIconButton key={control.id} control={control} onPress={() => run(control.id)} />
          ))}
        </div>
      ) : null}
    </div>
  )
}
