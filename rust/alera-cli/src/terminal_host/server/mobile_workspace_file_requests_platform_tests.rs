use super::absolute_workspace_file_target;

#[test]
fn absolute_files_preserve_literal_backslashes_in_file_names() {
    let workspace = tempfile::tempdir().unwrap();
    let file = workspace.path().join("foo\\bar.txt");
    std::fs::write(&file, b"literal").unwrap();

    let (_, relative) = absolute_workspace_file_target(
        &file.to_string_lossy(),
        vec![workspace.path().to_string_lossy().into_owned()],
    )
    .unwrap();

    assert_eq!(relative, "foo\\bar.txt");
}
