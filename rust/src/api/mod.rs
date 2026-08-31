pub mod agent_hooks;
pub mod ai_dictation;
pub mod clipboard;
pub mod git;
pub mod git_diff_blob;
pub mod git_explorer_status;
pub mod keep_alive;
pub mod merman_viewer;
pub mod process;
pub mod reading_diff;
pub mod workflow_approval;
pub mod workspace_files;
pub mod workspace_search;

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}
