import test from 'node:test'
import assert from 'node:assert/strict'

import {
  findExternalSubtitleStream,
  findNewExternalSubtitle,
  pollForNewExternalSubtitle,
  registerSubtitleRoutes,
  resolveJellyfinDeliveryUrl,
  srtToVtt,
  subtitleTextToVtt,
  subtitleMutationError,
} from './subtitles.js'
import { createSession, deleteSession } from './session.js'

function deferred() {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}

test('srtToVtt removes sequence numbers and converts comma timestamps', () => {
  const result = srtToVtt('\uFEFF1\r\n00:00:01,250 --> 00:00:03,500\r\nHello!\r\n\r\n2\r\n00:01:02,000 --> 00:01:05,125\r\nAgain')
  assert.equal(result, 'WEBVTT\n\n00:00:01.250 --> 00:00:03.500\nHello!\n\n00:01:02.000 --> 00:01:05.125\nAgain\n')
})

test('subtitleTextToVtt preserves WebVTT and converts SRT response content', () => {
  assert.equal(subtitleTextToVtt('\uFEFFWEBVTT\r\n\r\n00:01.000 --> 00:02.000\r\nHi'), 'WEBVTT\n\n00:01.000 --> 00:02.000\nHi\n')
  assert.equal(subtitleTextToVtt('1\n00:00:01,000 --> 00:00:02,500\nHi'), 'WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nHi\n')
})

test('findNewExternalSubtitle ignores existing and embedded tracks', () => {
  const before = { MediaSources: [{ Id: 'source', MediaStreams: [{ Type: 'Subtitle', Index: 2, IsExternal: true }] }] }
  const after = { MediaSources: [{ Id: 'source', MediaStreams: [
    { Type: 'Subtitle', Index: 2, IsExternal: true },
    { Type: 'Subtitle', Index: 3, IsExternal: false },
    { Type: 'Subtitle', Index: 4, IsExternal: true },
  ] }] }
  assert.equal(findNewExternalSubtitle(before, after, 'source')?.Index, 4)
})

test('pollForNewExternalSubtitle retries stale playback with a finite schedule', async () => {
  const before = { MediaSources: [{ MediaStreams: [] }] }
  const fresh = { MediaSources: [{ MediaStreams: [{ Type: 'Subtitle', Index: 8, IsExternal: true }] }] }
  const responses = [before, before, fresh]
  const waits = []
  const result = await pollForNewExternalSubtitle(() => Promise.resolve(responses.shift()), before, {
    delays: [0, 10, 20, 40],
    wait: ms => { waits.push(ms); return Promise.resolve() },
  })
  assert.equal(result.stream?.Index, 8)
  assert.deepEqual(waits, [10, 20])
})

test('findExternalSubtitleStream requires an exact external stream index with a delivery URL', () => {
  const playback = { MediaSources: [{ MediaStreams: [
    { Type: 'Subtitle', Index: 4, IsExternal: false, DeliveryUrl: '/Videos/a/Subtitles/4/Stream.vtt' },
    { Type: 'Subtitle', Index: 7, IsExternal: true, DeliveryUrl: '/Videos/a/Subtitles/7/Stream.vtt' },
    { Type: 'Audio', Index: 7, IsExternal: true, DeliveryUrl: '/audio' },
  ] }] }

  assert.equal(findExternalSubtitleStream(playback, 7)?.Index, 7)
  assert.equal(findExternalSubtitleStream(playback, 4), null)
  assert.equal(findExternalSubtitleStream(playback, 8), null)
})

test('resolveJellyfinDeliveryUrl accepts only URLs under the configured Jellyfin base', () => {
  const relative = resolveJellyfinDeliveryUrl('/jellyfin/Videos/a/Subtitles/7/Stream.vtt?api_key=client', 'server-token', 'https://media.test/jellyfin')
  assert.equal(relative?.href, 'https://media.test/jellyfin/Videos/a/Subtitles/7/Stream.vtt?api_key=server-token')

  assert.equal(resolveJellyfinDeliveryUrl('https://evil.test/subtitle.vtt', 'token', 'https://media.test/jellyfin'), null)
  assert.equal(resolveJellyfinDeliveryUrl('/outside/subtitle.vtt', 'token', 'https://media.test/jellyfin'), null)
  assert.equal(resolveJellyfinDeliveryUrl('/jellyfin/../outside/subtitle.vtt', 'token', 'https://media.test/jellyfin'), null)
})

