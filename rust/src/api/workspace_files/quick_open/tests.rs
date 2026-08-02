use std::fs;
use std::io;
use std::path::Path;
use std::thread;

use super::super::{WorkspaceFileErrorKind, WorkspaceQuickOpenSession};
use super::{
    search_workspace_quick_open_session, start_workspace_quick_open_session,
    stop_workspace_quick_open_session,
};

fn workspace_path(directory: &tempfile::TempDir) -> String {
    directory.path().to_string_lossy().into_owned()
}

fn create_file(directory: &Path, relative_path: &str) {
    let path = directory.join(relative_path);
    fs::create_dir_all(path.parent().expect("file parent")).expect("create file parent");
    fs::write(path, relative_path).expect("write file");
}

fn search_paths(session: &WorkspaceQuickOpenSession, query: &str, limit: u32) -> Vec<String> {
    search_workspace_quick_open_session(session.clone(), query.to_string(), limit)
        .expect("quick open search")
        .into_iter()
        .map(|result| result.relative_path)
        .collect()
}

#[test]
fn indexes_ignored_hidden_protected_and_parent_ignored_files() {
    let container = tempfile::tempdir().expect("container");
    let workspace = container.path().join("workspace");
    fs::create_dir(&workspace).expect("workspace");
    fs::create_dir(container.path().join(".git")).expect("parent git directory");
    fs::write(
        container.path().join(".gitignore"),
        "workspace/parent.txt\n",
    )
    .expect("parent gitignore");
    fs::write(workspace.join(".gitignore"), "ignored.txt\nignored-dir/\n")
        .expect("workspace gitignore");
    create_file(&workspace, ".env");
    create_file(&workspace, ".config/settings.json");
    create_file(&workspace, "visible.txt");
    create_file(&workspace, "parent.txt");
    create_file(&workspace, "ignored.txt");
    create_file(&workspace, "ignored-dir/secret.txt");
    for protected in [".git", ".hg", ".svn"] {
        create_file(&workspace, &format!("{protected}/secret.txt"));
    }

    let session = start_workspace_quick_open_session(workspace.to_string_lossy().into_owned())
        .expect("start session");
    let paths = search_paths(&session, "", 100);

    assert_eq!(session.indexed_file_count, 4);
    assert_eq!(
        paths,
        vec![".config/settings.json", ".env", ".gitignore", "visible.txt",]
    );
    stop_workspace_quick_open_session(session);
}

#[test]
fn indexes_more_than_twenty_thousand_files_without_truncation() {
    let workspace = tempfile::tempdir().expect("workspace");
    for index in 0..20_001 {
        create_file(workspace.path(), &format!("files/file_{index:05}.txt"));
    }

    let session = start_workspace_quick_open_session(workspace_path(&workspace)).expect("start");

    assert_eq!(session.indexed_file_count, 20_001);
    assert_eq!(
        search_paths(&session, "file_20000.txt", 50),
        ["files/file_20000.txt"]
    );
    assert_eq!(search_paths(&session, "", 50).len(), 50);
    stop_workspace_quick_open_session(session);
}

#[test]
fn ranks_all_tiers_with_dart_compatible_precedence() {
    let workspace = tempfile::tempdir().expect("workspace");
    for path in [
        "main.dart",
        "lib/main.dart",
        "lib/maintenance.dart",
        "src/main_test.dart",
        "lib/workspace_state.dart",
        "lib/workbench.dart",
        "README.md",
        "lib/terminal.dart",
        "lib/microtasks.dart",
    ] {
        create_file(workspace.path(), path);
    }
    let session = start_workspace_quick_open_session(workspace_path(&workspace)).expect("start");

    assert_eq!(
        search_paths(&session, "main.dart", 50),
        vec![
            "main.dart",
            "lib/main.dart",
            "src/main_test.dart",
            "lib/maintenance.dart",
        ]
    );
    assert!(search_paths(&session, "wst", 50).contains(&"lib/workspace_state.dart".to_string()));
    assert_eq!(search_paths(&session, "minal", 1), ["lib/terminal.dart"]);
    stop_workspace_quick_open_session(session);
}

#[test]
fn repeated_segments_keep_the_first_segment_score_once() {
    let workspace = tempfile::tempdir().expect("workspace");
    for path in [
        "src/file.dart",
        "lib/src/other.dart",
        "lib/src/src/repeated.dart",
    ] {
        create_file(workspace.path(), path);
    }
    let session = start_workspace_quick_open_session(workspace_path(&workspace)).expect("start");

    let matches = search_workspace_quick_open_session(session.clone(), "src".to_string(), 50)
        .expect("quick open search");
    assert_eq!(matches.len(), 3);
    assert_eq!(matches[0].relative_path, "src/file.dart");
    assert_eq!(matches[0].score, 90_000);
    assert_eq!(matches[1].relative_path, "lib/src/other.dart");
    assert_eq!(matches[1].score, 89_999);
    assert_eq!(matches[2].relative_path, "lib/src/src/repeated.dart");
    assert_eq!(matches[2].score, 89_999);
    stop_workspace_quick_open_session(session);
}

