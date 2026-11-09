import test from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { once } from 'node:events'
import { mkdtempSync, rmSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import { io } from 'socket.io-client'

const TICKS = 10_000_000
const media = { provider: 'youtube', videoId: 'dQw4w9WgXcQ', title: 'Example YouTube video' }

test('YouTube extension pairing, scoped rooms, timeline, chat, LiveKit, and revocation', { timeout: 30_000 }, async t => {
  const probe = createServer()
  probe.listen(0, '127.0.0.1')
  await once(probe, 'listening')
  const port = probe.address().port
  await new Promise(resolve => probe.close(resolve))
  const base = `http://127.0.0.1:${port}`
  const scratch = mkdtempSync(join(tmpdir(), 'watchparty-extension-'))
  const accounts = createServer(async (req, res) => {
    let raw = ''; for await (const chunk of req) raw += chunk
    const body = JSON.parse(raw || '{}')
    res.setHeader('content-type', 'application/json')
    if (body.Pw !== 'correct-password') { res.writeHead(401); res.end('{}'); return }
    res.end(JSON.stringify({ AccessToken: 'upstream-test-token', User: { Id: body.Username === 'admin' ? 'youtube-admin' : 'youtube-nonadmin', Name: body.Username, Policy: { IsAdministrator: body.Username === 'admin' } } }))
  })
  accounts.listen(0, '127.0.0.1'); await once(accounts, 'listening')
  const child = spawn(process.execPath, ['server/index.js'], {
    cwd: join(import.meta.dirname, '..'),
    env: { ...process.env, PORT: String(port), NODE_ENV: 'test', WP_TEST_MODE: '1', JELLYFIN_URL: `http://127.0.0.1:${accounts.address().port}`, SESSION_SECRET: 'extension-integration-secret', SESSION_STORE_DIR: join(scratch, 'sessions'), PARTY_DB_PATH: join(scratch, 'parties.sqlite'), LIVEKIT_API_KEY: 'extension-test', LIVEKIT_API_SECRET: 'extension-test-secret-with-entropy', LIVEKIT_URL: 'ws://127.0.0.1:1', LIVEKIT_PUBLIC_URL: `ws://127.0.0.1:${port}/livekit` },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  let output = ''
  child.stdout.on('data', chunk => { output += chunk })
  child.stderr.on('data', chunk => { output += chunk })
  const sockets = []
  t.after(async () => {
    for (const socket of sockets) socket.disconnect()
    if (child.exitCode === null) { const exited = once(child, 'exit'); child.kill('SIGTERM'); await exited }
    await new Promise(resolve => accounts.close(resolve))
    rmSync(scratch, { recursive: true, force: true })
  })
  let ready = false
  for (let attempt = 0; attempt < 150; attempt++) {
    if (child.exitCode !== null) assert.fail(`Server exited: ${output}`)
    try { if ((await fetch(`${base}/api/health`)).ok) { ready = true; break } } catch {}
    await delay(25)
  }
  assert.equal(ready, true, output)

  async function post(path, body, cookie) {
    const response = await fetch(`${base}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) }, body: JSON.stringify(body) })
    return { response, body: await response.json() }
  }
  async function account(name) {
    const { response, body } = name === 'YouTube Host' ? await post('/api/auth/login', { username: 'admin', password: 'correct-password' }) : await post('/api/auth/test-login', { name })
    return { user: body, cookie: response.headers.get('set-cookie').split(';')[0] }
  }
  async function pair(account) {
    const code = await post('/api/extension/pair-code', {}, account.cookie)
    assert.equal(code.response.status, 200)
    const paired = await post('/api/extension/pair', { code: code.body.code })
    assert.equal(paired.response.status, 200)
    assert.equal((await post('/api/extension/pair', { code: code.body.code })).response.status, 400, 'a pairing code is single-use')
    assert.equal(paired.body.user.userId, account.user.userId)
    assert.equal(paired.body.token.length, 64)
    return paired.body.token
  }
  async function connect(auth) {
    const socket = io(base, { transports: ['websocket'], forceNew: true, reconnection: false, ...auth })
    sockets.push(socket)
    await Promise.race([once(socket, 'connect'), once(socket, 'connect_error').then(([error]) => { throw error })])
    return socket
  }
  const ack = (socket, event, body = {}) => new Promise((resolve, reject) => socket.timeout(3000).emit(event, body, (error, result) => error ? reject(error) : resolve(result)))
  const hostAccount = await account('YouTube Host')
  const guestAccount = await account('YouTube Guest')
  const hostToken = await pair(hostAccount)
  const guestToken = await pair(guestAccount)
  const host = await connect({ auth: { extensionToken: hostToken } })
  const guest = await connect({ auth: { extensionToken: guestToken } })
  assert.equal((await post('/api/extension/login', { username: 'admin', password: 'wrong' })).response.status, 401)
  assert.equal((await post('/api/extension/login', { username: 'viewer', password: 'correct-password' })).response.status, 403)
  const adminLogin = await post('/api/extension/login', { username: 'admin', password: 'correct-password' })
  assert.equal(adminLogin.response.status, 200)
  assert.equal(adminLogin.body.user.isAdmin, true)
  assert.equal(adminLogin.body.password, undefined)
  const verified = await fetch(`${base}/api/extension/me`, { headers: { Authorization: `Bearer ${adminLogin.body.token}` } }).then(response => response.json())
  assert.equal(verified.user.isAdmin, true)
  assert.equal((await fetch(`${base}/api/extension/me`)).status, 401)
  const renamed = await fetch(`${base}/api/extension/me`, { method: 'PATCH', headers: { Authorization: `Bearer ${adminLogin.body.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ name: 'Updated name' }) }).then(response => response.json())
  assert.equal(renamed.user.name, 'Updated name')
  assert.ok((await ack(guest, 'party:create', { externalMedia: media })).error, 'guests cannot create invite codes')
  const web = await connect({ extraHeaders: { Cookie: hostAccount.cookie } })

  assert.equal((await post('/api/extension/pair-code', {})).response.status, 401)
  assert.equal((await fetch(`${base}/api/library/items`, { headers: { Authorization: `Bearer ${hostToken}` } })).status, 401, 'extension token is not a Jellyfin HTTP credential')
  const jellyfin = await ack(web, 'party:create')
  assert.ok(jellyfin.partyId)
  assert.equal((await ack(host, 'party:resume')).session, null)
  assert.ok((await ack(host, 'sync:pause', { positionTicks: 0 })).error, 'extension cannot operate on an existing Jellyfin room')
  assert.ok((await ack(host, 'party:join', { partyId: jellyfin.partyId })).error)
  await ack(web, 'party:end')
  assert.ok((await ack(host, 'party:create', { mediaItemId: 'a'.repeat(32), externalMedia: media })).error)
  assert.ok((await ack(host, 'party:create', { externalMedia: { ...media, videoId: 'bad' } })).error)

  const created = await ack(host, 'party:create', { externalMedia: media, resumePositionTicks: 30 * TICKS })
  assert.ok(created.partyId)
  assert.equal(created.session.externalMedia.videoId, media.videoId)
  assert.equal(created.session.schedule.positionTicks, 30 * TICKS)
  assert.equal(created.session.schedule.phase, 'paused')
  assert.equal(created.session.syncMode, 'hopping')
  assert.match(created.session.inviteCode, /^[A-F0-9]{12}$/)
  const partyId = created.partyId
  let generation = created.session.schedule.mediaGeneration
  assert.equal((await ack(web, 'party:resume')).session, null, 'ordinary web app must not auto-enter an extension party')
  assert.ok((await ack(web, 'party:join', { partyId })).error)
  assert.ok((await ack(host, 'party:selectMedia', { mediaItemId: 'a'.repeat(32) })).error)
  assert.equal((await ack(guest, 'party:join', { partyId })).status, 'waiting')
  const tokenPath = `${base}/api/extension/livekit-token?partyId=${partyId}`
  const extensionOrigin = `chrome-extension://${'a'.repeat(32)}`
  const preflight = await fetch(tokenPath, { method: 'OPTIONS', headers: { Origin: extensionOrigin, 'Access-Control-Request-Headers': 'authorization' } })
  assert.equal(preflight.status, 204)
  assert.equal(preflight.headers.get('access-control-allow-origin'), extensionOrigin)
  assert.equal(preflight.headers.get('access-control-allow-credentials'), null)
  assert.equal((await fetch(tokenPath, { headers: { Authorization: `Bearer ${guestToken}` } })).status, 403)
  assert.ok((await ack(guest, 'sync:play', { positionTicks: 30 * TICKS, mediaGeneration: generation })).error)
  const approved = once(guest, 'party:approved')
  assert.equal((await ack(host, 'party:approve', { userId: guestAccount.user.userId })).ok, true)
  await approved
  const rtc = await fetch(tokenPath, { headers: { Authorization: `Bearer ${guestToken}`, Origin: extensionOrigin } })
  assert.equal(rtc.status, 200)
  assert.equal(rtc.headers.get('access-control-allow-origin'), extensionOrigin)
  const grant = await rtc.json()
  const jwt = JSON.parse(Buffer.from(grant.token.split('.')[1], 'base64url').toString())
  assert.equal(jwt.video.room, partyId)
  assert.equal(jwt.sub, guestAccount.user.userId)
  assert.equal(grant.url, `ws://127.0.0.1:${port}/livekit`)
  const message = once(guest, 'chat:message')
  assert.equal((await ack(host, 'chat:message', { text: 'YouTube together' })).ok, true)
  assert.equal((await message)[0].text, 'YouTube together')
  assert.ok((await ack(guest, 'sync:seek', { positionTicks: 40 * TICKS, mediaGeneration: generation })).error)
  assert.ok((await ack(guest, 'party:setController', { userId: guestAccount.user.userId, enabled: true })).error)
  await ack(host, 'party:setController', { userId: guestAccount.user.userId, enabled: true })
  assert.equal((await ack(guest, 'sync:seek', { positionTicks: 40 * TICKS, mediaGeneration: generation })).ok, true)
  await ack(host, 'party:setController', { userId: guestAccount.user.userId, enabled: false })
  assert.ok((await ack(guest, 'sync:seek', { positionTicks: 40 * TICKS, mediaGeneration: generation })).error, 'revoked controls are rejected by the server')
  await ack(host, 'sync:play', { positionTicks: 40 * TICKS, mediaGeneration: generation })
  await ack(host, 'party:setExternalPlaybackRate', { rate: 2 })
  let state = (await ack(host, 'party:resume')).session
  assert.equal(state.schedule.rate, 2)
  assert.equal(state.externalMedia.playbackRate, 2)

  guest.emit('sync:stall', { stalled: true, ad: true, mediaGeneration: generation })
  await ack(guest, 'clock:ping')
  assert.equal((await ack(host, 'party:resume')).session.schedule.phase, 'playing', 'guest ads do not hold a Lead room')
  host.emit('sync:stall', { stalled: true, ad: true, mediaGeneration: generation })
  await ack(host, 'clock:ping')
  assert.equal((await ack(host, 'party:resume')).session.schedule.phase, 'stalled', 'host ad freezes the content timeline')
  host.emit('sync:stall', { stalled: false, ad: false, mediaGeneration: generation })
  await ack(host, 'clock:ping')
  assert.equal((await ack(host, 'party:resume')).session.schedule.phase, 'playing')
  await ack(host, 'party:setSyncMode', { mode: 'dragging' })
  assert.equal((await ack(host, 'party:resume')).session.schedule.phase, 'stalled', 'Follow room waits for guest ad')
  guest.emit('sync:stall', { stalled: false, ad: false, mediaGeneration: generation })
  await ack(guest, 'clock:ping')
  assert.equal((await ack(host, 'party:resume')).session.schedule.phase, 'playing')

  await ack(host, 'party:selectExternalMedia', { ...media, videoId: 'aaaaaaaaaaa' })
  state = (await ack(host, 'party:resume')).session
  assert.ok(state.schedule.mediaGeneration > generation)
  assert.equal(state.externalMedia.videoId, 'aaaaaaaaaaa')
  assert.equal(state.schedule.phase, 'playing')
  assert.equal((await ack(host, 'sync:play', { positionTicks: 99 * TICKS, mediaGeneration: generation })).error, 'media changed')
  generation = state.schedule.mediaGeneration
  assert.equal((await ack(host, 'sync:play', { positionTicks: 0, mediaGeneration: generation })).ok, true)
  assert.ok(!JSON.stringify(state).includes(hostToken), 'public session never exposes extension token')

  const invited = await post('/api/extension/join-invite', { code: created.session.inviteCode, name: 'No Jellyfin account' })
  assert.equal(invited.response.status, 200)
  assert.equal(invited.body.user.isAdmin, false)
  const codeGuest = await connect({ auth: { extensionToken: invited.body.token } })
  assert.equal((await ack(codeGuest, 'party:join', { partyId })).status, 'joined', 'an invite code is sufficient to join')
  assert.ok((await ack(codeGuest, 'party:create', { externalMedia: media })).error)
  assert.ok((await ack(codeGuest, 'sync:seek', { positionTicks: 1, mediaGeneration: generation })).error)
  await ack(host, 'party:setController', { userId: invited.body.user.userId, enabled: true })
  assert.equal((await ack(codeGuest, 'sync:seek', { positionTicks: 1, mediaGeneration: generation })).ok, true)
  await ack(host, 'party:selectExternalMedia', { provider: 'youtube', url: 'https://www.youtube.com/results?search_query=space', title: 'Search' })
  const browsing = (await ack(host, 'party:resume')).session
  assert.equal(browsing.externalMedia.videoId, null)
  assert.equal(browsing.externalMedia.url, 'https://www.youtube.com/results?search_query=space')
  assert.equal(browsing.schedule.phase, 'paused')
  const secondAdmin = await connect({ auth: { extensionToken: adminLogin.body.token } })
  assert.equal((await ack(secondAdmin, 'party:resume')).session.id, partyId, 'admin login survives independently of the web cookie')
  assert.ok((await ack(host, 'party:selectExternalMedia', { provider: 'youtube', url: 'https://evil.example/video' })).error)
  await ack(secondAdmin, 'party:end')
  assert.equal((await post('/api/extension/join-invite', { code: created.session.inviteCode })).response.status, 404, 'ended party codes cannot be reused')
  const nextParty = await ack(secondAdmin, 'party:create', { externalMedia: media })
  assert.notEqual(nextParty.session.inviteCode, created.session.inviteCode, 'every party has a fresh invite code')
  assert.ok((await ack(codeGuest, 'party:join', { partyId: nextParty.partyId })).error, 'guest credentials are scoped to the invited party')
  await ack(secondAdmin, 'party:end')
  const list = await fetch(`${base}/api/extension/devices`, { headers: { Cookie: hostAccount.cookie } }).then(response => response.json())
  assert.equal(list.length, 2)
  const disconnected = once(host, 'disconnect')
  const revoked = await fetch(`${base}/api/extension/devices/${list[0].id}`, { method: 'DELETE', headers: { Cookie: hostAccount.cookie } })
  assert.equal(revoked.status, 200)
  await disconnected
  assert.equal((await fetch(tokenPath, { headers: { Authorization: `Bearer ${hostToken}` } })).status, 401)
})
