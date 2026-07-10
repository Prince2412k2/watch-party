//! Multi-part resumable downloader. Owned by agent N2 (Phase 1). See
//! docs/native/PLAN.md, Agent Card N2 and §2b.
//!
//! Built on the `http-downloader` crate (multithreaded, breakpoint-resume,
//! tunable connection count — see §2b) instead of hand-rolling the
//! range/resume state machine. What this module adds on top:
//!   - a process-wide registry of `DownloadState`s (the §4.2 `dl_*` surface),
//!     mirrored to `<app_data>/downloads/registry.json` so `dl_list` survives
//!     relaunch and `active` downloads auto-resume on the next launch;
//!   - aggregate progress coalescing + `dl:progress`/`dl:done`/`dl:error`
//!     event emission;
//!   - moving a finished file into the offline dir and recording it via
//!     `offline.rs`.
//!
//! Per-part resume state itself is NOT reinvented: `http-downloader`'s
//! `breakpoint-resume` + `bson-file-archiver` extensions already write a
//! `<dest>.bson` archive of exactly which byte ranges are still outstanding,
//! updated as chunks complete and flushed on cancel — that file *is* our
//! "<dest>.part.json" equivalent (bson instead of json). Rebuilding a
//! downloader against the same destination path picks that archive back up
//! and resumes from the last committed offsets rather than from zero.

use std::collections::HashMap;
use std::num::NonZeroU8;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use http_downloader::breakpoint_resume::DownloadBreakpointResumeExtension;
use http_downloader::bson_file_archiver::{ArchiveFilePath, BsonFileArchiverBuilder};
use http_downloader::{DownloadingEndCause, ExtendedHttpFileDownloader, HttpDownloaderBuilder};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::Mutex as AsyncMutex;
use url::Url;
use uuid::Uuid;

use crate::ipc::DownloadRecord;
use crate::offline::{self, OfflineEntry};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DlPhase {
    Queued,
    Active,
    Paused,
    Done,
    Error,
}

impl DlPhase {
    fn as_str(&self) -> &'static str {
        match self {
            DlPhase::Queued => "queued",
            DlPhase::Active => "active",
            DlPhase::Paused => "paused",
            DlPhase::Done => "done",
            DlPhase::Error => "error",
        }
    }
}

/// Everything needed to (re)build a downloader for one title, plus the
/// live state a running download reports back through.
struct DownloadState {
    id: String,
    item_id: String,
    title: String,
    url: String,
    file_name: String,
    parts: u32,
    phase: StdMutex<DlPhase>,
    error_message: StdMutex<Option<String>>,
    received_bytes: AtomicU64,
    total_bytes: AtomicU64,
    /// Set just before `dl_cancel` calls `.cancel()` so the completion task
    /// knows this was a delete, not a pause, and should not resurrect the
    /// (already removed) registry entry.
    removed: AtomicBool,
    downloader: AsyncMutex<Option<ExtendedHttpFileDownloader>>,
}

/// On-disk mirror of the registry, used only for persistence (not as the
/// live source of truth — `REGISTRY` is).
#[derive(Serialize, Deserialize, Clone)]
struct PersistedDownload {
    id: String,
    item_id: String,
    title: String,
    url: String,
    file_name: String,
    parts: u32,
    state: String,
    received_bytes: u64,
    total_bytes: u64,
}

static REGISTRY: Lazy<StdMutex<HashMap<String, Arc<DownloadState>>>> =
    Lazy::new(|| StdMutex::new(HashMap::new()));
static INITIALIZED: Lazy<StdMutex<bool>> = Lazy::new(|| StdMutex::new(false));

fn downloads_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("downloads");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

/// Public so ipc.rs's `offline_*` commands can resolve the same directory
/// download.rs moves completed files into.
pub fn offline_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("offline");
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn registry_file(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(downloads_dir(app)?.join("registry.json"))
}

fn set_phase(ds: &DownloadState, phase: DlPhase) {
    *ds.phase.lock().unwrap() = phase;
}

fn set_error(ds: &DownloadState, message: String) {
    *ds.phase.lock().unwrap() = DlPhase::Error;
    *ds.error_message.lock().unwrap() = Some(message);
}

fn to_record(ds: &DownloadState) -> DownloadRecord {
    DownloadRecord {
        id: ds.id.clone(),
        item_id: ds.item_id.clone(),
        title: ds.title.clone(),
        state: ds.phase.lock().unwrap().as_str().to_string(),
        received_bytes: ds.received_bytes.load(Ordering::Relaxed),
        total_bytes: ds.total_bytes.load(Ordering::Relaxed),
        parts: ds.parts,
    }
}

