import test from 'node:test'
import assert from 'node:assert/strict'
import {
  HOST_ONLY_SUFFIX,
  allPartyControls,
  closedWidget,
  entryModules,
  inviteUrl,
  isJoinCode,
  isSettledUpdate,
  normalizeJoinCode,
  partyWidgetView,
  profileTrayControls,
  updateOutcome,
  widgetNext,
  type IconControl,
  type PartyWidgetInput,
  type UpdateStatus,
} from './cornerWidgets.ts'
import type { PartySession } from '../types.ts'

// ── the open/close machine ──────────────────────────────────────────────────

test('the corner trigger toggles its surface', () => {
  const open = widgetNext(closedWidget, { type: 'toggle' })
  assert.equal(open.open, true)
  assert.equal(widgetNext(open, { type: 'toggle' }).open, false)
})

test('hover never opens or closes a surface', () => {
  // "No hover-only controls." An icon-only trigger is exactly where a hover
  // opener gets added by accident, and it would put sign-out behind a gesture
  // touch and keyboard users do not have.
  assert.deepEqual(widgetNext(closedWidget, { type: 'hover' }), closedWidget)
  const open = widgetNext(closedWidget, { type: 'open' })
  assert.deepEqual(widgetNext(open, { type: 'hover' }), open)
})

test('escape closes and hands focus back to the trigger', () => {
  const open = widgetNext(closedWidget, { type: 'open' })
  assert.deepEqual(widgetNext(open, { type: 'escape' }), { open: false, returnFocus: true })
})

test('pointing somewhere else closes without stealing focus back', () => {
  const open = widgetNext(closedWidget, { type: 'open' })
  assert.deepEqual(widgetNext(open, { type: 'pointerOutside' }), { open: false, returnFocus: false })
})

test('pointing inside the surface leaves it open', () => {
  const open = widgetNext(closedWidget, { type: 'open' })
  assert.deepEqual(widgetNext(open, { type: 'pointerInside' }), open)
})

test('taking an action closes the surface, unless its result shows there', () => {
  const open = widgetNext(closedWidget, { type: 'open' })
  assert.deepEqual(widgetNext(open, { type: 'action' }), { open: false, returnFocus: true })
  // The update check and the QR toggle answer inside the surface; closing over
  // the answer would mean nothing visibly happened.
  assert.deepEqual(widgetNext(open, { type: 'action', sticky: true }), open)
})

test('events on a closed surface do nothing', () => {
  for (const event of ['close', 'escape', 'pointerOutside', 'pointerInside'] as const) {
    assert.deepEqual(widgetNext(closedWidget, { type: event }), closedWidget, event)
  }
  assert.deepEqual(widgetNext(closedWidget, { type: 'action' }), closedWidget)
})

test('opening an already-open surface is not a reopen', () => {
  const open = widgetNext(closedWidget, { type: 'open' })
  assert.equal(widgetNext(open, { type: 'open' }), open)
})

// ── the profile tray ────────────────────────────────────────────────────────

test('the tray offers update, sound, settings and sign out, and nothing else', () => {
  assert.deepEqual(
    profileTrayControls('idle', true).map((control) => control.id),
    ['update', 'sound', 'settings', 'signOut'],
  )
})

test('the sound toggle reports its state in more than its tint', () => {
  const on = profileTrayControls('idle', true)[1]
  const off = profileTrayControls('idle', false)[1]
  assert.equal(on.pressed, true)
  assert.equal(off.pressed, false)
  assert.notEqual(on.icon, off.icon)
  assert.notEqual(on.label, off.label)
})

test('the update control says which of its five states it is in', () => {
  const statuses: UpdateStatus[] = ['idle', 'checking', 'current', 'available', 'failed']
  const labels = statuses.map((status) => profileTrayControls(status, true)[0].label)
  assert.equal(new Set(labels).size, statuses.length, `distinct labels, got ${labels.join(' / ')}`)
  // Mid-check the control is inert: a second fetch would only race the first.
  assert.equal(profileTrayControls('checking', true)[0].disabled, true)
  assert.equal(profileTrayControls('idle', true)[0].disabled, undefined)
})

