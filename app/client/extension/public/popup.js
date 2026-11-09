const server = document.querySelector('#server')
const status = document.querySelector('#status')
const pair = document.querySelector('#pair')

function serverOrigin() {
  const url = new URL(server.value.trim())
  if (url.username || url.password || (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname)))) throw new Error('Use an HTTPS server, or HTTP localhost for development.')
  return url.origin
}
async function permission(origin) {
  if (!await chrome.permissions.request({ origins: [`${origin}/*`] })) throw new Error('Server access was not granted.')
}
chrome.storage.local.get(['connection']).then(({ connection }) => {
  if (!connection) return
  server.value = connection.server
  status.textContent = `Paired as ${connection.user.name}. Open a YouTube video to start.`
  document.querySelector('#disconnect').hidden = false
})
document.querySelector('#open-pair').addEventListener('click', async () => {
  try {
    const origin = serverOrigin()
    await permission(origin)
    await chrome.tabs.create({ url: `${origin}/extension` })
  } catch (error) { status.textContent = error.message }
})
document.querySelector('#pair-form').addEventListener('submit', async event => {
  event.preventDefault()
  pair.disabled = true
  try {
    const origin = serverOrigin()
    await permission(origin)
    const response = await fetch(`${origin}/api/extension/pair`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: document.querySelector('#code').value.trim() }), credentials: 'omit' })
    const data = await response.json()
    if (!response.ok) throw new Error(data.error || 'Pairing failed')
    await chrome.storage.local.set({ connection: { server: origin, token: data.token, user: data.user, expiresAt: data.expiresAt } })
    status.textContent = `Paired as ${data.user.name}. Reload your YouTube tab to connect.`
    document.querySelector('#code').value = ''
    document.querySelector('#disconnect').hidden = false
  } catch (error) { status.textContent = error.message || 'Could not reach your server' }
  finally { pair.disabled = false }
})
document.querySelector('#youtube').addEventListener('click', () => chrome.tabs.create({ url: 'https://www.youtube.com/' }))
document.querySelector('#disconnect').addEventListener('click', async () => {
  await chrome.storage.local.remove(['connection', 'activeParty'])
  status.textContent = 'Local pairing removed. You can also revoke it on your server’s pairing page.'
  document.querySelector('#disconnect').hidden = true
})
