import test from 'node:test'
import assert from 'node:assert/strict'
import { rmSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'
import express from 'express'

const databasePath = join(tmpdir(), `watchparty-servarr-${process.pid}-${Date.now()}.sqlite`)
process.env.PARTY_DB_PATH = databasePath
process.env.SESSION_SECRET = 'test-picker-secret'

const { registerServarrRoutes } = await import('./index.js')
const { radarr, sonarr } = await import('./arr.js')
const {
  activatePickerLease, beginPickerLease, claimPickerCancellation,
  markPickerCancelPending, pickerToken, validatePickerToken,
} = await import('./picker.js')

const originalRadarr = { ...radarr }
const originalSonarr = { ...sonarr }
let operationSequence = 0

const operationId = (prefix = 'operation') => `${prefix}-${++operationSequence}-abcdefgh`

function startServer() {
  const app = express()
  app.use(express.json())
  app.use((req, _res, next) => {
    // Acquisition routes are admin-only (see ../auth.js), so the default test
    // identity is an admin whose role was checked just now — the picker suite
    // below is about leases, not authorisation. `x-test-admin: 0` opts a request
    // out, which is what the gate tests use.
    req.session = {
      jellyfin: {
        userId: req.get('x-test-user') || 'user-a',
        isAdmin: req.get('x-test-admin') !== '0',
        adminCheckedAt: Date.now(),
      },
    }
    next()
  })
  registerServarrRoutes(app)
  return new Promise((resolve) => {
    const server = app.listen(0, '127.0.0.1', () => {
      const { port } = server.address()
      resolve({ server, origin: `http://127.0.0.1:${port}` })
    })
  })
}

async function post(origin, path, body, user = 'user-a') {
  const response = await fetch(`${origin}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-test-user': user },
    body: JSON.stringify(body),
  })
  return { response, body: await response.json() }
}

async function openMoviePicker(origin, id, { user = 'user-a', op = operationId('movie') } = {}) {
  radarr.add = async () => ({ id, title: 'Movie' })
  radarr.releaseSearch = async () => []
  return post(origin, '/api/servarr/radarr/releases', {
    operationId: op,
    movie: { tmdbId: id, title: 'Movie' },
    qualityProfileId: 1,
    rootFolderPath: '/movies',
  }, user)
}

async function openSeriesPicker(origin, id, { user = 'user-a', op = operationId('series') } = {}) {
  sonarr.add = async () => ({ id, title: 'Series' })
  sonarr.releaseSearch = async () => []
  return post(origin, '/api/servarr/sonarr/releases', {
    operationId: op,
    series: { tvdbId: id, title: 'Series' },
    qualityProfileId: 1,
    rootFolderPath: '/series',
    seasonNumber: 1,
  }, user)
}

test.before(() => {
  process.env.RADARR_URL = 'http://radarr.test'
  process.env.RADARR_API_KEY = 'radarr-key'
  process.env.SONARR_URL = 'http://sonarr.test'
  process.env.SONARR_API_KEY = 'sonarr-key'
})

test.after(() => {
  for (const suffix of ['', '-shm', '-wal']) {
    try { rmSync(databasePath + suffix) } catch (err) {
      if (err.code !== 'ENOENT') throw err
    }
  }
  delete process.env.PARTY_DB_PATH
  delete process.env.SESSION_SECRET
  delete process.env.RADARR_URL
  delete process.env.RADARR_API_KEY
  delete process.env.SONARR_URL
  delete process.env.SONARR_API_KEY
})

test.afterEach(() => {
  Object.assign(radarr, originalRadarr)
  Object.assign(sonarr, originalSonarr)
})

// Every route that can put something on the server's disk — or take it off —
// belongs to the admin. A signed-in member reaching one gets 403 and, crucially,
// NO upstream call: the gate has to run before Radarr/Sonarr/qBittorrent hear
// about the request at all, or a rejected member could still start a download.
test('acquisition routes are closed to a non-admin member, without touching upstream', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())

  let upstreamCalls = 0
  const count = async () => { upstreamCalls += 1; return { id: 1, title: 'x' } }
  for (const client of [radarr, sonarr]) {
    Object.assign(client, {
      add: count, remove: count, lookup: count, library: count, discover: count,
      releaseSearch: count, grabRelease: count, get: count, queue: count,
      update: count, episodes: count, command: count, pushRelease: count,
    })
  }

  const gated = [
    ['POST', '/api/servarr/radarr/add'],
    ['POST', '/api/servarr/radarr/request'],
    ['POST', '/api/servarr/radarr/releases'],
    ['POST', '/api/servarr/radarr/grab'],
    ['POST', '/api/servarr/radarr/releases/cancel'],
    ['POST', '/api/servarr/sonarr/add'],
    ['POST', '/api/servarr/sonarr/request'],
    ['POST', '/api/servarr/sonarr/request-season'],
    ['POST', '/api/servarr/sonarr/releases'],
    ['POST', '/api/servarr/sonarr/grab'],
    ['POST', '/api/servarr/sonarr/auto-season'],
    ['POST', '/api/servarr/sonarr/releases/cancel'],
    ['POST', '/api/servarr/sonarr/resolve'],
    ['POST', '/api/servarr/manual/magnet'],
    ['POST', '/api/servarr/qbittorrent/pause'],
    ['POST', '/api/servarr/qbittorrent/resume'],
    ['POST', '/api/servarr/qbittorrent/delete'],
    ['GET', '/api/servarr/radarr/discover'],
    ['GET', '/api/servarr/radarr/popular'],
    ['GET', '/api/servarr/sonarr/discover'],
    ['GET', '/api/servarr/sonarr/popular'],
    ['DELETE', '/api/servarr/radarr/movie/1'],
    ['DELETE', '/api/servarr/sonarr/series/1'],
    ['DELETE', '/api/servarr/radarr/queue/1'],
    ['DELETE', '/api/servarr/sonarr/queue/1'],
  ]

  for (const [method, path] of gated) {
    const response = await fetch(`${origin}${path}`, {
      method,
      headers: { 'content-type': 'application/json', 'x-test-admin': '0' },
      body: method === 'GET' ? undefined : JSON.stringify({}),
    })
    assert.equal(response.status, 403, `${method} ${path} should be admin-only`)
  }
  assert.equal(upstreamCalls, 0)
})

// The other half of the gate: a member can still see everything they need in
// order to watch. Closing these would break the library, not just Discover.
test('read-only routes stay open to a non-admin member', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  radarr.library = async () => []
  sonarr.library = async () => []
  sonarr.lookup = async () => []

  for (const path of [
    '/api/servarr/health',
    '/api/servarr/radarr/movies',
    '/api/servarr/sonarr/series',
    '/api/servarr/sonarr/search?term=anything',
  ]) {
    const response = await fetch(`${origin}${path}`, { headers: { 'x-test-admin': '0' } })
    assert.notEqual(response.status, 403, `GET ${path} should stay open to a member`)
  }
})

test('forged createdByPicker cannot authorize cancellation', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  let upstreamCalls = 0
  radarr.get = async () => { upstreamCalls += 1; return { id: 41, hasFile: false } }
  radarr.remove = async () => { upstreamCalls += 1 }

  const { response } = await post(origin, '/api/servarr/radarr/releases/cancel', {
    movieId: 41,
    createdByPicker: true,
  })

  assert.equal(response.status, 409)
  assert.equal(upstreamCalls, 0)
})

test('capabilities reject the wrong user, record, and service without being consumed', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  const opened = await openMoviePicker(origin, 42)
  const token = opened.body.cancellationToken
  assert.equal((await post(origin, '/api/servarr/radarr/releases/cancel', { movieId: 42, cancellationToken: token }, 'user-b')).response.status, 409)
  assert.equal((await post(origin, '/api/servarr/radarr/releases/cancel', { movieId: 999, cancellationToken: token })).response.status, 409)
  assert.equal((await post(origin, '/api/servarr/sonarr/releases/cancel', { seriesId: 42, cancellationToken: token })).response.status, 409)

  radarr.get = async () => ({ id: 42, hasFile: false })
  radarr.queue = async () => ({ records: [] })
  radarr.remove = async () => {}
  const owner = await post(origin, '/api/servarr/radarr/releases/cancel', { movieId: 42, cancellationToken: token })
  assert.equal(owner.body.removed, true)
  assert.equal((await post(origin, '/api/servarr/radarr/releases/cancel', {
    movieId: 42, cancellationToken: token,
  })).response.status, 409)
})

test('queue lookup failure is retryable and preserves cancellation authority', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  const opened = await openMoviePicker(origin, 43)
  let queueCalls = 0
  let removed = 0
  radarr.get = async () => ({ id: 43, hasFile: false })
  radarr.queue = async () => {
    queueCalls += 1
    if (queueCalls === 1) throw new Error('queue unavailable')
    return { records: [] }
  }
  radarr.remove = async () => { removed += 1 }
  const payload = { movieId: 43, cancellationToken: opened.body.cancellationToken }

  const failed = await post(origin, '/api/servarr/radarr/releases/cancel', payload)
  assert.equal(failed.response.status, 503)
  assert.equal(failed.body.retryable, true)
  assert.equal(removed, 0)

  const retried = await post(origin, '/api/servarr/radarr/releases/cancel', payload)
  assert.equal(retried.response.status, 200)
  assert.equal(retried.body.removed, true)
  assert.equal(removed, 1)
})

test('successful grab settles cancellation authority and is idempotent', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  const opened = await openMoviePicker(origin, 44)
  let grabs = 0
  let finishGrab
  let signalStarted
  const started = new Promise((resolve) => { signalStarted = resolve })
  radarr.grabRelease = async () => {
    grabs += 1
    signalStarted()
    await new Promise((resolve) => { finishGrab = resolve })
  }
  const payload = {
    movieId: 44,
    guid: 'release-guid',
    indexerId: 1,
    cancellationToken: opened.body.cancellationToken,
  }

  const firstGrab = post(origin, '/api/servarr/radarr/grab', payload)
  await started
  assert.equal((await post(origin, '/api/servarr/radarr/grab', payload)).response.status, 409)
  assert.equal((await post(origin, '/api/servarr/radarr/releases/cancel', {
    movieId: 44,
    cancellationToken: opened.body.cancellationToken,
  })).response.status, 409)
  finishGrab()
  assert.equal((await firstGrab).response.status, 200)
  assert.equal((await post(origin, '/api/servarr/radarr/grab', payload)).response.status, 200)
  assert.equal(grabs, 1)
  const cancelled = await post(origin, '/api/servarr/radarr/releases/cancel', {
    movieId: 44,
    cancellationToken: opened.body.cancellationToken,
  })
  assert.equal(cancelled.response.status, 409)
})

test('another active picker lease prevents owner deletion until it closes', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  let adds = 0
  radarr.add = async () => {
    adds += 1
    if (adds === 1) return { id: 45, title: 'Shared Movie' }
    throw Object.assign(new Error('exists'), { status: 400, body: 'already exists' })
  }
  radarr.library = async () => [{ id: 45, tmdbId: 45 }]
  radarr.releaseSearch = async () => []
  const request = (op) => ({
    operationId: op,
    movie: { tmdbId: 45, title: 'Shared Movie' },
    qualityProfileId: 1,
    rootFolderPath: '/movies',
  })
  const owner = await post(origin, '/api/servarr/radarr/releases', request(operationId('owner')), 'user-a')
  const viewer = await post(origin, '/api/servarr/radarr/releases', request(operationId('viewer')), 'user-b')
  let removed = 0
  radarr.get = async () => ({ id: 45, hasFile: false })
  radarr.queue = async () => ({ records: [] })
  radarr.remove = async () => { removed += 1 }

  const blocked = await post(origin, '/api/servarr/radarr/releases/cancel', {
    movieId: 45, cancellationToken: owner.body.cancellationToken,
  }, 'user-a')
  assert.equal(blocked.response.status, 409)
  assert.equal(blocked.body.retryable, true)
  assert.equal(removed, 0)

  const released = await post(origin, '/api/servarr/radarr/releases/cancel', {
    movieId: 45, cancellationToken: viewer.body.cancellationToken,
  }, 'user-b')
  assert.equal(released.response.status, 200)
  assert.equal(released.body.removed, true)
  assert.equal(removed, 1)
})

test('operation replay reuses one shell and one durable lease', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  let adds = 0
  radarr.add = async () => { adds += 1; return { id: 46, title: 'Movie' } }
  radarr.releaseSearch = async () => []
  const body = {
    operationId: operationId('strict-mode'),
    movie: { tmdbId: 46, title: 'Movie' },
    qualityProfileId: 1,
    rootFolderPath: '/movies',
  }
  const first = await post(origin, '/api/servarr/radarr/releases', body)
  const replay = await post(origin, '/api/servarr/radarr/releases', body)

  assert.equal(first.response.status, 200)
  assert.equal(replay.response.status, 200)
  assert.equal(adds, 1)
  assert.equal(replay.body.movieId, first.body.movieId)
  assert.equal(replay.body.cancellationToken, first.body.cancellationToken)
})

test('Sonarr uses the same cancellation and post-grab settlement semantics', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  const cancelledSeries = await openSeriesPicker(origin, 51)
  sonarr.get = async () => ({ id: 51, statistics: { sizeOnDisk: 0, episodeFileCount: 0 } })
  sonarr.queue = async () => ({ records: [] })
  let removals = 0
  sonarr.remove = async () => { removals += 1 }
  const cancelled = await post(origin, '/api/servarr/sonarr/releases/cancel', {
    seriesId: 51, cancellationToken: cancelledSeries.body.cancellationToken,
  })
  assert.equal(cancelled.body.removed, true)
  assert.equal(removals, 1)

  const grabbedSeries = await openSeriesPicker(origin, 52)
  sonarr.get = async () => ({ id: 52, title: 'Series', seasons: [{ seasonNumber: 1, monitored: false }] })
  sonarr.update = async () => ({})
  sonarr.grabRelease = async () => ({})
  const grab = await post(origin, '/api/servarr/sonarr/grab', {
    seriesId: 52,
    seasonNumber: 1,
    guid: 'series-release',
    indexerId: 1,
    cancellationToken: grabbedSeries.body.cancellationToken,
  })
  assert.equal(grab.response.status, 200)
  assert.equal((await post(origin, '/api/servarr/sonarr/releases/cancel', {
    seriesId: 52, cancellationToken: grabbedSeries.body.cancellationToken,
  })).response.status, 409)
})

test('signed picker capabilities expire', () => {
  const begun = beginPickerLease({
    operationId: operationId('expiry'),
    service: 'radarr',
    userId: 'expiry-user',
    now: 100,
    ttlMs: 10,
  })
  const lease = activatePickerLease(begun.lease.id, 60, true, 100)
  const token = pickerToken(lease)
  assert.ok(validatePickerToken(token, { service: 'radarr', recordId: 60, userId: 'expiry-user', now: 109 }))
  assert.equal(validatePickerToken(token, { service: 'radarr', recordId: 60, userId: 'expiry-user', now: 110 }), null)
})

test('a cancellation claim blocks new and opening leases for the same record', () => {
  const owner = activatePickerLease(beginPickerLease({
    operationId: operationId('mutex-owner'), service: 'radarr', userId: 'owner',
  }).lease.id, 61, true)
  markPickerCancelPending(owner.id)
  assert.equal(claimPickerCancellation(owner.id), true)

  assert.throws(() => beginPickerLease({
    operationId: operationId('mutex-viewer'), service: 'radarr', recordId: 61, userId: 'viewer',
  }), error => error.retryable === true)

  const opening = beginPickerLease({
    operationId: operationId('mutex-opening'), service: 'radarr', userId: 'viewer',
  })
  assert.throws(
    () => activatePickerLease(opening.lease.id, 61, false),
    error => error.retryable === true,
  )
})

test('production catalog responses expose only hardened artwork proxy paths', async (t) => {
  const { server, origin } = await startServer()
  t.after(() => server.close())
  const rawMovieUrl = 'https://image.tmdb.org/t/p/w500/movie.jpg'
  const rawSeriesUrl = 'https://artworks.thetvdb.com/banners/series.jpg'
  radarr.lookup = async () => [{
    tmdbId: 1,
    title: 'Movie',
    images: [{ coverType: 'poster', remoteUrl: rawMovieUrl, url: '/MediaCover/1/poster.jpg' }],
  }]
  sonarr.lookup = async () => [{
    tvdbId: 2,
    title: 'Series',
    images: [{ coverType: 'poster', remoteUrl: rawSeriesUrl, url: '/MediaCover/2/poster.jpg' }],
  }]

  for (const path of ['/api/servarr/radarr/search?term=movie', '/api/servarr/sonarr/search?term=series']) {
    const response = await fetch(`${origin}${path}`, { headers: { 'x-test-user': 'user-a' } })
    assert.equal(response.status, 200)
    const text = await response.text()
    assert.doesNotMatch(text, /https:\/\/(?:image\.tmdb\.org|artworks\.thetvdb\.com)/)
    assert.doesNotMatch(text, /MediaCover/)
    const [entry] = JSON.parse(text)
    assert.match(entry.images[0].remoteUrl, /^\/api\/servarr\/(?:remote-image|image)\?/)
    assert.equal('url' in entry.images[0], false)
  }
})
