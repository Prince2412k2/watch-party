//! Video-region bounds tracking, fullscreen, and window transparency.
//! Owned by agent N1 (Phase 1), alongside mpv.rs — the two are tightly
//! coupled (this module positions the surface mpv.rs renders into). See
//! docs/native/PLAN.md §2 for the compositing approach.