fn persist_registry(app: &AppHandle) {
    let Ok(path) = registry_file(app) else { return };
    let snapshot: Vec<PersistedDownload> = {
        let map = REGISTRY.lock().unwrap();
        map.values()
            .map(|ds| PersistedDownload {
                id: ds.id.clone(),
                item_id: ds.item_id.clone(),
                title: ds.title.clone(),
                url: ds.url.clone(),
                file_name: ds.file_name.clone(),
                parts: ds.parts,
                state: ds.phase.lock().unwrap().as_str().to_string(),
                received_bytes: ds.received_bytes.load(Ordering::Relaxed),
                total_bytes: ds.total_bytes.load(Ordering::Relaxed),
            })
            .collect()
    };
    if let Ok(json) = serde_json::to_vec_pretty(&snapshot) {
        let _ = std::fs::write(&path, json);
    }
}

/// Loads the registry off disk (once) and auto-resumes anything that was
/// `active`/`queued` at last save — per §4.2 "on launch, N2 rehydrates
/// unfinished downloads and auto-resumes active ones". Cheap to call from
/// every `dl_*`/`offline_*` command; only does real work the first time.
async fn ensure_initialized(app: &AppHandle) {
    {
        let mut init = INITIALIZED.lock().unwrap();
        if *init {
            return;
        }
        *init = true;
    }

    let Ok(path) = registry_file(app) else { return };
    let Ok(bytes) = std::fs::read(&path) else { return };
    let Ok(entries) = serde_json::from_slice::<Vec<PersistedDownload>>(&bytes) else {
        return;
    };

    for entry in entries {
        let should_resume = entry.state == "active" || entry.state == "queued";
        let phase = if should_resume {
            DlPhase::Queued
        } else if entry.state == "done" {
            DlPhase::Done
        } else {
            DlPhase::Paused
        };
        let ds = Arc::new(DownloadState {
            id: entry.id.clone(),
            item_id: entry.item_id,
            title: entry.title,
            url: entry.url.clone(),
            file_name: entry.file_name,
            parts: entry.parts,
            phase: StdMutex::new(phase),
            error_message: StdMutex::new(None),
            received_bytes: AtomicU64::new(entry.received_bytes),
            total_bytes: AtomicU64::new(entry.total_bytes),
            removed: AtomicBool::new(false),
            downloader: AsyncMutex::new(None),
        });
        REGISTRY
            .lock()
            .unwrap()
            .insert(entry.id.clone(), ds.clone());

        if should_resume {
            if let Ok(url) = Url::parse(&entry.url) {
                let app2 = app.clone();
                tokio::spawn(async move {
                    let _ = spawn_download(app2, ds, url).await;
                });
            }
        }
    }
}

fn build_downloader(
    url: Url,
    save_dir: PathBuf,
    file_name: String,
    parts: u32,
) -> Result<ExtendedHttpFileDownloader, String> {
    let count = NonZeroU8::new(parts.clamp(1, 8) as u8).unwrap_or(NonZeroU8::new(1).unwrap());
    let (downloader, _ext_state) = HttpDownloaderBuilder::new(url, save_dir)
        .file_name(Some(file_name))
        .download_connection_count(count)
        .build(DownloadBreakpointResumeExtension {
            download_archiver_builder: BsonFileArchiverBuilder::new(ArchiveFilePath::Suffix(
                "bson".to_string(),
            )),
        });
    Ok(downloader)
}

