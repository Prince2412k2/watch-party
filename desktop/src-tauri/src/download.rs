//! Multi-part resumable downloader. Owned by agent N2 (Phase 1). See
//! docs/native/PLAN.md, Agent Card N2: split into N byte-range parts fetched
//! concurrently, persist per-part progress to disk frequently enough that a
//! crash/quit loses at most a few seconds, rehydrate + auto-resume `active`
//! downloads on launch. Relies on N7's tray/close-hook wiring (§4.2
//! `app_quit`) only to flush state before a real exit — downloads themselves
//! keep running whenever the process is alive, tray-hidden or not.
