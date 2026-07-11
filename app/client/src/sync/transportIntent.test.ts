import test from 'node:test'
import assert from 'node:assert/strict'
import { createTransportIntent } from './transportIntent.ts'

test('ignores media events that were not caused by an explicit interaction', () => {
  const intent = createTransportIntent()

  assert.equal(intent.consume('pause'), false)
  assert.equal(intent.consume('play'), false)
  assert.equal(intent.consume('seek'), false)
})

test('an explicit intent authorizes only its matching media event once', () => {
  const intent = createTransportIntent()

  intent.arm('pause')
  assert.equal(intent.consume('play'), false)
  assert.equal(intent.consume('pause'), true)
  assert.equal(intent.consume('pause'), false)
})
