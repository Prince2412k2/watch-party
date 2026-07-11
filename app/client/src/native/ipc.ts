// Thin wrapper over @tauri-apps/api so callers never import it directly (keeps
// the web bundle free of a hard Tauri dependency, and gives every other native
// agent one seam to mock in tests instead of reaching into @tauri-apps/api).
//
// Gating on IS_NATIVE is the CALLER's job (Player.jsx only constructs an
// MpvBackend, which is the only thing that calls invoke/listen, when
// IS_NATIVE is true) — this module stays a dumb transport so
// __setMockTransport works identically in a plain node test environment
// where IS_NATIVE is always false.
type Invoke = (cmd: string, payload?: Record<string, unknown>) => Promise<unknown>
type Listen = (eventName: string, handler: (event: { payload: unknown }) => void) => Promise<() => void>

export interface NativeCommandPayloadMap {
  mpv_load: { url: string; startSec: number; paused: boolean }
  mpv_play: Record<string, never>
  mpv_pause: Record<string, never>
  mpv_seek: { sec: number }
  mpv_set_speed: { rate: number }
  mpv_set_volume: { vol: number }
  mpv_set_muted: { muted: boolean }
  mpv_set_region: { x: number; y: number; w: number; h: number; dpr: number }
  mpv_set_fullscreen: { fullscreen: boolean }
  mpv_set_can_control: { canControl?: boolean }
  mpv_teardown: Record<string, never>
  dl_start: { itemId: string; url: string; title: string; parts?: number }
  dl_pause: { id: string }
  dl_resume: { id: string }
  dl_cancel: { id: string }
  dl_list: Record<string, never>
  offline_list: Record<string, never>
  offline_path: { itemId: string }
  offline_remove: { itemId: string }
  app_quit: Record<string, never>
}

export interface NativeEventPayloadMap {
  'mpv:timepos': { sec: number }
  'mpv:pause': { paused: boolean }
  'mpv:duration': { sec: number }
  'mpv:seeking': Record<string, never>
  'mpv:seeked': { sec: number }
  'mpv:buffering': { active: boolean }
  'mpv:eof': Record<string, never>
  'mpv:loadedmetadata': { durationSec: number }
  'mpv:speed': { rate: number }
  'mpv:cache': { cachedAheadSec: number; cachedBytes: number }
  'dl:progress': { id: string; receivedBytes: number; totalBytes: number; bytesPerSec?: number }
  'dl:done': { id: string; itemId: string; path: string }
  'dl:error': { id: string; message?: string }
}

let invokeImpl: Invoke | null = null
let listenImpl: Listen | null = null

async function loadReal() {
  if (invokeImpl) return
  const core = await import('@tauri-apps/api/core')
  const event = await import('@tauri-apps/api/event')
  invokeImpl = (cmd, payload) => core.invoke<unknown>(cmd, payload)
  listenImpl = (eventName, handler) => event.listen<unknown>(eventName, handler)
}

// invoke(IPC.MPV_LOAD, { url, startSec, paused }) -> Promise<T>
export async function invoke<K extends keyof NativeCommandPayloadMap>(cmd: K, payload: NativeCommandPayloadMap[K]): Promise<unknown> {
  await loadReal()
  if (!invokeImpl) throw new Error('Native invoke transport is unavailable')
  return invokeImpl(cmd, payload)
}

// listen(EVENTS.MPV_TIMEPOS, ({ payload }) => { ... }) -> Promise<unlisten fn>
export async function listen(eventName: string, handler: (event: { payload: unknown }) => void): Promise<() => void> {
  await loadReal()
  if (!listenImpl) throw new Error('Native event transport is unavailable')
  return listenImpl(eventName, handler)
}

// Test/mocking seam: replace invoke/listen with fakes without touching
// @tauri-apps/api. Used by MpvBackend's and the offline UI's unit tests.
export function __setMockTransport({ invoke: mockInvoke, listen: mockListen }: { invoke?: Invoke | null; listen?: Listen | null } = {}) {
  invokeImpl = mockInvoke ?? null
  listenImpl = mockListen ?? null
}
