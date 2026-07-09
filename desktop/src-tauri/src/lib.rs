mod download;
mod ipc;
mod mpv;
mod offline;
mod window;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();

    // Testing/debugging bridge for @hypothesi/tauri-mcp-cli — debug builds only,
    // never present in release. See desktop/README.md and get-setup-instructions.
    #[cfg(debug_assertions)]
    let builder = builder.plugin(tauri_plugin_mcp_bridge::init());

    builder
        // N7: a second launch (e.g. double-clicking the app icon again while
        // it's tray-resident) focuses the existing window instead of spawning
        // a competing process that would fight N2's downloader over the same
        // on-disk state (docs/native/PLAN.md §2b/§0.5).
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        // N7: persist/restore window size + position across launches.
        .plugin(tauri_plugin_window_state::Builder::default().build())
        // N7: updater plugin registration — no update server configured yet
        // (see desktop/README.md "Updater" section for the stub/TODO).
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            // N7: system tray — "Show" restores the window, "Quit" runs the
            // real exit path (same body as the `app_quit` IPC command, so
            // N2's flush hook runs either way it's triggered).
            let show_item = MenuItem::with_id(app, "show", "Show Watchparty", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let tray_menu = Menu::with_items(app, &[&show_item, &quit_item])?;

            TrayIconBuilder::new()
                .icon(app.default_window_icon().cloned().unwrap())
                .menu(&tray_menu)
                .show_menu_on_left_click(true)
                .tooltip("Watchparty")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => {
                        let app_handle = app.clone();
                        tauri::async_runtime::spawn(async move {
                            let _ = ipc::app_quit(app_handle).await;
                        });
                    }
                    _ => {}
                })
                .build(app)?;

            // N1 dev-only embedded-playback smoke test (env-gated, see mpv.rs).
            mpv::maybe_smoke_test(&app.handle());
            Ok(())
        })
        // N7: closing the window hides it to the tray instead of quitting —
        // the process (and any of N2's in-flight downloads) stays alive.
        // Only the tray "Quit" item / `app_quit` command perform a real exit.
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            // mpv.rs (N1)
            ipc::mpv_load,
            ipc::mpv_play,
            ipc::mpv_pause,
            ipc::mpv_seek,
            ipc::mpv_set_speed,
            ipc::mpv_set_volume,
            ipc::mpv_set_muted,
            ipc::mpv_set_region,
            ipc::mpv_set_fullscreen,
            ipc::mpv_set_can_control,
            ipc::mpv_teardown,
            // download.rs / offline.rs (N2)
            ipc::dl_start,
            ipc::dl_pause,
            ipc::dl_resume,
            ipc::dl_cancel,
            ipc::dl_list,
            ipc::offline_list,
            ipc::offline_path,
            ipc::offline_remove,
            // lifecycle (N7)
            ipc::app_quit,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
