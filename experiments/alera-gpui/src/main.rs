mod activity;
mod app;
mod forge_api;
mod forge_service;
mod model;
mod runtime_bridge;
mod terminal;
mod terminal_palette;
mod theme;
mod workspace_git;
mod workspace_preview;
mod workspace_service;

use std::path::PathBuf;

use app::AleraApp;
use gpui::{App, AppContext as _, Application, WindowOptions};
use gpui_component::Root;
use runtime_bridge::RuntimeBridge;

fn main() {
    let bridge = RuntimeBridge::start(runtime_dir());
    Application::new().run(move |cx: &mut App| {
        gpui_component::init(cx);
        let bridge = bridge.clone();
        cx.open_window(WindowOptions::default(), move |window, cx| {
            let app = cx.new(|cx| AleraApp::new(bridge, window, cx));
            cx.new(|cx| Root::new(app, window, cx))
        })
        .expect("failed to open the Alera GPUI window");
    });
}

fn runtime_dir() -> PathBuf {
    std::env::var_os("ALERA_RUNTIME_DIR")
        .map(PathBuf::from)
        .or_else(|| {
            dirs::data_local_dir().map(|data| data.join("dev.leynier.alera").join("terminal_host"))
        })
        .expect("failed to resolve the Alera runtime directory")
}
