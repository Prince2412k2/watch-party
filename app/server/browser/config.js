// Deployment configuration for the shared browser.
//
// Off unless a deployment says otherwise, following the same plain-env-var
// convention as WP_TEST_MODE and SERVE_CLIENT: a deployment that sets nothing
// behaves exactly as it did before this feature existed.

import { leaseStorageReady } from '../party-store.js'

function parseBool(value) {
  return value === '1' || value === 'true'
}

function parseInteger(value, fallback, { min, max }) {
  const parsed = Number(value)
  if (!Number.isFinite(parsed)) return fallback
  return Math.min(max, Math.max(min, Math.round(parsed)))
}

export function browserConfig() {
  const agentToken = process.env.BROWSER_AGENT_TOKEN || ''
  return {
    // Three things have to be true, and every one of them fails to "unavailable"
    // rather than to an error:
    //   * the deployment asked for the feature,
    //   * a token exists (the agent refuses every request without one, so this
    //     would otherwise be a button that can only ever fail), and
    //   * the lease can be persisted — without it two parties could each believe
    //     they hold the single browser.
    enabled: parseBool(process.env.BROWSER_ENABLED) && agentToken.length > 0 && leaseStorageReady(),
    flagSet: parseBool(process.env.BROWSER_ENABLED),
    agentUrl: (process.env.BROWSER_AGENT_URL || 'http://watchparty-browser:8080').replace(/\/+$/, ''),
    agentToken,
    // The page a browser opens on. Not an allow-list — the driver may navigate
    // anywhere from here.
    homeUrl: process.env.BROWSER_HOME_URL || 'https://www.google.com',
    // Shares an uplink with everyone's cameras, so it gets a ceiling rather than
    // as much bitrate as the encoder would like. 2500 kbps was measured as
    // sufficient for 720p30 video (docs/specs/2026-08-04-remote-browser-spike.md).
    maxBitrateKbps: parseInteger(process.env.BROWSER_MAX_BITRATE_KBPS, 2500, { min: 200, max: 8000 }),
    fps: parseInteger(process.env.BROWSER_FPS, 30, { min: 5, max: 60 }),
    // Measured cold start was 6.3s for the whole container and 3.5s for the
    // browser alone; this is the give-up point, not the expected wait.
    startTimeoutMs: parseInteger(process.env.BROWSER_START_TIMEOUT_MS, 25_000, { min: 5_000, max: 120_000 }),
    // Every agent call is bounded: app/server must stay responsive even when the
    // container is wedged, because chat and playback run in the same process.
    requestTimeoutMs: parseInteger(process.env.BROWSER_REQUEST_TIMEOUT_MS, 5_000, { min: 500, max: 30_000 }),
    // The LiveKit identity the container publishes under. Clients use it to tell
    // the browser's tracks apart from a participant's camera.
    identity: process.env.BROWSER_IDENTITY || 'shared-browser',
    // The remote screen's size, sent to clients so they can translate a click in
    // their own window into a coordinate on that screen. Set from the SAME env
    // vars compose passes to the container, so the two cannot disagree; the
    // agent's own report refines it once the stream is up. Always present, because
    // a client that cannot learn the size cannot map a click, and the honest
    // failure mode for that is "slightly wrong", not "control silently dead".
    screen: {
      w: parseInteger(process.env.BROWSER_SCREEN_W, 1280, { min: 320, max: 3840 }),
      h: parseInteger(process.env.BROWSER_SCREEN_H, 720, { min: 240, max: 2160 }),
    },
  }
}

export function browserEnabled() {
  return browserConfig().enabled
}

let warned = false

// Called once at startup so a half-configured deployment is loud in the log
// rather than silently presenting a feature that cannot work.
export function warnIfMisconfigured(log = console.warn) {
  if (warned) return
  warned = true
  const config = browserConfig()
  if (config.flagSet && !config.agentToken) {
    log('BROWSER_ENABLED is set but BROWSER_AGENT_TOKEN is empty — the shared browser stays off')
  } else if (config.flagSet && !config.enabled) {
    log('BROWSER_ENABLED is set but the browser lease cannot be stored — the shared browser stays off')
  }
}
