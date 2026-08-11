import test from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { createServer, request } from 'node:http'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { setTimeout as delay } from 'node:timers/promises'
import { io as connectSocket } from 'socket.io-client'
import { AccessToken } from 'livekit-server-sdk'

const API_KEY = 'integration-key'
const API_SECRET = 'integration-secret-with-enough-entropy'

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(0, '127.0.0.1', () => resolve(server.address().port))
  })
}

async function unusedPort() {
  const server = createServer()
  const port = await listen(server)
  await new Promise(resolve => server.close(resolve))
  return port
}

async function waitForServer(baseUrl, child, output) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (child.exitCode !== null) throw new Error(`server exited ${child.exitCode}: ${output()}`)
    try {
      const response = await fetch(`${baseUrl}/api/health`)
      if (response.ok) return
    } catch {}
    await delay(25)
  }
  throw new Error(`server did not start: ${output()}`)
}

async function login(baseUrl, name) {
  const response = await fetch(`${baseUrl}/api/auth/test-login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name }),
  })
  assert.equal(response.status, 200)
  return response.headers.get('set-cookie').split(';', 1)[0]
}

function connect(baseUrl, cookie) {
  return new Promise((resolve, reject) => {
    const socket = connectSocket(baseUrl, {
      transports: ['websocket'],
      extraHeaders: { Cookie: cookie },
      forceNew: true,
    })
    socket.once('connect', () => resolve(socket))
    socket.once('connect_error', reject)
  })
}

function emitAck(socket, event, payload = {}) {
  return new Promise(resolve => socket.emit(event, payload, resolve))
}

function nextMatching(socket, event, predicate = () => true) {
  return new Promise(resolve => {
    const listener = payload => {
      if (!predicate(payload)) return
      socket.off(event, listener)
      resolve(payload)
    }
    socket.on(event, listener)
  })
}

async function expectNoMatching(sockets, event, predicate, action) {
  let received = false
  const listener = payload => { if (predicate(payload)) received = true }
  for (const socket of sockets) socket.on(event, listener)
  try {
    await action()
    await delay(100)
    assert.equal(received, false)
  } finally {
    for (const socket of sockets) socket.off(event, listener)
  }
}

function upgradeStatus(port, path, cookie) {
  return new Promise((resolve, reject) => {
    const headers = { Connection: 'Upgrade', Upgrade: 'websocket' }
    if (cookie) headers.Cookie = cookie
    const req = request({ host: '127.0.0.1', port, path, headers })
    req.once('upgrade', (response, socket) => {
      socket.destroy()
      resolve(response.statusCode)
    })
    req.once('response', response => {
      response.resume()
      resolve(response.statusCode)
    })
    req.once('error', reject)
    req.end()
  })
}

test('party rooms and LiveKit upgrades enforce authenticated membership boundaries', { timeout: 20_000 }, async () => {
  const livekitRequests = []
  const upstream = createServer((req, res) => {
    let body = ''
    req.on('data', chunk => { body += chunk })
    req.on('end', () => {
      livekitRequests.push({ path: req.url, body })
      res.setHeader('content-type', 'application/json')
      res.end('{}')
    })
  })
  upstream.on('upgrade', (_req, socket) => {
    socket.write('HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n')
    socket.end()
  })
  const upstreamPort = await listen(upstream)
  const port = await unusedPort()
  const baseUrl = `http://127.0.0.1:${port}`
  const scratch = join(tmpdir(), `watchparty-party-auth-${process.pid}-${Date.now()}`)
  let stdout = ''
  let stderr = ''
  const child = spawn(process.execPath, ['server/index.js'], {
    cwd: join(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      NODE_ENV: 'test',
      WP_TEST_MODE: '1',
      WP_HOST_GRACE_MS: '100',
      SESSION_SECRET: 'party-auth-integration-secret',
      SESSION_STORE_DIR: join(scratch, 'sessions'),
      PARTY_DB_PATH: join(scratch, 'parties.sqlite'),
      LIVEKIT_URL: `ws://127.0.0.1:${upstreamPort}`,
      LIVEKIT_API_KEY: API_KEY,
      LIVEKIT_API_SECRET: API_SECRET,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  child.stdout.on('data', chunk => { stdout += chunk })
  child.stderr.on('data', chunk => { stderr += chunk })
  const sockets = []

  try {
    await waitForServer(baseUrl, child, () => stdout + stderr)
    const hostCookie = await login(baseUrl, 'Host One')
    const otherHostCookie = await login(baseUrl, 'Host Two')
    const guestCookie = await login(baseUrl, 'Guest')
    const rejectedCookie = await login(baseUrl, 'Rejected')
    const host = await connect(baseUrl, hostCookie)
    const otherHost = await connect(baseUrl, otherHostCookie)
    const guestOne = await connect(baseUrl, guestCookie)
    const guestTwo = await connect(baseUrl, guestCookie)
    const guestUnrelated = await connect(baseUrl, guestCookie)
    const rejected = await connect(baseUrl, rejectedCookie)
    const hostBackup = await connect(baseUrl, hostCookie)
    const otherHostUnrelated = await connect(baseUrl, otherHostCookie)
    sockets.push(host, otherHost, guestOne, guestTwo, guestUnrelated, rejected, hostBackup, otherHostUnrelated)

    const firstParty = await emitAck(host, 'party:create')
    const secondParty = await emitAck(otherHost, 'party:create')
    assert.ok(firstParty.partyId)
    assert.ok(secondParty.partyId)
    assert.equal((await emitAck(hostBackup, 'party:resume')).session.id, firstParty.partyId)
    host.disconnect()
    assert.equal((await emitAck(hostBackup, 'party:resume')).session.id, firstParty.partyId)

    assert.equal((await emitAck(guestOne, 'party:join', { partyId: firstParty.partyId })).status, 'waiting')
    assert.equal((await emitAck(guestTwo, 'party:join', { partyId: firstParty.partyId })).status, 'waiting')
    assert.equal((await emitAck(guestOne, 'party:join', { partyId: secondParty.partyId })).error, 'already in a party')
    assert.equal((await emitAck(guestOne, 'party:create')).error, 'already in a party')

    otherHost.disconnect()
    await delay(200)
    assert.equal((await emitAck(otherHostUnrelated, 'party:resume')).session, null)

    await expectNoMatching([guestOne, guestTwo], 'chat:message', message => message.text === 'waiting-only', async () => {
      assert.equal((await emitAck(hostBackup, 'chat:message', { text: 'waiting-only' })).ok, true)
    })

    const approvedOne = nextMatching(guestOne, 'party:approved')
    const approvedTwo = nextMatching(guestTwo, 'party:approved')
    let unrelatedApproved = false
    guestUnrelated.on('party:approved', () => { unrelatedApproved = true })
    const guestId = firstParty.session.waiting[0]?.userId
      ?? (await emitAck(hostBackup, 'party:resume')).session.waiting[0].userId
    assert.equal((await emitAck(hostBackup, 'party:approve', { userId: guestId })).ok, true)
    await Promise.all([approvedOne, approvedTwo])
    await delay(50)
    assert.equal(unrelatedApproved, false)
    const joinedOne = nextMatching(guestOne, 'chat:message', message => message.text === 'approved')
    const joinedTwo = nextMatching(guestTwo, 'chat:message', message => message.text === 'approved')
    await emitAck(hostBackup, 'chat:message', { text: 'approved' })
    await Promise.all([joinedOne, joinedTwo])

    guestOne.disconnect()
    const remainingGuest = nextMatching(guestTwo, 'chat:message', message => message.text === 'guest-remains')
    await emitAck(hostBackup, 'chat:message', { text: 'guest-remains' })
    await remainingGuest
    assert.equal((await emitAck(guestTwo, 'party:resume')).session.id, firstParty.partyId)

    const memberToken = new AccessToken(API_KEY, API_SECRET, { identity: guestId })
    memberToken.addGrant({ roomJoin: true, room: firstParty.partyId })
    const memberJwt = await memberToken.toJwt()
    assert.equal(await upgradeStatus(port, `/livekit/rtc?access_token=${encodeURIComponent(memberJwt)}`), 101)

    const kickedTwo = nextMatching(guestTwo, 'party:kicked')
    let unrelatedKicked = false
    guestUnrelated.on('party:kicked', () => { unrelatedKicked = true })
    assert.equal((await emitAck(hostBackup, 'party:kick', { userId: guestId })).ok, true)
    await kickedTwo
    await delay(50)
    assert.equal(unrelatedKicked, false)
    assert.equal(await upgradeStatus(port, `/livekit/rtc?access_token=${encodeURIComponent(memberJwt)}`), 401)
    await expectNoMatching([guestTwo, guestUnrelated], 'chat:message', message => message.text === 'after-kick', async () => {
      await emitAck(hostBackup, 'chat:message', { text: 'after-kick' })
    })
    for (let attempt = 0; attempt < 50 && livekitRequests.length === 0; attempt++) await delay(20)
    assert.equal(livekitRequests.some(entry => entry.body.includes(guestId) && entry.body.includes(firstParty.partyId)), true)

    assert.equal((await emitAck(rejected, 'party:join', { partyId: firstParty.partyId })).status, 'waiting')
    const resumed = await emitAck(hostBackup, 'party:resume')
    const rejectedId = resumed.session.waiting[0].userId
    const rejection = nextMatching(rejected, 'party:rejected')
    assert.equal((await emitAck(hostBackup, 'party:reject', { userId: rejectedId })).ok, true)
    await rejection
    await expectNoMatching([rejected], 'chat:message', message => message.text === 'after-reject', async () => {
      await emitAck(hostBackup, 'chat:message', { text: 'after-reject' })
    })

    assert.equal(await upgradeStatus(port, '/livekit/rtc'), 401)
    assert.equal(await upgradeStatus(port, '/livekitfoo', hostCookie), 404)
    assert.equal(await upgradeStatus(port, '/livekit/rtc', hostCookie), 101)
    const nonMemberToken = new AccessToken(API_KEY, API_SECRET, { identity: 'native-user' })
    nonMemberToken.addGrant({ roomJoin: true, room: firstParty.partyId })
    const nonMemberJwt = await nonMemberToken.toJwt()
    assert.equal(await upgradeStatus(port, `/livekit/rtc?access_token=${encodeURIComponent(nonMemberJwt)}`), 401)

    // A Socket.IO connection must still be possible AFTER LiveKit traffic has
    // gone through its proxy. It was not: `ws: true` made the proxy middleware
    // subscribe itself to the server's 'upgrade' event on its first HTTP
    // request, with a path filter defaulting to '/', so every subsequent
    // websocket upgrade — Socket.IO's included — was forwarded to LiveKit,
    // whose 404 arrived on the socket right after engine.io's OPEN frame and
    // closed it. Native clients (websocket-only, no polling fallback) could not
    // start or join a party at all until the server was restarted.
    //
    // The trigger has to be an ORDINARY HTTP request through the proxy
    // middleware, which is what the LiveKit SDK sends before opening its socket.
    // Upgrades alone never reach the middleware (they are handled by the
    // server's own 'upgrade' listener), so without this line the subscription
    // never happens and this test passes with the bug present — as it did.
    const preflight = await fetch(`${baseUrl}/livekit/rtc/validate`, {
      headers: { Cookie: hostCookie },
    })
    assert.equal(preflight.status, 200)

    const afterLiveKit = await connect(baseUrl, hostCookie)
    sockets.push(afterLiveKit)
    assert.equal(afterLiveKit.connected, true)
    // Not just connected — usable. A socket the server is about to hang up on
    // still reports `connected` for a moment.
    assert.equal((await emitAck(afterLiveKit, 'party:resume')).session.id, firstParty.partyId)
    await delay(150)
    assert.equal(afterLiveKit.connected, true)
  } finally {
    for (const socket of sockets) socket.disconnect()
    child.kill('SIGTERM')
    await Promise.race([
      new Promise(resolve => child.once('exit', resolve)),
      delay(1000).then(() => child.kill('SIGKILL')),
    ])
    await new Promise(resolve => upstream.close(resolve))
    rmSync(scratch, { recursive: true, force: true })
  }
})
