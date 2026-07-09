//! libmpv lifecycle + playback control + property-observe → Tauri events.
//! Owned by agent N1 (Phase 1). See docs/native/PLAN.md, Agent Card N1, and §2.
//!
//! ARCHITECTURE (per PLAN.md §0.6): the player is NATIVE, not React. mpv owns
//! its own native window embedded in the Tauri window (an X11 child window on
//! Linux — see window.rs), positioned via `mpv_set_region` to cover the React
//! "video stage" placeholder, and draws its own OSC for transport controls.
//! There is NO transparent webview / DOM-over-video compositing.
//!
//! We link libmpv.so directly with a hand-rolled FFI surface (the dev box has no
//! libclang, so bindgen-based crates like `libmpv-sys` won't build). Only the
//! handful of client-API functions we actually use are declared. All state
//! changes — whether from a JS-invoked command OR a local OSC click — surface as
//! the same `mpv:*` Tauri events via property observation, which is what lets
//! the JS sync engine stay unchanged (PLAN.md §1/§4.2).

use std::ffi::CString;
use std::os::raw::{c_char, c_double, c_int, c_void};
use std::ptr;
use std::sync::{Mutex, OnceLock};

use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use tauri::{AppHandle, Emitter, Manager};

use crate::window::VideoWindow;

// ── FFI ─────────────────────────────────────────────────────────────────────

#[repr(C)]
struct MpvHandle {
    _private: [u8; 0],
}

#[repr(C)]
struct MpvEvent {
    event_id: c_int,
    error: c_int,
    reply_userdata: u64,
    data: *mut c_void,
}

#[repr(C)]
struct MpvEventProperty {
    name: *const c_char,
    format: c_int,
    data: *mut c_void,
}

// mpv_format
const FORMAT_NONE: c_int = 0;
const FORMAT_FLAG: c_int = 3;
const FORMAT_DOUBLE: c_int = 5;

// mpv_event_id
const EV_SHUTDOWN: c_int = 1;
const EV_END_FILE: c_int = 7;
const EV_FILE_LOADED: c_int = 8;
const EV_SEEK: c_int = 20;
const EV_PLAYBACK_RESTART: c_int = 21;
const EV_PROPERTY_CHANGE: c_int = 22;

// observe_property reply_userdata ids
const OBS_TIME_POS: u64 = 1;
const OBS_PAUSE: u64 = 2;
const OBS_DURATION: u64 = 3;
const OBS_SPEED: u64 = 4;
const OBS_PAUSED_FOR_CACHE: u64 = 5;
const OBS_CACHE_DURATION: u64 = 6;

#[link(name = "mpv")]
extern "C" {
    fn mpv_create() -> *mut MpvHandle;
    fn mpv_initialize(ctx: *mut MpvHandle) -> c_int;
    fn mpv_terminate_destroy(ctx: *mut MpvHandle);
    fn mpv_set_option_string(ctx: *mut MpvHandle, name: *const c_char, data: *const c_char) -> c_int;
    fn mpv_set_property_string(ctx: *mut MpvHandle, name: *const c_char, data: *const c_char) -> c_int;
    fn mpv_get_property(ctx: *mut MpvHandle, name: *const c_char, format: c_int, data: *mut c_void) -> c_int;
    fn mpv_command(ctx: *mut MpvHandle, args: *const *const c_char) -> c_int;
    fn mpv_observe_property(ctx: *mut MpvHandle, reply_userdata: u64, name: *const c_char, format: c_int) -> c_int;
    fn mpv_wait_event(ctx: *mut MpvHandle, timeout: c_double) -> *mut MpvEvent;
}

// glibc setlocale — libmpv refuses to create (`mpv_create` returns NULL) unless
// LC_NUMERIC is the C locale. Tauri/GTK sets a UTF-8 locale, so we pin it back
// for numeric parsing just before creating the mpv handle. LC_NUMERIC == 1 on
// glibc.
extern "C" {
    fn setlocale(category: c_int, locale: *const c_char) -> *mut c_char;
}
const LC_NUMERIC: c_int = 1;

fn pin_c_numeric_locale() {
    let c = CString::new("C").unwrap();
    unsafe {
        setlocale(LC_NUMERIC, c.as_ptr());
    }
}

// ── Player state ─────────────────────────────────────────────────────────────

/// The single global player. libmpv handles are documented thread-safe, so the
/// raw pointer is shared with the event-pump thread; all *other* access goes
/// through this mutex.
struct Player {
    ctx: *mut MpvHandle,
    video: VideoWindow,
}
unsafe impl Send for Player {}

fn player() -> &'static Mutex<Option<Player>> {
    static P: OnceLock<Mutex<Option<Player>>> = OnceLock::new();
    P.get_or_init(|| Mutex::new(None))
}

