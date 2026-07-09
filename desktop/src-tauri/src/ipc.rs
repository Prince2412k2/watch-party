//! Frozen IPC contract — see docs/native/PLAN.md §4.2 and
//! app/client/src/native/contract.ts (the JS mirror of this file). Command
//! names and payload shapes here MUST match the JS `IPC`/`EVENTS` constants
//! exactly; Phase 1 agents (N1 mpv, N2 downloader) fill in the real bodies,
//! they do not rename or reshape anything below without updating both sides.

use serde::{Deserialize, Serialize};

// ── mpv.rs (agent N1) ────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct MpvLoadArgs {
    pub url: String,
    pub start_sec: f64,
    pub paused: bool,
}

#[derive(Deserialize)]
pub struct MpvSeekArgs {
    pub sec: f64,
}

#[derive(Deserialize)]
pub struct MpvSetSpeedArgs {
    pub rate: f64,
}

#[derive(Deserialize)]
pub struct MpvSetVolumeArgs {
    pub vol: f64,
}

#[derive(Deserialize)]
pub struct MpvSetMutedArgs {
    pub muted: bool,
}

/// Positions the mpv render region behind the transparent webview (the "video
/// hole") in DEVICE pixels — the frontend reports its stage element's rect via
/// ResizeObserver and calls this on every change (including fullscreen).
#[derive(Deserialize)]
pub struct MpvSetRegionArgs {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    pub dpr: f64,
}

#[derive(Deserialize)]
pub struct MpvSetFullscreenArgs {
    pub on: bool,
}

#[tauri::command]
pub async fn mpv_load(args: MpvLoadArgs) -> Result<(), String> {
    let _ = args;
    // TODO(N1): mpv.rs — libmpv `loadfile`, seek to start_sec, set pause state.
    todo!("agent N1: implement mpv_load")
}

#[tauri::command]
pub async fn mpv_play() -> Result<(), String> {
    todo!("agent N1: implement mpv_play")
}

#[tauri::command]
pub async fn mpv_pause() -> Result<(), String> {
    todo!("agent N1: implement mpv_pause")
}

#[tauri::command]
pub async fn mpv_seek(args: MpvSeekArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N1: implement mpv_seek")
}

#[tauri::command]
pub async fn mpv_set_speed(args: MpvSetSpeedArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N1: implement mpv_set_speed")
}

#[tauri::command]
pub async fn mpv_set_volume(args: MpvSetVolumeArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N1: implement mpv_set_volume")
}

#[tauri::command]
pub async fn mpv_set_muted(args: MpvSetMutedArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N1: implement mpv_set_muted")
}

#[tauri::command]
pub async fn mpv_set_region(args: MpvSetRegionArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N1: implement mpv_set_region (see window.rs for the Phase-0 compositing approach)")
}

#[tauri::command]
pub async fn mpv_set_fullscreen(args: MpvSetFullscreenArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N1: implement mpv_set_fullscreen")
}

#[tauri::command]
pub async fn mpv_teardown() -> Result<(), String> {
    todo!("agent N1: implement mpv_teardown")
}

// ── download.rs / offline.rs (agent N2) ─────────────────────────────────────

#[derive(Deserialize)]
pub struct DlStartArgs {
    pub item_id: String,
    pub url: String,
    pub title: String,
    pub parts: Option<u32>,
}

#[derive(Deserialize)]
pub struct DlIdArgs {
    pub id: String,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct DownloadRecord {
    pub id: String,
    pub item_id: String,
    pub title: String,
    pub state: String, // "queued" | "active" | "paused" | "done" | "error"
    pub received_bytes: u64,
    pub total_bytes: u64,
    pub parts: u32,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct OfflineRecord {
    pub item_id: String,
    pub title: String,
    pub path: String,
    pub size_bytes: u64,
    pub added_at: String,
}

#[derive(Serialize)]
pub struct DlStartResult {
    pub id: String,
}

#[tauri::command]
pub async fn dl_start(args: DlStartArgs) -> Result<DlStartResult, String> {
    let _ = args;
    // TODO(N2): download.rs — multi-part resumable Range downloader; persist
    // per-part state so a crash/quit resumes from last offsets, not zero.
    todo!("agent N2: implement dl_start")
}

#[tauri::command]
pub async fn dl_pause(args: DlIdArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N2: implement dl_pause")
}

#[tauri::command]
pub async fn dl_resume(args: DlIdArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N2: implement dl_resume")
}

#[tauri::command]
pub async fn dl_cancel(args: DlIdArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N2: implement dl_cancel")
}

#[tauri::command]
pub async fn dl_list() -> Result<Vec<DownloadRecord>, String> {
    todo!("agent N2: implement dl_list (rehydrated from on-disk state on launch)")
}

#[derive(Deserialize)]
pub struct OfflinePathArgs {
    pub item_id: String,
}

#[derive(Serialize)]
pub struct OfflinePathResult {
    pub path: Option<String>,
}

#[tauri::command]
pub async fn offline_list() -> Result<Vec<OfflineRecord>, String> {
    todo!("agent N2: implement offline_list")
}

#[tauri::command]
pub async fn offline_path(args: OfflinePathArgs) -> Result<OfflinePathResult, String> {
    let _ = args;
    todo!("agent N2: implement offline_path")
}

#[tauri::command]
pub async fn offline_remove(args: OfflinePathArgs) -> Result<(), String> {
    let _ = args;
    todo!("agent N2: implement offline_remove")
}

// ── main.rs / window.rs (agent N7) ──────────────────────────────────────────

/// Real exit from the tray menu. Fires the flush hook N2 relies on to persist
/// in-flight download part-state before the process actually dies.
#[tauri::command]
pub async fn app_quit(app: tauri::AppHandle) -> Result<(), String> {
    // TODO(N7): call the N2-provided flush hook here before app.exit(0).
    app.exit(0);
    Ok(())
}
