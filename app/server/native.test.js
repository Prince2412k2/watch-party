import test from 'node:test'
import assert from 'node:assert/strict'
import { buildNativeStreamTarget } from './native.js'

test('native stream targets the selected Jellyfin media source', () => {
  const target = buildNativeStreamTarget({
    baseUrl: 'http://jellyfin:8096',
    itemId: 'movie/item',
    mediaSourceId: '4k source',
    jellyfinToken: 'secret token',
  })

  assert.equal(
    target,
    'http://jellyfin:8096/Videos/movie%2Fitem/stream?static=true&mediaSourceId=4k%20source&api_key=secret%20token',
  )
})
