import { io } from 'socket.io-client'
import fetch from 'node-fetch'
import { CookieJar } from 'tough-cookie'
import fetchCookie from 'fetch-cookie'

const jar = new CookieJar()
const fetchWithCookies = fetchCookie(fetch, jar)

// Login
const loginRes = await fetchWithCookies('http://localhost:3001/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'root', password: 'root' }),
})
const user = await loginRes.json()
console.log('Logged in as:', user.name)

// Get item
const items = await fetchWithCookies('http://localhost:3001/api/library/items').then(r => r.json())
const itemId = items[0].Id
console.log('Item:', items[0].Name)

// Get cookies string for socket.io
const cookies = await jar.getCookieString('http://localhost:3001')

const socket = io('http://localhost:3001', { extraHeaders: { Cookie: cookies } })

socket.on('connect', () => {
  console.log('Socket connected:', socket.id)
  socket.emit('party:create', { mediaItemId: itemId }, (res) => {
    if (res.error) { console.error('Error:', res.error); process.exit(1) }
    console.log('Party created! ID:', res.partyId)
    console.log('Session guests:', res.session.guests.length)
    console.log('SyncPlay group:', res.session.syncPlayGroupId)
    socket.disconnect()
    process.exit(0)
  })
})

socket.on('connect_error', (err) => {
  console.error('Connect error:', err.message)
  process.exit(1)
})

setTimeout(() => { console.error('Timeout'); process.exit(1) }, 10000)
