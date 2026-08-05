import test from 'node:test'
import assert from 'node:assert/strict'
import { mediaErrorMessage } from './mediaError.ts'

const denied = () => new DOMException('Permission denied', 'NotAllowedError')

test('a denied permission says what to do about it', () => {
  const msg = mediaErrorMessage('Camera', denied())
  assert.match(msg, /Camera access was blocked/)
  assert.match(msg, /site settings/)
})

test('a missing or busy device is named, not relayed as a DOMException', () => {
  assert.match(mediaErrorMessage('Microphone', new DOMException('x', 'NotFoundError')), /No microphone found/)
  assert.match(mediaErrorMessage('Camera', new DOMException('x', 'NotReadableError')), /already in use by another app/)
  assert.match(mediaErrorMessage('Camera', new DOMException('x', 'OverconstrainedError')), /No camera found/)
})

test('an insecure context outranks every device error', () => {
  // getUserMedia cannot succeed at all over plain http, so the device-level
  // message would only mislead.
  const msg = mediaErrorMessage('Camera', denied(), { secureContext: false })
  assert.match(msg, /secure \(HTTPS\) connection/)
})

test('an unrecognised failure still produces a visible message', () => {
  assert.equal(mediaErrorMessage('Camera', new Error('room disconnected')), 'room disconnected')
  assert.equal(mediaErrorMessage('Microphone', {}), 'Could not access your microphone.')
  assert.equal(mediaErrorMessage('Microphone', undefined), 'Could not access your microphone.')
  assert.equal(mediaErrorMessage('Camera', new Error('')), 'Could not access your camera.')
})
