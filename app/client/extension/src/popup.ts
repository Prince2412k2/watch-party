import { localGet, observeStorage, rpc } from './platform.ts'
import { DEFAULT_SERVER, type Connection, type Session, type Setup } from './core.ts'

interface Status { configured: boolean; connected: boolean; isAdmin: boolean; active?: boolean; authError?: string; setup?: Setup | null; connection?: Connection; party?: Session | null }
const element = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T
const input = (id: string) => element<HTMLInputElement>(id)
let current: Status = { configured: false, connected: false, isAdmin: false }
let busy = false
const format = (code: string) => code.replace(/(.{4})(?=.)/g, '$1-')
function error(message = '') { element('error').textContent = message; element('error').hidden = !message }
function settings(open: boolean) {
  element('settings-view').hidden = !open
  element('home').hidden = open
  element('settings-toggle').setAttribute('aria-expanded', String(open))
  if (open) input('server').focus()
}
function render() {
  const label = current.connected ? 'Connected' : current.configured ? 'Disconnected' : 'Not configured'
  element('connection-label').textContent = label
  element('connection-status').dataset.connected = String(current.connected)
  element('create').hidden = !current.isAdmin
  element<HTMLButtonElement>('create').disabled = busy || !current.connected
  element('join-form').hidden = false
  element<HTMLButtonElement>('join').disabled = busy || !current.connected
  element('auth-status').textContent = current.isAdmin ? 'Admin' : 'Guest'
  element('sign-out').hidden = !current.connection
  const code = current.party?.inviteCode
  element('party-code').hidden = !code
  element('disconnect').hidden = !current.active
  element<HTMLButtonElement>('disconnect').disabled = busy
  element('code-value').textContent = code ? format(code) : ''
}
observeStorage((changes, area) => {
  if (area !== 'local') return
  if (changes.activeParty) {
    const active = changes.activeParty.newValue as { id: string } | null
    current.active = !!active
    if (!active || current.party?.id !== active.id) current.party = null
  }
  if (changes.connection && !changes.connection.newValue) { current.connection = undefined; current.isAdmin = false }
  render()
})
async function refresh() {
  current = await rpc<Status>('status', {}, 11_000)
  render()
  if (current.authError) error(current.authError)
}
async function action(button: HTMLButtonElement, label: string, operation: () => Promise<void>) {
  if (busy) return
  busy = true; button.disabled = true
  render()
  const text = button.textContent
  button.textContent = label
  error()
  try { await operation() }
  catch (cause) { error(cause instanceof Error ? cause.message : 'Request failed.') }
  finally { busy = false; button.disabled = false; button.textContent = text; render() }
}
element('settings-toggle').addEventListener('click', () => { error(); settings(element('settings-view').hidden === true) })
element('cancel').addEventListener('click', () => settings(false))
element('settings-form').addEventListener('submit', event => {
  event.preventDefault()
  void action(element<HTMLButtonElement>('save'), 'Validating…', async () => {
    const server = new URL(input('server').value.trim()).origin
    if (!await chrome.permissions.request({ origins: [`${server}/*`] })) throw new Error('Server access denied.')
    const saved = await rpc<{ setup: Setup; connection: Connection | null; isAdmin: boolean }>('save-settings', { server: input('server').value, name: input('name').value, username: input('username').value, password: input('password').value }, 25_000)
    input('password').value = ''
    current = { configured: true, connected: true, setup: saved.setup, connection: saved.connection ?? undefined, isAdmin: saved.isAdmin }
    render()
    settings(false)
  })
})
element('create').addEventListener('click', () => void action(element<HTMLButtonElement>('create'), 'Creating…', async () => {
  const result = await rpc<{ code: string; partyId: string }>('create-party', {}, 30_000)
  await refresh()
  element('party-code').hidden = false
  element('code-value').textContent = format(result.code)
}))
element('join-form').addEventListener('submit', event => {
  event.preventDefault()
  void action(element<HTMLButtonElement>('join'), 'Joining…', async () => {
    await rpc('join-party', { code: input('invite').value }, 25_000)
    await refresh()
  })
})
element('copy').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(element('code-value').textContent || ''); element('copy').textContent = 'Copied'; setTimeout(() => { element('copy').textContent = 'Copy' }, 1500) }
  catch { error('Could not copy code.') }
})
element('sign-out').addEventListener('click', () => void action(element<HTMLButtonElement>('sign-out'), 'Signing out…', async () => {
  await rpc('sign-out', {}, 25_000)
  input('username').value = ''; input('password').value = ''
  await refresh()
}))
element('disconnect').addEventListener('click', () => void action(element<HTMLButtonElement>('disconnect'), 'Disconnecting…', async () => {
  await rpc('disconnect-party', {}, 25_000)
  current.party = null; current.active = false
  render()
  await refresh()
}))
void (async () => {
  try {
    const stored = await localGet<{ setup?: Setup; connection?: Connection }>(['setup', 'connection'])
    input('server').value = stored.setup?.server ?? stored.connection?.server ?? DEFAULT_SERVER
    input('name').value = stored.setup?.name ?? stored.connection?.user.name ?? ''
    input('username').value = stored.setup?.username ?? ''
    current.configured = !!input('server').value
    render()
    if (location.hash === '#settings') settings(true)
    await refresh()
  } catch (cause) { element('connection-label').textContent = 'Disconnected'; error(cause instanceof Error ? cause.message : 'Could not load settings.') }
})()
