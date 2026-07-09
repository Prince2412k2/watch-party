//! Embedding of mpv's native window + video-region bounds tracking +
//! fullscreen. Owned by agent N1 (Phase 1), alongside mpv.rs — the two are
//! tightly coupled (this module reparents/positions the opaque mpv window to
//! cover the React video-stage rect). NO window transparency is needed — the
//! player is native and opaque (PLAN.md §0.6/§2, superseding the old
//! transparent-webview plan).
//!
//! APPROACH (mirrors MaxVideoPlayer's X11-child path, PLAN.md §2b — studied, not
//! copied): create a plain X11 child window under the Tauri top-level window's
//! XID, hand its XID to libmpv via the `wid` option, and drive its geometry with
//! `XMoveResizeWindow` so it tracks the React "video stage" div. Child X windows
//! stack above the parent's own drawing, so the opaque mpv surface sits over the
//! webview at exactly the reported rect. The dev box is XWayland
//! (GDK_BACKEND=x11), so the Tauri window is a real X11 window — see
//! SPIKE-NOTES.md.

use std::os::raw::{c_int, c_uint};
use std::ptr;
use x11::xlib;

/// An opaque X11 child window that libmpv renders into (via `--wid`). Owns its
/// own Xlib display connection; mpv opens a *separate* connection internally.
pub struct VideoWindow {
    display: *mut xlib::Display,
    parent: xlib::Window,
    win: xlib::Window,
    /// Last requested rect in device pixels (x, y, w, h).
    rect: (i32, i32, u32, u32),
    fullscreen: bool,
}

// The raw Xlib pointers are only ever touched under the single Player mutex.
unsafe impl Send for VideoWindow {}

impl VideoWindow {
    /// Create + map a child window under `parent` (the Tauri window's XID).
    pub fn create(parent: xlib::Window) -> Result<Self, String> {
        unsafe {
            // Xlib must be told we may touch the display from >1 thread (mpv also
            // has its own connection, but we call XInitThreads defensively).
            xlib::XInitThreads();
            let display = xlib::XOpenDisplay(ptr::null());
            if display.is_null() {
                return Err("XOpenDisplay(NULL) failed — no X11 display (need GDK_BACKEND=x11?)".into());
            }
            let screen = xlib::XDefaultScreen(display);
            let black = xlib::XBlackPixel(display, screen);
            let win = xlib::XCreateSimpleWindow(display, parent, 0, 0, 16, 16, 0, black, black);
            if win == 0 {
                xlib::XCloseDisplay(display);
                return Err("XCreateSimpleWindow failed".into());
            }
            xlib::XMapWindow(display, win);
            xlib::XRaiseWindow(display, win);
            xlib::XFlush(display);
            Ok(VideoWindow {
                display,
                parent,
                win,
                rect: (0, 0, 16, 16),
                fullscreen: false,
            })
        }
    }

    /// XID to hand to libmpv's `wid` option.
    pub fn xid(&self) -> xlib::Window {
        self.win
    }

    pub fn set_region(&mut self, x: i32, y: i32, w: u32, h: u32) {
        self.rect = (x, y, w.max(1), h.max(1));
        if !self.fullscreen {
            self.apply();
        }
    }

    pub fn set_fullscreen(&mut self, on: bool) {
        self.fullscreen = on;
        self.apply();
    }

    fn apply(&self) {
        let (x, y, w, h) = if self.fullscreen {
            self.parent_geometry().unwrap_or(self.rect)
        } else {
            self.rect
        };
        unsafe {
            xlib::XMoveResizeWindow(self.display, self.win, x, y, w.max(1), h.max(1));
            xlib::XRaiseWindow(self.display, self.win);
            xlib::XFlush(self.display);
        }
    }

    /// Size of the parent (top-level) window, used for the fullscreen-fills-window
    /// case. Real OS fullscreen of the Tauri window itself is the frontend/N7's
    /// job; here we just grow the video surface to cover the whole window.
    fn parent_geometry(&self) -> Option<(i32, i32, u32, u32)> {
        unsafe {
            let mut root: xlib::Window = 0;
            let (mut x, mut y): (c_int, c_int) = (0, 0);
            let (mut w, mut h, mut bw, mut depth): (c_uint, c_uint, c_uint, c_uint) =
                (0, 0, 0, 0);
            let ok = xlib::XGetGeometry(
                self.display, self.parent, &mut root, &mut x, &mut y, &mut w, &mut h, &mut bw,
                &mut depth,
            );
            if ok == 0 {
                None
            } else {
                Some((0, 0, w, h))
            }
        }
    }
}

impl Drop for VideoWindow {
    fn drop(&mut self) {
        unsafe {
            if !self.display.is_null() {
                xlib::XDestroyWindow(self.display, self.win);
                xlib::XCloseDisplay(self.display);
            }
        }
    }
}
