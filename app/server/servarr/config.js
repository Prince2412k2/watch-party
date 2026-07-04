// Central config for the media-acquisition stack (Sonarr/Radarr/Bazarr/
// Prowlarr/qBittorrent). Reads env at call time so tests can toggle it, and
// treats a service as "configured" only when the pieces it needs are present.
// The client NEVER sees these values — they only flow into upstream requests.

function trim(v) {
  const s = (v ?? '').toString().trim()
  return s || null
}

// The *arr services authenticate with a URL + X-Api-Key. qBittorrent uses a
// URL + WebUI username/password (cookie session) instead.
export function arrConfig(name) {
  const baseUrl = trim(process.env[`${name}_URL`])
  const apiKey = trim(process.env[`${name}_API_KEY`])
  return { baseUrl, apiKey, configured: !!(baseUrl && apiKey) }
}

export function qbitConfig() {
  const baseUrl = trim(process.env.QBITTORRENT_URL)
  const user = trim(process.env.QBITTORRENT_USER)
  const pass = trim(process.env.QBITTORRENT_PASS)
  // A base URL + username is enough to attempt login; qBittorrent installs can
  // run with an empty password, so we don't require QBITTORRENT_PASS.
  return { baseUrl, user, pass, configured: !!(baseUrl && user) }
}

// The five services keyed by the id used in routes + health output.
export function serviceConfig(service) {
  switch (service) {
    case 'radarr': return arrConfig('RADARR')
    case 'sonarr': return arrConfig('SONARR')
    case 'prowlarr': return arrConfig('PROWLARR')
    case 'bazarr': return arrConfig('BAZARR')
    case 'qbittorrent': return qbitConfig()
    default: return { configured: false }
  }
}

export const SERVICES = ['radarr', 'sonarr', 'prowlarr', 'bazarr', 'qbittorrent']

// A public, key-free view of what's configured — safe to send to the client.
export function configuredMap() {
  const out = {}
  for (const s of SERVICES) out[s] = serviceConfig(s).configured
  return out
}
