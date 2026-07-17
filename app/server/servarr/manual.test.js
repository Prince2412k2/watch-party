import test from 'node:test'
import assert from 'node:assert/strict'

import {
  parseMagnet, parseManualSubmission, storeTorrent, takeTorrent, torrentCallbackUrl,
} from './manual.js'

test('parseMagnet accepts BitTorrent info hashes and rejects other URLs', () => {
  const magnet = 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Example'
  assert.equal(parseMagnet(magnet), magnet)
  assert.equal(parseMagnet('https://example.test/file.torrent'), null)
  assert.equal(parseMagnet('magnet:?dn=missing-hash'), null)
})

test('parseManualSubmission validates service targets and episode coordinates', () => {
  assert.deepEqual(parseManualSubmission({ service: 'radarr', title: 'Movie.2026.1080p', targetId: '7' }), {
    value: { service: 'radarr', title: 'Movie.2026.1080p', targetId: 7, seasonNumber: null, episodeNumber: null },
  })
  assert.equal(parseManualSubmission({ service: 'sonarr', title: 'Show.S01E02', targetId: 8, episodeNumber: 2 }).error,
    'episodeNumber requires a seasonNumber and must be a positive integer')
  assert.equal(parseManualSubmission({ service: 'other', title: 'Release', targetId: 1 }).error,
    'service must be radarr or sonarr')
})

test('torrent capabilities are single-use and callback URLs use configured origin', () => {
  const previous = process.env.SERVARR_TORRENT_CALLBACK_URL
  process.env.SERVARR_TORRENT_CALLBACK_URL = 'https://watch.example.test'
  try {
    const bytes = Buffer.from('d4:infode')
    const token = storeTorrent(bytes)
    assert.equal(torrentCallbackUrl(token), `https://watch.example.test/api/servarr/manual/torrents/${token}`)
    assert.deepEqual(takeTorrent(token), bytes)
    assert.equal(takeTorrent(token), null)
  } finally {
    if (previous === undefined) delete process.env.SERVARR_TORRENT_CALLBACK_URL
    else process.env.SERVARR_TORRENT_CALLBACK_URL = previous
  }
})