test('subtitleMutationError maps Jellyfin client and server failures safely', () => {
  assert.deepEqual(subtitleMutationError(400), { status: 422, error: 'Jellyfin rejected the subtitle file' })
  assert.equal(subtitleMutationError(403).status, 403)
  assert.equal(subtitleMutationError(404).status, 404)
  assert.equal(subtitleMutationError(500).status, 502)
  assert.equal(subtitleMutationError(undefined).status, 502)
})

test('party subtitle uploads serialize their Jellyfin snapshot and mutation', async () => {
  const routes = new Map()
  const app = {
    get() {},
    delete() {},
    post(path, ...handlers) { routes.set(path, handlers.at(-1)) },
  }
  let queue = Promise.resolve()
  const enqueuePlaybackMutation = (_session, operation) => {
    const current = queue.then(operation, operation)
    queue = current.catch(() => {})
    return current
  }
  registerSubtitleRoutes(app, { to: () => ({ emit() {} }) }, { enqueuePlaybackMutation })

  const session = createSession({
    hostId: 'subtitle-host',
    hostToken: 'token',
    hostDeviceId: 'device',
    hostName: 'Host',
    hostSocketId: 'socket',
    mediaItemId: 'movie',
    mediaSourceId: 'source',
  })
  session.playback = { selectedAudioIndex: null, playSessionId: 'play' }
  const mutationStarted = deferred()
  const releaseMutation = deferred()
  const originalFetch = globalThis.fetch
  const subtitles = []
  let playbackReads = 0
  let mutations = 0
  globalThis.fetch = async (input, init = {}) => {
    const path = new URL(input).pathname
    if (path.endsWith('/Subtitles')) {
      mutations++
      if (mutations === 1) {
        mutationStarted.resolve()
        await releaseMutation.promise
      }
      subtitles.push(9 + mutations)
      return new Response(null, { status: 204 })
    }
    if (path.endsWith('/PlaybackInfo')) {
      playbackReads++
      return Response.json({
        PlaySessionId: 'play',
        MediaSources: [{
          Id: 'source',
          DirectStreamUrl: '/Videos/movie/stream',
          MediaStreams: subtitles.map(Index => ({ Type: 'Subtitle', Index, IsExternal: true })),
        }],
      })
    }
    throw new Error(`unexpected fetch ${init.method ?? 'GET'} ${path}`)
  }

  const request = filename => ({
    session: { jellyfin: { userId: 'subtitle-host', accessToken: 'token', deviceId: 'device' } },
    query: { mediaItemId: 'movie' },
    body: Buffer.from('WEBVTT\n\n00:00.000 --> 00:01.000\nHello'),
    get: name => ({
      'content-type': 'text/vtt',
      'x-subtitle-filename': filename,
      'x-subtitle-language': 'eng',
    })[name.toLowerCase()] ?? '',
  })
  const response = () => ({
    statusCode: 200,
    status(code) { this.statusCode = code; return this },
    json(body) { this.body = body; return this },
  })
  const upload = routes.get('/api/library/subtitles/upload')
  const firstResponse = response()
  const secondResponse = response()

  try {
    const first = upload(request('first.vtt'), firstResponse)
    await mutationStarted.promise
    const second = upload(request('second.vtt'), secondResponse)
    await new Promise(resolve => setImmediate(resolve))
    assert.equal(playbackReads, 1)

    releaseMutation.resolve()
    await Promise.all([first, second])
    assert.equal(firstResponse.statusCode, 201)
    assert.equal(secondResponse.statusCode, 201)
    assert.equal(firstResponse.body.subtitleStreamIndex, 10)
    assert.equal(secondResponse.body.subtitleStreamIndex, 11)
  } finally {
    globalThis.fetch = originalFetch
    deleteSession(session.id)
  }
})