// ── small FFI helpers ─────────────────────────────────────────────────────────

fn command(ctx: *mut MpvHandle, args: &[&str]) -> Result<(), String> {
    let cstrings: Vec<CString> = args
        .iter()
        .map(|s| CString::new(*s).map_err(|e| e.to_string()))
        .collect::<Result<_, _>>()?;
    let mut ptrs: Vec<*const c_char> = cstrings.iter().map(|c| c.as_ptr()).collect();
    ptrs.push(ptr::null());
    let r = unsafe { mpv_command(ctx, ptrs.as_ptr()) };
    if r < 0 {
        Err(format!("mpv_command {:?} failed ({})", args, r))
    } else {
        Ok(())
    }
}

fn set_prop_str(ctx: *mut MpvHandle, name: &str, value: &str) -> Result<(), String> {
    let n = CString::new(name).map_err(|e| e.to_string())?;
    let v = CString::new(value).map_err(|e| e.to_string())?;
    let r = unsafe { mpv_set_property_string(ctx, n.as_ptr(), v.as_ptr()) };
    if r < 0 {
        Err(format!("set {}={} failed ({})", name, value, r))
    } else {
        Ok(())
    }
}

fn set_opt(ctx: *mut MpvHandle, name: &str, value: &str) {
    if let (Ok(n), Ok(v)) = (CString::new(name), CString::new(value)) {
        unsafe {
            mpv_set_option_string(ctx, n.as_ptr(), v.as_ptr());
        }
    }
}

fn get_prop_f64(ctx: *mut MpvHandle, name: &str) -> Option<f64> {
    let n = CString::new(name).ok()?;
    let mut out: f64 = 0.0;
    let r = unsafe {
        mpv_get_property(ctx, n.as_ptr(), FORMAT_DOUBLE, &mut out as *mut f64 as *mut c_void)
    };
    if r < 0 {
        None
    } else {
        Some(out)
    }
}

fn observe(ctx: *mut MpvHandle, id: u64, name: &str, format: c_int) {
    if let Ok(n) = CString::new(name) {
        unsafe {
            mpv_observe_property(ctx, id, n.as_ptr(), format);
        }
    }
}

fn parent_xid(app: &AppHandle) -> Result<x11::xlib::Window, String> {
    let win = app
        .get_webview_window("main")
        .ok_or_else(|| "no `main` window".to_string())?;
    let handle = win.window_handle().map_err(|e| e.to_string())?;
    match handle.as_raw() {
        RawWindowHandle::Xlib(h) => Ok(h.window as x11::xlib::Window),
        RawWindowHandle::Xcb(h) => Ok(h.window.get() as x11::xlib::Window),
        _ => Err("Tauri window is not X11 — launch with GDK_BACKEND=x11".into()),
    }
}

// ── lifecycle ─────────────────────────────────────────────────────────────────

