// Manual end-to-end smoke check for the party socket path.
//
//   npm run smoke:party                       # against http://localhost:3001
//   BASE=http://localhost:3005 npm run smoke:party
//
// This is a debugging tool, not a test — nothing in CI runs it, and it needs a
// live stack: the app server (`cd app && npm start`) with a reachable Jellyfin
// behind it, a `root`/`root` account, and at least one library item. It drives
// the same path a real client does — cookie login over HTTP, then a socket
// handshake authenticated by that cookie — so it tells you which half of the
// stack is broken when the browser "just doesn't join".
//
// It creates a real party and ends it again on the way out. Leaving one behind
// would make every later run fail with "already in a party".

import { io } from 'socket.io-client'
import fetch from 'node-fetch'
import { CookieJar } from 'tough-cookie'
import fetchCookie from 'fetch-cookie'

const base = process.env.BASE ?? 'http://localhost:3001'
const username = process.env.WP_USER ?? 'root'
const password = process.env.WP_PASS ?? 'root'

const jar = new CookieJar()
const fetchWithCookies = fetchCookie(fetch, jar)

const die = (message) => { console.error(`FAIL: ${message}`); process.exit(1) }

const loginRes = await fetchWithCookies(`${base}/api/auth/login`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username, password }),
})
if (!loginRes.ok) die(`login returned ${loginRes.status} — is the server up at ${base}?`)
const user = await loginRes.json()
console.log('logged in as:', user.name)

const itemsRes = await fetchWithCookies(`${base}/api/library/items`)
if (!itemsRes.ok) die(`/api/library/items returned ${itemsRes.status} — is Jellyfin reachable?`)
const items = await itemsRes.json()
if (!items.length) die('library is empty, nothing to start a party on')
console.log('item:', items[0].Name)

// The socket handshake is authenticated by the same session cookie the HTTP
// calls above just earned, so it has to be replayed onto the upgrade request.
const cookies = await jar.getCookieString(base)
const socket = io(base, { extraHeaders: { Cookie: cookies } })

const timeout = setTimeout(() => die('timed out waiting for the socket'), 10_000)

socket.on('connect_error', (error) => die(`socket connect: ${error.message}`))

socket.on('connect', () => {
  console.log('socket connected:', socket.id)
  socket.emit('party:create', { mediaItemId: items[0].Id }, (res) => {
    if (res.error) die(`party:create: ${res.error}`)
    console.log('party created:', res.partyId)
    console.log('  stage:   ', res.session.stage)
    console.log('  syncMode:', res.session.syncMode)
    console.log('  schedule:', JSON.stringify(res.session.schedule))
    console.log('  guests:  ', res.session.guests.length)

    socket.emit('party:end', {}, (end) => {
      if (end?.error) die(`party:end: ${end.error}`)
      console.log('party ended, cleaned up')
      clearTimeout(timeout)
      socket.disconnect()
      process.exit(0)
    })
  })
})
