// Thin wrapper over @tauri-apps/api so callers never import it directly (keeps
// the web bundle free of a hard Tauri dependency, and gives every other native
// agent one seam to mock in tests instead of reaching into @tauri-apps/api).
//
// Gating on IS_NATIVE is the CALLER's job (Player.jsx only constructs an
// MpvBackend, which is the only thing that calls invoke/listen, when
// IS_NATIVE is true) — this module stays a dumb transport so
// __setMockTransport works identically in a plain node test environment
// where IS_NATIVE is always false.
let invokeImpl = null
let listenImpl = null

async function loadReal() {
  if (invokeImpl) return
  const core = await import('@tauri-apps/api/core')
  const event = await import('@tauri-apps/api/event')
  invokeImpl = core.invoke
  listenImpl = event.listen
}

// invoke(IPC.MPV_LOAD, { url, startSec, paused }) -> Promise<T>
export async function invoke(cmd, payload) {
  await loadReal()
  return invokeImpl(cmd, payload)
}

// listen(EVENTS.MPV_TIMEPOS, ({ payload }) => { ... }) -> Promise<unlisten fn>
export async function listen(eventName, handler) {
  await loadReal()
  return listenImpl(eventName, handler)
}

// Test/mocking seam: replace invoke/listen with fakes without touching
// @tauri-apps/api. Used by MpvBackend's and the offline UI's unit tests.
export function __setMockTransport({ invoke: mockInvoke, listen: mockListen }) {
  invokeImpl = mockInvoke
  listenImpl = mockListen
}