/// Create the mpv instance + its embedded X11 child window if not already up.
/// Idempotent. Called by both `mpv_load` and `mpv_set_region` so the surface
/// exists whichever command the frontend fires first.
fn ensure_player(app: &AppHandle) -> Result<(), String> {
    let mut guard = player().lock().map_err(|e| e.to_string())?;
    if guard.is_some() {
        return Ok(());
    }

    let xid = parent_xid(app)?;
    let video = VideoWindow::create(xid)?;

    let cache_dir = app
        .path()
        .app_cache_dir()
        .map(|p| p.join("mpv-cache"))
        .map_err(|e| e.to_string())?;
    let _ = std::fs::create_dir_all(&cache_dir);

    pin_c_numeric_locale();
    let ctx = unsafe { mpv_create() };
    if ctx.is_null() {
        return Err("mpv_create returned null".into());
    }

    // Options that must be set before mpv_initialize.
    let debug = std::env::var("MPV_DEBUG").is_ok();
    set_opt(ctx, "terminal", if debug { "yes" } else { "no" });
    set_opt(ctx, "msg-level", if debug { "all=v" } else { "all=no" });
    // Video output. `gpu` is preferred (HW decode / 4K HEVC); overridable for
    // diagnosis on quirky compositors (e.g. `MPV_VO=x11`).
    if let Ok(vo) = std::env::var("MPV_VO") {
        set_opt(ctx, "vo", &vo);
    }
    set_opt(ctx, "config", "no");
    set_opt(ctx, "idle", "yes");
    set_opt(ctx, "force-window", "yes");
    // Embed into the X11 child window. `wid` is an X11 window id, so mpv must
    // use its X11 GPU context — otherwise (with WAYLAND_DISPLAY set) it opens its
    // OWN Wayland surface and ignores `wid`, leaving the embedded window black.
    set_opt(ctx, "wid", &video.xid().to_string());
    set_opt(ctx, "gpu-context", "x11egl");
    // Input + built-in OSC (transport controls drawn by mpv itself, PLAN §0.6).
    set_opt(ctx, "input-default-bindings", "yes");
    set_opt(ctx, "input-vo-keyboard", "yes");
    set_opt(ctx, "input-cursor", "yes");
    set_opt(ctx, "osc", "yes");
    // Best-effort monochrome-ish skin (PLAN §2 risk 3 — not pixel-perfect).
    set_opt(
        ctx,
        "script-opts",
        "osc-layout=bottombar,osc-seekbarstyle=bar,osc-boxalpha=90,osc-seekbarkeyframes=no,osc-visibility=auto",
    );
    // All-codec HW decode when safe.
    set_opt(ctx, "hwdec", "auto-safe");
    // Progressive on-disk watch cache (PLAN §0.3 / N1 task 3).
    set_opt(ctx, "cache", "yes");
    set_opt(ctx, "cache-on-disk", "yes");
    set_opt(ctx, "demuxer-cache-dir", &cache_dir.to_string_lossy());

    let r = unsafe { mpv_initialize(ctx) };
    if r < 0 {
        unsafe { mpv_terminate_destroy(ctx) };
        return Err(format!("mpv_initialize failed ({})", r));
    }

    // Property observation → mpv:* events (fired for OSC clicks AND JS commands).
    observe(ctx, OBS_TIME_POS, "time-pos", FORMAT_DOUBLE);
    observe(ctx, OBS_PAUSE, "pause", FORMAT_FLAG);
    observe(ctx, OBS_DURATION, "duration", FORMAT_DOUBLE);
    observe(ctx, OBS_SPEED, "speed", FORMAT_DOUBLE);
    observe(ctx, OBS_PAUSED_FOR_CACHE, "paused-for-cache", FORMAT_FLAG);
    observe(ctx, OBS_CACHE_DURATION, "demuxer-cache-duration", FORMAT_DOUBLE);

    spawn_event_thread(app.clone(), ctx as usize);

    *guard = Some(Player { ctx, video });
    Ok(())
}

fn spawn_event_thread(app: AppHandle, ctx_addr: usize) {
    std::thread::spawn(move || {
        let ctx = ctx_addr as *mut MpvHandle;
        loop {
            let ev = unsafe { mpv_wait_event(ctx, 1.0) };
            if ev.is_null() {
                continue;
            }
            let ev = unsafe { &*ev };
            match ev.event_id {
                EV_SHUTDOWN => {
                    unsafe { mpv_terminate_destroy(ctx) };
                    break;
                }
                EV_FILE_LOADED => {
                    if let Some(d) = get_prop_f64(ctx, "duration") {
                        let _ = app.emit("mpv:loadedmetadata", serde_json::json!({ "durationSec": d }));
                    }
                }
                EV_END_FILE => {
                    let _ = app.emit("mpv:eof", serde_json::json!({}));
                }
                EV_SEEK => {
                    let _ = app.emit("mpv:seeking", serde_json::json!({}));
                }
                EV_PLAYBACK_RESTART => {
                    let sec = get_prop_f64(ctx, "time-pos").unwrap_or(0.0);
                    let _ = app.emit("mpv:seeked", serde_json::json!({ "sec": sec }));
                }
                EV_PROPERTY_CHANGE => {
                    emit_property_change(&app, ev);
                }
                _ => {}
            }
        }
    });
}

fn emit_property_change(app: &AppHandle, ev: &MpvEvent) {
    if ev.data.is_null() {
        return;
    }
    let prop = unsafe { &*(ev.data as *const MpvEventProperty) };
    if prop.format == FORMAT_NONE || prop.data.is_null() {
        return;
    }
    match ev.reply_userdata {
        OBS_TIME_POS => {
            let v = unsafe { *(prop.data as *const f64) };
            let _ = app.emit("mpv:timepos", serde_json::json!({ "sec": v }));
        }
        OBS_PAUSE => {
            let v = unsafe { *(prop.data as *const c_int) } != 0;
            let _ = app.emit("mpv:pause", serde_json::json!({ "paused": v }));
        }
        OBS_DURATION => {
            let v = unsafe { *(prop.data as *const f64) };
            let _ = app.emit("mpv:duration", serde_json::json!({ "sec": v }));
        }
        OBS_SPEED => {
            let v = unsafe { *(prop.data as *const f64) };
            let _ = app.emit("mpv:speed", serde_json::json!({ "rate": v }));
        }
        OBS_PAUSED_FOR_CACHE => {
            let v = unsafe { *(prop.data as *const c_int) } != 0;
            let _ = app.emit("mpv:buffering", serde_json::json!({ "active": v }));
        }
        OBS_CACHE_DURATION => {
            let v = unsafe { *(prop.data as *const f64) };
            // cachedBytes isn't cheaply available as a scalar prop; the adapter
            // synthesizes `buffered` from cachedAheadSec, which is what matters.
            let _ = app.emit(
                "mpv:cache",
                serde_json::json!({ "cachedAheadSec": v, "cachedBytes": 0 }),
            );
        }
        _ => {}
    }
}

