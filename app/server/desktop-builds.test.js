import test from 'node:test'
import assert from 'node:assert/strict'
import { contentTypeFor, detectPlatform } from './desktop-builds.js'

test('detectPlatform exposes each packaged desktop installer', () => {
  assert.equal(detectPlatform('Watchparty-1.0.0-macos.dmg'), 'macos')
  assert.equal(detectPlatform('Watchparty-1.0.0-x86_64.AppImage'), 'linux')
  assert.equal(detectPlatform('Watchparty-1.0.0-windows-setup.exe'), 'windows')
  assert.equal(detectPlatform('SHA256SUMS'), null)
})

test('AppImage downloads use the AppImage media type', () => {
  assert.equal(contentTypeFor('Watchparty.AppImage'), 'application/vnd.appimage')
})
