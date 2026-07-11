// True when running inside the Tauri desktop shell, false in any browser
// (web guests, mobile PWA). Every native-only code path (MpvBackend, the
// Player.jsx native branch, the offline/download UI) is gated on this.
export const IS_NATIVE = typeof window !== 'undefined' && !!(window as Window & { __TAURI__?: unknown }).__TAURI__
