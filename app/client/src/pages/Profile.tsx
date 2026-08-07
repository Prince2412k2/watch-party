import { useEffect, useMemo, useState } from 'react'
import type { ReactNode } from 'react'
import { createPartPreview, getPartsForSlot } from '@humation/core'
import type { PartOption } from '@humation/core'
import { useAuth } from '../context/AuthContext.tsx'
import { useMediaQuery } from '../hooks/useIsMobile.ts'
import Avatar from '../components/Avatar.tsx'
import { assets, effectiveConfig, PALETTES } from '../lib/avatar.ts'
import type { AvatarConfig } from '../lib/avatar.ts'
import { errorMessage, isUserProfile } from '../guards.ts'
import { apiJson, stringField } from '../types/guards.ts'

// Matches the server's limit. Enforced here so the field stops accepting rather
// than letting a save fail for a reason the user can't see.
const NAME_MAX = 32

// Slot groups in the order the asset set wants them presented, so an asset-set
// update reorders or adds sections without a change here.
const GROUPS = [...assets.uiGroups].sort((a, b) => a.order - b.order)

// Wide enough for a column of options beside the preview. Below it the preview
// sits above the options instead — a sticky portrait would eat a phone screen.
const TWO_COLUMN = '(min-width: 900px)'

function hexInput(value: string | undefined, fallback: string) {
  const hex = value ?? fallback
  return hex.startsWith('#') ? hex : `#${hex}`
}

function Section({ label, children }: { label: string; children: ReactNode }) {
  return (
    <section style={{ display: 'flex', flexDirection: 'column', gap: 10, minWidth: 0 }}>
      <h2 style={{
        margin: 0, fontSize: 11, fontWeight: 700, letterSpacing: '.1em',
        textTransform: 'uppercase', color: 'var(--text3)',
      }}>{label}</h2>
      {children}
    </section>
  )
}

/**
 * A horizontally scrolling strip of choices. Every picker is one of these, so a
 * slot with 43 parts and a slot with 3 behave the same.
 *
 * `minWidth: 0` is what keeps it honest: a flex child defaults to min-width
 * auto, which lets it size to its content and push the page wider instead of
 * scrolling inside itself. `contain` stops a sideways swipe that runs off the
 * end of the strip from chaining to whatever scrolls behind it.
 */
function Strip({ children }: { children: ReactNode }) {
  return (
    <div style={{
      display: 'flex', gap: 8, overflowX: 'auto', paddingBottom: 4,
      minWidth: 0, overscrollBehaviorX: 'contain', scrollbarWidth: 'thin',
    }}>{children}</div>
  )
}

function Choice({ selected, onClick, label, children }: {
  selected: boolean; onClick: () => void; label: string; children: ReactNode
}) {
  return (
    <button
      type="button" onClick={onClick} title={label} aria-label={label} aria-pressed={selected}
      style={{
        width: 60, height: 60, flex: '0 0 auto', padding: 0, cursor: 'pointer',
        borderRadius: 12, overflow: 'hidden',
        background: 'var(--glass2)',
        // Selection is a brighter ring, not a colour fill — the same way the
        // rest of the app marks an active control.
        border: `1px solid ${selected ? 'var(--text)' : 'var(--stroke)'}`,
        boxShadow: selected ? 'inset 0 0 0 1px var(--text)' : 'none',
        display: 'grid', placeItems: 'center',
      }}
    >{children}</button>
  )
}

