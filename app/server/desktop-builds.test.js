import test from 'node:test'
import assert from 'node:assert/strict'
import { contentTypeFor, detectPlatform, parseReleaseMetadata } from './desktop-builds.js'

test('detectPlatform exposes each packaged desktop installer', () => {
  assert.equal(detectPlatform('Watchparty-1.0.0-macos.dmg'), 'macos')
  assert.equal(detectPlatform('Watchparty-1.0.0-x86_64.AppImage'), 'linux')
  assert.equal(detectPlatform('Watchparty-1.0.0-windows-setup.exe'), 'windows')
  assert.equal(detectPlatform('SHA256SUMS'), null)
})

test('AppImage downloads use the AppImage media type', () => {
  assert.equal(contentTypeFor('Watchparty.AppImage'), 'application/vnd.appimage')
})

const metadata = {
  version: '1.0.0-main.42',
  build: 42,
  commit: 'a'.repeat(40),
  builtAt: '2026-07-18T12:00:00Z',
  artifacts: {
    macos: { filename: 'Watchparty-1.0.0-macos.dmg', size: 10, sha256: '1'.repeat(64) },
    windows: { filename: 'Watchparty-1.0.0-windows-setup.exe', size: 11, sha256: '2'.repeat(64) },
    linux: { filename: 'Watchparty-1.0.0-x86_64.AppImage', size: 12, sha256: '3'.repeat(64) },
  },
}

test('release metadata accepts complete platform artifacts', () => {
  assert.deepEqual(parseReleaseMetadata(metadata), metadata)
})

test('release metadata rejects traversal and malformed hashes', () => {
  assert.throws(() => parseReleaseMetadata({
    ...metadata,
    artifacts: { ...metadata.artifacts, linux: { ...metadata.artifacts.linux, filename: '../bad.AppImage' } },
  }))
  assert.throws(() => parseReleaseMetadata({
    ...metadata,
    artifacts: { ...metadata.artifacts, macos: { ...metadata.artifacts.macos, sha256: 'unsigned' } },
  }))
})