#[test]
fn ranks_empty_queries_case_insensitively_and_breaks_ties_deterministically() {
    let workspace = tempfile::tempdir().expect("workspace");
    for path in ["lib/README.md", "A.dart", "a.dart", "lib/reader.dart"] {
        create_file(workspace.path(), path);
    }
    let session = start_workspace_quick_open_session(workspace_path(&workspace)).expect("start");

    assert_eq!(
        search_paths(&session, "", 50),
        ["A.dart", "a.dart", "lib/reader.dart", "lib/README.md",]
    );
    assert_eq!(search_paths(&session, "ReAdMe", 50), ["lib/README.md"]);
    stop_workspace_quick_open_session(session);
}

#[test]
fn honors_result_limit_without_sorting_the_whole_index() {
    let workspace = tempfile::tempdir().expect("workspace");
    for path in ["src/c.dart", "src/b.dart", "src/a.dart"] {
        create_file(workspace.path(), path);
    }
    let session = start_workspace_quick_open_session(workspace_path(&workspace)).expect("start");

    assert_eq!(
        search_paths(&session, "src", 2),
        ["src/a.dart", "src/b.dart"]
    );
    assert!(search_paths(&session, "src", 0).is_empty());
    stop_workspace_quick_open_session(session);
}

#[cfg(unix)]
fn create_file_symlink(source: &Path, link: &Path) -> io::Result<()> {
    std::os::unix::fs::symlink(source, link)
}

#[cfg(windows)]
fn create_file_symlink(source: &Path, link: &Path) -> io::Result<()> {
    std::os::windows::fs::symlink_file(source, link)
}

#[cfg(not(any(unix, windows)))]
fn create_file_symlink(source: &Path, link: &Path) -> io::Result<()> {
    let _ = (source, link);
    Err(io::Error::new(
        io::ErrorKind::Unsupported,
        "file symlinks are unsupported on this platform",
    ))
}

#[test]
fn includes_local_file_symlinks_but_never_external_targets() {
    let workspace = tempfile::tempdir().expect("workspace");
    let outside = tempfile::tempdir().expect("outside");
    let local = workspace.path().join("local.txt");
    let external = outside.path().join("external.txt");
    fs::write(&local, "local").expect("local file");
    fs::write(&external, "external").expect("external file");
    if create_file_symlink(&local, &workspace.path().join("local-link.txt")).is_err()
        || create_file_symlink(&external, &workspace.path().join("external-link.txt")).is_err()
    {
        eprintln!("skipping symlink assertions because symlink creation failed");
        return;
    }

    let session = start_workspace_quick_open_session(workspace_path(&workspace)).expect("start");
    let paths = search_paths(&session, "", 50);

    assert!(paths.contains(&"local.txt".to_string()));
    assert!(paths.contains(&"local-link.txt".to_string()));
    assert!(!paths.contains(&"external-link.txt".to_string()));
    stop_workspace_quick_open_session(session);
}

#[test]
fn sessions_are_independent_when_searched_concurrently() {
    let first = tempfile::tempdir().expect("first workspace");
    let second = tempfile::tempdir().expect("second workspace");
    create_file(first.path(), "first.txt");
    create_file(second.path(), "second.txt");
    let first_session = start_workspace_quick_open_session(workspace_path(&first)).expect("first");
    let second_session =
        start_workspace_quick_open_session(workspace_path(&second)).expect("second");

    let first_thread = thread::spawn(move || search_paths(&first_session, "", 50));
    let second_thread = thread::spawn(move || search_paths(&second_session, "", 50));

    assert_eq!(first_thread.join().expect("first search"), ["first.txt"]);
    assert_eq!(second_thread.join().expect("second search"), ["second.txt"]);
}

#[test]
fn stop_is_idempotent_and_unknown_sessions_use_not_found() {
    let workspace = tempfile::tempdir().expect("workspace");
    create_file(workspace.path(), "file.txt");
    let session = start_workspace_quick_open_session(workspace_path(&workspace)).expect("start");
    let stopped = session.clone();
    stop_workspace_quick_open_session(session);
    stop_workspace_quick_open_session(stopped.clone());

    let error = search_workspace_quick_open_session(stopped, "".to_string(), 50).unwrap_err();
    assert_eq!(error.kind, WorkspaceFileErrorKind::NotFound);
    stop_workspace_quick_open_session(WorkspaceQuickOpenSession {
        id: "unknown".to_string(),
        indexed_file_count: 0,
    });
}

#[test]
fn failed_starts_do_not_create_searchable_sessions() {
    let error =
        start_workspace_quick_open_session("/path/that/does/not/exist".to_string()).unwrap_err();
    assert_eq!(error.kind, WorkspaceFileErrorKind::NotFound);
}
