mod activity;
mod app;
mod app_log;
mod app_menu;
mod assets;
mod design_system;
mod editor_theme;
mod file_icons;
mod forge_api;
mod forge_service;
mod icons;
mod markdown_images;
mod material_icon_layers;
pub use alera_desktop_core::model;
pub use alera_desktop_core::runtime_bridge;
mod terminal;
mod terminal_palette;
mod terminal_theme_catalog;
mod theme;
mod workspace_git;
mod workspace_service;

use std::{path::PathBuf, sync::Arc};

use app::AleraApp;
use assets::AleraAssets;
use gpui::{px, size, App, AppContext as _, Bounds, TitlebarOptions, WindowBounds, WindowOptions};
use gpui_component::Root;
use runtime_bridge::RuntimeBridge;

fn main() {
    app_log::configure(app_log_directory());
    app_log::install_panic_hook();
    let _crash_reporting = app_log::init_crash_reporting(false);
    let bridge = RuntimeBridge::start(runtime_dir());
    let app_name = app_display_name();
    gpui_platform::application()
        .with_assets(AleraAssets)
        .with_http_client(Arc::new(markdown_images::AleraImageHttpClient::new()))
        .run(move |cx: &mut App| {
            gpui_component::init(cx);
            icons::register_fonts(cx);
            editor_theme::register_editor_languages();
            design_system::configure_component_theme(cx);
            app::register_keyboard_actions(cx);
            let bridge = bridge.clone();
            // Start at a desktop-sized canvas so the first GPUI frame matches
            // Flutter's full-window reference on the native MacBook display.
            // The platform clamps this to the available work area while still
            // preserving the user's later window geometry.
            let bounds = Bounds::centered(None, size(px(1400.0), px(900.0)), cx);
            cx.open_window(
                WindowOptions {
                    // Maximized here uses GPUI's reversible native window zoom,
                    // the same operation as double-clicking the titlebar on
                    // macOS, rather than entering fullscreen.
                    window_bounds: Some(WindowBounds::Maximized(bounds)),
                    titlebar: Some(TitlebarOptions {
                        title: Some(app_name.into()),
                        ..Default::default()
                    }),
                    app_id: Some("dev.leynier.alera.gpui".to_string()),
                    window_min_size: Some(size(px(860.0), px(560.0))),
                    ..Default::default()
                },
                move |window, cx| {
                    let app = cx.new(|cx| AleraApp::new(bridge, window, cx));
                    app_menu::install(app_name, &app, window.window_handle(), cx);
                    let root = cx.new(|cx| Root::new(app.clone(), window, cx));
                    // Root must retain the app before startup spawns weak-entity
                    // tasks. Starting immediately afterwards also covers a
                    // bridge that connected before the first frame or defer.
                    app.update(cx, |app, cx| app.start(window, cx));
                    root
                },
            )
            .expect("failed to open the Alera GPUI window");
        });
}

pub fn app_display_name() -> &'static str {
    if std::env::var("ALERA_APP_ID").is_ok_and(|app_id| app_id.ends_with(".dev")) {
        "Alera Dev"
    } else {
        "Alera"
    }
}

fn runtime_dir() -> PathBuf {
    std::env::var_os("ALERA_RUNTIME_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            let app_id = std::env::var_os("ALERA_APP_ID")
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| "dev.leynier.alera.dev".into());
            dirs::data_local_dir().map(|data| data.join(app_id).join("terminal_host"))
        })
        .expect("failed to resolve the Alera runtime directory")
}

pub(crate) fn app_log_directory() -> PathBuf {
    runtime_dir()
        .parent()
        .map(|directory| directory.join("logs"))
        .unwrap_or_else(|| PathBuf::from("logs"))
}

pub(crate) fn local_database_path() -> Option<PathBuf> {
    runtime_dir()
        .parent()
        .map(|directory| directory.join("alera.sqlite"))
}