/// Builds (or rebuilds, for resume) a downloader for `ds` and drives it to
/// completion in the background. Safe to call again on a `Paused`/`Error`
/// entry — the breakpoint-resume archive next to the destination file (if
/// any) makes the rebuild pick up from the last committed offsets rather
/// than starting over.
async fn spawn_download(app: AppHandle, ds: Arc<DownloadState>, url: Url) -> Result<(), String> {
    let save_dir = downloads_dir(&app)?;
    let mut downloader = build_downloader(url, save_dir, ds.file_name.clone(), ds.parts)?;

    let download_future = downloader
        .prepare_download()
        .map_err(|e| e.to_string())?;
    let mut len_rx = downloader.downloaded_len_receiver().clone();
    let total_fut = downloader.total_size_future();
    let file_path = downloader.get_file_path();

    *ds.downloader.lock().await = Some(downloader);
    set_phase(&ds, DlPhase::Active);
    persist_registry(&app);

    // Learn the total size once headers arrive (falls back to whatever was
    // persisted from a previous run if the server never answers with one).
    {
        let ds2 = ds.clone();
        tokio::spawn(async move {
            if let Some(total) = total_fut.await {
                ds2.total_bytes.store(total.get(), Ordering::Relaxed);
            }
        });
    }

    // Aggregate progress, coalesced to ~3Hz per §4.2 ("coalesced ~2-4Hz").
    {
        let ds2 = ds.clone();
        let app2 = app.clone();
        tokio::spawn(async move {
            let mut last_emit_bytes = 0u64;
            let mut last_emit_at = tokio::time::Instant::now();
            loop {
                if len_rx.changed().await.is_err() {
                    break;
                }
                let received = *len_rx.borrow();
                ds2.received_bytes.store(received, Ordering::Relaxed);
                let elapsed = last_emit_at.elapsed();
                if elapsed >= Duration::from_millis(300) {
                    let secs = elapsed.as_secs_f64().max(0.001);
                    let bytes_per_sec =
                        ((received.saturating_sub(last_emit_bytes)) as f64 / secs) as u64;
                    last_emit_bytes = received;
                    last_emit_at = tokio::time::Instant::now();
                    let _ = app2.emit(
                        "dl:progress",
                        serde_json::json!({
                            "id": ds2.id,
                            "receivedBytes": received,
                            "totalBytes": ds2.total_bytes.load(Ordering::Relaxed),
                            "bytesPerSec": bytes_per_sec,
                        }),
                    );
                    persist_registry(&app2);
                }
            }
        });
    }

    // Drive the actual transfer; finalize on completion/cancel/error.
    tokio::spawn(async move {
        let result = download_future.await;
        finish_download(app, ds, file_path, result).await;
    });

    Ok(())
}

async fn finish_download(
    app: AppHandle,
    ds: Arc<DownloadState>,
    file_path: PathBuf,
    result: Result<DownloadingEndCause, http_downloader::DownloadError>,
) {
    if ds.removed.load(Ordering::SeqCst) {
        return; // dl_cancel already tore this entry down.
    }
    match result {
        Ok(DownloadingEndCause::DownloadFinished) => {
            set_phase(&ds, DlPhase::Done);
            if let Ok(offline_root) = offline_dir(&app) {
                let dest = offline_root.join(&ds.file_name);
                if std::fs::rename(&file_path, &dest).is_ok() {
                    if let Ok(f) = std::fs::File::open(&dest) {
                        let _ = f.sync_all();
                    }
                    let size = std::fs::metadata(&dest)
                        .map(|m| m.len())
                        .unwrap_or_else(|_| ds.total_bytes.load(Ordering::Relaxed));
                    offline::add(
                        &offline_root,
                        OfflineEntry {
                            item_id: ds.item_id.clone(),
                            title: ds.title.clone(),
                            path: dest.to_string_lossy().to_string(),
                            size_bytes: size,
                            added_at: chrono_now_iso(),
                        },
                    );
                    let bson_path = bson_archive_path(&file_path);
                    let _ = std::fs::remove_file(bson_path);
                    let _ = app.emit(
                        "dl:done",
                        serde_json::json!({
                            "id": ds.id,
                            "itemId": ds.item_id,
                            "path": dest.to_string_lossy(),
                        }),
                    );
                } else {
                    set_error(&ds, "failed to move completed download into offline dir".into());
                }
            }
            persist_registry(&app);
        }
        Ok(DownloadingEndCause::Cancelled) => {
            // A `dl_pause` cancel — the breakpoint-resume extension has
            // already archived exactly which ranges are outstanding.
            set_phase(&ds, DlPhase::Paused);
            persist_registry(&app);
        }
        Err(e) => {
            let message = e.to_string();
            set_error(&ds, message.clone());
            persist_registry(&app);
            let _ = app.emit(
                "dl:error",
                serde_json::json!({ "id": ds.id, "message": message }),
            );
        }
    }
}

fn bson_archive_path(file_path: &PathBuf) -> PathBuf {
    let ext = file_path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");
    file_path.with_extension(format!("{ext}.bson"))
}

fn chrono_now_iso() -> String {
    chrono::Utc::now().to_rfc3339()
}

fn sanitize_file_name(title: &str, item_id: &str, url: &Url) -> String {
    let ext = url
        .path_segments()
        .and_then(|mut s| s.next_back())
        .and_then(|last| last.rsplit_once('.'))
        .map(|(_, ext)| ext)
        .filter(|ext| ext.len() <= 8 && !ext.is_empty())
        .unwrap_or("mkv");
    let base: String = title
        .chars()
        .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect();
    let base = if base.trim_matches('_').is_empty() {
        item_id.to_string()
    } else {
        base
    };
    format!("{item_id}_{base}.{ext}")
}

