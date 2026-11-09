import { io, type Socket } from 'socket.io-client'
import type { Connection, Setup } from './core.ts'
import { deadline } from './platform.ts'

type ActiveParty = { id: string; server: string; userId: string; tabId: number; canControl: boolean; inviteCode?: string }
const ports = new Set<chrome.runtime.Port>()
const ready = new Map<string, { tabId: number; resolve: () => void }>()
const trusted = (sender: chrome.runtime.MessageSender) => sender.id === chrome.runtime.id && sender.url?.startsWith(chrome.runtime.getURL('/')) === true
void chrome.storage.local.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' })
chrome.runtime.onInstalled.addListener(() => { void chrome.storage.local.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' }) })

chrome.runtime.onConnect.addListener(port => {
  if (port.name !== 'watchparty-state' || !port.sender || !trusted(port.sender)) { port.disconnect(); return }
  ports.add(port)
  port.onDisconnect.addListener(() => ports.delete(port))
  port.onMessage.addListener(() => {})
})
chrome.storage.onChanged.addListener((changes, area) => {
  for (const port of ports) { try { port.postMessage({ type: 'storage', changes, area }) } catch { ports.delete(port) } }
})

function origin(value: unknown) {
  const url = new URL(typeof value === 'string' ? value.trim() : '')
  if (url.username || url.password || (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname)))) throw new Error('Enter an HTTPS server URL.')
  return url.origin
}
async function api(server: string, path: string, options: { body?: unknown; token?: string; method?: string } = {}) {
  let response: Response
  try {
    response = await fetch(`${server}${path}`, { method: options.method ?? (options.body ? 'POST' : 'GET'), credentials: 'omit', signal: AbortSignal.timeout(8000), headers: { ...(options.body ? { 'Content-Type': 'application/json' } : {}), ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}) }, ...(options.body ? { body: JSON.stringify(options.body) } : {}) })
  } catch { throw new Error('Server unreachable.') }
  let data
  try { data = await response.json() } catch { throw new Error('Server needs the latest extension update.') }
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status}).`)
  return data
}
async function status() {
  const stored = await chrome.storage.local.get<{ setup?: Setup; connection?: Connection; activeParty?: ActiveParty }>(['setup', 'connection', 'activeParty'])
  const server = stored.setup?.server ?? stored.connection?.server
  if (!server) return { configured: false, connected: false, isAdmin: false, setup: stored.setup ?? null }
  const health = await api(server, '/api/extension/health')
  if (!health.ok) throw new Error('Not a Watch Party server.')
  if (!stored.connection?.token || stored.connection.server !== server) return { configured: true, connected: true, isAdmin: false, setup: stored.setup }
  try {
    const me = await api(server, '/api/extension/me', { token: stored.connection.token })
    const latest = await chrome.storage.local.get<{ connection?: Connection }>('connection')
    if (latest.connection?.token !== stored.connection.token) return status()
    const connection = { ...stored.connection, user: me.user, expiresAt: me.expiresAt }
    if (JSON.stringify(connection) !== JSON.stringify(stored.connection)) await chrome.storage.local.set({ connection })
    return { configured: true, connected: true, isAdmin: me.user.isAdmin, setup: stored.setup, connection, party: me.session }
  } catch (error) {
    return { configured: true, connected: true, isAdmin: false, setup: stored.setup, authError: error instanceof Error ? error.message : 'Sign in again.' }
  }
}
async function saveSettings(message: Record<string, any>) {
  const server = origin(message.server)
  const name = typeof message.name === 'string' ? message.name.trim() : ''
  const username = typeof message.username === 'string' ? message.username.trim() : ''
  const password = typeof message.password === 'string' ? message.password : ''
  if (name.length > 32 || /[\r\n]/.test(name)) throw new Error('Name must be one line, up to 32 characters.')
  if (password && !username) throw new Error('Enter a username.')
  const health = await api(server, '/api/extension/health')
  if (!health.ok) throw new Error('Not a Watch Party server.')
  const previous = await chrome.storage.local.get<{ setup?: Setup; connection?: Connection }>(['setup', 'connection'])
  let connection: Connection | null = null
  if (username) {
    if (password) {
      const login = await api(server, '/api/extension/login', { body: { username, password, name } })
      if (!login.user?.isAdmin || !login.token) throw new Error('Admin login failed.')
      connection = { server, token: login.token, user: login.user, expiresAt: login.expiresAt }
    } else {
      if (previous.setup?.server !== server || previous.setup.username !== username || !previous.connection?.token) throw new Error('Enter the password to validate this login.')
      const me = await api(server, '/api/extension/me', { token: previous.connection.token })
      if (!me.user.isAdmin) throw new Error('Admin login required.')
      connection = { ...previous.connection, user: me.user, expiresAt: me.expiresAt }
    }
  } else if (previous.connection?.server === server && !previous.connection.user.isAdmin) {
    const me = await api(server, '/api/extension/me', { token: previous.connection.token }).catch(() => null)
    if (me) connection = { ...previous.connection, user: me.user, expiresAt: me.expiresAt }
  }
  if (connection) {
    const me = await api(server, '/api/extension/me', { token: connection.token })
    if (username && !me.user?.isAdmin) throw new Error('Admin login failed.')
    connection = { ...connection, user: me.user, expiresAt: me.expiresAt }
  }
  if (connection && name && connection.user.name !== name) {
    const me = await api(server, '/api/extension/me', { method: 'PATCH', token: connection.token, body: { name } })
    connection = { ...connection, user: me.user }
  }
  // Nothing is persisted until the server and optional credentials validate.
  const setup = { server, name, username }
  await chrome.storage.local.set({ setup, connection })
  return { setup, connection, connected: true, isAdmin: !!connection?.user.isAdmin }
}

async function connect(connection: Connection) {
  const socket = io(connection.server, { transports: ['websocket'], auth: { extensionToken: connection.token }, reconnection: false, forceNew: true, autoConnect: false })
  const opened = new Promise<void>((resolve, reject) => { socket.once('connect', resolve); socket.once('connect_error', reject) })
  socket.connect()
  try { await deadline(opened, 8000, 'Connection timed out.'); return socket }
  catch (error) { socket.disconnect(); throw error }
}
const request = (socket: Socket, event: string, payload: unknown = {}): Promise<Record<string, any>> => new Promise((resolve, reject) => {
  socket.timeout(8000).emit(event, payload, (error: Error | null, value: Record<string, any> = {}) => error ? reject(new Error('Server did not respond.')) : value.error ? reject(new Error(value.error)) : resolve(value))
})
async function targetTab() {
  const [active] = await chrome.tabs.query({ active: true, currentWindow: true })
  if (active?.id && active.url?.startsWith('https://www.youtube.com/')) return active
  if (active?.id) {
    const page = await chrome.tabs.sendMessage(active.id, { type: 'watchparty-page' }).catch(() => null)
    if (page?.url?.startsWith('https://www.youtube.com/')) return { ...active, url: page.url as string }
  }
  return chrome.tabs.create({ url: 'about:blank' })
}
async function handoff(connection: Connection, party: Record<string, any>, tab: chrome.tabs.Tab) {
  if (tab.id === undefined) throw new Error('YouTube tab unavailable.')
  const tabId = tab.id
  const received = new Promise<void>(resolve => ready.set(party.id, { tabId, resolve }))
  try {
    await chrome.storage.local.set({ connection, activeParty: { id: party.id, inviteCode: party.inviteCode, server: connection.server, userId: connection.user.userId, tabId, canControl: party.hostId === connection.user.userId } })
    if (!tab.url?.startsWith('https://www.youtube.com/')) await chrome.tabs.update(tabId, { url: party.externalMedia?.url || 'https://www.youtube.com/' })
    else await chrome.tabs.sendMessage(tabId, { type: 'watchparty-open-panel' }).catch(() => chrome.tabs.reload(tabId))
    await deadline(received, 12_000, 'Panel did not connect. Reload the YouTube tab.')
  } finally { ready.delete(party.id) }
}
let creating: Promise<unknown> | null = null
async function createParty() {
  const checked = await status()
  if (!checked.isAdmin || !checked.connection) throw new Error('Validate your admin login in Settings.')
  const connection = checked.connection
  const socket = await connect(connection)
  try {
    let party = (await request(socket, 'party:resume')).session
    const tab = await targetTab()
    if (!party) {
      const url = tab.url?.startsWith('https://www.youtube.com/') ? tab.url : 'https://www.youtube.com/'
      party = (await request(socket, 'party:create', { externalMedia: { provider: 'youtube', url } })).session
    }
    await handoff(connection, party, tab)
    return { code: party.inviteCode, partyId: party.id }
  } finally { socket.disconnect() }
}
async function joinParty(message: Record<string, any>) {
  const { setup, connection: previous } = await chrome.storage.local.get<{ setup?: Setup; connection?: Connection }>(['setup', 'connection'])
  const server = setup?.server ?? previous?.server
  if (!server) throw new Error('Set the server URL in Settings.')
  const data = await api(server, '/api/extension/join-invite', { body: { code: message.code, name: setup?.name, token: previous?.server === server ? previous.token : undefined } })
  const connection = { server, token: data.token, user: data.user, expiresAt: data.expiresAt }
  const tab = await targetTab()
  await handoff(connection, { id: data.partyId, externalMedia: data.media }, tab)
  return { partyId: data.partyId }
}

async function dispatch(message: Record<string, any>, sender: chrome.runtime.MessageSender): Promise<unknown> {
  if (message.type === 'bootstrap') {
    const stored = await chrome.storage.local.get(['setup', 'connection', 'activeParty'])
    const tabId = sender.tab?.id ?? null
    const follow: Record<string, unknown> = await deadline(chrome.storage.session.get(`follow-${tabId}`), 500).catch(() => ({}))
    return { ...stored, tabId, follow: follow[`follow-${tabId}`] ?? '' }
  }
  if (message.type === 'storage-get' || message.type === 'storage-set' || message.type === 'storage-remove') {
    const store = message.area === 'session' ? chrome.storage.session : chrome.storage.local
    if (message.type === 'storage-get') return store.get(message.keys)
    if (message.type === 'storage-set') await store.set(message.value)
    else await store.remove(message.keys)
    return {}
  }
  if (message.type === 'status') return status()
  if (message.type === 'open-settings') { await chrome.action.openPopup(); return {} }
  if (message.type === 'save-settings') return saveSettings(message)
  if (message.type === 'create-party') {
    if (!creating) creating = createParty().finally(() => { creating = null })
    return creating
  }
  if (message.type === 'join-party') return joinParty(message)
  if (message.type === 'room-ready') { const pending = ready.get(message.partyId); if (pending && pending.tabId === sender.tab?.id) pending.resolve(); return {} }
  if (message.type === 'sign-out') { await chrome.storage.local.remove(['connection', 'activeParty']); return {} }
  throw new Error('Reload the extension.')
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message?.type === 'watchparty-context') { respond({ tabId: sender.tab?.id ?? null }); return false }
  if (message?.type === 'watchparty-open-setup') { chrome.action.openPopup().then(() => respond({ ok: true }), () => respond({ error: 'Open Settings from the extension toolbar.' })); return true }
  if (message?.channel !== 'watchparty' || !trusted(sender)) return false
  void dispatch(message, sender).then(value => respond({ value }), error => respond({ error: error instanceof Error ? error.message : 'Extension error.' }))
  return true
})
