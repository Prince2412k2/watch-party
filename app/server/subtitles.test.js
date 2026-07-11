import test from 'node:test'
import assert from 'node:assert/strict'

import { srtToVtt } from './subtitles.js'

test('srtToVtt removes sequence numbers and converts comma timestamps', () => {
  const result = srtToVtt('\uFEFF1\r\n00:00:01,250 --> 00:00:03,500\r\nHello!\r\n\r\n2\r\n00:01:02,000 --> 00:01:05,125\r\nAgain')
  assert.equal(result, 'WEBVTT\n\n00:00:01.250 --> 00:00:03.500\nHello!\n\n00:01:02.000 --> 00:01:05.125\nAgain\n')
})