// ── public API used by ipc.rs ───────────────────────────────────────────────

pub async fn start(
    app: AppHandle,
    item_id: String,
    url: String,
    title: String,
    parts: Option<u32>,
) -> Result<String, String> {
    ensure_initialized(&app).await;

    let parsed_url = Url::parse(&url).map_err(|e| format!("invalid url: {e}"))?;
    let id = Uuid::new_v4().to_string();
    let file_name = sanitize_file_name(&title, &item_id, &parsed_url);
    let parts = parts.unwrap_or(6).clamp(1, 8);

    let ds = Arc::new(DownloadState {
        id: id.clone(),
        item_id,
        title,
        url: url.clone(),
        file_name,
        parts,
        phase: StdMutex::new(DlPhase::Queued),
        error_message: StdMutex::new(None),
        received_bytes: AtomicU64::new(0),
        total_bytes: AtomicU64::new(0),
        removed: AtomicBool::new(false),
        downloader: AsyncMutex::new(None),
    });
    REGISTRY.lock().unwrap().insert(id.clone(), ds.clone());
    persist_registry(&app);

    spawn_download(app, ds, parsed_url).await?;
    Ok(id)
}

pub async fn pause(app: AppHandle, id: String) -> Result<(), String> {
    ensure_initialized(&app).await;
    let ds = {
        let map = REGISTRY.lock().unwrap();
        map.get(&id).cloned()
    }
    .ok_or_else(|| format!("unknown download id: {id}"))?;

    set_phase(&ds, DlPhase::Paused);
    let downloader = ds.downloader.lock().await.take();
    if let Some(downloader) = downloader {
        downloader.cancel().await;
    }
    persist_registry(&app);
    Ok(())
}

pub async fn resume(app: AppHandle, id: String) -> Result<(), String> {
    ensure_initialized(&app).await;
    let ds = {
        let map = REGISTRY.lock().unwrap();
        map.get(&id).cloned()
    }
    .ok_or_else(|| format!("unknown download id: {id}"))?;

    {
        let phase = *ds.phase.lock().unwrap();
        if phase == DlPhase::Active {
            return Ok(()); // already running
        }
    }
    let url = Url::parse(&ds.url).map_err(|e| e.to_string())?;
    spawn_download(app, ds, url).await
}

pub async fn cancel(app: AppHandle, id: String) -> Result<(), String> {
    ensure_initialized(&app).await;
    let ds = {
        let mut map = REGISTRY.lock().unwrap();
        map.remove(&id)
    }
    .ok_or_else(|| format!("unknown download id: {id}"))?;

    ds.removed.store(true, Ordering::SeqCst);
    let downloader = ds.downloader.lock().await.take();
    if let Some(downloader) = downloader {
        let file_path = downloader.get_file_path();
        downloader.cancel().await;
        let _ = std::fs::remove_file(&file_path);
        let _ = std::fs::remove_file(bson_archive_path(&file_path));
    }
    persist_registry(&app);
    Ok(())
}

pub async fn list(app: AppHandle) -> Result<Vec<DownloadRecord>, String> {
    ensure_initialized(&app).await;
    let map = REGISTRY.lock().unwrap();
    Ok(map.values().map(|ds| to_record(ds)).collect())
}

/// Called by N7's `app_quit` before the process exits — synchronously
/// flushes the registry snapshot to disk. (Per-part offsets are already
/// continuously archived by the http-downloader breakpoint-resume extension
/// as chunks complete; this just makes sure our own `dl_list`-facing
/// metadata — received/total bytes, state — isn't stale on next launch.)
pub fn flush(app: &AppHandle) {
    persist_registry(app);
}

// ── self-test ────────────────────────────────────────────────────────────
//
// Exercises the actual mechanism (build_downloader + http-downloader) end to
// end against a real public Range-capable file, without going through
// Tauri's AppHandle (these are unit tests, not the IPC surface). Requires
// network access; run with `cargo test -- --ignored --nocapture` if network
// is unavailable in CI.
#[cfg(test)]
mod tests {
    use super::*;

    // A small, stable, publicly-hosted file known to support byte ranges.
    const TEST_URL: &str = "https://proof.ovh.net/files/10Mb.dat";
    const TEST_SIZE: u64 = 10_485_760; // 10 * 1024 * 1024