test('only a finished check is worth forgetting when the tray closes', () => {
  assert.equal(isSettledUpdate('current'), true)
  assert.equal(isSettledUpdate('failed'), true)
  // An available update outlives the tray — it is still available next time.
  assert.equal(isSettledUpdate('available'), false)
  assert.equal(isSettledUpdate('checking'), false)
  assert.equal(isSettledUpdate('idle'), false)
})

// ── the update check ────────────────────────────────────────────────────────

test('the entry modules are read out of a served index.html', () => {
  const html = `<!doctype html><html><head>
    <link rel="modulepreload" href="/assets/vendor-9f1.js" />
  </head><body><div id="root"></div>
  <script type="module" crossorigin src="/assets/index-a1b2c3.js"></script>
  </body></html>`
  assert.deepEqual(entryModules(html), ['/assets/index-a1b2c3.js'])
})

test('a dev index.html names its unhashed entry but not the dev server', () => {
  // Vite's own client comes and goes on its own schedule; counting it would
  // report an update on every reload while developing.
  const html =
    '<body><script type="module" src="/@vite/client"></script>' +
    '<script type="module" src="/src/main.jsx"></script></body>'
  assert.deepEqual(entryModules(html), ['/src/main.jsx'])
})

test('a changed build hash is an available update', () => {
  assert.equal(updateOutcome(['/assets/index-a1.js'], ['/assets/index-a1.js']), 'current')
  assert.equal(updateOutcome(['/assets/index-a1.js'], ['/assets/index-b2.js']), 'available')
})

test('an unreadable answer is a failure, never "up to date"', () => {
  // Reporting unknown as current is the one wrong answer this control can give:
  // the user walks away believing they are on the newest build.
  assert.equal(updateOutcome([], []), 'failed')
  assert.equal(updateOutcome(['/assets/index-a1.js'], []), 'failed')
  assert.equal(updateOutcome([], ['/assets/index-a1.js']), 'failed')
})

// ── join codes ──────────────────────────────────────────────────────────────

test('a party code is eight uppercase hex characters', () => {
  assert.equal(isJoinCode('A1B2C3D4'), true)
  assert.equal(isJoinCode('a1b2c3d4'), true)
  assert.equal(isJoinCode('  a1b2c3d4 '), true)
  assert.equal(isJoinCode('A1B2C3D'), false)
  assert.equal(isJoinCode('A1B2C3D45'), false)
  assert.equal(isJoinCode('G1B2C3D4'), false)
  assert.equal(isJoinCode(''), false)
})

test('pasting the invite link joins the party it points at', () => {
  // The widget's own copy-link button is the control next to this field, so a
  // pasted link is the likely input rather than an exotic one.
  assert.equal(normalizeJoinCode('https://watch.example/party/a1b2c3d4'), 'A1B2C3D4')
  assert.equal(isJoinCode('https://watch.example/party/a1b2c3d4'), true)
  assert.equal(isJoinCode(inviteUrl('https://watch.example', 'A1B2C3D4')), true)
  // A trailing slash or query must not swallow the code.
  assert.equal(normalizeJoinCode('https://watch.example/party/A1B2C3D4/'), 'A1B2C3D4')
  assert.equal(normalizeJoinCode('https://watch.example/party/A1B2C3D4?ref=x'), 'A1B2C3D4')
})

test('the invite link is the party URL, whatever the origin ends with', () => {
  assert.equal(inviteUrl('https://watch.example', 'A1B2C3D4'), 'https://watch.example/party/A1B2C3D4')
  assert.equal(inviteUrl('https://watch.example/', 'A1B2C3D4'), 'https://watch.example/party/A1B2C3D4')
})

// ── the watch-party widget ──────────────────────────────────────────────────

const session = (patch: Partial<PartySession> = {}): PartySession => ({
  id: 'A1B2C3D4',
  hostId: 'host-1',
  hostName: 'Prince',
  stage: 'lobby',
  guests: [{ userId: 'guest-1', name: 'Ada' }],
  ...patch,
})

const idsOf = (input: PartyWidgetInput) => partyWidgetView(input).controls.map((c) => c.id)

test('outside a party the widget offers create and join', () => {
  const view = partyWidgetView({ session: null, role: null })
  assert.equal(view.mode, 'idle')
  assert.equal(view.live, false)
  assert.deepEqual(view.controls.map((c) => c.id), ['create', 'join'])
  assert.deepEqual(view.roster, [])
})

