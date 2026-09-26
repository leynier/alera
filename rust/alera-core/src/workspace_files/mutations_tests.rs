use super::*;

fn workspace() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    fs::create_dir_all(dir.path().join("src/nested")).unwrap();
    fs::create_dir_all(dir.path().join(".git")).unwrap();
    fs::write(dir.path().join("src/main.rs"), "fn main() {}\n").unwrap();
    fs::write(dir.path().join(".git/HEAD"), "ref: refs/heads/main\n").unwrap();
    dir
}

#[test]
fn write_reports_conflicts_and_refreshes_the_token() {
    let dir = workspace();
    let root = dir.path().to_str().unwrap();
    let stale = "0:0";
    let error =
        write_workspace_file(root, "src/main.rs", b"changed", Some(stale), false).unwrap_err();
    assert_eq!(error.kind, WorkspaceFileErrorKind::Conflict);
    assert_eq!(
        fs::read_to_string(dir.path().join("src/main.rs")).unwrap(),
        "fn main() {}\n"
    );
    let written = write_workspace_file(root, "src/main.rs", b"changed", Some(stale), true).unwrap();
    assert_eq!(written.relative_path, "src/main.rs");
    assert_eq!(written.size, 7);
    assert_eq!(
        written.content_token,
        content_token(&fs::metadata(dir.path().join("src/main.rs")).unwrap())
    );
    let again = write_workspace_file(
        root,
        "src/main.rs",
        b"again",
        Some(&written.content_token),
        false,
    )
    .unwrap();
    assert_eq!(again.size, 5);
    assert_eq!(
        write_workspace_file(root, ".git/HEAD", b"x", None, true)
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::ProtectedPath
    );
    assert_eq!(
        write_workspace_file(root, "src", b"x", None, true)
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::Unsupported
    );
    assert_eq!(
        write_workspace_file(root, "../escape", b"x", None, true)
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::InvalidPath
    );
}

#[test]
fn create_rename_copy_move_and_delete_stay_inside_the_workspace() {
    let dir = workspace();
    let root = dir.path().to_str().unwrap();
    let created = create_workspace_file(root, "src", "lib.rs").unwrap();
    assert_eq!(created.relative_path, "src/lib.rs");
    assert_eq!(
        create_workspace_file(root, "src", "lib.rs")
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::AlreadyExists
    );
    assert_eq!(
        create_workspace_file(root, "", ".git").unwrap_err().kind,
        WorkspaceFileErrorKind::ProtectedPath
    );
    assert_eq!(
        create_workspace_directory(root, "src", "../x")
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::InvalidPath
    );
    let folder = create_workspace_directory(root, "", "docs").unwrap();
    assert_eq!(
        folder.kind,
        super::super::WorkspaceExplorerEntryKind::Directory
    );
    let renamed = rename_workspace_entry(root, "src/lib.rs", "util.rs").unwrap();
    assert_eq!(renamed.relative_path, "src/util.rs");
    assert_eq!(
        rename_workspace_entry(root, "src/util.rs", "main.rs")
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::AlreadyExists
    );
    let copied = copy_workspace_entry(root, "src/util.rs", "src").unwrap();
    assert_eq!(copied.relative_path, "src/util copy.rs");
    let moved = move_workspace_entry(root, "src/util copy.rs", "docs").unwrap();
    assert_eq!(moved.relative_path, "docs/util copy.rs");
    assert_eq!(
        move_workspace_entry(root, "src", "src/nested")
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::InvalidPath
    );
    delete_workspace_entry(root, "docs", false).unwrap();
    assert!(!dir.path().join("docs").exists());
    assert_eq!(
        delete_workspace_entry(root, ".git", false)
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::ProtectedPath
    );
    assert!(dir.path().join(".git/HEAD").exists());
}