    #[tokio::test]
    #[ignore] // hits the network; run explicitly
    async fn downloads_with_multiple_connections_and_is_byte_correct() {
        let dir = tempfile::tempdir().unwrap();
        let url = Url::parse(TEST_URL).unwrap();
        let mut downloader =
            build_downloader(url, dir.path().to_path_buf(), "full.bin".into(), 4).unwrap();

        let fut = downloader.prepare_download().unwrap();
        // The download only actually runs once the future is polled, so
        // spawn it as a task rather than just holding it — then give the
        // chunk manager a beat to fan out its connections before asserting
        // on it. download_connection_count(4) + a Range-capable 10MB file
        // should produce >1 live chunk.
        let handle = tokio::spawn(fut);
        tokio::time::sleep(Duration::from_millis(2000)).await;
        let chunks = downloader.get_chunks().await;
        eprintln!(
            "is_downloading={} downloaded_len={} chunks={}",
            downloader.is_downloading(),
            downloader.downloaded_len(),
            chunks.len()
        );
        assert!(
            chunks.len() > 1,
            "expected multiple concurrent chunks for a Range-capable file, got {}",
            chunks.len()
        );

        let cause = handle.await.unwrap().unwrap();
        assert!(matches!(cause, DownloadingEndCause::DownloadFinished));

        let path = dir.path().join("full.bin");
        let bytes = std::fs::read(&path).unwrap();
        assert_eq!(bytes.len() as u64, TEST_SIZE);
    }

    #[tokio::test]
    #[ignore] // hits the network; run explicitly
    async fn resumes_from_persisted_offset_instead_of_restarting() {
        let dir = tempfile::tempdir().unwrap();
        let url = Url::parse(TEST_URL).unwrap();

        // Start, let a few chunks land, then cancel — simulating dl_pause /
        // a process kill. The breakpoint-resume extension archives exactly
        // which byte ranges are still outstanding as chunks complete.
        let mut downloader =
            build_downloader(url.clone(), dir.path().to_path_buf(), "resume.bin".into(), 4)
                .unwrap();
        let fut = downloader.prepare_download().unwrap();
        let handle = tokio::spawn(fut);
        // Poll until we catch it strictly mid-flight (network speed in CI
        // varies enough that a fixed sleep is flaky either direction).
        let mut received_before_cancel = 0u64;
        for _ in 0..100 {
            tokio::time::sleep(Duration::from_millis(20)).await;
            received_before_cancel = downloader.downloaded_len();
            if received_before_cancel > 0 && received_before_cancel < TEST_SIZE {
                break;
            }
        }
        assert!(
            received_before_cancel > 0 && received_before_cancel < TEST_SIZE,
            "expected to catch the download strictly mid-flight, got {received_before_cancel}/{TEST_SIZE} bytes"
        );
        downloader.cancel().await;
        let _ = handle.await; // resolves with Cancelled

        let archive = bson_archive_path(&dir.path().join("resume.bin"));
        assert!(archive.exists(), "breakpoint-resume archive was not written");

        // Rebuild against the same destination — this is exactly what
        // `resume()`/auto-resume-on-launch does. It must pick up the
        // archive rather than starting from zero.
        let mut downloader2 =
            build_downloader(url, dir.path().to_path_buf(), "resume.bin".into(), 4).unwrap();
        let fut2 = downloader2.prepare_download().unwrap();
        let handle2 = tokio::spawn(fut2);
        // As soon as the resumed request's response headers land, the
        // breakpoint-resume archive is loaded and `downloaded_len` jumps
        // straight to the archived offset — well before enough time could
        // have passed to redownload the whole file from scratch. Poll for
        // that first non-zero report rather than assuming a fixed delay.
        let mut received_after_resume = 0u64;
        for _ in 0..100 {
            tokio::time::sleep(Duration::from_millis(20)).await;
            received_after_resume = downloader2.downloaded_len();
            if received_after_resume > 0 {
                break;
            }
        }
        assert!(
            received_after_resume >= received_before_cancel,
            "resume started from {received_after_resume} bytes, expected >= {received_before_cancel} (the pre-cancel offset), i.e. it did not restart from zero"
        );

        let cause = handle2.await.unwrap().unwrap();
        assert!(matches!(cause, DownloadingEndCause::DownloadFinished));

        let bytes = std::fs::read(dir.path().join("resume.bin")).unwrap();
        assert_eq!(bytes.len() as u64, TEST_SIZE);
    }
}
