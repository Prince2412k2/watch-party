//! libmpv lifecycle + playback control + property-observe → Tauri events.
//! Owned by agent N1 (Phase 1). See docs/native/PLAN.md, Agent Card N1, and §2.
//!
//! ARCHITECTURE (per PLAN.md §0.6): the player is NATIVE, not React. mpv owns
//! its own native window embedded in the Tauri window (GTK child /
//! wl_subsurface on Linux), positioned via `mpv_set_region` to cover the React
//! "video stage" placeholder, and draws its own OSC for transport controls.
//! There is NO transparent webview / DOM-over-video compositing (that earlier
//! approach was superseded — see SPIKE-NOTES.md "SUPERSEDED"). N1's first task
//! is the embedding spike; then OSC + `mpv_set_can_control` gating; then the
//! full command/event surface. Phase 0 leaves this empty on purpose.
