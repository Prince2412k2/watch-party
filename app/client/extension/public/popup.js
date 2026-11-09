const server = document.querySelector('#server')
const status = document.querySelector('#status')
const name = document.querySelector('#name')
const username = document.querySelector('#username')
const password = document.querySelector('#password')

function selectView(view) {
  document.querySelector('#setup-view').hidden = view !== 'setup'
  document.querySelector('#join-view').hidden = view !== 'join'
  for (const tab of document.querySelectorAll('[role="tab"]')) {
    const selected = tab.dataset.view === view
    tab.setAttribute('aria-selected', String(selected))
    tab.tabIndex = selected ? 0 : -1
  }
}
for (const button of document.querySelectorAll('[data-view]')) button.addEventListener('click', () => {
  selectView(button.dataset.view)
  if (button.getAttribute('role') !== 'tab') document.querySelector(`#${button.dataset.view}-view input`)?.focus()
})
for (const tab of document.querySelectorAll('[role="tab"]')) tab.addEventListener('keydown', event => {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
  event.preventDefault()
  const target = event.key === 'Home' ? 'join' : event.key === 'End' ? 'setup' : tab.dataset.view === 'join' ? 'setup' : 'join'
  selectView(target)
  document.querySelector(`[role="tab"][data-view="${target}"]`).focus()
})
function notify(message, error = false) {
  status.textContent = message
  status.dataset.tone = error ? 'error' : 'success'
}
function updateName() { document.querySelector('#joining-name').textContent = name.value.trim() || 'Guest' }
name.addEventListener('input', updateName)
function updateServer() {
  let label = 'Add a server URL in Setup'
  let valid = false
  try { label = new URL(serverOrigin()).host; valid = true } catch {}
  document.querySelector('#saved-server').textContent = label
  document.querySelector('#join').disabled = !valid
}
server.addEventListener('input', updateServer)

function serverOrigin() {
  const url = new URL(server.value.trim())
  if (url.username || url.password || (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname)))) throw new Error('Use an HTTPS server, or HTTP localhost for development.')
  return url.origin
}
async function permission(origin) {
  if (!await chrome.permissions.request({ origins: [`${origin}/*`] })) throw new Error('Server access was not granted.')
}
async function api(origin, path, body) {
  const response = await fetch(`${origin}/api/extension/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), credentials: 'omit' })
  const data = await response.json()
  if (!response.ok) throw new Error(data.error || 'Could not connect to Watch Party')
  return data
}
function showAccount(connection) {
  document.querySelector('#admin-status').textContent = connection?.user.isAdmin ? `Admin signed in as ${connection.user.name}. Login is remembered.` : 'Guests do not need an account.'
  document.querySelector('#disconnect').hidden = !connection
  const details = document.querySelector('.admin-details')
  details.dataset.admin = connection?.user.isAdmin ? 'true' : 'false'
  details.querySelector('summary small').textContent = connection?.user.isAdmin ? `Signed in as ${connection.user.name}` : 'Optional admin sign-in'
}
chrome.storage.local.get(['setup', 'connection']).then(({ setup, connection }) => {
  server.value = setup?.server || connection?.server || ''
  name.value = setup?.name || connection?.user.name || ''
  username.value = setup?.username || ''
  showAccount(connection)
  updateName()
  updateServer()
  selectView(server.value ? 'join' : 'setup')
})
document.querySelector('#setup-form').addEventListener('submit', async event => {
  event.preventDefault()
  const button = document.querySelector('#save')
  button.disabled = true
  button.firstChild.textContent = 'Saving… '
  try {
    const origin = serverOrigin()
    await permission(origin)
    const stored = await chrome.storage.local.get('connection')
    let connection = stored.connection?.server === origin ? stored.connection : null
    if (password.value) {
      if (!username.value.trim()) throw new Error('Enter the admin username with the password')
      const data = await api(origin, 'login', { username: username.value.trim(), password: password.value })
      connection = { server: origin, token: data.token, user: data.user, expiresAt: data.expiresAt }
      password.value = ''
    } else if (username.value.trim() && !connection?.user.isAdmin) throw new Error('Enter the admin password, or leave the username empty to join as a guest')
    await chrome.storage.local.set({ setup: { server: origin, name: name.value.trim(), username: username.value.trim() }, connection })
    showAccount(connection)
    updateName()
    updateServer()
    selectView('join')
    notify(connection?.user.isAdmin ? 'Admin login saved. Open YouTube and create your party to get an invite code.' : 'Setup saved. You’re ready to join with your host’s code.')
  } catch (error) { notify(error.message || 'Could not save setup', true) }
  finally { button.disabled = false; button.firstChild.textContent = 'Save setup ' }
})
document.querySelector('#join-form').addEventListener('submit', async event => {
  event.preventDefault()
  const button = document.querySelector('#join')
  button.disabled = true
  button.firstChild.textContent = 'Joining… '
  try {
    const origin = serverOrigin()
    await permission(origin)
    const { connection: previous } = await chrome.storage.local.get('connection')
    const data = await api(origin, 'join-invite', { code: document.querySelector('#invite').value.trim(), name: name.value.trim(), token: previous?.server === origin ? previous.token : undefined })
    const connection = { server: origin, token: data.token, user: data.user, expiresAt: data.expiresAt }
    let [tab] = await chrome.tabs.query({ active: true, currentWindow: true })
    if (!tab?.url?.startsWith('https://www.youtube.com/')) tab = await chrome.tabs.create({ url: 'about:blank' })
    await chrome.storage.local.set({ setup: { server: origin, name: name.value.trim() || data.user.name, username: username.value.trim() }, connection, activeParty: { id: data.partyId, server: origin, userId: data.user.userId, tabId: tab.id, canControl: false } })
    await chrome.tabs.update(tab.id, { url: data.media.url || 'https://www.youtube.com/' })
    notify('Opening your party. Your friends are waiting.')
    showAccount(connection)
  } catch (error) { notify(error.message || 'Could not join party', true); if (!server.value.trim()) selectView('setup') }
  finally { updateServer(); button.firstChild.textContent = 'Join party ' }
})
document.querySelector('#youtube').addEventListener('click', () => chrome.tabs.create({ url: 'https://www.youtube.com/' }))
document.querySelector('#disconnect').addEventListener('click', async () => {
  await chrome.storage.local.remove(['connection', 'activeParty'])
  showAccount(null)
  notify('Signed out. Your server URL and display name are still saved.')
})
