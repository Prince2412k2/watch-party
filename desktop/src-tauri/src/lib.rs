mod download;
mod ipc;
mod mpv;
mod offline;
mod window;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
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
