use super::*;

#[test]
fn host_accessible_path_resolves_relative_paths_against_current_dir() {
    let current_dir = std::env::temp_dir().join("alera-cli-path-test");
    let resolved = host_accessible_path("runtime/archive.json".to_string(), &current_dir);

    assert_eq!(resolved, current_dir.join("runtime/archive.json"));
}

#[test]
fn host_accessible_path_keeps_absolute_paths() {
    let current_dir = Path::new("ignored");
    let absolute_path = std::env::temp_dir().join("alera-runtime.tar.gz");
    let resolved = host_accessible_path(absolute_path.to_string_lossy().into_owned(), current_dir);

    assert_eq!(resolved, absolute_path);
}

#[test]
fn workspace_path_value_trims_empty_arguments() {
    assert_eq!(normalized_workspace_path_value(" \t "), None);
    assert_eq!(
        normalized_workspace_path_value(" relative-worktree "),
        Some("relative-worktree".to_string())
    );
}

#[test]
fn host_accessible_path_resolves_relative_workspace_paths_for_rpc() {
    let current_dir = std::env::temp_dir().join("alera-cli-workspace-path-test");
    let resolved = host_accessible_path(
        normalized_workspace_path_value("relative-worktree").unwrap(),
        &current_dir,
    );

    assert_eq!(resolved, current_dir.join("relative-worktree"));
}
