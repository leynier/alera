use super::*;
use alera_core::workspace_files::{
    search_workspace_quick_open_session, stop_workspace_quick_open_session,
};

#[tokio::test]
async fn remote_file_catalog_searches_owner_paths_and_closes_without_local_fallback() {
    let (_state, _local, store, project) = fixture().await;
    let path = "/remote/only/project";
    register(&store, request(&project, path), &Remote::folder(path))
        .await
        .unwrap();
    let mut remote = Remote::folder(path);
    remote.response =
        json!({"version": 1, "path": path, "files": ["src/remote-only.dart", "literal\\name.txt"]});
    let session = crate::project_file_catalog::list(&store, &project, "ssh", &remote)
        .await
        .unwrap();
    let matches =
        search_workspace_quick_open_session(session.clone(), "remote-only".into(), 10).unwrap();
    assert_eq!(matches[0].relative_path, "src/remote-only.dart");
    assert!(
        search_workspace_quick_open_session(session.clone(), "keep".into(), 10)
            .unwrap()
            .is_empty()
    );
    assert!(remote.scripts.lock().unwrap()[0].contains("inspect-checkout-files"));
    stop_workspace_quick_open_session(session.clone());
    assert!(search_workspace_quick_open_session(session, "remote".into(), 10).is_err());
    for response in [
        json!({"version": 1, "path": "/wrong", "files": []}),
        json!({"version": 2, "path": path, "files": []}),
        json!({"version": 1, "path": path, "files": ["../outside"]}),
        json!({"version": 1, "path": path, "files": ["/absolute"]}),
        json!({"version": 1, "path": path, "files": ["a".repeat(2 * 1024 * 1024 + 1)]}),
    ] {
        remote.response = response;
        assert!(
            crate::project_file_catalog::list(&store, &project, "ssh", &remote)
                .await
                .is_err()
        );
    }
}

#[tokio::test]
async fn owner_file_catalog_excludes_ignored_protected_and_symlink_files() {
    let folder = tempfile::tempdir().unwrap();
    std::fs::write(folder.path().join(".gitignore"), "ignored.txt\n").unwrap();
    std::fs::write(folder.path().join("ignored.txt"), "ignore").unwrap();
    std::fs::write(folder.path().join("visible.txt"), "visible").unwrap();
    std::fs::create_dir(folder.path().join(".git")).unwrap();
    std::fs::write(folder.path().join(".git/config"), "protected").unwrap();
    #[cfg(unix)]
    std::os::unix::fs::symlink("visible.txt", folder.path().join("link.txt")).unwrap();
    let catalog = crate::project_file_catalog::inspect(folder.path().to_str().unwrap().into())
        .await
        .unwrap();
    assert!(catalog.files.contains(&"visible.txt".into()));
    assert!(!catalog
        .files
        .iter()
        .any(|file| file == "ignored.txt" || file == "link.txt" || file.starts_with(".git/")));
}
