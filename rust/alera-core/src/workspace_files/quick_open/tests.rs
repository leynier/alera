use std::fs;
use std::io;
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Barrier};
use std::thread;
use std::time::{Duration, Instant};

use super::*;

fn start(workspace: &tempfile::TempDir) -> WorkspaceQuickOpenSession {
    start_workspace_quick_open_session(workspace.path().to_string_lossy().into_owned()).unwrap()
}

fn paths(session: &WorkspaceQuickOpenSession, query: &str, limit: u32) -> Vec<String> {
    search_workspace_quick_open_session(session.clone(), query.to_string(), limit)
        .unwrap()
        .into_iter()
        .map(|item| item.relative_path)
        .collect()
}

#[test]
fn indexes_and_ranks_workspace_files() {
    let workspace = tempfile::tempdir().unwrap();
    fs::create_dir(workspace.path().join("lib")).unwrap();
    fs::write(workspace.path().join("lib/main.dart"), "void main() {}").unwrap();
    fs::write(workspace.path().join("readme.md"), "Alera").unwrap();
    let session = start(&workspace);
    assert_eq!(paths(&session, "main", 20)[0], "lib/main.dart");
    stop_workspace_quick_open_session(session);
}

#[test]
fn preserves_exact_path_segment_ranking() {
    let workspace = tempfile::tempdir().unwrap();
    for relative in [
        "src/file.dart",
        "lib/src/other.dart",
        "lib/src/src/repeated.dart",
        "lib/src-prefix.dart",
    ] {
        let path = workspace.path().join(relative);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, relative).unwrap();
    }
    let session = start(&workspace);
    let matches = search_workspace_quick_open_session(session.clone(), "src".into(), 20).unwrap();
    assert_eq!(matches[0].relative_path, "src/file.dart");
    assert_eq!(matches[0].score, 90_000);
    assert_eq!(matches[1].relative_path, "lib/src/other.dart");
    assert_eq!(matches[1].score, 89_999);
    assert_eq!(matches[2].relative_path, "lib/src/src/repeated.dart");
    assert_eq!(matches[2].score, 89_999);
    assert_eq!(matches[3].relative_path, "lib/src-prefix.dart");
    assert!(matches[3].score < matches[2].score);
    stop_workspace_quick_open_session(session);
}

#[test]
fn breaks_normalized_path_ties_with_the_original_path() {
    let mut files = vec![
        QuickOpenFile::new("a.dart".to_string()),
        QuickOpenFile::new("A.dart".to_string()),
    ];
    sort_quick_open_files(&mut files);
    assert_eq!(
        files
            .iter()
            .map(|file| file.relative_path.as_str())
            .collect::<Vec<_>>(),
        ["A.dart", "a.dart"]
    );
}

#[test]
fn fuzzy_scoring_prefers_path_boundaries_and_contiguous_matches() {
    let workspace = tempfile::tempdir().unwrap();
    fs::create_dir(workspace.path().join("foo")).unwrap();
    fs::write(workspace.path().join("foo/bar.txt"), "boundary").unwrap();
    fs::write(workspace.path().join("farboo.txt"), "gap").unwrap();
    let session = start(&workspace);

    let matches = search_workspace_quick_open_session(session.clone(), "fb".into(), 20).unwrap();

    assert_eq!(matches[0].relative_path, "foo/bar.txt");
    assert_eq!(matches[1].relative_path, "farboo.txt");
    assert!(matches[0].score > matches[1].score);
    stop_workspace_quick_open_session(session);
}

#[cfg(unix)]
#[test]
fn preserves_literal_backslashes_as_distinct_unix_file_names() {
    let workspace = tempfile::tempdir().unwrap();
    fs::create_dir(workspace.path().join("foo")).unwrap();
    fs::write(workspace.path().join("foo/bar.txt"), "nested").unwrap();
    fs::write(workspace.path().join("foo\\bar.txt"), "literal").unwrap();
    let session = start(&workspace);

    let indexed = paths(&session, "", 20);

    assert!(indexed.contains(&"foo/bar.txt".to_string()));
    assert!(indexed.contains(&"foo\\bar.txt".to_string()));
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
    let workspace = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    let local = workspace.path().join("local.txt");
    let external = outside.path().join("external.txt");
    fs::write(&local, "local").unwrap();
    fs::write(&external, "external").unwrap();
    if create_file_symlink(&local, &workspace.path().join("local-link.txt")).is_err()
        || create_file_symlink(&external, &workspace.path().join("external-link.txt")).is_err()
    {
        return;
    }
    let session = start(&workspace);
    let indexed = paths(&session, "", 20);
    assert!(indexed.contains(&"local.txt".to_string()));
    assert!(indexed.contains(&"local-link.txt".to_string()));
    assert!(!indexed.contains(&"external-link.txt".to_string()));
    stop_workspace_quick_open_session(session);
}

#[test]
fn strict_sessions_exclude_all_file_symlinks() {
    let workspace = tempfile::tempdir().unwrap();
    let local = workspace.path().join("local.txt");
    fs::write(&local, "local").unwrap();
    if create_file_symlink(&local, &workspace.path().join("local-link.txt")).is_err() {
        return;
    }
    let session = start_workspace_quick_open_session_without_symlinks(
        workspace.path().to_string_lossy().into_owned(),
    )
    .expect("start strict session");
    let indexed = paths(&session, "", 20);
    assert!(indexed.contains(&"local.txt".to_string()));
    assert!(!indexed.contains(&"local-link.txt".to_string()));
    stop_workspace_quick_open_session(session);
}

