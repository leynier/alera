use std::fs;

use git2::{IndexAddOption, Oid, Repository, Signature};

use super::*;

#[test]
fn extracts_worktree_staged_commit_and_range_patches() {
    let directory = tempfile::tempdir().expect("tempdir");
    let repository = Repository::init(directory.path()).expect("repository");
    let file = directory.path().join("app.txt");
    fs::write(&file, "before\n").expect("initial file");
    let base = commit(&repository, "base");

    fs::write(&file, "worktree\n").expect("worktree file");
    let worktree = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        Some("app.txt".to_string()),
        None,
        Some(GitChangeArea::Unstaged),
        None,
        None,
        None,
    )
    .expect("worktree patch");
    assert!(worktree
        .windows(b"+worktree".len())
        .any(|row| row == b"+worktree"));

    let mut index = repository.index().expect("index");
    index
        .add_path(std::path::Path::new("app.txt"))
        .expect("stage");
    index.write().expect("write index");
    let staged = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        Some(GitChangeArea::Staged),
        None,
        None,
        None,
    )
    .expect("staged patch");
    assert!(staged
        .windows(b"-before".len())
        .any(|row| row == b"-before"));

    let head = commit(&repository, "change");
    let commit_patch = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        None,
        Some(head.to_string()),
        Some(base.to_string()),
        None,
    )
    .expect("commit patch");
    let range_patch = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        None,
        None,
        None,
        Some(base.to_string()),
    )
    .expect("range patch");
    assert_eq!(range_patch, commit_patch);
}

#[test]
fn preserves_missing_final_newline_markers() {
    let directory = tempfile::tempdir().expect("tempdir");
    let repository = Repository::init(directory.path()).expect("repository");
    let file = directory.path().join("no-eol.txt");
    fs::write(&file, "old").expect("initial file");
    commit(&repository, "base");
    fs::write(&file, "new").expect("changed file");

    let patch = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        Some("no-eol.txt".to_string()),
        None,
        Some(GitChangeArea::Unstaged),
        None,
        None,
        None,
    )
    .expect("missing-eol patch");
    let patch = String::from_utf8(patch).expect("utf8 patch");
    assert!(
        patch.contains("-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n")
    );
    assert!(!patch.contains("-old>"));
    assert!(!patch.contains("+new<"));
}

#[test]
fn preserves_rename_sources_and_complete_untracked_inputs() {
    let directory = tempfile::tempdir().expect("tempdir");
    let repository = Repository::init(directory.path()).expect("repository");
    fs::write(directory.path().join("old.txt"), "unchanged content\n").expect("old file");
    let base = commit(&repository, "base");
    fs::rename(
        directory.path().join("old.txt"),
        directory.path().join("new.txt"),
    )
    .expect("rename");
    let mut index = repository.index().expect("index");
    index
        .add_all(["*"], IndexAddOption::DEFAULT, None)
        .expect("stage rename");
    index.write().expect("write rename index");
    let staged_rename = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        Some(GitChangeArea::Staged),
        None,
        None,
        None,
    )
    .expect("staged rename patch");
    let staged_rename = String::from_utf8(staged_rename).expect("utf8 staged rename");
    assert!(staged_rename.contains("rename from old.txt"));
    assert!(staged_rename.contains("rename to new.txt"));
    let selected_rename = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        Some("new.txt".to_string()),
        Some("old.txt".to_string()),
        Some(GitChangeArea::Staged),
        None,
        None,
        None,
    )
    .expect("selected staged rename patch");
    let selected_rename = String::from_utf8(selected_rename).expect("utf8 selected rename");
    assert!(selected_rename.contains("rename from old.txt"));
    assert!(selected_rename.contains("rename to new.txt"));
    let head = commit(&repository, "rename");

    let rename = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        Some("new.txt".to_string()),
        Some("old.txt".to_string()),
        None,
        Some(head.to_string()),
        Some(base.to_string()),
        None,
    )
    .expect("rename patch");
    let rename = String::from_utf8(rename).expect("utf8 rename");
    assert!(rename.contains("rename from old.txt"));
    assert!(rename.contains("rename to new.txt"));

    fs::write(directory.path().join("binary.bin"), [0, 1, 2, 3]).expect("binary file");
    fs::write(
        directory.path().join("large.txt"),
        format!("{}complete tail\n", "x".repeat(256 * 1024)),
    )
    .expect("large file");
    let untracked = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        Some(GitChangeArea::Untracked),
        None,
        None,
        None,
    )
    .expect("untracked patch");
    let untracked = String::from_utf8(untracked).expect("utf8 placeholders");
    assert!(untracked.contains("Binary file /dev/null and b/binary.bin differ"));
    assert!(untracked.contains("diff --git a/large.txt b/large.txt"));
    assert!(untracked.contains("complete tail"));
}

#[test]
fn rejects_untracked_text_above_the_reading_diff_limit() {
    let directory = tempfile::tempdir().expect("tempdir");
    Repository::init(directory.path()).expect("repository");
    fs::write(
        directory.path().join("too-large.txt"),
        vec![b'x'; MAX_READING_DIFF_BYTES + 1],
    )
    .expect("large file");

    let error = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        Some(GitChangeArea::Untracked),
        None,
        None,
        None,
    )
    .expect_err("oversized reading input");

    assert!(error.context.contains("4 MiB safety limit"));
}