test('entering a code swaps the pair for submit and cancel', () => {
  const view = partyWidgetView({ session: null, role: null, joining: true })
  assert.equal(view.mode, 'joining')
  assert.deepEqual(view.controls.map((c) => c.id), ['joinSubmit', 'joinCancel'])
})

test('a request in flight disables the control that started it', () => {
  assert.equal(partyWidgetView({ session: null, role: null, busy: true }).controls[0].disabled, true)
  assert.equal(
    partyWidgetView({ session: null, role: null, joining: true, busy: true }).controls[0].disabled,
    true,
  )
  // Cancel stays live: a stuck request must not trap the user in the field.
  assert.equal(
    partyWidgetView({ session: null, role: null, joining: true, busy: true }).controls[1].disabled,
    undefined,
  )
})

test('in a party every participant gets QR, copy, roster and a way out', () => {
  assert.deepEqual(idsOf({ session: session(), role: 'guest' }), ['qr', 'copy', 'roster', 'leave'])
})

test('the host gets end, collaborative control and the shared browser instead', () => {
  const ids = idsOf({ session: session({ browserAvailable: true }), role: 'host' })
  assert.deepEqual(ids, ['qr', 'copy', 'roster', 'collaborative', 'browserStart', 'end'])
})

test('every host-only control is marked and says so', () => {
  const view = partyWidgetView({ session: session({ browserAvailable: true }), role: 'host' })
  const hostOnly = allPartyControls(view).filter((control) => control.hostOnly)
  assert.deepEqual(
    hostOnly.map((c) => c.id).sort(),
    ['collaborative', 'browserStart', 'end', 'promote:guest-1', 'kick:guest-1'].sort(),
  )
  for (const control of hostOnly) {
    assert.ok(
      control.label.endsWith(HOST_ONLY_SUFFIX),
      `${control.id} is host-only but its name does not say so: ${control.label}`,
    )
  }
})

test('a guest is never handed a host-only control', () => {
  const view = partyWidgetView({
    session: session({ browserAvailable: true, waiting: [{ userId: 'w1', name: 'Bo' }] }),
    role: 'guest',
  })
  assert.deepEqual(allPartyControls(view).filter((control) => control.hostOnly), [])
  assert.equal(view.alerts, 0)
})

test('the shared browser follows the server, not the role alone', () => {
  const host = 'host' as const
  // No browser in this deployment at all.
  assert.equal(idsOf({ session: session(), role: host }).includes('browserStart'), false)
  // Available and idle -> offer it.
  assert.equal(
    idsOf({ session: session({ browserAvailable: true }), role: host }).includes('browserStart'),
    true,
  )
  // Already on the stage -> the only thing left to do is close it.
  const running = idsOf({ session: session({ browserAvailable: true, stage: 'browser' }), role: host })
  assert.equal(running.includes('browserStart'), false)
  assert.equal(running.includes('browserStop'), true)
})

test('the collaborative toggle reports the state it is in', () => {
  const off = partyWidgetView({ session: session(), role: 'host' }).controls.find(
    (c) => c.id === 'collaborative',
  )
  const on = partyWidgetView({
    session: session({ collaborativeControl: true }),
    role: 'host',
  }).controls.find((c) => c.id === 'collaborative')
  assert.equal(off?.pressed, false)
  assert.equal(on?.pressed, true)
  assert.notEqual(off?.icon, on?.icon, 'the state must not be carried by colour alone')
})

test('the QR and roster toggles report their state', () => {
  const shown = partyWidgetView({ session: session(), role: 'guest', showQr: true, showRoster: true })
  const byId = new Map(shown.controls.map((c) => [c.id, c]))
  assert.equal(byId.get('qr')?.pressed, true)
  assert.equal(byId.get('roster')?.pressed, true)
  const hidden = partyWidgetView({ session: session(), role: 'guest' })
  assert.equal(hidden.controls.find((c) => c.id === 'qr')?.pressed, false)
})

test('copying the invite link changes the icon, not just the tooltip', () => {
  const before = partyWidgetView({ session: session(), role: 'guest' }).controls.find((c) => c.id === 'copy')
  const after = partyWidgetView({ session: session(), role: 'guest', copied: true }).controls.find(
    (c) => c.id === 'copy',
  )
  assert.notEqual(before?.icon, after?.icon)
  assert.notEqual(before?.label, after?.label)
})