#[test]
fn prunes_idle_and_excess_sessions() {
    let now = Instant::now();
    let index = || Arc::new(QuickOpenIndex::new(Vec::new()));
    let mut entries = HashMap::from([
        (
            "expired".to_string(),
            QuickOpenSessionEntry {
                index: index(),
                last_accessed: now - QUICK_OPEN_SESSION_IDLE_TTL - Duration::from_secs(1),
            },
        ),
        (
            "live".to_string(),
            QuickOpenSessionEntry {
                index: index(),
                last_accessed: now,
            },
        ),
    ]);
    prune_sessions(&mut entries, now);
    assert!(!entries.contains_key("expired"));
    assert!(entries.contains_key("live"));
    for offset in 0..=MAX_QUICK_OPEN_SESSIONS {
        entries.insert(
            format!("session-{offset}"),
            QuickOpenSessionEntry {
                index: index(),
                last_accessed: now + Duration::from_secs(offset as u64),
            },
        );
    }
    enforce_session_limit(&mut entries);
    assert_eq!(entries.len(), MAX_QUICK_OPEN_SESSIONS);
    assert!(!entries.contains_key("live"));
}

#[test]
fn refreshes_a_requested_session_before_pruning_idle_entries() {
    let now = Instant::now();
    let expired_at = now - QUICK_OPEN_SESSION_IDLE_TTL - Duration::from_secs(1);
    let index = || Arc::new(QuickOpenIndex::new(Vec::new()));
    let mut entries = HashMap::from([
        (
            "requested".to_string(),
            QuickOpenSessionEntry {
                index: index(),
                last_accessed: expired_at,
            },
        ),
        (
            "abandoned".to_string(),
            QuickOpenSessionEntry {
                index: index(),
                last_accessed: expired_at,
            },
        ),
    ]);

    let requested = access_session(&mut entries, "requested", now).unwrap();

    assert!(Arc::ptr_eq(&requested, &entries["requested"].index));
    assert_eq!(entries["requested"].last_accessed, now);
    assert!(!entries.contains_key("abandoned"));
}

#[test]
fn uses_the_rarest_character_index_and_bounds_ranked_results() {
    let mut files = (0..100)
        .map(|index| QuickOpenFile::new(format!("lib/common-{index}.dart")))
        .collect::<Vec<_>>();
    files.push(QuickOpenFile::new("lib/unique-zebra.dart".to_string()));
    let index = QuickOpenIndex::new(files);
    let query_code_units = "zebra".encode_utf16().collect::<Vec<_>>();
    let query_counts = character_counts(&query_code_units);
    assert_eq!(
        index
            .character_index
            .candidates(&query_counts)
            .unwrap()
            .len(),
        1
    );
    let workspace = tempfile::tempdir().unwrap();
    for index in 0..20 {
        fs::write(workspace.path().join(format!("match-{index}.txt")), "match").unwrap();
    }
    let session = start(&workspace);
    assert_eq!(paths(&session, "match", 3).len(), 3);
    stop_workspace_quick_open_session(session);
}

#[test]
fn returns_a_bounded_partial_index_when_budgets_are_exhausted() {
    let workspace = tempfile::tempdir().unwrap();
    for relative in ["one.txt", "two.txt", "three.txt"] {
        fs::write(workspace.path().join(relative), relative).unwrap();
    }

    let files = collect_quick_open_files(workspace.path(), 2, usize::MAX, true).unwrap();
    assert_eq!(
        files
            .iter()
            .map(|file| file.relative_path.as_str())
            .collect::<Vec<_>>(),
        ["one.txt", "three.txt"]
    );

    let files = collect_quick_open_files(workspace.path(), usize::MAX, 8, true).unwrap();
    assert!(files.len() <= 1);
    assert!(files.iter().all(|file| file.relative_path.len() <= 8));
}

#[test]
fn serializes_concurrent_index_builds() {
    const WORKERS: usize = 8;
    let start = Arc::new(Barrier::new(WORKERS));
    let active = Arc::new(AtomicUsize::new(0));
    let maximum = Arc::new(AtomicUsize::new(0));
    let workers = (0..WORKERS)
        .map(|_| {
            let start = Arc::clone(&start);
            let active = Arc::clone(&active);
            let maximum = Arc::clone(&maximum);
            thread::spawn(move || {
                start.wait();
                with_quick_open_build_gate(|| {
                    let current = active.fetch_add(1, Ordering::SeqCst) + 1;
                    maximum.fetch_max(current, Ordering::SeqCst);
                    thread::sleep(Duration::from_millis(5));
                    active.fetch_sub(1, Ordering::SeqCst);
                    Ok(())
                })
                .unwrap();
            })
        })
        .collect::<Vec<_>>();

    for worker in workers {
        worker.join().unwrap();
    }

    assert_eq!(maximum.load(Ordering::SeqCst), 1);
}

#[cfg(unix)]
#[test]
fn keeps_accessible_files_when_a_nested_directory_is_unreadable() {
    use std::os::unix::fs::PermissionsExt;

    let workspace = tempfile::tempdir().unwrap();
    fs::write(workspace.path().join("visible.txt"), "visible").unwrap();
    let denied = workspace.path().join("denied");
    fs::create_dir(&denied).unwrap();
    fs::write(denied.join("hidden.txt"), "hidden").unwrap();
    fs::set_permissions(&denied, fs::Permissions::from_mode(0o0)).unwrap();

    let result = collect_quick_open_files(workspace.path(), usize::MAX, usize::MAX, true);

    fs::set_permissions(&denied, fs::Permissions::from_mode(0o700)).unwrap();
    let files = result.unwrap();
    assert!(files.iter().any(|file| file.relative_path == "visible.txt"));
}
