//! libmpv lifecycle + playback control + property-observe → Tauri events.
//! Owned by agent N1 (Phase 1). See docs/native/PLAN.md, Agent Card N1, and
//! §2 ("The crux risk") for the compositing approach this module must
//! implement (mpv render region behind the transparent webview, positioned
//! via `mpv_set_region`).
//!
//! Phase 0 leaves this empty on purpose: the Phase-0 spike's job is to prove
//! the compositing approach works at all (see SPIKE-NOTES.md once written),
//! not to build the production mpv module. N1 builds the real thing here
//! against that proven approach.