export default function Profile() {
  const { user, applyProfile } = useAuth()
  const userId = user?.userId ?? ''
  const twoColumn = useMediaQuery(TWO_COLUMN)

  const [loaded, setLoaded] = useState(false)
  const [accountName, setAccountName] = useState('')
  const [displayName, setDisplayName] = useState('')
  // null means "no customisation saved" — draw the derived default. The first
  // edit materialises the full config so every slot has something to show.
  const [avatar, setAvatar] = useState<AvatarConfig | null>(null)
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState<{ ok: boolean; text: string } | null>(null)

  useEffect(() => {
    if (!user) return
    let active = true
    fetch('/api/profile', { credentials: 'include' })
      .then(async response => {
        const value = await apiJson(response)
        if (!response.ok) throw new Error(errorMessage(value, 'Could not load your profile'))
        return value
      })
      .then(value => {
        if (!active) return
        setAccountName(stringField(value, 'accountName') ?? user.name ?? '')
        if (isUserProfile(value)) {
          setDisplayName(value.displayName ?? '')
          setAvatar(value.avatar)
        }
        setLoaded(true)
      })
      .catch(reason => {
        if (!active) return
        setStatus({ ok: false, text: reason instanceof Error ? reason.message : 'Could not load your profile' })
        setLoaded(true)
      })
    return () => { active = false }
  }, [user?.userId])

  const resolved = useMemo(() => effectiveConfig(userId, avatar), [userId, avatar])

  // Part thumbnails are drawn in the colours currently selected, so picking hair
  // shows *your* hair colour. Rebuilt only when the colours change — not on
  // every part change, and not on every render.
  const previews = useMemo(() => {
    const byPart = new Map<string, string>()
    for (const group of GROUPS) {
      for (const slot of group.selectionSlots) {
        for (const part of getPartsForSlot(assets, slot)) {
          byPart.set(part.id, createPartPreview(assets, part, {
            colors: resolved.colors,
            background: 'transparent',
          }).toDataUri())
        }
      }
    }
    return byPart
  }, [JSON.stringify(resolved.colors)])

  function editConfig(change: (base: AvatarConfig) => AvatarConfig) {
    setStatus(null)
    // Edits are applied to the resolved config, not to the sparse saved one:
    // changing one slot must not drop the derived values of the others.
    setAvatar(previous => change(effectiveConfig(userId, previous)))
  }

  const selectPart = (slot: string, partId: string) =>
    editConfig(base => ({ ...base, selections: { ...base.selections, [slot]: partId } }))
  const selectColor = (slot: string, hex: string) =>
    editConfig(base => ({ ...base, colors: { ...base.colors, [slot]: hex.replace('#', '').toUpperCase() } }))
  const selectBackground = (value: string) =>
    editConfig(base => ({ ...base, background: value === 'transparent' ? value : value.replace('#', '').toUpperCase() }))

  async function save() {
    setSaving(true)
    setStatus(null)
    try {
      const response = await fetch('/api/profile', {
        method: 'PUT',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ displayName: displayName.trim() || null, avatar }),
      })
      const value = await apiJson(response)
      if (!response.ok) throw new Error(errorMessage(value, 'Could not save your profile'))
      if (isUserProfile(value)) {
        setDisplayName(value.displayName ?? '')
        setAvatar(value.avatar)
        // Every surface showing *me* reads this, so my own account control
        // redraws immediately.
        applyProfile(value)
      }
      setStatus({ ok: true, text: 'Saved' })
    } catch (reason) {
      setStatus({ ok: false, text: reason instanceof Error ? reason.message : 'Could not save your profile' })
    } finally {
      setSaving(false)
    }
  }

  if (!user) return null // the router sends unauthenticated visitors to /login

  const shownName = displayName.trim() || accountName

  return (
    <div style={{
      position: 'fixed', inset: 0, overflowY: 'auto',
      // Nothing here may scroll sideways: the options scroll inside their own
      // strips, never by dragging the page.
      overflowX: 'clip',
      background: 'var(--bg)', color: 'var(--text)',
      fontFamily: 'var(--font-sans)',
    }}>
      <header style={{
        position: 'sticky', top: 0, zIndex: 3,
        display: 'flex', alignItems: 'center', gap: 12,
        background: 'var(--bg)', borderBottom: '1px solid var(--stroke)',
        padding: `calc(var(--sa-t, 0px) + 12px) calc(var(--sa-r, 0px) + 16px) 12px calc(var(--sa-l, 0px) + 16px)`,
      }}>
        <button
          type="button" onClick={() => window.history.back()} aria-label="Back"
          style={{
            width: 44, height: 44, flex: '0 0 auto', borderRadius: 999, cursor: 'pointer',
            border: '1px solid var(--stroke)', background: 'var(--glass)', color: 'var(--text)',
            display: 'grid', placeItems: 'center',
          }}
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m15 18-6-6 6-6" /></svg>
        </button>
        <h1 style={{ flex: 1, minWidth: 0, margin: 0, fontSize: 17, fontWeight: 700 }}>Profile</h1>
        <button
          type="button" onClick={save} disabled={saving || !loaded}
          style={{
            height: 40, padding: '0 18px', borderRadius: 999, cursor: saving ? 'default' : 'pointer',
            border: 'none', background: 'var(--accent)', color: 'var(--on-accent)',
            fontSize: 13.5, fontWeight: 700, opacity: saving || !loaded ? .6 : 1,
          }}
        >{saving ? 'Saving…' : 'Save'}</button>
      </header>

      <div style={{
        display: 'flex', flexDirection: twoColumn ? 'row' : 'column',
        alignItems: twoColumn ? 'flex-start' : 'stretch',
        gap: twoColumn ? 34 : 22,
        maxWidth: 1140, margin: '0 auto', minWidth: 0,
        padding: `22px calc(var(--sa-r, 0px) + 16px) calc(var(--sa-b, 0px) + 40px) calc(var(--sa-l, 0px) + 16px)`,
      }}>
        {/* Preview. On a wide window it stays put while the options scroll past
            it, so you can always see what you're changing. */}
        <aside style={{
          flex: '0 0 auto',
          alignSelf: twoColumn ? 'flex-start' : 'center',
          ...(twoColumn ? { position: 'sticky', top: 'calc(var(--sa-t, 0px) + 92px)' } : null),
          display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12,
        }}>
          <Avatar
            userId={userId}
            name={shownName}
            config={avatar}
            size={twoColumn ? 300 : 132}
            circle
            style={{ border: '1px solid var(--stroke2)' }}
          />
          {twoColumn ? (
            <span style={{
              maxWidth: 300, fontSize: 14, fontWeight: 600, color: 'var(--text2)',
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            }}>{shownName}</span>
          ) : null}
        </aside>

        {/* Everything you can change, scrolling past the preview. */}
        <div style={{ flex: '1 1 auto', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 26 }}>
          <Section label="Display name">
            <input
              id="display-name"
              value={displayName}
              maxLength={NAME_MAX}
              placeholder={accountName}
              onChange={event => { setDisplayName(event.target.value); setStatus(null) }}
              style={{
                height: 44, padding: '0 13px', borderRadius: 10, width: '100%',
                border: '1px solid var(--stroke)', background: 'var(--glass2)', color: 'var(--text)',
                fontSize: 14, fontFamily: 'inherit', minWidth: 0, boxSizing: 'border-box',
              }}
            />
            <small style={{ fontSize: 12, color: 'var(--text2)' }}>
              {displayName.trim()
                ? `Everyone sees you as ${displayName.trim()}.`
                : `Leave this empty to stay ${accountName || 'your account name'}.`}
            </small>
          </Section>

          {/* Parts — one strip per slot the asset set defines */}
          {GROUPS.map(group => (
            <Section key={group.id} label={group.label}>
              {group.selectionSlots.map(slot => (
                <Strip key={slot}>
                  {getPartsForSlot(assets, slot).map((part: PartOption) => (
                    <Choice
                      key={part.id}
                      selected={resolved.selections?.[slot] === part.id}
                      onClick={() => selectPart(slot, part.id)}
                      label={part.name ?? part.id}
                    >
                      <img src={previews.get(part.id)} alt="" width={52} height={52} style={{ display: 'block' }} />
                    </Choice>
                  ))}
                </Strip>
              ))}
            </Section>
          ))}

          {/* Colours — one row per colour slot, including the background plate */}
          {assets.colors.map(slot => {
            const isBackground = slot.id === 'background'
            const current = isBackground
              ? resolved.background ?? assets.defaults.background
              : resolved.colors?.[slot.id] ?? slot.default
            const swatches = PALETTES[slot.id] ?? []
            return (
              <Section key={slot.id} label={slot.label}>
                <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', minWidth: 0 }}>
                  {swatches.map(hex => (
                    <button
                      key={hex} type="button" aria-label={`${slot.label} ${hex}`} title={`#${hex}`}
                      aria-pressed={current.toUpperCase() === hex}
                      onClick={() => (isBackground ? selectBackground(hex) : selectColor(slot.id, hex))}
                      style={{
                        width: 36, height: 36, borderRadius: 999, cursor: 'pointer', padding: 0, flex: '0 0 auto',
                        background: `#${hex}`,
                        border: `2px solid ${current.toUpperCase() === hex ? 'var(--text)' : 'var(--stroke2)'}`,
                      }}
                    />
                  ))}
                  {slot.allowTransparent ? (
                    <button
                      type="button" onClick={() => selectBackground('transparent')}
                      aria-pressed={current === 'transparent'}
                      style={{
                        height: 36, padding: '0 12px', borderRadius: 999, cursor: 'pointer', flex: '0 0 auto',
                        background: 'transparent', color: 'var(--text2)', fontSize: 12, fontWeight: 600,
                        border: `1px solid ${current === 'transparent' ? 'var(--text)' : 'var(--stroke2)'}`,
                      }}
                    >None</button>
                  ) : null}
                  {/* Anything the swatches don't cover. */}
                  <input
                    type="color"
                    aria-label={`${slot.label} colour`}
                    value={hexInput(current === 'transparent' ? undefined : current, slot.default)}
                    onChange={event => (isBackground ? selectBackground(event.target.value) : selectColor(slot.id, event.target.value))}
                    style={{
                      width: 36, height: 36, padding: 0, cursor: 'pointer', flex: '0 0 auto',
                      background: 'transparent', border: '1px solid var(--stroke2)', borderRadius: 999,
                    }}
                  />
                </div>
              </Section>
            )
          })}

          <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap', borderTop: '1px solid var(--stroke)', paddingTop: 18 }}>
            <button
              type="button"
              onClick={() => { setAvatar(null); setStatus(null) }}
              style={{
                height: 40, padding: '0 16px', borderRadius: 999, cursor: 'pointer',
                border: '1px solid var(--stroke2)', background: 'transparent', color: 'var(--text2)',
                fontSize: 13, fontWeight: 600,
              }}
            >Reset to my default avatar</button>
            {status ? (
              <span role="status" style={{ fontSize: 13, fontWeight: 600, color: status.ok ? 'var(--green)' : 'var(--red)' }}>
                {status.text}
              </span>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  )
}
