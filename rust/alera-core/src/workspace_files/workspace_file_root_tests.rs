use super::*;

#[test]
fn bounded_read_rejects_traversal_and_symlink_escape() {
    let workspace = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    fs::write(workspace.path().join("inside.txt"), "hello").unwrap();
    fs::create_dir(workspace.path().join(".git")).unwrap();
    fs::write(workspace.path().join(".git/config"), "secret").unwrap();
    fs::write(outside.path().join("secret.txt"), "secret").unwrap();
    let root = workspace.path().to_string_lossy();
    assert!(read_workspace_file_range(&root, "../secret.txt", 0, 10).is_err());
    assert_eq!(
        read_workspace_file_range(&root, ".git/config", 0, 10)
            .unwrap_err()
            .kind,
        WorkspaceFileErrorKind::InvalidPath
    );
    assert!(is_protected_workspace_path(Path::new(".GIT/config")));
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(
            workspace.path().join(".git/config"),
            workspace.path().join("config-link"),
        )
        .unwrap();
        assert_eq!(
            read_workspace_file_range(&root, "config-link", 0, 10)
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
        std::os::unix::fs::symlink(
            workspace.path().join(".git"),
            workspace.path().join("metadata-link"),
        )
        .unwrap();
        assert_eq!(
            read_workspace_file_range(&root, "metadata-link/config", 0, 10)
                .unwrap_err()
                .kind,
            WorkspaceFileErrorKind::InvalidPath
        );
        std::os::unix::fs::symlink(
            outside.path().join("secret.txt"),
            workspace.path().join("link.txt"),
        )
        .unwrap();
        assert!(read_workspace_file_range(&root, "link.txt", 0, 10).is_err());
    }
    let result = read_workspace_file_range(&root, "inside.txt", 1, 3).unwrap();
    assert_eq!(result.bytes, b"ell");
    assert_eq!(result.next_offset, 4);
}

#[cfg(unix)]
#[test]
fn opened_root_stays_pinned_when_workspace_path_is_replaced() {
    let parent = tempfile::tempdir().unwrap();
    let workspace = parent.path().join("workspace");
    let moved_workspace = parent.path().join("workspace-moved");
    let replacement = parent.path().join("replacement");
    fs::create_dir(&workspace).unwrap();
    fs::create_dir(&replacement).unwrap();
    fs::write(workspace.join("inside.txt"), "inside").unwrap();
    fs::write(replacement.join("config"), "secret").unwrap();
    let root = open_workspace_file_root(&workspace.to_string_lossy()).unwrap();

    fs::rename(&workspace, &moved_workspace).unwrap();
    std::os::unix::fs::symlink(&replacement, &workspace).unwrap();

    let inside = read_workspace_file_range_from_root(&root, "inside.txt", 0, 10).unwrap();
    assert_eq!(inside.bytes, b"inside");
    assert!(read_workspace_file_range_from_root(&root, "config", 0, 10).is_err());
}

#[test]
fn ranged_text_detection_allows_split_utf8_code_points() {
    let workspace = tempfile::tempdir().unwrap();
    let path = workspace.path().join("utf8.txt");
    fs::write(&path, "aéz").unwrap();
    let root = workspace.path().to_string_lossy();

    let leading_half = read_workspace_file_range(&root, "utf8.txt", 0, 2).unwrap();
    let trailing_half = read_workspace_file_range(&root, "utf8.txt", 2, 2).unwrap();

    assert!(leading_half.is_text);
    assert!(trailing_half.is_text);
}

#[test]
fn ranged_text_detection_rejects_invalid_interior_utf8() {
    assert!(!range_is_probably_utf8(&[b'a', 0xff, b'z'], false));
    assert!(!range_is_probably_utf8(&[b'a', 0, b'z'], false));
    assert!(!range_is_probably_utf8(&[b'a', 0xc3], false));
    assert!(!range_is_probably_utf8(&[0x80, b'a'], false));
    assert!(range_is_probably_utf8(&[b'a', 0xc3], true));
}

#[test]
fn ranged_text_detection_rejects_incomplete_utf8_at_eof() {
    let workspace = tempfile::tempdir().unwrap();
    fs::write(workspace.path().join("broken.bin"), [b'a', 0xc3]).unwrap();
    fs::write(workspace.path().join("invalid-prefix.bin"), [0x80, b'a']).unwrap();
    let root = workspace.path().to_string_lossy();

    let result = read_workspace_file_range(&root, "broken.bin", 0, 2).unwrap();
    assert!(!result.is_text);
    assert_eq!(result.mime_type, "application/octet-stream");

    let result = read_workspace_file_range(&root, "invalid-prefix.bin", 0, 2).unwrap();
    assert!(!result.is_text);
    assert_eq!(result.mime_type, "application/octet-stream");
}

#[cfg(unix)]
#[test]
fn relative_paths_preserve_literal_backslashes_in_file_names() {
    let workspace = tempfile::tempdir().unwrap();
    let root = fs::canonicalize(workspace.path()).unwrap();
    let literal = root.join("foo\\bar.txt");
    fs::write(&literal, b"literal").unwrap();
    let canonical = fs::canonicalize(&literal).unwrap();

    assert_eq!(relative_string(&root, &canonical).unwrap(), "foo\\bar.txt");
    let range = read_workspace_file_range(&root.to_string_lossy(), "foo\\bar.txt", 0, 7).unwrap();
    assert_eq!(range.bytes, b"literal");
}

#[test]
fn ranged_reads_keep_mixed_file_classification_stable() {
    let workspace = tempfile::tempdir().unwrap();
    fs::write(workspace.path().join("mixed.bin"), b"hello\0world").unwrap();
    let root = workspace.path().to_string_lossy();

    let ascii_range = read_workspace_file_range(&root, "mixed.bin", 0, 5).unwrap();
    let binary_range = read_workspace_file_range(&root, "mixed.bin", 5, 6).unwrap();

    assert!(!ascii_range.is_text);
    assert!(!binary_range.is_text);
    assert_eq!(ascii_range.mime_type, "application/octet-stream");
    assert_eq!(binary_range.mime_type, "application/octet-stream");
}

#[test]
fn binary_preview_mime_is_not_exposed_as_text() {
    let workspace = tempfile::tempdir().unwrap();
    fs::write(workspace.path().join("document.pdf"), b"plain ascii").unwrap();
    let root = workspace.path().to_string_lossy();

    let result = read_workspace_file_range(&root, "document.pdf", 0, 5).unwrap();

    assert!(!result.is_text);
    assert_eq!(result.mime_type, "application/pdf");
}
