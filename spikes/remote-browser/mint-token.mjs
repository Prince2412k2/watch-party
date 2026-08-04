// Mints the two tokens the spike needs: one for the in-container browser
// (publish only) and one for you (subscribe only). Reuses the repo's existing
// livekit-server-sdk and the same key/secret the app already runs on, so the
// spike joins the real LiveKit rather than standing up a second one.
//
//   node mint-token.mjs [room]
//
// Key/secret resolution order: environment, then secrets/.env, then the keys:
// block in secrets/livekit.yaml.

import { readFileSync, existsSync } from 'node:fs'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'

const ROOT = new URL('../../', import.meta.url)
const argv = process.argv.slice(2)
const flags = argv.filter(a => a.startsWith('--'))
const room = argv.find(a => !a.startsWith('--')) || 'spike-remote-browser'

function fromDotEnv() {
  const p = new URL('secrets/.env', ROOT)
  if (!existsSync(p)) return {}
  const out = {}
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    const m = /^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/.exec(line)
    if (m) out[m[1]] = m[2].trim().replace(/^["']|["']$/g, '')
  }
  return out
}

function fromLivekitYaml() {
  const p = new URL('secrets/livekit.yaml', ROOT)
  if (!existsSync(p)) return null
  const lines = readFileSync(p, 'utf8').split('\n')
  const at = lines.findIndex(l => /^keys:\s*$/.test(l))
  if (at === -1) return null
  for (const line of lines.slice(at + 1)) {
    if (/^\S/.test(line)) break            // dedented out of the keys: block
    const m = /^\s+([A-Za-z0-9_-]+)\s*:\s*(\S+)\s*$/.exec(line)
    if (m) return { key: m[1], secret: m[2] }
  }
  return null
}

const env = { ...fromDotEnv(), ...process.env }
let key = env.LIVEKIT_API_KEY
let secret = env.LIVEKIT_API_SECRET
if (!key || !secret) {
  const y = fromLivekitYaml()
  if (y) ({ key, secret } = y)
}
if (!key || !secret) {
  console.error('Could not find a LiveKit API key/secret.')
  console.error('Set LIVEKIT_API_KEY and LIVEKIT_API_SECRET, or put them in secrets/.env.')
  process.exit(1)
}

// The SDK lives in app/node_modules, not here.
const req = createRequire(new URL('app/package.json', ROOT))
const { AccessToken } = await import(pathToFileURL(req.resolve('livekit-server-sdk')).href)

async function mint(identity, grant) {
  const t = new AccessToken(key, secret, { identity, name: identity, ttl: '4h' })
  t.addGrant({ roomJoin: true, room, ...grant })
  return t.toJwt()
}

// The browser never needs to subscribe to anything — it only sends. Keeping
// canSubscribe false means a misconfigured container cannot quietly pull every
// participant's camera into a server-side browser.
const publisher = await mint('remote-browser', { canPublish: true, canSubscribe: false })
const viewer = await mint('spike-viewer', { canPublish: false, canSubscribe: true })

if (flags.includes('--publisher-only')) {
  process.stdout.write(publisher)
} else if (flags.includes('--viewer-only')) {
  process.stdout.write(viewer)
} else {
  console.log(`room:      ${room}`)
  console.log(`\nPUBLISHER (container, publish-only):\n${publisher}`)
  console.log(`\nVIEWER (you, subscribe-only):\n${viewer}`)
  console.log(`\nViewer URL — serve viewer/ and open:`)
  console.log(`  http://localhost:8899/viewer.html?lk=ws://localhost:7880&token=${viewer}`)
}