test('the trigger names the room it is standing for', () => {
  assert.equal(partyWidgetView({ session: null, role: null }).triggerLabel, 'Watch party')
  const view = partyWidgetView({
    session: session({ guests: [{ userId: 'g1', name: 'Ada' }, { userId: 'g2', name: 'Bo' }] }),
    role: 'host',
  })
  assert.equal(view.triggerLabel, 'Watch party — 3 here')
})

test('the roster lists the host first and the queue last', () => {
  const view = partyWidgetView({
    session: session({ waiting: [{ userId: 'w1', name: 'Bo' }] }),
    role: 'host',
  })
  assert.deepEqual(view.roster.map((entry) => entry.userId), ['host-1', 'guest-1', 'w1'])
  assert.deepEqual(view.roster.map((entry) => entry.host), [true, false, false])
  assert.deepEqual(view.roster.map((entry) => entry.waiting), [false, false, true])
  assert.equal(view.alerts, 1)
  assert.deepEqual(
    view.roster[2].actions.map((action) => action.id),
    ['approve:w1', 'reject:w1'],
  )
})

test('a guest sees who is here and nothing to do about them', () => {
  const view = partyWidgetView({
    session: session({ waiting: [{ userId: 'w1', name: 'Bo' }] }),
    role: 'guest',
  })
  // The queue is the host's business; a guest is not shown a list it cannot act on.
  assert.deepEqual(view.roster.map((entry) => entry.userId), ['host-1', 'guest-1'])
  assert.deepEqual(view.roster.flatMap((entry) => entry.actions), [])
})

// ── the icon-only contract ──────────────────────────────────────────────────

/** Every state either widget can be in, so nothing hides from the sweep below. */
function everyControl(): IconControl[] {
  const statuses: UpdateStatus[] = ['idle', 'checking', 'current', 'available', 'failed']
  const trays = statuses.flatMap((status) =>
    [true, false].flatMap((soundOn) => profileTrayControls(status, soundOn)),
  )

  const roles = ['host', 'guest'] as const
  const sessions = [
    session(),
    session({ browserAvailable: true }),
    session({ browserAvailable: true, stage: 'browser' }),
    session({ collaborativeControl: true, waiting: [{ userId: 'w1', name: 'Bo' }] }),
  ]
  const live = roles.flatMap((role) =>
    sessions.flatMap((current) =>
      [false, true].flatMap((flag) =>
        allPartyControls(
          partyWidgetView({ session: current, role, showQr: flag, showRoster: flag, copied: flag }),
        ),
      ),
    ),
  )
  const idle = [false, true].flatMap((joining) =>
    [false, true].flatMap((busy) => partyWidgetView({ session: null, role: null, joining, busy }).controls),
  )

  return [...trays, ...live, ...idle]
}

test('every icon-only control carries an accessible name', () => {
  const controls = everyControl()
  // A sweep that found nothing would pass silently forever.
  assert.ok(controls.length > 30, `expected to sweep the whole widget surface, saw ${controls.length}`)
  const unnamed = controls.filter((control) => control.label.trim().length === 0).map((c) => c.id)
  assert.deepEqual(unnamed, [], 'these controls render an icon and nothing else, with no name to read')
})

test('an accessible name is never just the icon it draws', () => {
  // "Qr", "X", "Link" would technically be names and would tell a screen-reader
  // user nothing about what pressing the button does.
  for (const control of everyControl()) {
    assert.ok(
      control.label.length > control.icon.length,
      `${control.id} is named after its glyph rather than its action: ${control.label}`,
    )
  }
})

test('no two controls on one surface share a name', () => {
  const surfaces: IconControl[][] = [
    profileTrayControls('idle', true),
    profileTrayControls('current', false),
    allPartyControls(partyWidgetView({ session: session({ browserAvailable: true }), role: 'host' })),
    allPartyControls(
      partyWidgetView({ session: session({ browserAvailable: true, stage: 'browser' }), role: 'host' }),
    ),
    allPartyControls(partyWidgetView({ session: session(), role: 'guest' })),
    partyWidgetView({ session: null, role: null }).controls,
  ]
  for (const surface of surfaces) {
    const labels = surface.map((control) => control.label)
    assert.equal(
      new Set(labels).size,
      labels.length,
      `two controls with one name is two identical buttons: ${labels.join(' / ')}`,
    )
  }
})
