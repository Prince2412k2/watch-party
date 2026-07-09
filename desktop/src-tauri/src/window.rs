//! Embedding of mpv's native window + video-region bounds tracking +
//! fullscreen. Owned by agent N1 (Phase 1), alongside mpv.rs — the two are
//! tightly coupled (this module reparents/positions the opaque mpv window to
//! cover the React video-stage rect). NO window transparency is needed — the
//! player is native and opaque (PLAN.md §0.6/§2, superseding the old
//! transparent-webview plan).
