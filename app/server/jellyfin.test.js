import test from 'node:test'
import assert from 'node:assert/strict'

import { buildHlsUrl } from './jellyfin.js'

test('HLS URLs ask Jellyfin to advertise subtitle renditions', () => {
  for (const options of [{ abr: true }, { maxBitrate: 1_500_000 }, {}]) {
    const url = new URL(buildHlsUrl('media-id', options), 'http://watch-party.test')

    assert.equal(url.searchParams.get('EnableSubtitlesInManifest'), 'true')
  }
})
