use std::fs;

use super::*;
use tempfile::tempdir;

#[test]
fn search_can_include_git_ignored_files() {
    let dir = tempdir().unwrap();
    fs::create_dir(dir.path().join(".git")).unwrap();
    fs::write(dir.path().join(".gitignore"), "ignored.txt\n").unwrap();
    fs::write(dir.path().join("visible.txt"), "needle\n").unwrap();
    fs::write(dir.path().join("ignored.txt"), "needle\n").unwrap();
    fs::write(dir.path().join(".git/config"), "needle\n").unwrap();

    let hidden = search_workspace(search_options(dir.path(), false)).unwrap();

    assert_eq!(hidden.total_matches, 1);
    assert_eq!(hidden.files.len(), 1);
    assert_eq!(hidden.files[0].relative_path, "visible.txt");

    let included = search_workspace(search_options(dir.path(), true)).unwrap();
    let paths = included
        .files
        .iter()
        .map(|file| file.relative_path.as_str())
        .collect::<Vec<_>>();

    assert_eq!(included.total_matches, 2);
    assert!(paths.contains(&"visible.txt"));
    assert!(paths.contains(&"ignored.txt"));
    assert!(!paths.contains(&".git/config"));
}

fn search_options(path: &std::path::Path, include_ignored: bool) -> WorkspaceSearchOptions {
    WorkspaceSearchOptions {
        workspace_path: path.to_string_lossy().to_string(),
        query: "needle".to_string(),
        case_sensitive: true,
        whole_word: false,
        use_regex: false,
        include_pattern: None,
        exclude_pattern: None,
        include_ignored,
        max_results: None,
    }
}
