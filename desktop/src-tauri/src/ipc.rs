//! Frozen IPC contract — see docs/native/PLAN.md §4.2 and
//! app/client/src/native/contract.ts (the JS mirror of this file). Command
//! names and payload shapes here MUST match the JS `IPC`/`EVENTS` constants
//! exactly; Phase 1 agents (N1 mpv, N2 downloader) fill in the real bodies,
//! they do not rename or reshape anything below without updating both sides.

use serde::{Deserialize, Serialize};
use tauri::Emitter;

// ── mpv.rs (agent N1) ────────────────────────────────────────────────────────

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
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

/// Positions the embedded (opaque) mpv window to cover the React "video stage"
/// placeholder, in DEVICE pixels — the frontend reports its stage element's
/// rect via ResizeObserver and calls this on every change (including
/// fullscreen). No transparency involved: the player is native (PLAN.md §0.6).
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

/// Gates whether mpv's own OSC (seek bar / play-pause) is interactive.
/// Host + collaborative-control guests → true; plain guests → false, so a
/// guest can't disrupt their own playback via the native controls (§2 risk 2).
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MpvSetCanControlArgs {
    pub can_control: bool,
}

// NOTE: commands take flat, individual params (not a single `args` struct) so
// the frozen JS contract's flat payloads — e.g. invoke('mpv_load', {url,
// startSec, paused}) — deserialize correctly. `rename_all = "camelCase"` maps
// the camelCase JS keys onto these snake_case params. A single struct param
// would make Tauri require the payload wrapped as {args:{...}}, which the
// client does not send (see contract.ts).
#[tauri::command(rename_all = "camelCase")]
pub async fn mpv_load(app: tauri::AppHandle, url: String, start_sec: f64, paused: bool) -> Result<(), String> {
    crate::mpv::load(&app, &url, start_sec, paused)
}

#[tauri::command]
pub async fn mpv_play() -> Result<(), String> {
    crate::mpv::play()
}

#[tauri::command]
pub async fn mpv_pause() -> Result<(), String> {
    crate::mpv::pause()
}

#[tauri::command]
pub async fn mpv_seek(sec: f64) -> Result<(), String> {
    crate::mpv::seek(sec)
}

#[tauri::command]
pub async fn mpv_set_speed(rate: f64) -> Result<(), String> {
    crate::mpv::set_speed(rate)
}

#[tauri::command]
pub async fn mpv_set_volume(vol: f64) -> Result<(), String> {
    crate::mpv::set_volume(vol)
}

#[tauri::command]
pub async fn mpv_set_muted(muted: bool) -> Result<(), String> {
    crate::mpv::set_muted(muted)
}

#[tauri::command(rename_all = "camelCase")]
pub async fn mpv_set_region(app: tauri::AppHandle, x: f64, y: f64, w: f64, h: f64, dpr: f64) -> Result<(), String> {
    crate::mpv::set_region(&app, x, y, w, h, dpr)
}

#[tauri::command]
pub async fn mpv_set_fullscreen(on: bool) -> Result<(), String> {
    crate::mpv::set_fullscreen(on)
}

#[tauri::command(rename_all = "camelCase")]
pub async fn mpv_set_can_control(can_control: bool) -> Result<(), String> {
    crate::mpv::set_can_control(can_control)
}

#[tauri::command]
pub async fn mpv_teardown() -> Result<(), String> {
    crate::mpv::teardown()
}

// ── download.rs / offline.rs (agent N2) ─────────────────────────────────────

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
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

#[tauri::command(rename_all = "camelCase")]
pub async fn dl_start(
    app: tauri::AppHandle,
    item_id: String,
    url: String,
    title: String,
    parts: Option<u32>,
) -> Result<DlStartResult, String> {
    let id = crate::download::start(app, item_id, url, title, parts).await?;
    Ok(DlStartResult { id })
}

#[tauri::command]
pub async fn dl_pause(app: tauri::AppHandle, id: String) -> Result<(), String> {
    crate::download::pause(app, id).await
}

#[tauri::command]
pub async fn dl_resume(app: tauri::AppHandle, id: String) -> Result<(), String> {
    crate::download::resume(app, id).await
}

#[tauri::command]
pub async fn dl_cancel(app: tauri::AppHandle, id: String) -> Result<(), String> {
    crate::download::cancel(app, id).await
}

#[tauri::command]
pub async fn dl_list(app: tauri::AppHandle) -> Result<Vec<DownloadRecord>, String> {
    crate::download::list(app).await
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OfflinePathArgs {
    pub item_id: String,
}

#[derive(Serialize)]
pub struct OfflinePathResult {
    pub path: Option<String>,
}

#[tauri::command]
pub async fn offline_list(app: tauri::AppHandle) -> Result<Vec<OfflineRecord>, String> {
    let dir = crate::download::offline_dir(&app)?;
    Ok(crate::offline::list(&dir)
        .into_iter()
        .map(|e| OfflineRecord {
            item_id: e.item_id,
            title: e.title,
            path: e.path,
            size_bytes: e.size_bytes,
            added_at: e.added_at,
        })
        .collect())
}

#[tauri::command(rename_all = "camelCase")]
pub async fn offline_path(
    app: tauri::AppHandle,
    item_id: String,
) -> Result<OfflinePathResult, String> {
    let dir = crate::download::offline_dir(&app)?;
    let path = crate::offline::get(&dir, &item_id).map(|e| e.path);
    Ok(OfflinePathResult { path })
}

#[tauri::command(rename_all = "camelCase")]
pub async fn offline_remove(app: tauri::AppHandle, item_id: String) -> Result<(), String> {
    let dir = crate::download::offline_dir(&app)?;
    crate::offline::remove(&dir, &item_id);
    Ok(())
}

// ── main.rs / window.rs (agent N7) ──────────────────────────────────────────

/// Real exit — invoked both directly (frontend `invoke('app_quit')`) and from
/// the tray "Quit" menu item (see `lib.rs`'s `on_menu_event`), so there is
/// exactly one exit path regardless of trigger.
///
/// Emits `app:before-quit` (so any frontend listener can react), then
/// synchronously flushes N2's download registry to disk before the process
/// dies. Per-part byte offsets are already continuously archived by
/// http-downloader's breakpoint-resume; this flush persists our own
/// `dl_list`-facing metadata so it isn't stale on next launch.
#[tauri::command]
pub async fn app_quit(app: tauri::AppHandle) -> Result<(), String> {
    app.emit("app:before-quit", ())
        .map_err(|e: tauri::Error| e.to_string())?;
    crate::download::flush(&app);
    app.exit(0);
    Ok(())
}