#[cfg(unix)]
#[test]
fn preserves_untracked_executable_modes() {
    use std::os::unix::fs::PermissionsExt;

    let directory = tempfile::tempdir().expect("tempdir");
    Repository::init(directory.path()).expect("repository");
    let script = directory.path().join("run.sh");
    fs::write(&script, "#!/bin/sh\nexit 0\n").expect("script");
    let mut permissions = fs::metadata(&script).expect("metadata").permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&script, permissions).expect("executable mode");

    let patch = git_reading_diff_patch(
        directory.path().to_string_lossy().to_string(),
        None,
        None,
        Some(GitChangeArea::Untracked),
        None,
        None,
        None,
    )
    .expect("untracked executable patch");

    assert!(String::from_utf8(patch)
        .expect("utf8 patch")
        .contains("new file mode 100755"));
}

#[test]
fn quotes_unusual_untracked_paths_in_patch_headers() {
    let path = "dir/line\nquote\"slash\\tab\t.txt";

    let text = build_untracked_patch(path, "body\n", false, false);
    let binary = untracked_placeholder_patch(path, true, false);

    let quoted = "\"b/dir/line\\nquote\\\"slash\\\\tab\\t.txt\"";
    assert!(text.contains(&format!("+++ {quoted}\n")));
    assert!(text.contains(&format!(
        "diff --git \"a/dir/line\\nquote\\\"slash\\\\tab\\t.txt\" {quoted}\n"
    )));
    assert!(!text.contains("dir/line\nquote"));
    assert!(binary.contains(&format!("and {quoted} differ\n")));
}

#[test]
fn expands_dirty_submodule_worktrees() {
    let child_directory = tempfile::tempdir().expect("child tempdir");
    let child = Repository::init(child_directory.path()).expect("child repository");
    fs::write(child_directory.path().join("inside.txt"), "before\n").expect("child file");
    fs::write(child_directory.path().join("tracked.bin"), [0, 1, 2]).expect("tracked binary");
    fs::create_dir_all(child_directory.path().join("x b")).expect("spaced directory");
    fs::write(child_directory.path().join("x b/y.txt"), "before\n").expect("spaced child file");
    commit(&child, "child base");

    let parent_directory = tempfile::tempdir().expect("parent tempdir");
    let parent = Repository::init(parent_directory.path()).expect("parent repository");
    fs::write(parent_directory.path().join("root.txt"), "root\n").expect("root file");
    commit(&parent, "parent base");
    let mut submodule = parent
        .submodule(
            child_directory.path().to_string_lossy().as_ref(),
            std::path::Path::new("deps/child"),
            true,
        )
        .expect("configure submodule");
    submodule.clone(None).expect("clone submodule");
    submodule.add_to_index(true).expect("index submodule");
    submodule.add_finalize().expect("finalize submodule");
    commit(&parent, "add submodule");

    fs::write(
        parent_directory.path().join("deps/child/inside.txt"),
        "after\n",
    )
    .expect("modify child");
    fs::write(
        parent_directory.path().join("deps/child/x b/y.txt"),
        "after\n",
    )
    .expect("modify spaced child file");
    fs::write(
        parent_directory.path().join("deps/child/tracked.bin"),
        [0, 3, 2],
    )
    .expect("modify tracked binary");
    fs::write(
        parent_directory.path().join("deps/child/untracked.bin"),
        [0, 4, 2],
    )
    .expect("create untracked binary");
    let patch = git_reading_diff_patch(
        parent_directory.path().to_string_lossy().to_string(),
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("submodule patch");
    let patch = String::from_utf8(patch).expect("utf8 patch");
    assert!(patch.contains("diff --git a/deps/child/inside.txt"));
    assert!(patch.contains("-before"));
    assert!(patch.contains("+after"));
    assert!(patch.contains("diff --git a/deps/child/x b/y.txt b/deps/child/x b/y.txt"));
    assert!(patch.contains("+++ b/deps/child/x b/y.txt"));
    assert!(
        patch.contains("Binary files a/deps/child/tracked.bin and b/deps/child/tracked.bin differ")
    );
    assert!(patch.contains("Binary file /dev/null and b/deps/child/untracked.bin differ"));
}

fn commit(repository: &Repository, message: &str) -> Oid {
    let mut index = repository.index().expect("index");
    index
        .add_all(["*"], IndexAddOption::DEFAULT, None)
        .expect("add files");
    index.write().expect("write index");
    let tree = repository
        .find_tree(index.write_tree().expect("tree id"))
        .expect("tree");
    let signature = Signature::now("Alera", "alera@example.com").expect("signature");
    let parent = repository
        .head()
        .ok()
        .and_then(|head| head.target())
        .map(|oid| repository.find_commit(oid).expect("parent"));
    let parents = parent.iter().collect::<Vec<_>>();
    repository
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        )
        .expect("commit")
}
