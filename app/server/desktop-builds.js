// ── Desktop app build downloads ──────────────────────────────────────────────
// Serves the latest packaged desktop builds to logged-in
// users only. Two endpoints: `/api/downloads` lists what's on disk, and
// `/api/downloads/:filename` streams one file. Both sit behind requireAuth —
// these are real installers, not something to leave open on the internet.
import { createReadStream, existsSync, realpathSync, statSync } from 'fs'
import { readFile, readdir } from 'fs/promises'
import { basename, extname, join, resolve } from 'path'
import { requireAuth } from './auth.js'

const BUILDS_DIR = resolve(process.env.DESKTOP_BUILDS_DIR || '/opt/watch-party/builds/desktop/latest')

const MAC_EXT = new Set(['.dmg', '.pkg'])
const WIN_EXT = new Set(['.exe', '.msi'])
const RELEASE_FILE = 'release.json'
const PLATFORMS = ['macos', 'windows', 'linux']

export function detectPlatform(filename) {
  const ext = extname(filename).toLowerCase()
  if (MAC_EXT.has(ext)) return 'macos'
  if (WIN_EXT.has(ext)) return 'windows'
  if (ext === '.appimage') return 'linux'
  if (ext === '.zip') {
    const lower = filename.toLowerCase()
    if (lower.includes('mac') || lower.includes('darwin') || lower.includes('osx')) return 'macos'
    if (lower.includes('win')) return 'windows'
  }
  return null
}

const CONTENT_TYPES = {
  '.dmg': 'application/x-apple-diskimage',
  '.pkg': 'application/x-newton-compatible-pkg',
  '.exe': 'application/x-msdownload',
  '.msi': 'application/x-msi',
  '.appimage': 'application/vnd.appimage',
  '.zip': 'application/zip',
}

export function contentTypeFor(filename) {
  return CONTENT_TYPES[extname(filename).toLowerCase()] || 'application/octet-stream'
}

export function parseReleaseMetadata(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('metadata must be an object')
  const { version, build, commit, builtAt, artifacts } = value
  if (typeof version !== 'string' || !/^\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?$/.test(version)) throw new Error('invalid version')
  if (!Number.isSafeInteger(build) || build < 1) throw new Error('invalid build')
  if (typeof commit !== 'string' || !/^[0-9a-f]{40}$/.test(commit)) throw new Error('invalid commit')
  if (typeof builtAt !== 'string' || !Number.isFinite(Date.parse(builtAt))) throw new Error('invalid builtAt')
  if (!artifacts || typeof artifacts !== 'object' || Array.isArray(artifacts)) throw new Error('invalid artifacts')

  const safeArtifacts = {}
  for (const platform of PLATFORMS) {
    const artifact = artifacts[platform]
    if (!artifact || typeof artifact !== 'object') throw new Error(`missing ${platform} artifact`)
    const { filename, size, sha256 } = artifact
    if (typeof filename !== 'string' || basename(filename) !== filename || detectPlatform(filename) !== platform) {
      throw new Error(`invalid ${platform} filename`)
    }
    if (!Number.isSafeInteger(size) || size < 1) throw new Error(`invalid ${platform} size`)
    if (typeof sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(sha256)) throw new Error(`invalid ${platform} sha256`)
    safeArtifacts[platform] = { filename, size, sha256 }
  }
  return { version, build, commit, builtAt, artifacts: safeArtifacts }
}

async function currentRelease() {
  const raw = await readFile(join(BUILDS_DIR, RELEASE_FILE), 'utf8')
  const release = parseReleaseMetadata(JSON.parse(raw))
  for (const artifact of Object.values(release.artifacts)) {
    const path = resolveBuildPath(artifact.filename)
    if (!path || statSync(path).size !== artifact.size) throw new Error(`artifact does not match metadata: ${artifact.filename}`)
    artifact.url = `/api/downloads/${encodeURIComponent(artifact.filename)}`
  }
  return release
}

async function listBuilds() {
  let entries
  try {
    entries = await readdir(BUILDS_DIR, { withFileTypes: true })
  } catch {
    return [] // missing dir → no builds, not an error
  }

  const builds = []
  for (const entry of entries) {
    if (!entry.isFile()) continue
    const platform = detectPlatform(entry.name)
    if (!platform) continue
    const stat = statSync(join(BUILDS_DIR, entry.name))
    builds.push({ platform, filename: entry.name, size: stat.size, url: `/api/downloads/${encodeURIComponent(entry.name)}` })
  }
  return builds
}

// Resolves `requested` against BUILDS_DIR and returns the real path only if
// it names a regular file directly inside BUILDS_DIR. basename() strips any
// `..`/slashes from the input up front, and the realpath check afterward
// closes the remaining hole: a symlink living in BUILDS_DIR that points
// outside it. Returns null for anything that doesn't check out.
function resolveBuildPath(requested) {
  const safeName = basename(requested)
  if (!safeName || safeName === '.' || safeName === '..') return null
  const candidate = join(BUILDS_DIR, safeName)
  if (!existsSync(candidate)) return null

  let real
  try {
    real = realpathSync(candidate)
  } catch {
    return null
  }
  const realDir = realpathSync(BUILDS_DIR)
  if (real !== join(realDir, safeName)) return null

  const stat = statSync(real)
  if (!stat.isFile()) return null
  return real
}

export function registerDesktopBuildRoutes(app) {
  app.get('/api/desktop/releases/current', requireAuth, async (_req, res) => {
    try {
      res.json(await currentRelease())
    } catch (err) {
      console.error('desktop release metadata unavailable:', err.message)
      res.status(503).json({ error: 'desktop release metadata unavailable' })
    }
  })

  app.get('/api/downloads', requireAuth, async (_req, res) => {
    const builds = await listBuilds()
    res.json({ builds })
  })

  app.get('/api/downloads/:filename', requireAuth, (req, res) => {
    const real = resolveBuildPath(req.params.filename)
    if (!real) return res.status(404).json({ error: 'not found' })

    const filename = basename(real)
    const contentType = contentTypeFor(filename)
    res.set('Content-Type', contentType)
    res.set('Content-Disposition', `attachment; filename="${filename.replace(/"/g, '')}"`)
    res.set('Content-Length', String(statSync(real).size))

    const stream = createReadStream(real)
    stream.on('error', () => { if (!res.headersSent) res.status(500).end(); else res.destroy() })
    req.on('close', () => stream.destroy())
    stream.pipe(res)
  })
}