/// Run a closure with the live mpv ctx, or error if the player isn't up yet.
fn with_ctx<F>(f: F) -> Result<(), String>
where
    F: FnOnce(*mut MpvHandle) -> Result<(), String>,
{
    let guard = player().lock().map_err(|e| e.to_string())?;
    match guard.as_ref() {
        Some(p) => f(p.ctx),
        None => Err("mpv not initialized (call mpv_load first)".into()),
    }
}

// ── public API (called from ipc.rs command bodies) ────────────────────────────

pub fn load(app: &AppHandle, url: &str, start_sec: f64, paused: bool) -> Result<(), String> {
    ensure_player(app)?;
    with_ctx(|ctx| {
        let opts = format!("start={}", start_sec);
        command(ctx, &["loadfile", url, "replace", &opts])?;
        set_prop_str(ctx, "pause", if paused { "yes" } else { "no" })?;
        Ok(())
    })
}

pub fn play() -> Result<(), String> {
    with_ctx(|ctx| set_prop_str(ctx, "pause", "no"))
}

pub fn pause() -> Result<(), String> {
    with_ctx(|ctx| set_prop_str(ctx, "pause", "yes"))
}

pub fn seek(sec: f64) -> Result<(), String> {
    with_ctx(|ctx| command(ctx, &["seek", &sec.to_string(), "absolute+exact"]))
}

pub fn set_speed(rate: f64) -> Result<(), String> {
    with_ctx(|ctx| set_prop_str(ctx, "speed", &rate.to_string()))
}

pub fn set_volume(vol: f64) -> Result<(), String> {
    // contract: 0..1 → mpv: 0..100
    let v = (vol.clamp(0.0, 1.0) * 100.0).round();
    with_ctx(|ctx| set_prop_str(ctx, "volume", &v.to_string()))
}

pub fn set_muted(muted: bool) -> Result<(), String> {
    with_ctx(|ctx| set_prop_str(ctx, "mute", if muted { "yes" } else { "no" }))
}

pub fn set_region(app: &AppHandle, x: f64, y: f64, w: f64, h: f64, _dpr: f64) -> Result<(), String> {
    ensure_player(app)?;
    let mut guard = player().lock().map_err(|e| e.to_string())?;
    if let Some(p) = guard.as_mut() {
        p.video
            .set_region(x.round() as i32, y.round() as i32, w.round() as u32, h.round() as u32);
    }
    Ok(())
}

pub fn set_fullscreen(on: bool) -> Result<(), String> {
    let mut guard = player().lock().map_err(|e| e.to_string())?;
    if let Some(p) = guard.as_mut() {
        p.video.set_fullscreen(on);
    }
    Ok(())
}

/// Gate mpv's own OSC (PLAN §2 risk 2). When `false`, hide the OSC so a plain
/// guest has no seek-bar/play-pause to click, and drop default input bindings so
/// keyboard transport is inert too. When `true`, restore both.
pub fn set_can_control(can: bool) -> Result<(), String> {
    with_ctx(|ctx| {
        let vis = if can { "auto" } else { "never" };
        command(ctx, &["script-message", "osc-visibility", vis])?;
        set_prop_str(ctx, "input-default-bindings", if can { "yes" } else { "no" })?;
        Ok(())
    })
}

pub fn teardown() -> Result<(), String> {
    // Unload the current file but keep the mpv instance + embedded window alive
    // for reuse (single-window app). Safe: no window teardown races mpv render.
    with_ctx(|ctx| command(ctx, &["stop"]))
}

/// Dev-only self-test: if `MPV_SMOKE` points at a media file, embed the player
/// over a fixed rect and start playing it a couple seconds after boot. Lets N1
/// screenshot real embedded playback without a backend/login/party. No-op unless
/// the env var is set, so it never affects normal runs.
pub fn maybe_smoke_test(app: &AppHandle) {
    let Ok(path) = std::env::var("MPV_SMOKE") else {
        return;
    };
    let app = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(1500));
        if let Err(e) = set_region(&app, 40.0, 60.0, 900.0, 520.0, 1.0) {
            eprintln!("[mpv-smoke] set_region failed: {e}");
            return;
        }
        if let Err(e) = load(&app, &path, 0.0, false) {
            eprintln!("[mpv-smoke] load failed: {e}");
        } else {
            eprintln!("[mpv-smoke] loaded {path} into embedded region");
        }
    });
}
