import test from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { createServer } from 'node:http'
import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { setTimeout as delay } from 'node:timers/promises'
import { io as connectSocket } from 'socket.io-client'

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

function deferred() {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}

test('media selection commits only the latest still-authorized request', { timeout: 20_000 }, async () => {
  const heldSources = new Map()
  const heldPlayback = new Map()
  const jellyfin = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost')
    const playbackMatch = url.pathname.match(/^\/Items\/([^/]+)\/PlaybackInfo$/)
    const itemId = playbackMatch?.[1] ?? url.searchParams.get('Ids')
    if (!itemId) {
      res.writeHead(404).end()
      return
    }

    const gate = playbackMatch ? heldPlayback.get(itemId) : heldSources.get(itemId)
    if (gate) {
      gate.arrived.resolve()
      await gate.release.promise
      if (playbackMatch) heldPlayback.delete(itemId)
      else heldSources.delete(itemId)
    }

    res.setHeader('content-type', 'application/json')
    if (!playbackMatch) {
      res.end(JSON.stringify({ Items: [{ MediaSources: [{ Id: `source-${itemId}` }] }] }))
      return
    }
    res.end(JSON.stringify({
      PlaySessionId: `play-${itemId}`,
      MediaSources: [{
        Id: `source-${itemId}`,
        MediaStreams: [
          { Type: 'Audio', Index: 2 },
          { Type: 'Audio', Index: 5, IsDefault: true },
          { Type: 'Subtitle', Index: 8 },
          { Type: 'Subtitle', Index: 11, IsDefault: true, IsExternal: true },
        ],
        DirectStreamUrl: `/Videos/${itemId}/stream`,
      }],
    }))
  })
  const jellyfinPort = await listen(jellyfin)
  const holdPlayback = itemId => {
    const gate = { arrived: deferred(), release: deferred() }
    heldPlayback.set(itemId, gate)
    return gate
  }
  const holdSource = itemId => {
    const gate = { arrived: deferred(), release: deferred() }
    heldSources.set(itemId, gate)
    return gate
  }

  const port = await unusedPort()
  const baseUrl = `http://127.0.0.1:${port}`
  const scratch = join(tmpdir(), `watchparty-media-selection-${process.pid}-${Date.now()}`)
  let stdout = ''
  let stderr = ''
  const child = spawn(process.execPath, ['server/index.js'], {
    cwd: join(import.meta.dirname, '..'),
    env: {
      ...process.env,
      PORT: String(port),
      NODE_ENV: 'test',
      WP_TEST_MODE: '1',
      SESSION_SECRET: 'media-selection-integration-secret',
      SESSION_STORE_DIR: join(scratch, 'sessions'),
      PARTY_DB_PATH: join(scratch, 'parties.sqlite'),
      JELLYFIN_URL: `http://127.0.0.1:${jellyfinPort}`,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  child.stdout.on('data', chunk => { stdout += chunk })
  child.stderr.on('data', chunk => { stderr += chunk })
  const sockets = []

  try {
    await waitForServer(baseUrl, child, () => stdout + stderr)
    const host = await connect(baseUrl, await login(baseUrl, 'Selection Host'))
    const guest = await connect(baseUrl, await login(baseUrl, 'Selection Guest'))
    sockets.push(host, guest)

    const created = await emitAck(host, 'party:create')
    assert.ok(created.partyId)

    const firstGate = holdPlayback('first')
    const firstAck = emitAck(host, 'party:selectMedia', { mediaItemId: 'first' })
    await firstGate.arrived.promise
    const latestSource = holdSource('latest')
    const latestAck = emitAck(host, 'party:selectMedia', { mediaItemId: 'latest' })
    await latestSource.arrived.promise
    latestSource.release.resolve()
    firstGate.release.resolve()
    assert.deepEqual(await firstAck, { error: 'media selection superseded' })
    assert.deepEqual(await latestAck, { ok: true })
    let session = (await emitAck(host, 'party:resume')).session
    assert.equal(session.mediaItemId, 'latest')
    assert.equal(session.playback.playSessionId, 'play-latest')
    assert.equal(session.playback.selectedAudioIndex, 5)
    assert.equal(session.playback.selectedSubtitleIndex, 11)

    assert.deepEqual(await emitAck(host, 'party:backToLobby'), { ok: true })
    const lobbyGate = holdPlayback('after-lobby')
    const lobbySelection = emitAck(host, 'party:selectMedia', { mediaItemId: 'after-lobby' })
    await lobbyGate.arrived.promise
    assert.deepEqual(await emitAck(host, 'party:backToLobby'), { ok: true })
    lobbyGate.release.resolve()
    assert.deepEqual(await lobbySelection, { error: 'media selection superseded' })
    session = (await emitAck(host, 'party:resume')).session
    assert.equal(session.stage, 'lobby')
    assert.equal(session.mediaItemId, null)
    assert.equal(session.playback, null)

    assert.equal((await emitAck(guest, 'party:join', { partyId: created.partyId })).status, 'waiting')
    session = (await emitAck(host, 'party:resume')).session
    const guestId = session.waiting[0].userId
    assert.deepEqual(await emitAck(host, 'party:approve', { userId: guestId }), { ok: true })

    const transferGate = holdPlayback('after-transfer')
    const transferredSelection = emitAck(host, 'party:selectMedia', { mediaItemId: 'after-transfer' })
    await transferGate.arrived.promise
    assert.deepEqual(await emitAck(host, 'party:transferHost', { userId: guestId }), { ok: true })
    transferGate.release.resolve()
    assert.deepEqual(await transferredSelection, { error: 'media selection superseded' })
    session = (await emitAck(guest, 'party:resume')).session
    assert.equal(session.hostId, guestId)
    assert.equal(session.stage, 'lobby')
    assert.equal(session.mediaItemId, null)

    const endGate = holdPlayback('after-end')
    const endedSelection = emitAck(guest, 'party:selectMedia', { mediaItemId: 'after-end' })
    await endGate.arrived.promise
    assert.deepEqual(await emitAck(guest, 'party:end'), { ok: true })
    endGate.release.resolve()
    assert.deepEqual(await endedSelection, { error: 'not allowed' })
    assert.equal((await emitAck(guest, 'party:resume')).session, null)
  } finally {
    for (const socket of sockets) socket.disconnect()
    child.kill('SIGTERM')
    await Promise.race([
      new Promise(resolve => child.once('exit', resolve)),
      delay(1000).then(() => child.kill('SIGKILL')),
    ])
    await new Promise(resolve => jellyfin.close(resolve))
    rmSync(scratch, { recursive: true, force: true })
  }
})
