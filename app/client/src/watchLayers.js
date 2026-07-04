// ── Watch-screen z-index scale ───────────────────────────────────────────────
// One coherent stacking order for the immersive watch screen so the mobile
// control layer, camera strip, chat sheet, and room chrome never collide.
// Desktop reuses the same scale (its clusters slot into the same bands).
export const Z = {
  video: 0,        // <Player> / HlsPlayer fills the stage
  cameraStrip: 10, // collapsible camera strip / dock
  chatEdge: 21,    // desktop right-edge chat reveal + notification ripple
  buffering: 25,   // "Catching up…" / "Switching quality…" overlay
  controlBar: 30,  // mobile top + bottom control bars (and desktop clusters)
  chatScrim: 39,   // scrim behind the mobile chat sheet
  chat: 40,        // chat panel (desktop) / slide-over sheet (mobile)
  hostModal: 50,   // RoomControls host modal + its scrim
  toast: 60,       // toasts / connection errors — never hidden
  rotateHint: 300, // non-rotating "rotate your phone" hint (lobby + watch screen)
}
