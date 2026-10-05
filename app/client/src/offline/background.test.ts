import test from 'node:test'
import assert from 'node:assert/strict'
import 'fake-indexeddb/auto'
import {
  startBackground,
  finishBackground,
  backgroundResponse,
  mediaRequest,
  type BackgroundJob,
  type BackgroundRegistration
} from './background.ts'
import {
  CHUNK_SIZE,
  prepare,
  putChunk,
  getMedia,
  setOwner,
  updateMedia,
  removeMedia,
  chunk
} from './storage.ts'
const movie = (itemId: string) => ({
  owner: 'alice',
  itemId,
  sourceId: 'source',
  revision: 'one',
  size: CHUNK_SIZE + 3,
  title: 'Movie',
  series: '',
  duration: 120,
  audioIndex: 1,
  etag: '"one"',
  modified: '',
  subtitles: []
})
const job = (
  id: string,
  requests: Request[],
  result: 'success' | 'failure' = 'success'
): BackgroundJob => ({
  id,
  downloaded: 3,
  result,
  failureReason: '',
  recordsAvailable: true,
  abort: async () => true,
  matchAll: async () =>
    requests.map((request) => ({
      request,
      responseReady: Promise.resolve(
        new Response('end', {
          status: 206,
          headers: {
            'content-range': `bytes ${CHUNK_SIZE}-${CHUNK_SIZE + 2}/${CHUNK_SIZE + 3}`
          }
        })
      )
    }))
})
test('background transfer reuses watched chunks and imports only validated missing ranges', async () => {
  await setOwner('alice')
  const file = await prepare(movie('background'), 'download')
  await putChunk(file, 0, new Blob([new Uint8Array(CHUNK_SIZE)]))
  await updateMedia(
    file.key,
    (value) => value && { ...value, resumeOnOpen: true, state: 'downloading' }
  )
  let requests: Request[] = []
  let downloadTotal = 0
  let id = ''
  const registration = {
    backgroundFetch: {
      get: async () => undefined,
      fetch: async (
        value: string,
        parts: Request[],
        options: { downloadTotal: number }
      ) => {
        id = value
        requests = parts
        downloadTotal = options.downloadTotal
        return job(value, parts)
      }
    }
  } as unknown as BackgroundRegistration
  assert.equal(
    await startBackground(
      registration,
      (await getMedia(file.key))!,
      'https://example.test'
    ),
    true
  )
  assert.equal(requests.length, 1)
  assert.equal(downloadTotal, 3)
  assert.equal(
    requests[0].headers.get('range'),
    `bytes=${CHUNK_SIZE}-${CHUNK_SIZE + 2}`
  )
  assert.equal(requests[0].credentials, 'include')
  await finishBackground(job(id, requests))
  assert.equal((await getMedia(file.key))?.state, 'complete')
  assert.equal((await getMedia(file.key))?.received, file.size)
  assert.equal((await getMedia(file.key))?.backgroundId, undefined)
})
test('browser rejection falls back without losing the download intent', async () => {
  const file = await prepare(movie('rejected'), 'download')
  await updateMedia(
    file.key,
    (value) => value && { ...value, resumeOnOpen: true }
  )
  const registration = {
    backgroundFetch: {
      get: async () => undefined,
      fetch: async () => {
        throw new DOMException('denied', 'NotAllowedError')
      }
    }
  } as unknown as BackgroundRegistration
  assert.equal(
    await startBackground(registration, file, 'https://example.test'),
    false
  )
  const current = await getMedia(file.key)
  assert.equal(current?.backgroundId, undefined)
  assert.equal(current?.retention, 'download')
  assert.equal(current?.resumeOnOpen, true)
})
test('late background completion cannot recreate a removed movie or import for another account', async () => {
  await setOwner('alice')
  for (const scenario of ['removed', 'changed-account']) {
    const file = await prepare(movie(scenario), 'download')
    const id = `watchparty-media:${file.generation}:${encodeURIComponent(file.key)}`
    await updateMedia(
      file.key,
      (value) => value && { ...value, backgroundId: id, resumeOnOpen: true }
    )
    if (scenario === 'removed') {
      await removeMedia(file.key)
      await prepare(movie(scenario), 'download')
    } else await setOwner('bob')
    await finishBackground(
      job(id, [mediaRequest(file, 1, 'https://example.test')])
    )
    assert.equal(await chunk(file.key, 1), undefined)
  }
  await setOwner('alice')
})
test('wrong range and truncated background responses never become playable saved chunks', async () => {
  const file = await prepare(movie('bad-response'), 'download')
  const id = `watchparty-media:${file.generation}:${encodeURIComponent(file.key)}`
  await updateMedia(
    file.key,
    (value) => value && { ...value, backgroundId: id, resumeOnOpen: true }
  )
  const bad = job(id, [mediaRequest(file, 1, 'https://example.test')])
  for (const response of [
    new Response('bad', { status: 200 }),
    new Response('no', {
      status: 206,
      headers: {
        'content-range': `bytes ${CHUNK_SIZE}-${CHUNK_SIZE + 2}/${CHUNK_SIZE + 3}`
      }
    })
  ]) {
    await updateMedia(
      file.key,
      (current) =>
        current && { ...current, backgroundId: id, resumeOnOpen: true }
    )
    bad.matchAll = async () => [
      {
        request: mediaRequest(file, 1, 'https://example.test'),
        responseReady: Promise.resolve(response)
      }
    ]
    await finishBackground(bad)
    assert.equal(await chunk(file.key, 1), undefined)
    assert.equal((await getMedia(file.key))?.state, 'error')
    assert.match(
      (await getMedia(file.key))?.error || '',
      /changed|range|Incomplete/
    )
  }
})
test('manual pause preserves completed background chunks without restarting the transfer', async () => {
  const file = await prepare(movie('manual-pause'), 'download')
  const id = `watchparty-media:${file.generation}:${encodeURIComponent(file.key)}`
  await updateMedia(
    file.key,
    (value) =>
      value && {
        ...value,
        backgroundId: id,
        resumeOnOpen: false,
        state: 'paused'
      }
  )
  await finishBackground(
    job(id, [mediaRequest(file, 1, 'https://example.test')], 'failure')
  )
  assert.equal((await chunk(file.key, 1))?.size, 3)
  assert.equal((await getMedia(file.key))?.state, 'paused')
  assert.equal((await getMedia(file.key))?.resumeOnOpen, false)
})

test('playback can reuse a delivered background response without consuming its stored body', async () => {
  const file = await prepare(movie('background-playback'), 'download')
  const request = mediaRequest(file, 1, 'https://example.test'),
    response = new Response('end', {
      status: 206,
      headers: {
        'content-range': `bytes ${CHUNK_SIZE}-${CHUNK_SIZE + 2}/${CHUNK_SIZE + 3}`
      }
    })
  const active = { ...file, backgroundId: 'active' }
  const manager = {
    get: async () => ({
      ...job('active', []),
      match: async () => ({ request, responseReady: Promise.resolve(response) })
    })
  }
  const registration = {
    backgroundFetch: manager
  } as unknown as BackgroundRegistration
  const reused = await backgroundResponse(registration, active, request)
  assert.equal(await reused?.text(), 'end')
  assert.equal(response.bodyUsed, false)
})
