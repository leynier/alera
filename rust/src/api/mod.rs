pub mod agent_hooks;
pub mod git;
pub mod merman_viewer;
pub mod workspace_files;
pub mod workspace_search;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}
