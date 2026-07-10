//! Offline manifest store (completed downloads). Owned by agent N2, alongside
//! download.rs. See docs/native/PLAN.md, Agent Card N2.
//!
//! Deliberately dumb: a JSON array of `OfflineEntry`, kept in a process-wide
//! in-memory cache and mirrored to `<offline_dir>/manifest.json` on every
//! mutation. `download.rs` calls `add()` once a completed part-download has
//! been moved into the offline dir; `ipc.rs`'s `offline_*` commands call
//! `list`/`get`/`remove` directly.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OfflineEntry {
    pub item_id: String,
    pub title: String,
    pub path: String,
    pub size_bytes: u64,
    pub added_at: String,
}

static MANIFEST: Lazy<Mutex<Vec<OfflineEntry>>> = Lazy::new(|| Mutex::new(Vec::new()));
static LOADED: Lazy<Mutex<bool>> = Lazy::new(|| Mutex::new(false));

fn manifest_path(offline_dir: &Path) -> PathBuf {
    offline_dir.join("manifest.json")
}

/// Loads the manifest off disk the first time it's touched. Cheap to call
/// repeatedly — every call after the first is just a lock check.
pub fn ensure_loaded(offline_dir: &Path) {
    let mut loaded = LOADED.lock().unwrap();
    if *loaded {
        return;
    }
    *loaded = true;
    let path = manifest_path(offline_dir);
    if let Ok(bytes) = fs::read(&path) {
        if let Ok(entries) = serde_json::from_slice::<Vec<OfflineEntry>>(&bytes) {
            *MANIFEST.lock().unwrap() = entries;
        }
    }
}

fn persist(offline_dir: &Path) {
    let entries = MANIFEST.lock().unwrap().clone();
    let path = manifest_path(offline_dir);
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(json) = serde_json::to_vec_pretty(&entries) {
        let _ = fs::write(&path, json);
    }
}

pub fn list(offline_dir: &Path) -> Vec<OfflineEntry> {
    ensure_loaded(offline_dir);
    MANIFEST.lock().unwrap().clone()
}

pub fn get(offline_dir: &Path, item_id: &str) -> Option<OfflineEntry> {
    ensure_loaded(offline_dir);
    MANIFEST
        .lock()
        .unwrap()
        .iter()
        .find(|e| e.item_id == item_id)
        .cloned()
}

pub fn add(offline_dir: &Path, entry: OfflineEntry) {
    ensure_loaded(offline_dir);
    let mut guard = MANIFEST.lock().unwrap();
    guard.retain(|e| e.item_id != entry.item_id);
    guard.push(entry);
    drop(guard);
    persist(offline_dir);
}

pub fn remove(offline_dir: &Path, item_id: &str) -> Option<OfflineEntry> {
    ensure_loaded(offline_dir);
    let mut guard = MANIFEST.lock().unwrap();
    let idx = guard.iter().position(|e| e.item_id == item_id)?;
    let entry = guard.remove(idx);
    drop(guard);
    persist(offline_dir);
    let _ = fs::remove_file(&entry.path);
    Some(entry)
}
